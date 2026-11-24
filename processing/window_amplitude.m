function out = window_amplitude(ecog_uV, fs, sz_on, sz_off, opts)
% WINDOW_AMPLITUDE  Windowed ECoG amplitude, band power and spike rate for
% one recording, relative to its baseline. Processing only: no thresholds
% and no recovery times (those are computed across animals in
% analyze_primary.m).
%
%   out = window_amplitude(ecog_uV, fs, sz_on, sz_off, opts)
%
% Inputs
%   ecog_uV : ECoG signal (uV), one channel (notch-filtered on loading)
%   fs      : sampling rate (Hz)
%   sz_on   : seizure (or pseudo-seizure) onset, s from recording start
%   sz_off  : seizure (or pseudo-seizure) offset, s from recording start
%   opts    : struct of options; any field left out takes its default
%             (see Options below). heat_start is needed for the
%             pre-heating baseline; spike_t (from detect_spikes.m) for the
%             spike rate. NOTE THAT SPIKES ARE DETECTED IN ANOTHER FUNCTION
%             AND JUST PASSED INTO HERE
%
% Steps
%   1. Windows: 10 s windows every 5 s. For each window, remove the mean
%      and take log10 of the RMS (uV). A window is artifact if any sample
%      (after removing the mean) exceeds opts.artifact_uV; artifact windows
%      get NaN (in every measure below). A window whose signal is flat (all
%      samples equal: a disconnected channel or dropped data) stops with an
%      error, so the recording is reported rather than silently analysed.
%   2. Band power: in each window, the power spectrum is the average of
%      2 s Hann-windowed segments every 1 s (Welch; 0.5 Hz resolution).
%      log10 power is summed over each band in opts.bands (lower edge
%      included, upper edge not). Delta/theta = log10(delta power / theta
%      power).
%   3. Spikes: number of spikes (opts.spike_t) in each window; rate per
%      minute.
%   4. Baseline: the period from baseline_period.m (by default the 5 min
%      before heating starts). Baseline mean of each measure = mean over
%      the artifact-free windows lying entirely inside it.
%   5. Values after offset: for each bin in opts.post_bins_s (e.g. 0-60 s
%      after offset), the mean over the artifact-free windows lying
%      entirely inside the bin, relative to baseline:
%        bin_ratio      RMS ratio, 10^(mean log10 RMS - baseline mean), i.e.
%                       the ratio of geometric mean RMS to baseline
%        bin_dt_ratio   delta/theta ratio relative to baseline, the same way
%        bin_spike_rate spike rate (per min); compare with base_spike_rate
%      Blank (NaN) if the recording ends before the bin does, or if fewer
%      than opts.min_clean_frac of the bin's windows are artifact-free.
%
% Output (struct)
%   t_win, t_start, t_end : window centre / start / end (s), one per window
%   log_rms         log10 RMS per window (uV); NaN = artifact
%   log_rms_all     the same with no windows removed, and
%   max_abs_uV      largest |sample| per window: together these let the
%                   artifact limit be changed without reloading the data
%   artifact        true for artifact windows
%   band_names, band_edges   opts.bands
%   log_bp          log10 band power per window (uV^2), windows x bands
%   log_dt          log10(delta / theta power) per window
%   spike_count     spikes per window; spike_rate = per minute
%   is_base         true for windows inside the baseline
%   base_start, base_end   baseline period (s)
%   base_clean_s    artifact-free baseline time (s)
%   base_mean       baseline mean log10 RMS
%   base_bp, base_dt, base_spike_rate   baseline means of the other measures
%   bin_edges       opts.post_bins_s
%   bin_ratio, bin_dt_ratio, bin_spike_rate   per bin (see step 5)
%   bin_clean_frac  artifact-free fraction of each bin's windows
%   dur_s           recording length (s)
%   opts            options used
%
% Figure (opts.plot): raw ECoG on top (spikes marked); below, RMS /
% baseline, delta/theta / baseline and spike rate per window, each with a
% 30 s moving average for display (computed separately before onset,
% during the seizure and after offset), the baseline, heating start and
% seizure.

%% Options
def = struct( ...
    'win_s',          10, ...     % window length (s)
    'step_s',         5, ...      % window step (s)
    'artifact_uV',    3000, ...   % max |ECoG| allowed in a window (uV); batch passes cfg.artifact_uV
    'base_mode',      'pre_heating', ... % see baseline_period.m
    'heat_start',     NaN, ...    % heating start (s); needed for 'pre_heating'
    'base_dur_s',     300, ...    % baseline length (s)
    'base_min_s',     60, ...     % 'pre_heating': minimum baseline length (s)
    'base_gap_s',     60, ...     % 'pre_onset': baseline ends this long before onset (s)
    'min_base_win',   10, ...     % minimum artifact-free baseline windows
    'post_bins_s',    [0 60; 60 120; 120 300; 300 600], ... % bins after offset (s)
    'min_clean_frac', 0.5, ...    % min artifact-free fraction of a bin (or any window used later)
    'plot',           true, ...
    'title_str',      '', ...
    'smooth_s',       30, ...     % figure only: moving-average span (s)
    'font_size',      14, ...
    'bands', {{'delta', [1 4]; 'theta', [4 8]; 'alpha', [8 13]; 'beta', [13 30]; 'gamma', [30 55]}}, ... % batch passes cfg.bands
    'spec_win_s',     2, ...      % segment length for band power (s); step = half of it
    'rms_band',       [1 30], ... % band-pass for RMS (Hz); [] = broadband (batch passes cfg.rms_band)
    'spike_t',        []);        % spike times (s), from detect_spikes.m; [] = none detected
if nargin < 5 || isempty(opts), opts = struct(); end
f = fieldnames(def);
for i = 1:numel(f)
    if ~isfield(opts, f{i}), opts.(f{i}) = def.(f{i}); end
end

ecog_uV = ecog_uV(:);
n   = numel(ecog_uV);
dur = n / fs;                                       % recording length (s)
assert(sz_on < sz_off, 'sz_on must be before sz_off');
assert(sz_off < dur, 'Seizure offset (%.1f s) is after the end of the recording (%.1f s)', sz_off, dur);
assert(opts.step_s <= opts.win_s, 'step_s should not exceed win_s');

%% 1-2. Windowed log RMS and band power
win_n  = round(opts.win_s  * fs);
step_n = round(opts.step_s * fs);
starts = (1:step_n:(n - win_n + 1))';               % first sample of each window
n_win  = numel(starts);
% Sample k is at t = (k-1)/fs
t_start = (starts - 1) / fs;
t_end   = t_start + opts.win_s;
t_win   = t_start + opts.win_s / 2;

% Band power set-up (step 2): 2 s Hann segments every 1 s inside each
% window; one-sided power spectral density in uV^2/Hz
band_names = opts.bands(:, 1)';
band_edges = cell2mat(opts.bands(:, 2));
seg_n  = round(opts.spec_win_s * fs);
seg_st = 0:round(seg_n / 2):(win_n - seg_n);        % segment starts within a window
hann_w = 0.5 - 0.5 * cos(2 * pi * (0:seg_n - 1)' / seg_n);
freqs  = (0:floor(seg_n / 2))' * fs / seg_n;
df     = fs / seg_n;
in_band = false(numel(freqs), numel(band_names));
for b = 1:numel(band_names)
    in_band(:, b) = freqs >= band_edges(b, 1) & freqs < band_edges(b, 2);
end
assert(all(any(in_band, 1)), 'A band in opts.bands contains no frequency bins');
seg_idx = bsxfun(@plus, (1:seg_n)', seg_st);        % sample indices of each segment, within a window

% RMS signal: the ECoG band-passed to opts.rms_band (high-pass then
% low-pass, butter_filtfilt.m), so movement and muscle activity above the
% band do not add to the amplitude. Artifact detection and band power use
% the unfiltered ECoG.
if isempty(opts.rms_band)
    rms_sig = ecog_uV;
else
    rms_sig = butter_filtfilt(ecog_uV, fs, opts.rms_band(1), 'high');
    rms_sig = butter_filtfilt(rms_sig, fs, opts.rms_band(2), 'low');
end

log_rms  = nan(n_win, 1);
log_rms_broadband = nan(n_win, 1);                  % RMS of the unfiltered ECoG, for comparison
max_abs  = nan(n_win, 1);                           % largest |sample| per window (uV)
artifact = false(n_win, 1);
log_bp   = nan(n_win, numel(band_names));
for w = 1:n_win
    seg = ecog_uV(starts(w):starts(w) + win_n - 1);
    seg = seg - mean(seg);                          % RMS after removing the mean = SD
    rseg = rms_sig(starts(w):starts(w) + win_n - 1);
    log_rms(w)  = log10(sqrt(mean((rseg - mean(rseg)).^2)));
    log_rms_broadband(w) = log10(sqrt(mean(seg.^2)));
    max_abs(w)  = max(abs(seg));
    assert(max_abs(w) > 1e-6, ['Flat signal (every sample equal) in the 10 s window starting at %.0f s: ' ...
        'check the recording (disconnected channel or dropped data?)'], t_start(w));
    artifact(w) = max_abs(w) > opts.artifact_uV;
    if ~artifact(w) % if thought to be artifact, default to nan
        S = seg(seg_idx);                           % segments as columns
        S = bsxfun(@minus, S, mean(S, 1)); % subtract mean before FFT
        F = fft(bsxfun(@times, S, hann_w));
        psd = abs(F(1:numel(freqs), :)).^2 / (fs * sum(hann_w.^2));
        psd(2:end - 1, :) = 2 * psd(2:end - 1, :);  % one-sided (DC and Nyquist once)
        psd = mean(psd, 2);                         % Welch average
        log_bp(w, :) = log10(sum(bsxfun(@times, psd, in_band), 1) * df);
    end
end
log_rms_all = log_rms;                              % before artifact removal (to try other limits later)
log_rms(artifact) = NaN;
log_rms_broadband(artifact) = NaN;

% Delta/theta (log10 of the power ratio)
id = find(strcmp(band_names, 'delta')); it = find(strcmp(band_names, 'theta'));
assert(numel(id) == 1 && numel(it) == 1, 'opts.bands must include delta and theta');
log_dt = log_bp(:, id) - log_bp(:, it);

%% 3. Spikes per window (NaN for artifact windows)
spike_t = opts.spike_t(:);
spike_count = nan(n_win, 1);
for w = 1:n_win
    if ~artifact(w)
        spike_count(w) = sum(spike_t >= t_start(w) & spike_t < t_end(w));
    end
end
spike_rate = spike_count / opts.win_s * 60;         % per minute

%% 4. Baseline
[base_start, base_end] = baseline_period(opts, sz_on);
is_base = t_start >= base_start & t_end <= base_end;   % windows entirely inside
n_clean = sum(is_base & ~artifact);
assert(n_clean >= opts.min_base_win, 'Only %d artifact-free baseline windows (need %d)', ...
    n_clean, opts.min_base_win);
base_clean_s = n_clean * opts.step_s;               % windows overlap: each adds one step
base_mean    = mean(log_rms(is_base & ~artifact));
base_mean_broadband = mean(log_rms_broadband(is_base & ~artifact));
base_bp      = mean(log_bp(is_base & ~artifact, :), 1);
base_dt      = mean(log_dt(is_base & ~artifact));
base_spike_rate = mean(spike_rate(is_base & ~artifact));

%% 5. Values relative to baseline in bins after offset
bin_edges      = opts.post_bins_s;
n_bins         = size(bin_edges, 1);
bin_ratio      = nan(1, n_bins);
bin_dt_ratio   = nan(1, n_bins);
bin_spike_rate = nan(1, n_bins);
bin_clean_frac = nan(1, n_bins);
for b = 1:n_bins
    lo = sz_off + bin_edges(b, 1);
    hi = sz_off + bin_edges(b, 2);
    if hi > dur, continue; end                      % recording ends before the bin does
    in_bin = t_start >= lo & t_end <= hi;           % windows entirely inside the bin
    if ~any(in_bin), continue; end
    v = log_rms(in_bin);
    bin_clean_frac(b) = mean(~isnan(v));
    if bin_clean_frac(b) >= opts.min_clean_frac
        ok = in_bin & ~artifact;
        bin_ratio(b)      = 10^(mean(log_rms(ok)) - base_mean);
        bin_dt_ratio(b)   = 10^(mean(log_dt(ok)) - base_dt);
        bin_spike_rate(b) = mean(spike_rate(ok));
    end
end

%% Output
out = struct('t_win', t_win, 't_start', t_start, 't_end', t_end, 'log_rms', log_rms, ...
    'log_rms_all', log_rms_all, 'log_rms_broadband', log_rms_broadband, ...
    'base_mean_broadband', base_mean_broadband, 'max_abs_uV', max_abs, 'artifact', artifact, ...
    'band_names', {band_names}, 'band_edges', band_edges, 'log_bp', log_bp, 'log_dt', log_dt, ...
    'spike_count', spike_count, 'spike_rate', spike_rate, ...
    'is_base', is_base, 'base_start', base_start, 'base_end', base_end, ...
    'base_clean_s', base_clean_s, 'base_mean', base_mean, 'base_bp', base_bp, 'base_dt', base_dt, ...
    'base_spike_rate', base_spike_rate, 'bin_edges', bin_edges, 'bin_ratio', bin_ratio, ...
    'bin_dt_ratio', bin_dt_ratio, 'bin_spike_rate', bin_spike_rate, ...
    'bin_clean_frac', bin_clean_frac, 'dur_s', dur, 'opts', opts);
if opts.plot
    plot_amplitude(ecog_uV, fs, sz_on, sz_off, out);
end
end

%% ------------------------------------------------------------------------
function plot_amplitude(ecog_uV, fs, sz_on, sz_off, out)
% Top: raw ECoG with the seizure shaded and spikes marked. Below: RMS /
% baseline, delta/theta / baseline (log axes) and spike rate per window,
% each with display smoothing, the baseline, heating start and seizure.
o = out.opts;
t = (0:numel(ecog_uV) - 1)' / fs;
figure('Color', 'w', 'Position', [100 50 1200 950]);

% Raw ECoG
ax1 = subplot(4, 1, 1); hold on
yl = [min(ecog_uV) max(ecog_uV)];
if yl(1) == yl(2), yl = yl + [-1 1]; end
patch([sz_on sz_off sz_off sz_on], yl([1 1 2 2]), [1 0.8 0.8], 'EdgeColor', 'none');
plot(t, ecog_uV, 'k', 'LineWidth', 0.25);
if ~isempty(o.spike_t)
    plot(o.spike_t, yl(2) * ones(numel(o.spike_t), 1), 'v', 'Color', [0 0.6 0], ...
        'MarkerSize', 3, 'MarkerFaceColor', [0 0.6 0]);
end
ylim(yl); xlim([0 t(end)]);
ylabel('ECoG (\muV)'); title([o.title_str sprintf('  (green: %d spikes)', numel(o.spike_t))], 'Interpreter', 'none'); box off

% RMS / baseline, with each bin's ratio as an orange bar
ax2 = subplot(4, 1, 2); hold on
plot_measure(out, out.log_rms - out.base_mean, true, sz_on, sz_off, t(end));
for b = 1:size(out.bin_edges, 1)
    if ~isnan(out.bin_ratio(b))
        plot(sz_off + out.bin_edges(b, :), out.bin_ratio(b) * [1 1], '-', 'Color', [0.85 0.4 0], 'LineWidth', 3);
    end
end
ylabel('RMS / baseline');
title(sprintf(['Blue: baseline; pink: seizure; dashed: heating start; orange: ratio per bin after offset ' ...
    '(0-60 s = %.2f); magenta: artifact'], out.bin_ratio(1)), 'FontWeight', 'normal');

% Delta/theta / baseline
ax3 = subplot(4, 1, 3); hold on
plot_measure(out, out.log_dt - out.base_dt, true, sz_on, sz_off, t(end));
ylabel('\delta/\theta / baseline');
title(sprintf('Delta (%g-%g Hz) / theta (%g-%g Hz) power, relative to baseline; 0-60 s = %.2f', ...
    out.band_edges(strcmp(out.band_names, 'delta'), :), out.band_edges(strcmp(out.band_names, 'theta'), :), ...
    out.bin_dt_ratio(1)), 'FontWeight', 'normal');

% Spike rate
ax4 = subplot(4, 1, 4); hold on
plot_measure(out, out.spike_rate, false, sz_on, sz_off, t(end));
plot([0 t(end)], out.base_spike_rate * [1 1], 'k:');
ylabel('Spikes / min'); xlabel('Time (s)');
title(sprintf('Spike rate; baseline %.1f / min, 0-60 s %.1f / min', out.base_spike_rate, out.bin_spike_rate(1)), ...
    'FontWeight', 'normal');

linkaxes([ax1 ax2 ax3 ax4], 'x');
set(findall(gcf, '-property', 'FontSize'), 'FontSize', o.font_size);
end

function plot_measure(out, y, is_log, sz_on, sz_off, t_end)
% One measure per window (dots) and its display moving average, computed
% separately before onset, during the seizure and after offset. is_log:
% y is log10 relative to baseline, drawn as 10.^y on a log axis.
o  = out.opts;
k  = max(1, round(o.smooth_s / o.step_s));
sm = nan(size(y));
pre  = out.t_end <= sz_on; post = out.t_start >= sz_off; mid = ~pre & ~post;
sm(pre)  = nanmovmean(y(pre),  k);
sm(post) = nanmovmean(y(post), k);
sm(mid)  = y(mid);
sm(out.artifact) = NaN;
if is_log
    yl = [0.05 5]; f = @(v) 10.^v; base = 1; art_y = 0.06;
else
    yl = [0 max([1; y(:)]) * 1.05]; f = @(v) v; base = NaN; art_y = 0.02 * yl(2);
end
patch([out.base_start out.base_end out.base_end out.base_start], yl([1 1 2 2]), [0.85 0.91 1], 'EdgeColor', 'none');
patch([sz_on sz_off sz_off sz_on], yl([1 1 2 2]), [1 0.85 0.85], 'EdgeColor', 'none');
h1 = plot(out.t_win, f(y), '.', 'Color', [0.6 0.6 0.6], 'MarkerSize', 6);
h2 = plot(out.t_win, f(sm), 'b-', 'LineWidth', 1.5);
if any(out.artifact)
    plot(out.t_win(out.artifact), art_y * ones(sum(out.artifact), 1), 'm.', 'MarkerSize', 8);
end
if ~isnan(base), plot([0 t_end], [base base], 'k:'); end
if ~isnan(o.heat_start), plot(o.heat_start * [1 1], yl, 'k--'); end
if is_log, set(gca, 'YScale', 'log'); end
ylim(yl); xlim([0 t_end]); box off
legend([h1 h2], {'10 s windows', sprintf('%g s moving average (display)', o.smooth_s)}, 'Location', 'northeast');
end
