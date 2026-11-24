function make_figures(varargin)
% MAKE_FIGURES  All paper and supplementary figures. Run analyze_primary
% for each measure first:
%   analyze_primary; analyze_primary('delta_alpha'); analyze_primary('spike_rate');
%   analyze_primary('delta'); analyze_primary('alpha')
% Figure 1 also reads the example recording's raw ECoG (needs the data
% folder).
%
%   make_figures
%   make_figures('example_mouse', [3697 1779])   % the example seizures, by mouse ID (one column each)
%   make_figures('example_row', [52 7])          % ... or by spreadsheet row
%   make_figures('example_row', 163, 'fig1_file', 'figure1_row163', 'only_figure1', true)
%                                                % one extra Figure 1-style plot (also controls), nothing else
%   (other options as name-value pairs: see section 1)
%
% Figure 1. Example seizures, one column each (drawn here; default two:
%   mice 3697 and 1779, both with post-ictal suppression, slowing and
%   spiking). Left column panels A-E, right column F-J. Both columns
%   share every y axis and the colour scale.
%   A  raw ECoG (notch-filtered), y axis +/- 750 uV; detected spikes
%      outside the seizure marked (green). Onset/offset dashed.
%   B  spectrogram, 1-30 Hz, power relative to each frequency's baseline
%      mean (dB); the two bands of the slowing ratio (cfg.slowing) are marked.
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
% Figure S3. As Figure 2, the two bands of the slowing ratio (delta and alpha)
%   separately, with effect sizes
% Figure S4. As Figure 3, absolute power in each frequency band (delta,
%   theta, alpha, beta, gamma; cfg.bands), each relative to its baseline
% Figure S5. DS seizure mice, depth over 0-5 min vs seizure duration, age,
%   sex, and seizure 1 vs 2 (make_covariate_figure.m)
%
% The example seizures (Figure 1): mice 3697 and 1779 by default, neither
% with artifact windows in the 7 minutes shown. Amplitude in the first
% minute after offset: 3697 0.28 x baseline, 1779 0.54 x (near the group
% median), with isolated large spikes. Mouse 5532 (0.08 x) is a strongly
% suppressed alternative. Choose others with
% 'example_mouse' or 'example_row' (any number of columns). With
% make_figures('example_mouse', NaN): one column, the DS seizure (no
% longer than the median seizure, at least opts.example_min_after_s
% recorded after offset) whose RMS depth over 0-5 min is closest to the
% group median (a typical seizure).
%
% Outputs in <output>/figures/ (.png at 300 dpi and .svg, plus the CSV
% files written by each figure function).

%% 1. Settings and inputs
addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();   % scripts folder and its subfolders
opts = struct();
opts.example_mouse = [3697 1779]; % Figure 1: mouse IDs of the examples, one column each (their primary-cohort seizures)
opts.example_row  = NaN;          % or spreadsheet rows instead (overrides example_mouse)
opts.fig1_window_min = [-2 5];    % Figure 1: x axis, minutes from seizure onset (all panels)
opts.example_min_after_s = 600;   % automatic example: at least this much recorded after offset (s)
opts.fig1a_ylim   = [-750 750];   % Figure 1A: y axis (uV); the seizure may be cut off
opts.spec_clim_db = [-20 10];     % Figure 1B: colour range (dB relative to baseline; white = 0 dB)
opts.font_size    = 20;
opts.fig1_file    = 'figure1';    % Figure 1 file name (figure1_example.csv is written only for 'figure1')
opts.only_figure1 = false;        % true: draw Figure 1 only (e.g. an extra example), no other figures
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

%% 2. Choose the example seizures (Figure 1), one column each
if ~all(isnan(opts.example_row))
    example_row = opts.example_row;
    for j = 1:numel(example_row)
        assert(ismember(example_row(j), [A.pa.sheet_row]), 'Row %d is not in the primary cohort', example_row(j));
    end
elseif ~all(isnan(opts.example_mouse))
    example_row = zeros(size(opts.example_mouse));
    for j = 1:numel(opts.example_mouse)
        k = find([A.pa.mouse_id] == opts.example_mouse(j));
        assert(numel(k) == 1, 'Mouse %d has %d recordings in the primary cohort; use example_row', ...
            opts.example_mouse(j), numel(k));
        example_row(j) = A.pa(k).sheet_row;
    end
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
% r(j) = example j's batch row (onset, offset, heating start, ...);
% o_ex{j} = its window values (window_amplitude.m), including spike times
r = R.res([]); o_ex = cell(1, numel(example_row));
ex = struct('sheet_row', {}, 'mouse_id', {}, 'project', {}, 'sz_dur_s', {}, 'depth_0_60s', {}, depth_field, {});
for j = 1:numel(example_row)
    i_ex = find([R.res.sheet_row] == example_row(j), 1);
    r(j) = R.res(i_ex); o_ex{j} = R.outs{i_ex};
    p = A.pa([A.pa.sheet_row] == example_row(j));
    fprintf('Example %d: row %d, mouse %d (%s), seizure %.0f s, amplitude 0-1 min %.2f x baseline\n', j, ...
        r(j).sheet_row, r(j).mouse_id, r(j).project, r(j).sz_off - r(j).sz_on, p.depth_0_60s);
    ex(j) = struct('sheet_row', r(j).sheet_row, 'mouse_id', r(j).mouse_id, 'project', r(j).project, ...
        'sz_dur_s', r(j).sz_off - r(j).sz_on, 'depth_0_60s', p.depth_0_60s, depth_field, p.(depth_field));
end
if strcmp(opts.fig1_file, 'figure1')
    write_results_csv(ex, fullfile(out_dir, 'figure1_example.csv'));   % for make_results_report
end

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
if opts.only_figure1
    fprintf('Saved %s.png and .svg only (only_figure1).\n', fullfile(out_dir, opts.fig1_file));
    return
end

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
% Band titles with their ranges from cfg.bands, e.g. 'Theta (4-8 Hz)'
bands = {'delta', 'theta', 'alpha', 'beta', 'gamma'};
band_titles = cell(size(bands));
for b = 1:numel(bands)
    edges = cfg.bands{strcmp(cfg.bands(:, 1), bands{b}), 2};
    band_titles{b} = sprintf('%s (%g-%g Hz)', [upper(bands{b}(1)) bands{b}(2:end)], edges(1), edges(2));
end
slow_bands = strsplit(cfg.slowing, '_');           % the slowing ratio's two bands, e.g. delta and alpha
make_depth_figure('measures', slow_bands, 'names', band_titles(ismember(bands, slow_bands)), 'show_effect', true, ...
    'file_name', 'figureS3_slowing_bands', 'font_size', opts.font_size);
close_new_figures(open_before);
make_bin_figure('measures', bands, 'names', band_titles, 'n_cols', 3, 'file_name', 'figureS4_band_bins', ...
    'font_size', opts.font_size);
close_new_figures(open_before);
make_covariate_figure('file_name', 'figureS5_clinical');
close_new_figures(open_before);
fprintf('Written to %s (open the .png or .svg files to view)\n', out_dir);
end

%% ------------------------------------------------------------------------
function close_new_figures(open_before)
% Close every figure that was not open when make_figures started
close(setdiff(findall(0, 'Type', 'figure'), open_before));
end

%% ------------------------------------------------------------------------
function draw_figure1(r, o_ex, cfg, opts, out_dir)
% Figure 1, one column per example recording: r(j) = its batch results row,
% o_ex{j} = its window values (window_amplitude.m). Every row of panels
% shares its y axis across the columns, and the spectrograms share one
% colour scale, so the examples can be compared directly.
n_ex = numel(r);
x0 = opts.fig1_window_min(1); x1 = opts.fig1_window_min(2);
seizure_yellow = [1 0.93 0.55]; baseline_blue = [0.85 0.91 1]; artifact_grey = [0.8 0.8 0.8];
measures = cfg.primary_measures;                   % amplitude, slowing (cfg.slowing), spiking
names    = {'Amplitude', 'Slowing', 'Spiking'};

% 1. Per example: raw ECoG (notch-filtered, as in the batch), spectrogram
%    and the three measures, all as x = minutes from that seizure's onset.
%    Values during the seizure are not drawn (they would set the y axis).
rows = prepare_rows(cfg);
D = struct();
for j = 1:n_ex
    to_x = @(t) (t - r(j).sz_on) / 60;
    L = load_row_ecog(rows([rows.sheet_row] == r(j).sheet_row), cfg.data_root, cfg.ecog_multi, cfg.notch);
    assert(isempty(L.err_msg) && isempty(L.skip_msg), 'Could not load row %d: %s%s', r(j).sheet_row, ...
        L.err_msg, L.skip_msg);
    sig = double(L.ecog(:)); fs = L.fs;
    samples = max(1, round((r(j).sz_on + x0 * 60) * fs) + 1):min(numel(sig), round((r(j).sz_on + x1 * 60) * fs));
    D(j).ecog_x = to_x((samples - 1) / fs); D(j).ecog_y = sig(samples);
    [t_spec, D(j).freqs, D(j).power_db] = spectrogram_vs_baseline(sig, fs, o_ex{j}, [1 30]);
    D(j).spec_x = to_x(t_spec);
    for m = 1:3
        [o, M] = measure_view(o_ex{j}, measures{m});   % value - base_value: log10 ratio or difference
        y = to_plot_scale(o.value - o.base_value, M.is_log);
        t_grid = r(j).sz_on + (x0 * 60:o.opts.step_s:x1 * 60);
        y_smooth = to_plot_scale(smoothed_timecourse(o, r(j).sz_on, r(j).sz_off, t_grid, ...
            round(30 / o.opts.step_s)), M.is_log);
        y(o.t_end > r(j).sz_on & o.t_start < r(j).sz_off) = NaN;
        y_smooth(t_grid > r(j).sz_on & t_grid < r(j).sz_off) = NaN;
        in_view = to_x(o.t_win) >= x0 & to_x(o.t_win) <= x1;
        D(j).m(m) = struct('o', o, 'M', M, 'x', to_x(o.t_win), 'y', y, 'x_smooth', to_x(t_grid), ...
            'y_smooth', y_smooth, 'in_view', in_view);
    end
end
% Shared y limits per measure, from every example's values in view
yl_m = cell(1, 3);
for m = 1:3
    vals = [];
    for j = 1:n_ex
        vals = [vals; D(j).m(m).y(D(j).m(m).in_view); D(j).m(m).y_smooth(:)]; %#ok<AGROW>
    end
    yl_m{m} = fig_ylim(D(1).m(m).M.is_log, vals);
end

% 2. Layout: one column per example. Positions are [left bottom width
%    height] as fractions of the figure; the colour bar and the delta /
%    theta labels go right of the last column only.
fig = figure('Color', 'w', 'Position', [40 20 650 + 700 * n_ex 1650]);
left = 0.09; right_margin = 0.12; gap = 0.085;
col_w = (1 - left - right_margin - gap * (n_ex - 1)) / n_ex;
row_pos = [0.78 0.15; 0.595 0.15; 0.425 0.13; 0.255 0.13; 0.085 0.13];   % [bottom height] of A-E
all_axes = zeros(5, n_ex);
for j = 1:n_ex
    to_x = @(t) (t - r(j).sz_on) / 60;
    col_x = left + (j - 1) * (col_w + gap);
    pos = @(k) [col_x row_pos(k, 1) col_w row_pos(k, 2)];

    % 3. Raw ECoG, onset/offset dashed, detected spikes outside the
    %    seizure as green triangles; the column title names the example
    all_axes(1, j) = axes('Position', pos(1)); hold on
    plot(D(j).ecog_x, D(j).ecog_y, 'k', 'LineWidth', 0.5);
    yl = opts.fig1a_ylim;
    plot([0 0], yl, '--', 'Color', [0.8 0 0], 'LineWidth', 1.5);
    plot(to_x(r(j).sz_off) * [1 1], yl, '--', 'Color', [0 0 0.8], 'LineWidth', 1.5);
    is_control = ~strcmp(r(j).group, 'DS seizure');  % controls: pseudo-seizure times
    pre = ''; if is_control, pre = 'pseudo-'; end
    text(0, yl(2), [pre 'onset '], 'Color', [0.8 0 0], 'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'right');
    text(to_x(r(j).sz_off), yl(2), [' ' pre 'offset'], 'Color', [0 0 0.8], 'VerticalAlignment', 'bottom');
    spike_t = o_ex{j}.spikes.t(:); spike_x = to_x(spike_t);
    show = spike_x >= x0 & spike_x <= x1 & (spike_t < r(j).sz_on | spike_t > r(j).sz_off);
    plot(spike_x(show), 0.88 * yl(2) * ones(sum(show), 1), 'v', 'Color', [0 0.6 0], ...
        'MarkerFaceColor', [0 0.6 0], 'MarkerSize', 7);
    ylim(yl);
    if is_control
        col_title = sprintf('Mouse %d, %s control, no seizure', r(j).mouse_id, r(j).group);
    else
        col_title = sprintf('Mouse %d, seizure %.0f s', r(j).mouse_id, r(j).sz_off - r(j).sz_on);
    end
    title(col_title, ...
        'FontWeight', 'normal', 'Units', 'normalized', 'Position', [0.5 1.12 0]);

    % 4. Spectrogram relative to baseline; slowing-ratio bands dashed
    all_axes(2, j) = axes('Position', pos(2)); hold on
    h_img = imagesc(D(j).spec_x, D(j).freqs, D(j).power_db);
    set(h_img, 'AlphaData', double(~isnan(D(j).power_db)));   % artifact windows blank
    set(all_axes(2, j), 'YDir', 'normal', 'CLim', opts.spec_clim_db, 'Color', artifact_grey);   % ... and grey
    colormap(all_axes(2, j), blue_white_red(256, opts.spec_clim_db));   % white = baseline
    slow_bands = strsplit(cfg.slowing, '_');      % the slowing ratio's two bands, e.g. delta and alpha
    for band = [slow_bands; strcat('\', slow_bands)]
        edges = cfg.bands{strcmp(cfg.bands(:, 1), band{1}), 2};
        for e = edges
            plot([x0 x1], [e e], '--', 'Color', [0.2 0.2 0.2], 'LineWidth', 1.2);
        end
        if j == n_ex
            text(x1, mean(edges), [' ' band{2}], 'VerticalAlignment', 'middle', 'FontWeight', 'bold', 'Tag', 'band_label');
        end
    end
    ylim([1 30]);
    if j == n_ex
        cbar = colorbar(all_axes(2, j));
        set(all_axes(2, j), 'Position', pos(2));        % undo the shrinking, so all panels line up
        p = pos(2);
        set(cbar, 'Position', [p(1) + p(3) + 0.035, p(2), 0.012, p(4)]);   % room for the band labels
        ylabel(cbar, 'dB vs baseline');
    end

    % 5. The three measures: dots = 10 s windows every 5 s; line = 30 s
    %    moving average (smoothed_timecourse.m)
    for m = 1:3
        q = D(j).m(m); o = q.o; yl = yl_m{m};
        all_axes(2 + m, j) = axes('Position', pos(2 + m)); hold on
        shade(to_x(o.base_start), to_x(o.base_end), yl, baseline_blue);   % only if in view
        spans = artifact_spans(o);                    % artifact windows, merged where they overlap
        for k = 1:size(spans, 1)
            shade(to_x(spans(k, 1)), to_x(spans(k, 2)), yl, artifact_grey);
        end
        shade(0, to_x(r(j).sz_off), yl, seizure_yellow);
        GC = group_colors();                          % red for a seizure, black for a control
        if strcmp(r(j).group, 'DS seizure'), line_col = GC.seizure; else, line_col = GC.control; end
        plot(q.x, q.y, '.', 'Color', [0.65 0.65 0.65], 'MarkerSize', 9);
        plot(q.x_smooth, q.y_smooth, '-', 'Color', line_col, 'LineWidth', 2.5);
        baseline_level = to_plot_scale(0, q.M.is_log); % 1 for ratios, 0 for spike rate
        plot([x0 x1], [baseline_level baseline_level], 'k:');
        heat_x = to_x(r(j).heat_start);
        if heat_x > x0                                % heating start, if within the window
            plot([heat_x heat_x], yl, 'k--');
            if m == 1, text(heat_x, yl(2), ' heating on', 'VerticalAlignment', 'top'); end
        end
        if q.M.is_log, use_log_axis(gca, 'Y', yl); else, ylim(yl); end
        if j == 1, ylabel(q.M.label); end
        text(0.01, 1.02, names{m}, 'Units', 'normalized', 'VerticalAlignment', 'bottom');
    end
end
ylabel(all_axes(1, 1), 'ECoG (\muV)');
ylabel(all_axes(2, 1), 'Frequency (Hz)');

% 6. Shared x axis within each column (minutes from that seizure's onset);
%    tick labels and x label on the bottom panels only
for j = 1:n_ex
    linkaxes(all_axes(:, j), 'x');
    xlim(all_axes(1, j), [x0 x1]);
    set(all_axes(1:4, j), 'XTickLabel', []);
    xlabel(all_axes(5, j), 'Time from seizure onset (min)');
end
set(all_axes(:), 'Box', 'off');
set_fonts(fig, opts.font_size);
set(findall(fig, 'Tag', 'band_label'), 'FontSize', opts.font_size + 8);   % delta/theta labels larger

% 7. Panel letters in figure coordinates, left of each panel's top-left
%    corner, down each column: A-E, F-J, ... Added after set_fonts so they
%    stay larger.
for j = 1:n_ex
    col_x = left + (j - 1) * (col_w + gap);
    for k = 1:5
        annotation(fig, 'textbox', [col_x - 0.07, row_pos(k, 1) + row_pos(k, 2) - 0.03, 0.03, 0.04], ...
            'String', char('A' + 5 * (j - 1) + k - 1), 'EdgeColor', 'none', 'FontWeight', 'bold', ...
            'FontSize', opts.font_size + 6, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', 'Margin', 1);
    end
end

% 8. Save
print(fig, fullfile(out_dir, [opts.fig1_file '.png']), '-dpng', '-r300');
print(fig, fullfile(out_dir, [opts.fig1_file '.svg']), '-dsvg', '-painters');
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
