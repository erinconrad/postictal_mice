function make_figures(varargin)
% MAKE_FIGURES  All paper and supplementary figures. Run analyze_primary
% for each measure first:
%   analyze_primary; analyze_primary('delta_theta'); analyze_primary('spike_rate');
%   analyze_primary('delta'); analyze_primary('theta')
% Figure 1 also reads the example recording's raw ECoG (needs the data
% folder).
%
%   make_figures
%   make_figures('example_mouse', 3697)      % choose the example seizure by mouse ID
%   make_figures('example_row', 52)          % ... or by spreadsheet row
%   (other options as name-value pairs: see section 1)
%
% Figure 1. Methods: one example seizure (drawn here)
%   A  raw ECoG (notch-filtered), y axis +/- 750 uV; detected spikes
%      outside the seizure marked (green). Onset/offset dashed.
%   B  spectrogram, 1-30 Hz, power relative to each frequency's baseline
%      mean (dB); the delta (1-4 Hz) and theta (6-10 Hz) bands are marked.
%   C  RMS / baseline
%   D  delta/theta power / baseline delta/theta
%   E  spike rate minus the baseline rate (spikes/min)
%   All panels share the x axis: minutes from seizure onset, -2 to +5
%   (opts.fig1_window_min). C-E: 10 s windows every 5 s (dots) and their
%   30 s moving average (line); the seizure shaded yellow (its values are
%   not drawn, so they don't set the y axis). B-E: grey = 10 s windows
%   left out as artifact (any sample beyond cfg.artifact_uV).
% Figure 2. Depth over 0-5 min after (pseudo-)offset, Control vs DS seizure
%   (make_depth_figure.m)
% Figure 3. The three measures in 30 s bins, 4 min before onset and 10 min
%   after offset (make_bin_figure.m)
% Figure S1. Raw ECoG 60-75 s after offset in 10 randomly chosen
%   DS seizure mice, with every spike detection (make_spike_examples_figure.m)
% Figure S2. As Figure 2, WT vs DS no seizure, with effect sizes
% Figure S3. As Figure 2, delta and theta power separately, with effect sizes
% Figure S4. As Figure 3, delta and theta power separately
% Figure S5. DS seizure mice, depth over 0-5 min vs seizure duration, age,
%   sex, and seizure 1 vs 2 (make_covariate_figure.m)
%
% The example seizure (Figure 1): mouse 3697 by default: abnormal on all
% three measures, no artifact windows in the 7 minutes shown. Choose
% another with 'example_mouse' or 'example_row'. With
% make_figures('example_mouse', NaN): among DS
% seizures no longer than the median seizure and with at least
% opts.example_min_after_s (600 s) recorded after offset, the one whose RMS depth over 0-5 min
% is closest to the median of all DS seizures (a typical seizure).
%
% Outputs in <output>/figures/ (.png at 300 dpi and .pdf, plus the CSV
% files written by each figure function).

%% 1. Settings and inputs
addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();   % scripts folder and its subfolders
opts = struct();
opts.example_mouse = 3697;        % Figure 1: mouse ID of the example (EEG_NRI; its primary-cohort seizure)
opts.example_row  = NaN;          % or a spreadsheet row instead (overrides example_mouse)
opts.fig1_window_min = [-2 5];    % Figure 1: x axis, minutes from seizure onset (all panels)
opts.example_min_after_s = 600;   % automatic example: at least this much recorded after offset (s)
opts.fig1a_ylim   = [-750 750];   % Figure 1A: y axis (uV); the seizure may be cut off
opts.spec_clim_db = [-20 10];     % Figure 1B: colour range (dB relative to baseline; white = 0 dB)
opts.font_size    = 20;
for k = 1:2:numel(varargin)
    assert(isfield(opts, varargin{k}), 'Unknown option %s', varargin{k});
    opts.(varargin{k}) = varargin{k + 1};
end
cfg = analysis_config();
out_dir = fullfile(cfg.out_root, 'figures');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

% RMS results (analyze_primary.m), for choosing the example; the other
% figures load what they need themselves
[~, M_rms] = measure_view([], 'rms');
A = load(fullfile(cfg.out_root, M_rms.out_dir, 'primary_analysis.mat'), 'pa');
depth_field = sprintf('depth_0_%ds', cfg.depth_main_s);
assert(isfield(A.pa, depth_field), 'primary_analysis.mat is from an older version: re-run analyze_primary');
% Batch results: every recording's windowed values and spike times
R = load(fullfile(cfg.out_root, 'postictal_batch', 'postictal_results.mat'), 'res', 'outs');

%% 2. Choose the example seizure (Figure 1)
if ~isnan(opts.example_row)
    example_row = opts.example_row;
    assert(ismember(example_row, [A.pa.sheet_row]), 'Row %d is not in the primary cohort', example_row);
elseif ~isnan(opts.example_mouse)
    k = find([A.pa.mouse_id] == opts.example_mouse);
    assert(numel(k) == 1, 'Mouse %d has %d recordings in the primary cohort; use example_row', ...
        opts.example_mouse, numel(k));
    example_row = A.pa(k).sheet_row;
else
    pa = A.pa(strcmp({A.pa.group}, 'DS seizure'));
    depth  = [pa.(depth_field)];
    sz_dur = [pa.sz_dur_s];
    % recorded time after offset, from the batch results
    recorded_after = nan(size(pa));
    for k = 1:numel(pa)
        i = find([R.res.sheet_row] == pa(k).sheet_row, 1);
        recorded_after(k) = R.outs{i}.t_end(end) - R.res(i).sz_off;
    end
    candidates = find(sz_dur <= median(sz_dur) & recorded_after >= opts.example_min_after_s & ~isnan(depth));
    assert(~isempty(candidates), 'No candidate example seizure; set example_row');
    [~, j] = min(abs(depth(candidates) - median(depth(~isnan(depth)))));
    example_row = pa(candidates(j)).sheet_row;
end
% r = the example's batch row (onset, offset, heating start, ...);
% o_ex = its window values (window_amplitude.m), including spike times
i_ex = find([R.res.sheet_row] == example_row, 1);
r = R.res(i_ex); o_ex = R.outs{i_ex};
fprintf('Example: row %d, mouse %d (%s), seizure %.0f s\n', r.sheet_row, r.mouse_id, r.project, r.sz_off - r.sz_on);
write_results_csv(struct('sheet_row', r.sheet_row, 'mouse_id', r.mouse_id, 'project', r.project, ...
    'sz_dur_s', r.sz_off - r.sz_on), fullfile(out_dir, 'figure1_example.csv'));   % for make_results_report

%% 3. Draw and save every figure without opening windows
% The figures are taller than a laptop screen; on macOS, MATLAB can hang
% while the system resizes such a window. Hidden figures print the same.
% Each figure is closed once saved (close_new_figures, below). The
% default is restored when make_figures ends, even after an error.
old_visible = get(0, 'DefaultFigureVisible');
set(0, 'DefaultFigureVisible', 'off');
restore_visible = onCleanup(@() set(0, 'DefaultFigureVisible', old_visible));
open_before = findall(0, 'Type', 'figure');           % figures you already had open: left alone

draw_figure1(r, o_ex, cfg, opts, out_dir);
close_new_figures(open_before);

% The other figures (each saves itself)
make_depth_figure('file_name', 'figure2', 'font_size', opts.font_size);
close_new_figures(open_before);
make_bin_figure('file_name', 'figure3', 'font_size', opts.font_size);
close_new_figures(open_before);
make_spike_examples_figure('file_name', 'figureS1_spike_examples');   % reads raw ECoG for 10 mice
close_new_figures(open_before);
make_depth_figure('compare', 'dsno_vs_wt', 'show_effect', true, 'file_name', 'figureS2_control_groups', ...
    'font_size', opts.font_size);
close_new_figures(open_before);
band_names = {'Delta (1-4 Hz)', 'Theta (6-10 Hz)'};
make_depth_figure('measures', {'delta', 'theta'}, 'names', band_names, 'show_effect', true, ...
    'file_name', 'figureS3_delta_theta', 'font_size', opts.font_size);
close_new_figures(open_before);
make_bin_figure('measures', {'delta', 'theta'}, 'names', band_names, 'file_name', 'figureS4_delta_theta_bins', ...
    'font_size', opts.font_size);
close_new_figures(open_before);
make_covariate_figure('file_name', 'figureS5_clinical');
close_new_figures(open_before);
fprintf('Written to %s (open the .png or .pdf files to view)\n', out_dir);
end

%% ------------------------------------------------------------------------
function close_new_figures(open_before)
% Close every figure that was not open when make_figures started
close(setdiff(findall(0, 'Type', 'figure'), open_before));
end

%% ------------------------------------------------------------------------
function draw_figure1(r, o_ex, cfg, opts, out_dir)
% Figure 1 for the example recording: r = its batch results row, o_ex = its
% window values (window_amplitude.m)

% 1. Raw ECoG (notch-filtered, as in the batch)
rows = prepare_rows(cfg);
L = load_row_ecog(rows([rows.sheet_row] == r.sheet_row), cfg.data_root, cfg.ecog_multi, cfg.notch);
assert(isempty(L.err_msg) && isempty(L.skip_msg), 'Could not load the example: %s%s', L.err_msg, L.skip_msg);
sig = double(L.ecog(:)); fs = L.fs;

% 2. Layout. Every panel shares the x axis: minutes from seizure onset,
%    opts.fig1_window_min (default -5 to +5). Positions are [left bottom
%    width height] as fractions of the figure.
x0 = opts.fig1_window_min(1); x1 = opts.fig1_window_min(2);
to_x = @(t) (t - r.sz_on) / 60;                     % s from recording start -> x (min from onset)
fig = figure('Color', 'w', 'Position', [60 20 1150 1650]);
positions = {[0.15 0.80 0.68 0.15], ...             % A
             [0.15 0.61 0.68 0.15], ...             % B
             [0.15 0.435 0.68 0.13], [0.15 0.26 0.68 0.13], [0.15 0.085 0.68 0.13]};   % C, D, E
seizure_yellow = [1 0.93 0.55]; baseline_blue = [0.85 0.91 1];
all_axes = zeros(1, 5);

% 3. Panel A: raw ECoG, onset/offset dashed, detected spikes outside the
%    seizure as green triangles
all_axes(1) = axes('Position', positions{1}); hold on
samples = max(1, round((r.sz_on + x0 * 60) * fs) + 1):min(numel(sig), round((r.sz_on + x1 * 60) * fs));
plot(to_x((samples - 1) / fs), sig(samples), 'k', 'LineWidth', 0.5);
yl = opts.fig1a_ylim;
plot([0 0], yl, '--', 'Color', [0.8 0 0], 'LineWidth', 1.5);
plot(to_x(r.sz_off) * [1 1], yl, '--', 'Color', [0 0 0.8], 'LineWidth', 1.5);
text(0, yl(2), 'onset ', 'Color', [0.8 0 0], 'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'right');
text(to_x(r.sz_off), yl(2), ' offset', 'Color', [0 0 0.8], 'VerticalAlignment', 'bottom');
spike_x = to_x(o_ex.spikes.t(:));
show = spike_x >= x0 & spike_x <= x1 & (o_ex.spikes.t(:) < r.sz_on | o_ex.spikes.t(:) > r.sz_off);
plot(spike_x(show), 0.88 * yl(2) * ones(sum(show), 1), 'v', 'Color', [0 0.6 0], ...
    'MarkerFaceColor', [0 0.6 0], 'MarkerSize', 7);
ylim(yl); ylabel('ECoG (\muV)');

% 4. Panel B: spectrogram relative to baseline (spectrogram_vs_baseline,
%    below); the delta and theta bands are marked with dashed lines and
%    labelled just right of the panel, left of the colour bar
all_axes(2) = axes('Position', positions{2}); hold on
[t_spec, freqs, power_db] = spectrogram_vs_baseline(sig, fs, o_ex, [1 30]);
h_img = imagesc(to_x(t_spec), freqs, power_db);
set(h_img, 'AlphaData', double(~isnan(power_db)));          % artifact windows blank
artifact_grey = [0.8 0.8 0.8];
set(all_axes(2), 'YDir', 'normal', 'CLim', opts.spec_clim_db, 'Color', artifact_grey);   % artifact windows show grey
colormap(all_axes(2), blue_white_red(256, opts.spec_clim_db));   % white = baseline
for band = {'delta', '\delta'; 'theta', '\theta'}'
    edges = cfg.bands{strcmp(cfg.bands(:, 1), band{1}), 2};
    for e = edges
        plot([x0 x1], [e e], '--', 'Color', [0.2 0.2 0.2], 'LineWidth', 1.2);
    end
    text(x1, mean(edges), [' ' band{2}], 'VerticalAlignment', 'middle', 'FontWeight', 'bold', 'Tag', 'band_label');
end
ylim([1 30]); ylabel('Frequency (Hz)');
cbar = colorbar(all_axes(2));
set(all_axes(2), 'Position', positions{2});          % undo the shrinking, so all panels line up
p = positions{2};
set(cbar, 'Position', [p(1) + p(3) + 0.045, p(2), 0.015, p(4)]);   % leave room for the band labels
ylabel(cbar, 'dB vs baseline');

% 5. Panels C-E: one measure each. Dots = 10 s windows every 5 s; line =
%    30 s moving average (smoothed_timecourse.m), on a 5 s grid. Values
%    during the seizure are not drawn (they would set the y axis).
measures = {'rms', 'delta_theta', 'spike_rate'};
names    = {'Amplitude', 'Slowing', 'Spiking'};
for m = 1:3
    [o, M] = measure_view(o_ex, measures{m});        % value - base_value: log10 ratio or difference
    y = to_plot_scale(o.value - o.base_value, M.is_log);
    t_grid = r.sz_on + (x0 * 60:o.opts.step_s:x1 * 60);
    y_smooth = to_plot_scale(smoothed_timecourse(o, r.sz_on, r.sz_off, t_grid, round(30 / o.opts.step_s)), M.is_log);
    y(o.t_end > r.sz_on & o.t_start < r.sz_off) = NaN;
    y_smooth(t_grid > r.sz_on & t_grid < r.sz_off) = NaN;

    all_axes(2 + m) = axes('Position', positions{2 + m}); hold on
    in_view = to_x(o.t_win) >= x0 & to_x(o.t_win) <= x1;
    yl = fig_ylim(M.is_log, [y(in_view); y_smooth(:)]);
    shade(to_x(o.base_start), to_x(o.base_end), yl, baseline_blue);   % only if in view
    spans = artifact_spans(o);                        % artifact windows, merged where they overlap
    for k = 1:size(spans, 1)
        shade(to_x(spans(k, 1)), to_x(spans(k, 2)), yl, artifact_grey);
    end
    shade(0, to_x(r.sz_off), yl, seizure_yellow);
    plot(to_x(o.t_win), y, '.', 'Color', [0.65 0.65 0.65], 'MarkerSize', 9);
    plot(to_x(t_grid), y_smooth, 'k-', 'LineWidth', 2.5);
    baseline_level = to_plot_scale(0, M.is_log);      % 1 for ratios, 0 for spike rate
    plot([x0 x1], [baseline_level baseline_level], 'k:');
    heat_x = to_x(r.heat_start);
    if heat_x > x0                                    % heating start, if within the window
        plot([heat_x heat_x], yl, 'k--');
        if m == 1, text(heat_x, yl(2), ' heating on', 'VerticalAlignment', 'top'); end
    end
    if M.is_log, use_log_axis(gca, 'Y', yl); else, ylim(yl); end
    ylabel(M.label);
    text(0.01, 1.02, names{m}, 'Units', 'normalized', 'VerticalAlignment', 'bottom');
end

% 6. Shared x axis; tick labels and x label on the bottom panel only
linkaxes(all_axes, 'x');
xlim(all_axes(1), [x0 x1]);
set(all_axes, 'Box', 'off');
set(all_axes(1:4), 'XTickLabel', []);
xlabel(all_axes(5), 'Time from seizure onset (min)');
set_fonts(fig, opts.font_size);
set(findall(fig, 'Tag', 'band_label'), 'FontSize', opts.font_size + 8);   % delta/theta labels larger

% 7. Panel letters in figure coordinates, left of each panel's top-left
%    corner (letters placed relative to the axes drift once the axes are
%    linked and rescaled). Added after set_fonts so they stay larger.
for k = 1:5
    p = positions{k};
    annotation(fig, 'textbox', [p(1) - 0.11, p(2) + p(4) - 0.03, 0.04, 0.04], 'String', char('A' + k - 1), ...
        'EdgeColor', 'none', 'FontWeight', 'bold', 'FontSize', opts.font_size + 6, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', 'Margin', 1);
end

% 8. Save
print(fig, fullfile(out_dir, 'figure1.png'), '-dpng', '-r300');
print(fig, fullfile(out_dir, 'figure1.pdf'), '-dpdf', '-painters', '-bestfit');
end

function shade(x0, x1, yl, col)
% Shaded vertical band from x0 to x1
patch([x0 x1 x1 x0], yl([1 1 2 2]), col, 'EdgeColor', 'none');
end

function y = to_plot_scale(d, is_log)
% A measure relative to baseline (value - base_value) on its plotted
% scale: ratio = 10^d for log measures (d = 0 gives 1 = baseline);
% spike-rate difference unchanged
if is_log, y = 10 .^ d; else, y = d; end
end

function yl = fig_ylim(is_log, y)
% y-axis limits from the values shown: ratios on a log axis (at least
% 0.5-2), spike rate on a linear axis (at least -1 to 5)
y = y(isfinite(y));
if is_log
    y = y(y > 0);
    if isempty(y), y = 1; end
    yl = [min(0.5, min(y) / 1.3), max(2, max(y) * 1.3)];
else
    if isempty(y), y = 0; end
    data_range = max(max(y) - min(y), 1);
    yl = [min(-1, min(y) - 0.08 * data_range), max(5, max(y) + 0.15 * data_range)];
end
end
