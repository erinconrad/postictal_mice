function T = make_bin_figure(varargin)
% MAKE_BIN_FIGURE  Measures in 30 s bins before (pseudo-)onset and after
% (pseudo-)offset: median and interquartile range across animals, DS
% seizures vs controls (Figure 3; Figure S4 for the frequency bands). Reads the
% batch results only (run run_postictal_batch first).
%
%   make_bin_figure                                       % Figure 3
%   make_bin_figure('measures', {'delta', 'alpha'}, ...
%       'names', {'Delta (1-4 Hz)', 'Theta (4-8 Hz)'}, 'file_name', 'figureS4_band_bins')
%
% Options (name-value pairs)
%   measures   default cfg.primary_measures: rms, cfg.slowing, spike_rate (measure_view.m)
%   names      panel titles; default Amplitude, Slowing, Spiking
%   bin_s      bin width (s); default 30
%   pre_s      bins from this long before onset (s); default 240 (4 min)
%   post_s     bins to this long after offset (s); default 600 (10 min)
%   tick_s     x tick spacing on both sides of the seizure (s); default 120
%   min_n      median and IQR drawn only where at least this many animals
%              have a value; default 5
%   gap_s      width of the seizure gap on the x axis (s of axis); default 60
%   n_cols     panels per row; default all in one row (Figure S4: 3)
%   file_name  default 'figure3'
%   font_size  default 20
%
% Bins: from pre_s before onset to onset (aligned to onset; during heating,
% so these show where each group is when the seizure starts), and from
% offset to post_s after offset (aligned to offset). The seizure itself is
% left out (its length differs between animals): in the figure the two
% segments are separated by a yellow bar marked "seizure".
%
% Cohort: the primary cohort, as in analyze_primary.m. Controls = WT and
% DS no seizure together (aligned to their pseudo-onset and offset);
% seizures = DS seizure.
%
% Value per animal and bin: depth_window.m over the bin (the 10 s windows
% lying entirely inside it, 5 for a 30 s bin), relative to the animal's own
% pre-heating baseline: ratio for RMS, delta/theta and band power,
% spikes/min difference for spike rate. No smoothing. Blank if fewer than
% half the bin's windows are artifact-free or the recording ends first.
%
% Figure: one panel per measure; thick line = median across animals,
% shaded = interquartile range, at bin centres. Ratios on a log axis
% (dotted line at 1 = baseline), spike rate on a linear axis (dotted at 0).
%
% Outputs in <output>/figures/:
%   <file_name>.png (300 dpi), <file_name>.svg
%   <file_name>_per_animal.csv   one row per animal and measure, one column
%                         per bin (pre<a>_<b>: a to b s before onset;
%                         post<a>_<b>: a to b s after offset)
%   <file_name>_summary.csv      median, quartiles and n per group, measure
%                         and bin
% T: the per-animal table as a struct array.

%% 1. Settings and inputs
opts = struct('measures', {{}}, ...               % {} = cfg.primary_measures (amplitude, slowing, spiking)
    'names', {{}}, ...
    'bin_s', 30, 'pre_s', 240, 'post_s', 600, 'tick_s', 120, 'min_n', 5, 'gap_s', 60, ...
    'n_cols', NaN, 'file_name', 'figure3', 'font_size', 20);
for k = 1:2:numel(varargin)                          % name-value pairs override the defaults
    assert(isfield(opts, varargin{k}), 'Unknown option %s', varargin{k});
    opts.(varargin{k}) = varargin{k + 1};
end
addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();   % scripts folder and its subfolders
cfg = analysis_config();
if isempty(opts.measures)
    opts.measures = cfg.primary_measures;
    if isempty(opts.names), opts.names = {'Amplitude', 'Slowing', 'Spiking'}; end
end
assert(numel(opts.names) == numel(opts.measures), 'Give one name per measure');
out_dir = fullfile(cfg.out_root, 'figures');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
S = load(fullfile(cfg.out_root, 'postictal_batch', 'postictal_results.mat'), 'res', 'outs');

% Cohort (as in analyze_primary.m): primary-cohort recordings that the
% batch processed. is_sz: true = DS seizure, false = control
use  = find([S.res.in_primary] == 1 & ~ismember({S.res.status}, {'error', 'skipped'}));
res  = S.res(use); outs = S.outs(use);
is_sz = strcmp({res.group}, 'DS seizure')';
fprintf('Controls: %d (WT %d, DS no seizure %d); seizures: %d\n', sum(~is_sz), ...
    sum(strcmp({res.group}, 'WT')), sum(strcmp({res.group}, 'DS no seizure')), sum(is_sz));

%% 2. Bins
% bins = one row per bin, [start end] in s: relative to onset for the
% pre-onset bins (negative, e.g. [-240 -210]), relative to offset for the
% post-offset bins (e.g. [0 30]). is_pre marks which.
pre_edges  = -opts.pre_s:opts.bin_s:0;
post_edges = 0:opts.bin_s:opts.post_s;
bins = [pre_edges(1:end - 1)' pre_edges(2:end)'; post_edges(1:end - 1)' post_edges(2:end)'];
is_pre = [true(numel(pre_edges) - 1, 1); false(numel(post_edges) - 1, 1)];
n_bins = size(bins, 1);
% x position in the figure (s): post bins at their time from offset; pre
% bins at their time from onset, shifted left by the seizure gap
x_ctr = mean(bins, 2)';
x_ctr(is_pre) = x_ctr(is_pre) - opts.gap_s;
% Column names for the per-animal CSV
bin_names = cell(1, n_bins);
for b = 1:n_bins
    if is_pre(b), bin_names{b} = sprintf('pre%d_%d', -bins(b, 1), -bins(b, 2));
    else,         bin_names{b} = sprintf('post%d_%d', bins(b, 1), bins(b, 2)); end
end

%% 3. Bin values per animal
% V{m}(i, b) = animal i's value of measure m in bin b (NaN = no value).
% T collects the same values as rows for the CSV.
n_m = numel(opts.measures);
V = cell(1, n_m); M = cell(1, n_m);
T = struct([]);
for m = 1:n_m
    V{m} = nan(numel(res), n_bins);
    for i = 1:numel(res)
        [o, M{m}] = measure_view(outs{i}, opts.measures{m});   % this measure in value / base_value
        for b = 1:n_bins
            if is_pre(b), t_align = res(i).sz_on; else, t_align = res(i).sz_off; end
            V{m}(i, b) = depth_window(o, t_align + bins(b, 1), opts.bin_s);
        end
        row = struct('sheet_row', res(i).sheet_row, 'mouse_id', res(i).mouse_id, 'group', res(i).group, ...
            'measure', opts.measures{m});
        for b = 1:n_bins, row.(bin_names{b}) = V{m}(i, b); end
        if isempty(T), T = row; else, T(end + 1) = row; end %#ok<AGROW>
    end
end

%% 4. Summary: median and quartiles per group, measure and bin
% Q = one row per measure, group and bin (quartile.m; only where at
% least min_n animals have a value)
Q = struct([]);
groups = {'controls', ~is_sz; 'DS seizure', is_sz};
for m = 1:n_m
    for k = 1:2
        for b = 1:n_bins
            v = V{m}(groups{k, 2}, b); v = v(~isnan(v));
            if is_pre(b), aligned_to = 'onset'; else, aligned_to = 'offset'; end
            q = struct('measure', opts.measures{m}, 'group', groups{k, 1}, 'aligned_to', aligned_to, ...
                'bin_start_s', bins(b, 1), 'bin_end_s', bins(b, 2), 'n', numel(v), ...
                'median', NaN, 'q25', NaN, 'q75', NaN);
            if numel(v) >= opts.min_n
                q.median = quartile(v, 0.5); q.q25 = quartile(v, 0.25); q.q75 = quartile(v, 0.75);
            end
            if isempty(Q), Q = q; else, Q(end + 1) = q; end %#ok<AGROW>
        end
    end
end

%% 5. Figure: one panel per measure
% x axis: pre-onset bins on the left, the seizure gap (yellow), then the
% post-offset bins. Axis units are s; tick labels are in minutes.
C = group_colors();
colors = [C.control; C.seizure];                     % controls black, seizures red (group_colors.m)
seizure_yellow = [1 0.93 0.55];                      % as the seizure in Figure 1
if isnan(opts.n_cols), n_cols = n_m; else, n_cols = opts.n_cols; end
n_rows = ceil(n_m / n_cols);
f = figure('Color', 'w', 'Position', [60 60 620 * n_cols 620 * n_rows]);
x_left = -opts.pre_s - opts.gap_s;                   % left edge of the axis
for m = 1:n_m
    ax = subplot(n_rows, n_cols, m); hold on
    q_m = Q(strcmp({Q.measure}, opts.measures{m}));
    if M{m}.is_log, baseline_level = 1; else, baseline_level = 0; end

    % 5a. y range from the IQRs of both groups and the baseline level
    y_low  = min([q_m.q25, baseline_level]);
    y_high = max([q_m.q75, baseline_level]);
    if M{m}.is_log
        yl = [y_low / 1.25, y_high * 1.25];           % log axis: margin = a factor of 1.25
    else
        margin = 0.08 * max(y_high - y_low, 1);       % linear axis: 8% of the range
        yl = [y_low - margin, y_high + margin];
    end

    % 5b. The seizure gap
    patch([-opts.gap_s 0 0 -opts.gap_s], yl([1 1 2 2]), seizure_yellow, 'EdgeColor', 'none');
    text(-opts.gap_s / 2, yl(2), 'seizure ', 'Rotation', 90, 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'middle');               % inside the bar, reading upward from the top

    % 5c. IQR bands first (layer 1), then the median lines on top (layer
    %     2). The two segments are drawn separately, so lines are not
    %     joined across the seizure. Bins below min_n animals are NaN.
    h = zeros(1, 2);
    for layer = 1:2
        for k = 1:2
            q_k = q_m(strcmp({q_m.group}, groups{k, 1}));
            med = [q_k.median]; lo = [q_k.q25]; hi = [q_k.q75];
            for segment = {is_pre', ~is_pre'}
                sel = segment{1} & ~isnan(med);
                if ~any(sel), continue; end
                if layer == 1
                    fill([x_ctr(sel) fliplr(x_ctr(sel))], [lo(sel) fliplr(hi(sel))], colors(k, :), ...
                        'FaceAlpha', C.fill_alpha, 'EdgeColor', 'none');
                else
                    h(k) = plot(x_ctr(sel), med(sel), '-', 'Color', colors(k, :), 'LineWidth', 3);
                end
            end
        end
    end

    % 5d. Baseline level, axes. x ticks every tick_s on both sides (e.g.
    %     -4, -2 | 0, 2, 4, ... min); pre-onset ticks are placed like the
    %     bins (shifted by the gap) but labelled with the time from onset.
    plot([x_left opts.post_s], [baseline_level baseline_level], 'k:');
    if M{m}.is_log, use_log_axis(ax, 'Y', yl); else, ylim(yl); end
    xlim([x_left opts.post_s]); box off
    pre_ticks  = -opts.pre_s:opts.tick_s:-opts.tick_s;          % s from onset
    post_ticks = 0:opts.tick_s:opts.post_s;                     % s from offset
    set(ax, 'XTick', [pre_ticks - opts.gap_s, post_ticks], ...
        'XTickLabel', arrayfun(@(t) sprintf('%g', t / 60), [pre_ticks, post_ticks], 'UniformOutput', false));
    xlabel('Time from onset | from offset (min)');
    ylabel(M{m}.label);
    title(opts.names{m}, 'FontWeight', 'normal');
    panel_letter(ax, char('A' + m - 1));
    if m == 1
        legend(h, {'Control', 'DS seizure'}, 'Location', 'southeast', 'Box', 'off');
    end
end
set_fonts(f, opts.font_size);

%% 6. Save the figure and the two tables
print(f, fullfile(out_dir, [opts.file_name '.png']), '-dpng', '-r300');
print(f, fullfile(out_dir, [opts.file_name '.svg']), '-dsvg', '-painters');   % vector; check that the IQR shading stays see-through
write_results_csv(T, fullfile(out_dir, [opts.file_name '_per_animal.csv']));
write_results_csv(Q, fullfile(out_dir, [opts.file_name '_summary.csv']));
fprintf('Written to %s\n', out_dir);
end
