function out = postictal_recovery(ecog_uV, fs, sz_on, sz_off, opts)
% POSTICTAL_RECOVERY  Time for ECoG amplitude to return to pre-ictal baseline.
%
%   out = postictal_recovery(ecog_uV, fs, sz_on, sz_off)
%   out = postictal_recovery(ecog_uV, fs, sz_on, sz_off, opts)
%
%   ecog_uV : ECoG signal (vector, uV)
%   fs      : sampling rate (Hz)
%   sz_on   : seizure onset, s from recording start
%   sz_off  : seizure offset, s from recording start
%
%   Method
%     1. Signal is cut into windows of opts.win_s, every opts.step_s.
%        Each window is mean-subtracted; amplitude = log10(RMS, uV).
%     2. A window is flagged as artifact if max|ECoG| > opts.artifact_uV
%        or it overlaps any row of opts.exclude ([start end] in s).
%     3. Baseline = artifact-free windows lying entirely within the
%        opts.base_dur_s seconds that end opts.base_gap_s before onset:
%        [sz_on - base_gap_s - base_dur_s, sz_on - base_gap_s].
%        The baseline period is the same length in every recording;
%        artifact windows inside it are dropped, not replaced.
%     4. Baseline and post-ictal series are smoothed separately (moving
%        mean over opts.smooth_s, ignoring artifact windows), so smoothing
%        never crosses the seizure. The threshold is computed on the
%        smoothed baseline, so both sides are on the same scale:
%          'sd'  : mean - opts.k_sd * SD
%          'pct' : opts.pct-th percentile
%     5. Recovery = centre of the first artifact-free post-offset window
%        that is >= threshold and begins a hold period of opts.hold_s in
%        which every artifact-free window is also >= threshold. Artifact
%        windows inside the hold period are skipped (they neither pass nor
%        fail), but at least opts.hold_min_clean of the hold period must be
%        artifact-free. Set opts.hold_artifact = 'break' to make artifact
%        windows end the run instead. If no such period exists, recovery
%        is NaN (not recovered within the recording; treat as censored at
%        out.max_observable_s after offset).
%     6. Suppression test (is there any post-ictal state?): mean log RMS of
%        the artifact-free windows in the first opts.early_s after offset
%        is compared with the same threshold used for recovery. Suppression
%        is present if the early mean is below threshold, i.e. the signal
%        starts out below the level it later has to climb back above. If
%        fewer than opts.early_min_clean of the early windows are
%        artifact-free, the test is indeterminate.
%
%   out.status summarizes steps 5-6:
%     'indeterminate'  too much artifact right after offset to test
%     'no suppression' early post-ictal amplitude within baseline range
%     'recovered'      suppression present, then recovered (rec_from_offset)
%     'not recovered'  suppression present, not recovered within recording
%
%   Output (struct)
%     t_win            window centres (s)
%     log_rms          log10 RMS per window (NaN = artifact)
%     artifact         logical, per window
%     is_base, is_post logical masks for baseline / post-offset windows
%     sm               smoothed log10 RMS (NaN outside baseline/post)
%     base_start, base_end baseline period (s from recording start)
%     base_clean_s     artifact-free time within the baseline period (s)
%     base_mean, base_sd   of smoothed baseline log10 RMS
%     thresh           threshold (log10 uV)
%     recovered        true if a qualifying run was found
%     rec_time         recovery time, s from recording start
%     rec_from_offset  recovery time, s after seizure offset
%     hold_end         end of the sustained-above-threshold check, s from start
%     max_observable_s last post-offset time a run could start, s after offset
%     hold_clean_frac  artifact-free fraction of the hold period (NaN if
%                      not recovered); low values mean the recovery time may
%                      mark the end of an artifact stretch
%     status           see above
%     suppressed       true / false / NaN (indeterminate)
%     early_mean       mean log10 RMS, first early_s after offset
%     early_clean_frac fraction of early windows that are artifact-free
%     early_ratio      early RMS / mean baseline RMS (e.g. 0.6 = 40% lower)
%     opts             options used
%
%   Code sections (in order):
%     Options                  defaults, merged with anything passed in opts
%     1. Windowed log RMS      amplitude per window; artifact flags
%     2. Baseline/post masks   which windows are baseline, which post-ictal
%     3. Smoothing             moving mean, baseline and post-ictal separately
%     4. Threshold             from the smoothed baseline
%     5. Recovery              first sustained run above threshold
%     6. Suppression test      first 60 s after offset vs threshold
%     Output                   pack results into a struct; plot if asked
%   Helper functions at the end: nanmovmean (smoothing), pctile
%   (percentile), plot_recovery (figure), uistack_bottom (draw order).

%% Options
% Defaults. Any field the caller passes in opts overrides the default;
% any field not passed keeps the default below.
def = struct( ...
    'win_s',         10, ...      % window length (s)
    'step_s',        5, ...       % window step (s); 5 with win_s 10 = 50% overlap
    'smooth_s',      30, ...      % moving-mean span (s); 0 = none
    'artifact_uV',   1500, ...    % max |ECoG| allowed in a window (uV)
    'exclude',       zeros(0,2), ... % [start end] intervals to drop (s)
    'base_dur_s',    300, ...     % baseline length (s)
    'base_gap_s',    60, ...      % baseline ends this long before onset (s)
    'min_base_win',  10, ...      % minimum baseline windows required
    'thresh_method', 'sd', ...    % 'sd' or 'pct'
    'k_sd',          2, ...       % for 'sd'
    'pct',           5, ...       % for 'pct'
    'hold_s',        60, ...      % required sustained time above threshold (s)
    'hold_artifact', 'skip', ...  % artifact in hold period: 'skip' or 'break'
    'hold_min_clean', 0.5, ...    % min artifact-free fraction of hold period ('skip')
    'early_s',       60, ...      % post-offset period tested for suppression (s)
    'early_min_clean', 0.5, ...   % min artifact-free fraction of that period
    'plot',          true, ...
    'title_str',     '', ...
    'font_size',     14);         % font size for all plot text (MATLAB default ~10)
% Fill in any option the caller did not set with its default
if nargin < 5 || isempty(opts), opts = struct(); end
f = fieldnames(def);
for i = 1:numel(f)
    if ~isfield(opts, f{i}), opts.(f{i}) = def.(f{i}); end
end

% Force a column vector so indexing below is unambiguous
ecog_uV = ecog_uV(:);
n       = numel(ecog_uV);   % total samples
dur     = n / fs;           % recording length (s)

% Input sanity checks
assert(sz_on < sz_off, 'sz_on must be before sz_off');
assert(sz_off < dur, 'Seizure offset (%.1f s) is after the end of the recording (%.1f s)', sz_off, dur);
assert(opts.step_s <= opts.win_s, 'step_s should not exceed win_s');
assert(any(strcmp(opts.thresh_method, {'sd','pct'})), 'thresh_method must be ''sd'' or ''pct''');
assert(any(strcmp(opts.hold_artifact, {'skip','break'})), 'hold_artifact must be ''skip'' or ''break''');

%% 1. Windowed log RMS
% Window length and step in samples
win_n   = round(opts.win_s  * fs);
step_n  = round(opts.step_s * fs);

% Sample index of the first sample of each window. The last window must end
% at or before the last sample, so starts run up to n - win_n + 1.
starts  = (1:step_n:(n - win_n + 1))';
n_win   = numel(starts);

% Window timing in seconds from recording start. Sample 1 is t = 0, so
% sample k is at (k-1)/fs. t_win (the window centre) is the time each
% window's value is plotted at and reported as.
t_start = (starts - 1) / fs;
t_end   = t_start + opts.win_s;
t_win   = t_start + opts.win_s/2;

log_rms  = nan(n_win, 1);
artifact = false(n_win, 1);
for w = 1:n_win
    % Samples in this window
    seg = ecog_uV(starts(w):starts(w) + win_n - 1);

    % Remove the window mean so slow DC drift doesn't inflate the RMS.
    % After this, RMS equals the standard deviation of the window.
    seg = seg - mean(seg);

    % Amplitude = log10 of RMS (uV). Log is used so that the baseline
    % mean/SD and the threshold work on ratios (e.g. "13% below
    % baseline") rather than absolute uV, and so the distribution of
    % window amplitudes is closer to symmetric.
    log_rms(w)  = log10(sqrt(mean(seg.^2)));

    % Artifact if any sample exceeds the amplitude limit (catches
    % movement, cable artifact and amplifier saturation at ~6390 uV)
    artifact(w) = max(abs(seg)) > opts.artifact_uV;
end

% Manually excluded intervals: flag every window that overlaps one,
% even partially (window ends after interval start AND starts before
% interval end)
for r = 1:size(opts.exclude, 1)
    artifact = artifact | (t_end > opts.exclude(r,1) & t_start < opts.exclude(r,2));
end

% Artifact windows carry no amplitude value from here on
log_rms(artifact) = NaN;

%% 2. Baseline and post-ictal masks
% Logical vectors, one entry per window: true if the window belongs to
% the baseline period / the post-ictal period.
% Baseline: windows lying entirely within the base_dur_s seconds that end
% base_gap_s before onset. The gap keeps pre-ictal changes just before
% onset out of the baseline. A fixed duration means the baseline is the
% same length regardless of how much pre-ictal recording a file has.
base_end   = sz_on - opts.base_gap_s;
base_start = base_end - opts.base_dur_s;
assert(base_start >= 0, ...
    'Recording has only %.0f s before the baseline end; %.0f s of baseline requested', ...
    base_end, opts.base_dur_s);
is_base  = t_start >= base_start & t_end <= base_end;

% Post-ictal: windows that start at or after seizure offset, so no
% post-ictal window contains any seizure signal
is_post  = t_start >= sz_off;

% Artifact-free baseline time: clean windows x step (windows overlap, so
% step, not window length, is the time each one adds)
base_clean_s = sum(is_base & ~artifact) * opts.step_s;
assert(sum(is_base & ~artifact) >= opts.min_base_win, ...
    'Only %d artifact-free baseline windows (need %d)', sum(is_base & ~artifact), opts.min_base_win);
assert(any(is_post), 'No complete windows after seizure offset');

%% 3. Smooth each segment separately
% Smoothing span in windows (e.g. 30 s / 5 s step = 6 windows). A span of
% 1 means no smoothing.
sm_span = max(1, round(opts.smooth_s / opts.step_s));

% Baseline and post-ictal segments are smoothed independently, so the
% moving mean never averages seizure windows into either one. Artifact
% windows (NaN) are skipped by nanmovmean rather than counted as zero.
sm = nan(n_win, 1);
sm(is_base) = nanmovmean(log_rms(is_base), sm_span);
sm(is_post) = nanmovmean(log_rms(is_post), sm_span);

% nanmovmean fills in a value at artifact windows from their neighbours;
% blank those out so an artifact window can never count as "recovered"
sm(artifact) = NaN;

%% 4. Threshold
% Smoothed baseline values (artifact windows excluded). The threshold is
% computed from the SMOOTHED baseline because it is compared against the
% SMOOTHED post-ictal curve; smoothing shrinks the SD, so mixing raw and
% smoothed would put the two on different scales.
b = sm(is_base & ~artifact);
base_mean = mean(b);
base_sd   = std(b);

if strcmp(opts.thresh_method, 'sd')
    % Lower edge of the normal range: mean - k SDs (in log10 uV)
    thresh = base_mean - opts.k_sd * base_sd;
else
    % Lower edge of the normal range: a low percentile of baseline values
    thresh = pctile(b, opts.pct);
end

%% 5. Recovery: first sustained run above threshold
% Number of consecutive windows needed so that the window centres span
% hold_s. E.g. hold_s 60, step_s 5 -> 13 windows, centres 0,5,...,60 s
% after the first one.
n_hold   = floor(opts.hold_s / opts.step_s) + 1;

% Post-ictal windows in time order. For each: is it artifact-free, and
% if so, is its smoothed amplitude at or above threshold?
post_idx = find(is_post);
clean    = ~artifact(post_idx);
above    = clean & sm(post_idx) >= thresh;   % passing = clean AND above
below    = clean & ~above;                   % failing = clean AND below

% Scan forward from offset. Candidate recovery = a clean window above
% threshold. Its hold period is that window plus the next n_hold-1.
%   'skip' : the hold passes if no CLEAN window in it is below threshold
%            and at least hold_min_clean of its windows are clean.
%            Artifact windows are ignored rather than counted as failures.
%   'break': every window in the hold must be clean and above threshold.
rec_time = NaN;
hold_clean_frac = NaN;
for i = 1:(numel(above) - n_hold + 1)
    if ~above(i), continue; end          % recovery must start on a clean, passing window
    span = i:i + n_hold - 1;
    if strcmp(opts.hold_artifact, 'skip')
        hold_ok = ~any(below(span)) && mean(clean(span)) >= opts.hold_min_clean;
    else
        hold_ok = all(above(span));
    end
    if hold_ok
        rec_time = t_win(post_idx(i));   % centre of the first window in the hold
        hold_clean_frac = mean(clean(span));   % artifact-free fraction of the hold
        break
    end
end
recovered = ~isnan(rec_time);

% End of the hold check: centre of the last window in the run (NaN if
% not recovered)
hold_end  = rec_time + (n_hold - 1) * opts.step_s;

% Latest time after offset at which a full run could still begin before
% the recording ends. If not recovered, recovery time is only known to be
% later than this (censored).
max_obs   = t_win(post_idx(max(1, numel(post_idx) - n_hold + 1))) - sz_off;

%% 6. Suppression test: is there any post-ictal amplitude reduction?
% Number of windows that fit fully inside the first early_s after offset
% (60 s with 10 s windows every 5 s -> 11 windows)
n_early = floor((opts.early_s - opts.win_s) / opts.step_s) + 1;
assert(n_early >= 1, 'early_s must be at least win_s');

% Early post-ictal windows. Artifact windows are NaN in log_rms and are
% left out of the mean. Unsmoothed values are used: averaging over the
% whole early period already does the smoothing.
early_idx  = post_idx(1:min(n_early, numel(post_idx)));
early_vals = log_rms(early_idx);
early_clean_frac = mean(~isnan(early_vals));
early_mean = mean(early_vals(~isnan(early_vals)));   % NaN if none clean

if early_clean_frac < opts.early_min_clean
    % Too much artifact right after offset to tell
    suppressed = NaN;
else
    % Same threshold as the recovery criterion: "no suppression" means the
    % signal is already at or above the recovery threshold at offset
    suppressed = early_mean < thresh;
end

% Early amplitude relative to mean baseline, as a ratio of RMS
early_ratio = 10^(early_mean - base_mean);

% Overall result for this recording. The suppression test comes first:
% a recovery time only means something if there was suppression.
if isnan(suppressed)
    status = 'indeterminate';
elseif ~suppressed
    status = 'no suppression';
elseif recovered
    status = 'recovered';
else
    status = 'not recovered';
end

%% Output
% Everything needed to check or re-plot the result (see the Output list
% in the header), then draw the figure if opts.plot is true
out = struct('t_win', t_win, 'log_rms', log_rms, 'artifact', artifact, ...
    'is_base', is_base, 'is_post', is_post, 'sm', sm, ...
    'base_start', base_start, 'base_end', base_end, 'base_clean_s', base_clean_s, ...
    'base_mean', base_mean, 'base_sd', base_sd, 'thresh', thresh, ...
    'recovered', recovered, 'rec_time', rec_time, ...
    'rec_from_offset', rec_time - sz_off, 'hold_end', hold_end, ...
    'max_observable_s', max_obs, 'hold_clean_frac', hold_clean_frac, ...
    'status', status, 'suppressed', suppressed, 'early_mean', early_mean, ...
    'early_clean_frac', early_clean_frac, 'early_ratio', early_ratio, ...
    'opts', opts);

if opts.plot
    plot_recovery(ecog_uV, fs, sz_on, sz_off, out);
end
end

%% ------------------------------------------------------------------------
function y = nanmovmean(x, k)
% Centred moving mean over k points, ignoring NaNs, shrinking at the edges.
% Each output point is the mean of the non-NaN values among the k points
% centred on it. Near the ends, fewer points are available and the mean
% is over just those (so at the start of the post-ictal segment the
% average only looks forward in time).
x = x(:);
good = ~isnan(x);

% Replace NaNs with 0 so they add nothing to the sum...
x0 = x; x0(~good) = 0;
ker = ones(k, 1);

% ...then divide the windowed sum by the windowed count of real values
s = conv(x0, ker, 'same');           % sum of non-NaN values in each span
c = conv(double(good), ker, 'same'); % number of non-NaN values in each span
y = s ./ c;
y(c == 0) = NaN;                     % span contained only NaNs
end

function p = pctile(x, q)
% Percentile with linear interpolation (same as MATLAB prctile), no toolbox needed.
% The i-th sorted value is treated as the (i - 0.5)/m quantile; values in
% between are linearly interpolated, and q beyond the ends is clamped.
x = sort(x(~isnan(x)));
m = numel(x);
pos = q/100 * m + 0.5;          % fractional position in the sorted list
pos = min(max(pos, 1), m);      % clamp to the first/last value
lo = floor(pos); hi = ceil(pos);
p = x(lo) + (pos - lo) * (x(hi) - x(lo));
end

function plot_recovery(ecog_uV, fs, sz_on, sz_off, out)
% Top panel: raw ECoG with the seizure (red) and hold check (green) shaded.
% Bottom panel: window RMS, smoothed RMS, threshold, baseline period and
% recovery time, on a log y-axis (the analysis is done in log10 uV).
t = (0:numel(ecog_uV)-1)' / fs;   % sample times (s), matching t_win convention
o = out.opts;

figure('Color', 'w', 'Position', [100 100 1200 650]);

%% Top: raw ECoG
ax1 = subplot(2,1,1);
plot(t, ecog_uV, 'k', 'LineWidth', 0.25); hold on
yl = ylim;
% Seizure period, drawn behind the trace
patch([sz_on sz_off sz_off sz_on], yl([1 1 2 2]), [1 0.6 0.6], ...
    'EdgeColor', 'none', 'FaceAlpha', 0.4);
uistack_bottom(ax1);
ylabel('ECoG (\muV)');
title(o.title_str, 'Interpreter', 'none');
box off

if out.recovered && isequal(out.suppressed, true)
    % Shade the sustained-above-threshold check on the raw trace too
    patch([out.rec_time out.hold_end out.hold_end out.rec_time], yl([1 1 2 2]), ...
        [0.6 0.9 0.6], 'EdgeColor', 'none', 'FaceAlpha', 0.4);
    uistack_bottom(ax1);
end

%% Bottom: amplitude analysis
ax2 = subplot(2,1,2);
% Convert from log10 uV back to uV for display; the log y-axis keeps the
% same visual spacing the analysis uses
rms_uV = 10.^out.log_rms;
sm_uV  = 10.^out.sm;

% Collect handles and labels together so the legend always matches,
% whichever optional items are drawn
hc = {}; leg = {};
hc{end+1} = semilogy(out.t_win, rms_uV, '.', 'Color', [0.6 0.6 0.6], 'MarkerSize', 6); hold on
leg{end+1} = 'Window RMS';
hc{end+1} = semilogy(out.t_win, sm_uV, 'b', 'LineWidth', 1.5);
leg{end+1} = sprintf('Smoothed (%g s)', o.smooth_s);

% Artifact windows have no RMS value, so mark them as a row of dots just
% below the lowest real value
art = out.artifact;
if any(art)
    ya = min(rms_uV(~art)) * 0.8;
    hc{end+1} = semilogy(out.t_win(art), ya * ones(sum(art),1), 'm.', 'MarkerSize', 8);
    leg{end+1} = 'Artifact/excluded';
end

xl = [0 t(end)];
hc{end+1} = semilogy(xl, 10^out.thresh * [1 1], 'r--', 'LineWidth', 1);
leg{end+1} = 'Threshold';

% Freeze y-limits now so the vertical lines/patches below span the axis
yl = ylim;

% Baseline period as a thick bar along the bottom of the axis
hc{end+1} = semilogy([out.base_start out.base_end], yl(1) * [1 1] * 1.05, 'g-', 'LineWidth', 4);
leg{end+1} = 'Baseline period';

% Seizure onset and offset
semilogy([sz_on sz_on], yl, 'k:'); semilogy([sz_off sz_off], yl, 'k:');

% Early post-ictal block used for the suppression test, with its mean RMS
early_end = sz_off + o.early_s;
hc{end+1} = patch([sz_off early_end early_end sz_off], yl([1 1 2 2]), ...
    [1 0.85 0.5], 'EdgeColor', 'none', 'FaceAlpha', 0.4);
leg{end+1} = sprintf('Suppression test (first %g s)', o.early_s);
uistack_bottom(ax2);
if ~isnan(out.early_mean)
    hc{end+1} = semilogy([sz_off early_end], 10^out.early_mean * [1 1], ...
        '-', 'Color', [0.85 0.45 0], 'LineWidth', 2.5);
    leg{end+1} = 'Early post-ictal mean';
end

if out.recovered && isequal(out.suppressed, true)
    % Hold check period, behind the data
    hc{end+1} = patch([out.rec_time out.hold_end out.hold_end out.rec_time], ...
        yl([1 1 2 2]), [0.6 0.9 0.6], 'EdgeColor', 'none', 'FaceAlpha', 0.4);
    leg{end+1} = sprintf('Hold check (%g s, artifact: %s)', o.hold_s, o.hold_artifact);
    uistack_bottom(ax2);
    % Recovery time
    hc{end+1} = semilogy(out.rec_time * [1 1], yl, 'r-', 'LineWidth', 1.5);
    leg{end+1} = 'Recovery';
end

% Title: suppression result first, then recovery
switch out.status
    case 'indeterminate'
        rec_str = sprintf('Suppression test indeterminate: only %.0f%% of first %g s after offset artifact-free', ...
            100 * out.early_clean_frac, o.early_s);
    case 'no suppression'
        rec_str = sprintf('No post-ictal suppression: first %g s at %.0f%% of baseline RMS (threshold %.0f%%)', ...
            o.early_s, 100 * out.early_ratio, 100 * 10^(out.thresh - out.base_mean));
    case 'recovered'
        rec_str = sprintf('Suppressed to %.0f%% of baseline; recovered %.0f s after offset (held through %.0f s)', ...
            100 * out.early_ratio, out.rec_from_offset, out.hold_end - sz_off);
    case 'not recovered'
        rec_str = sprintf('Suppressed to %.0f%% of baseline; not recovered within recording (%.0f s observable)', ...
            100 * out.early_ratio, out.max_observable_s);
end
ylim(yl);
ylabel(sprintf('RMS, %g s windows (\\muV)', o.win_s));
xlabel('Time from recording start (s)');
title(rec_str);
legend([hc{:}], leg, 'Location', 'eastoutside');
box off

% Apply one font size to every text element (tick labels, axis labels,
% titles, legend). Done before matching axis widths, since larger text
% changes how much space the legend takes.
set(findall(gcf, '-property', 'FontSize'), 'FontSize', o.font_size);

% Outside legend shrinks ax2; match ax1 so the time axes line up
drawnow;   % let the legend finish resizing ax2 before reading its position
p1 = get(ax1, 'Position'); p2 = get(ax2, 'Position');
set(ax1, 'Position', [p2(1) p1(2) p2(3) p1(4)]);

linkaxes([ax1 ax2], 'x');
xlim(xl);
end

function uistack_bottom(ax)
% Move the most recently drawn object (a shading patch) behind everything
% else in the axes. Children are listed newest first, so ch(1) is the
% patch; moving it to the end of the list draws it first (at the back).
ch = get(ax, 'Children');
set(ax, 'Children', [ch(2:end); ch(1)]);
end
