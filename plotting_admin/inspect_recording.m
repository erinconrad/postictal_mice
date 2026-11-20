function fig = inspect_recording(sheet_row)
% INSPECT_RECORDING  Scrollable check of one recording's measurements: a
% 10 s ECoG page that is exactly one analysis window, with its spike
% detections and its values, above the whole recording's spectrogram,
% amplitude, slowing and spike rate. Every value shown is the batch's own
% (postictal_results.mat), so it can be compared with
% postictal_results.csv and the per_animal.csv depths. Run
% run_postictal_batch first; needs the raw data.
%
%   inspect_recording(52)          % spreadsheet row
%
% Top left: notch-filtered ECoG for one 10 s analysis window (batch window
%   k: o.t_start(k) to o.t_end(k)); red circles = spike detections;
%   dashed lines = heating start (blue), onset (red), offset (blue);
%   grey background = the window is artifact.
% Top right: that window's values (RMS, delta, theta, delta/theta, spikes),
%   each also relative to the baseline mean, and the recording's depth
%   after offset for 0-1, 0-2 and 0-5 min (depth_window.m, as in
%   per_animal.csv).
% Below, the whole recording, x = minutes from recording start:
%   spectrogram (dB relative to baseline, white = baseline; dashed lines =
%   delta and theta bands), RMS / baseline, delta/theta / baseline, and
%   spikes/min minus baseline, one dot per window. Blue shading = baseline
%   windows, yellow = seizure (or pseudo-seizure), grey = artifact. The red
%   band = the window shown at the top.
%
% Keys (click the figure first)
%   right / left    next / previous window (5 s step, as the analysis)
%   page down / up  1 min forward / back
%   up / down       gain: zoom the ECoG in / out
%   o / f           jump to the window starting at onset / offset
%   h / b           jump to heating start / start of the baseline
%   click on any of the lower panels: jump to that time

%% 1. Load the recording
addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();
cfg = analysis_config();
B = load(fullfile(cfg.out_root, 'postictal_batch', 'postictal_results.mat'), 'res', 'outs');
i = find([B.res.sheet_row] == sheet_row, 1);
assert(~isempty(i), 'Row %d is not in the batch results', sheet_row);
r = B.res(i);
assert(~ismember(r.status, {'error', 'skipped'}), 'Row %d was not analysed: %s', sheet_row, r.message);
o = B.outs{i};
rows = prepare_rows(cfg);
L = load_row_ecog(rows([rows.sheet_row] == sheet_row), cfg.data_root, cfg.ecog_multi, cfg.notch);
assert(isempty(L.err_msg) && isempty(L.skip_msg), 'Could not load row %d: %s%s', sheet_row, L.err_msg, L.skip_msg);

% st = everything the callbacks need, stored in the figure (UserData)
st = struct();
st.r = r; st.o = o; st.cfg = cfg;
st.sig = double(L.ecog(:)); st.fs = L.fs;
st.k = 1;                                          % window shown
st.half_range_uV = 500;                            % ECoG y axis: +/- this
st.depth_text = depth_table(o, r, cfg);

%% 2. Figure and the five axes ([left bottom width height], figure fractions)
fig = figure('Color', 'w', 'Position', [40 40 1400 860], 'Name', ...
    sprintf('Row %d: mouse %d (%s, %s)', r.sheet_row, r.mouse_id, r.project, r.group), 'NumberTitle', 'off', ...
    'KeyPressFcn', @on_key, 'WindowButtonDownFcn', @on_click);
st.ax_ecog = axes('Position', [0.06 0.64 0.60 0.31]);
st.info = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', 'Position', [0.68 0.60 0.31 0.38], ...
    'HorizontalAlignment', 'left', 'FontName', 'Courier', 'FontSize', 11, 'BackgroundColor', 'w');
st.ax_full = [axes('Position', [0.06 0.43 0.88 0.12]), axes('Position', [0.06 0.30 0.88 0.10]), ...
    axes('Position', [0.06 0.17 0.88 0.10]), axes('Position', [0.06 0.04 0.88 0.10])];

%% 3. Whole-recording panels (drawn once)
to_min = @(t) t / 60;
% 3a. Spectrogram, as Figure 1B
ax = st.ax_full(1); axes(ax); hold on %#ok<LAXES>
[t_spec, freqs, power_db] = spectrogram_vs_baseline(st.sig, st.fs, o, [1 30]);
clim = [-20 10];
h_img = imagesc(to_min(t_spec), freqs, power_db);
set(h_img, 'AlphaData', double(~isnan(power_db)));
set(ax, 'YDir', 'normal', 'CLim', clim, 'Color', [0.8 0.8 0.8]);
colormap(ax, blue_white_red(256, clim));
for band = {'delta', 'theta'}
    for e = cfg.bands{strcmp(cfg.bands(:, 1), band{1}), 2}
        plot(to_min([0 o.dur_s]), [e e], '--', 'Color', [0.2 0.2 0.2]);
    end
end
ylim([1 30]); ylabel('Hz'); title('Spectrogram, dB vs baseline (-20 to +10; white = baseline)', 'FontWeight', 'normal');

% 3b-d. RMS, delta/theta, spike rate relative to baseline, one dot per window
measures = {'rms', 'delta_theta', 'spike_rate'};
titles = {'RMS / baseline', '\delta/\theta / baseline', 'Spikes/min - baseline'};
for m = 1:3
    ax = st.ax_full(1 + m); axes(ax); hold on %#ok<LAXES>
    [om, M] = measure_view(o, measures{m});
    y = om.value - om.base_value;
    if M.is_log, y = 10 .^ y; baseline_level = 1; else, baseline_level = 0; end
    good = y(~isnan(y));
    if M.is_log
        yl = [min([good; 0.5]) / 1.2, max([good; 2]) * 1.2];
    else
        yl = [min([good; -1]) - 1, max([good; 5]) + 1];
    end
    shade_spans(ax, [o.base_start o.base_end], yl, [0.85 0.91 1]);
    shade_spans(ax, [r.sz_on r.sz_off], yl, [1 0.93 0.55]);
    shade_spans(ax, artifact_spans(o), yl, [0.85 0.85 0.85]);
    plot(to_min(o.t_win), y, '.', 'Color', [0.2 0.2 0.2], 'MarkerSize', 7);
    plot(to_min([0 o.dur_s]), [baseline_level baseline_level], 'k:');
    if M.is_log, use_log_axis(ax, 'Y', yl); else, ylim(yl); end
    title(titles{m}, 'FontWeight', 'normal');
end
xlabel(st.ax_full(4), 'Time from recording start (min)');
st.cursor = cell(1, numel(st.ax_full));             % red band marking the window shown
for c = 1:numel(st.ax_full)
    ax = st.ax_full(c);
    xlim(ax, to_min([0 o.dur_s]));
    yl = get(ax, 'YLim');
    plot(ax, to_min(r.heat_start) * [1 1], yl, 'b--');   % heating start
    st.cursor{c} = patch(ax, [0; 0; 0; 0], yl([1; 1; 2; 2]), [1 0 0], ...
        'EdgeColor', [0.8 0 0], 'FaceAlpha', 0.25, 'HitTest', 'off');
    set(get(ax, 'Children'), 'HitTest', 'off');      % clicks go to the axes (on_click)
    set(ax, 'Box', 'off');
end
set(st.ax_full(1:3), 'XTickLabel', []);
linkaxes(st.ax_full, 'x');

set(fig, 'UserData', st);
redraw(fig);
end

%% ------------------------------------------------------------------------
function redraw(fig)
% Draw the ECoG page for window st.k, move the red band, update the values
st = get(fig, 'UserData');
o = st.o; r = st.r; k = st.k;
t0 = o.t_start(k); t1 = o.t_end(k);

% ECoG page
ax = st.ax_ecog; cla(ax); hold(ax, 'on');
yl = st.half_range_uV * [-1 1];
if o.artifact(k)
    patch(ax, [t0 t1 t1 t0], yl([1 1 2 2]), [0.85 0.85 0.85], 'EdgeColor', 'none');
end
samples = max(1, round(t0 * st.fs) + 1):min(numel(st.sig), round(t1 * st.fs));
plot(ax, (samples - 1) / st.fs, st.sig(samples), 'k', 'LineWidth', 0.5);
for t_line = ceil(t0):floor(t1)                    % 1 s markings
    plot(ax, [t_line t_line], yl, ':', 'Color', [0.6 0.6 0.6]);
end
events = {r.heat_start, 'heating', [0 0 0.8]; r.sz_on, 'onset', [0.8 0 0]; r.sz_off, 'offset', [0 0 0.8]};
for e = 1:size(events, 1)
    if events{e, 1} >= t0 && events{e, 1} <= t1
        plot(ax, events{e, 1} * [1 1], yl, '--', 'Color', events{e, 3}, 'LineWidth', 1.5);
        text(ax, events{e, 1}, yl(2), [' ' events{e, 2}], 'Color', events{e, 3}, 'VerticalAlignment', 'top');
    end
end
spike_t = o.spikes.t(:);
spike_t = spike_t(spike_t >= t0 & spike_t < t1);   % as the batch counts them
spike_y = st.sig(min(numel(st.sig), round(spike_t * st.fs) + 1));
plot(ax, spike_t, min(max(spike_y, yl(1)), yl(2)), 'o', 'Color', [0.85 0.1 0.1], 'MarkerSize', 9, 'LineWidth', 1.5);
xlim(ax, [t0 t1]); ylim(ax, yl);
xlabel(ax, 'Time from recording start (s)'); ylabel(ax, 'ECoG (\muV)');
title(ax, sprintf('Window %d of %d: %.0f-%.0f s (%s)   [arrows: scroll / gain; o f h b: jump; click below]', ...
    k, numel(o.t_start), t0, t1, where_text(t0, t1, r, o)), 'FontWeight', 'normal');

% Red band on the lower panels
for c = 1:numel(st.cursor)
    set(st.cursor{c}, 'XData', [t0; t1; t1; t0] / 60);
end

% Values for this window
set(st.info, 'String', [window_text(o, k, numel(spike_t)); {''}; st.depth_text(:)]);
end

function lines = window_text(o, k, n_spikes_shown)
% This window's batch values, as numbers and relative to baseline
it = find(strcmp(o.band_names, 'theta')); id = find(strcmp(o.band_names, 'delta'));
if o.artifact(k)
    lines = {sprintf('ARTIFACT (max |x| = %.0f uV):', o.max_abs_uV(k)); 'left out of every measure'};
    return
end
lines = {
    'This window (batch values)'
    sprintf('RMS       %8.1f uV     %5.2fx baseline', 10^o.log_rms(k), 10^(o.log_rms(k) - o.base_mean))
    sprintf('delta     %8.0f uV^2   %5.2fx', 10^o.log_bp(k, id), 10^(o.log_bp(k, id) - o.base_bp(id)))
    sprintf('theta     %8.0f uV^2   %5.2fx', 10^o.log_bp(k, it), 10^(o.log_bp(k, it) - o.base_bp(it)))
    sprintf('delta/th  %8.2f        %5.2fx', 10^o.log_dt(k), 10^(o.log_dt(k) - o.base_dt))
    sprintf('spikes    %3d = %4.1f/min  %+5.1f vs baseline', o.spike_count(k), o.spike_rate(k), ...
        o.spike_rate(k) - o.base_spike_rate)
    };
if o.is_base(k), lines{end + 1} = '(baseline window)'; end
if n_spikes_shown ~= o.spike_count(k)
    lines{end + 1} = sprintf('(%d spikes drawn; check)', n_spikes_shown);
end
end

function lines = depth_table(o, r, cfg)
% The recording's depth after offset for every measure and window
% (depth_window.m), as in per_animal.csv
lines = {sprintf('Depth after offset  %s', strjoin(arrayfun(@(w) sprintf('0-%gmin', w / 60), ...
    cfg.depth_windows_s, 'UniformOutput', false), '  '))};
names = {'rms', 'RMS'; 'delta_theta', 'delta/th'; 'spike_rate', 'spikes'; 'delta', 'delta'; 'theta', 'theta'};
for m = 1:size(names, 1)
    om = measure_view(o, names{m, 1});
    vals = arrayfun(@(w) depth_window(om, r.sz_off, w), cfg.depth_windows_s);
    lines{end + 1} = sprintf('%-18s %s', names{m, 2}, sprintf('%7.2f', vals)); %#ok<AGROW>
end
lines{end + 1} = sprintf('Baseline %.0f-%.0f s; RMS %.1f uV', o.base_start, o.base_end, 10^o.base_mean);
end

function s = where_text(t0, t1, r, o)
% Where the window sits relative to the seizure
if t1 <= r.sz_on
    s = sprintf('%.0f s before onset', r.sz_on - t1);
elseif t0 >= r.sz_off
    s = sprintf('%.0f-%.0f s after offset', t0 - r.sz_off, t1 - r.sz_off);
else
    s = 'overlaps the seizure';
end
if t0 >= o.base_start && t1 <= o.base_end, s = [s ', baseline']; end
end

function on_key(fig, evt)
% Keyboard: scroll, gain, jumps
st = get(fig, 'UserData');
o = st.o; n = numel(o.t_start);
per_min = round(60 / o.opts.step_s);               % windows per minute
switch evt.Key
    case 'rightarrow', st.k = st.k + 1;
    case 'leftarrow',  st.k = st.k - 1;
    case 'pagedown',   st.k = st.k + per_min;
    case 'pageup',     st.k = st.k - per_min;
    case 'uparrow',    st.half_range_uV = st.half_range_uV / 1.5;
    case 'downarrow',  st.half_range_uV = st.half_range_uV * 1.5;
    case 'o', st.k = first_window_from(o, st.r.sz_on);
    case 'f', st.k = first_window_from(o, st.r.sz_off);
    case 'h', st.k = first_window_from(o, st.r.heat_start);
    case 'b', st.k = first_window_from(o, o.base_start);
    otherwise, return
end
st.k = min(max(st.k, 1), n);
set(fig, 'UserData', st);
redraw(fig);
end

function on_click(fig, ~)
% Click on a lower panel: show the window centred nearest that time
st = get(fig, 'UserData');
ax = get(fig, 'CurrentAxes');
if ~any(ax == st.ax_full), return; end
pt = get(ax, 'CurrentPoint');
[~, st.k] = min(abs(st.o.t_win - pt(1, 1) * 60));
set(fig, 'UserData', st);
redraw(fig);
end

function k = first_window_from(o, t)
% First window starting at or after time t (s)
k = find(o.t_start >= t, 1);
if isempty(k), k = numel(o.t_start); end
end

function shade_spans(ax, spans, yl, col)
% Shaded bands for each [start end] row (s), on an axis in minutes
for k = 1:size(spans, 1)
    patch(ax, spans(k, [1 2 2 1]) / 60, yl([1 1 2 2]), col, 'EdgeColor', 'none');
end
end
