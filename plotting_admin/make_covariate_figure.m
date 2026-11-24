function T = make_covariate_figure(varargin)
% MAKE_COVARIATE_FIGURE  Post-ictal depth vs seizure duration, age, sex,
% and first vs second heated seizure, DS seizure mice only (Figure S5).
% One row per measure (amplitude, slowing, spiking), one column per
% factor: 12 panels. Run analyze_primary for all three measures first.
%
%   make_covariate_figure
%   make_covariate_figure('window_s', 60, 'file_name', 'figureS5_clinical_0-1min')
%
% Options (name-value pairs)
%   window_s   depth window after offset (s), one of cfg.depth_windows_s;
%              default cfg.depth_main_s (300 s)
%   file_name  default 'figureS5_clinical'
%   font_size  default 18
%
% Depth: as in Figure 2 (analyze_primary.m, pa.depth_0_<N>s).
% Columns:
%   Duration  seizure duration (s, offset - onset) vs depth; Spearman rank
%             correlation (spearman_test.m)
%   Age       recording age (days, spreadsheet) vs depth; Spearman rank
%             correlation (spearman_test.m)
%   Sex       M vs F; dots, geometric mean with 95% CI (spike rate: mean);
%             Mann-Whitney U, shown as asterisks (p_stars.m)
%   Seizure   seizure 1 (the mouse's first seizure, the primary cohort) vs
%             seizure 2 (its next one) in the same mice; one line per mouse;
%             Wilcoxon signed-rank test on the paired differences of log10
%             depth (spike rate: of depth), as asterisks. Only mice with a
%             depth for both seizures (analyze_primary.m section 3).
% Exploratory: p-values are not corrected for the 12 tests.
%
% Outputs in <output>/figures/: <file_name>.png (300 dpi) and .svg, and
% <file_name>_stats.csv (one row per measure and factor: test, n,
% estimate, p). T: the same table as a struct array.

%% 1. Settings and inputs
addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();
cfg = analysis_config();
opts = struct('window_s', cfg.depth_main_s, 'file_name', 'figureS5_clinical', 'font_size', 18);
for k = 1:2:numel(varargin)
    assert(isfield(opts, varargin{k}), 'Unknown option %s', varargin{k});
    opts.(varargin{k}) = varargin{k + 1};
end
assert(ismember(opts.window_s, cfg.depth_windows_s), 'window_s must be one of cfg.depth_windows_s');
out_dir = fullfile(cfg.out_root, 'figures');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
depth_field    = sprintf('depth_0_%ds', opts.window_s);         % session 1 (primary)
depth_field_s2 = sprintf('s2_depth_0_%ds', opts.window_s);      % second seizure, same mice

measures = cfg.primary_measures;                 % amplitude, slowing (cfg.slowing), spiking
names    = {'Amplitude', 'Slowing', 'Spiking'};
C = group_colors(); red = C.seizure; light_red = C.seizure_dots;   % DS seizure mice only
window_label = sprintf('0-%g min', opts.window_s / 60);

%% 2. One row of panels per measure
f = figure('Color', 'w', 'Position', [60 20 2000 1400]);
n_cols = 4;
letter = @(m, c) char('A' + n_cols * (m - 1) + c - 1);  % panel letters A-L, row by row
T = struct([]);
for m = 1:3
    % 2a. This measure's DS seizure animals (analyze_primary.m)
    [~, M] = measure_view([], measures{m});
    result_file = fullfile(cfg.out_root, M.out_dir, 'primary_analysis.mat');
    assert(exist(result_file, 'file') == 2, 'No %s: run analyze_primary(''%s'') first', result_file, measures{m});
    A = load(result_file, 'pa');
    assert(isfield(A.pa, depth_field_s2), '%s is from an older version: re-run analyze_primary(''%s'')', ...
        result_file, measures{m});
    seizures = A.pa(strcmp({A.pa.group}, 'DS seizure'));
    depth = [seizures.(depth_field)]';
    age   = [seizures.age_days]';
    sz_dur = [seizures.sz_dur_s]';                    % seizure duration (s)
    sex   = {seizures.sex}';
    y_label = sprintf('%s, %s', M.label, window_label);
    if M.is_log, baseline_level = 1; else, baseline_level = 0; end

    % 2b. Seizure duration: scatter and Spearman correlation
    ax = subplot(3, n_cols, n_cols * (m - 1) + 1); hold on
    [rho, p, n] = spearman_test(sz_dur, depth);
    T = add_row(T, measures{m}, 'seizure duration', 'Spearman rho', n, rho, p);
    ok = ~isnan(sz_dur) & ~isnan(depth);
    plot(sz_dur(ok), depth(ok), 'o', 'MarkerFaceColor', light_red, 'MarkerEdgeColor', 'none', 'MarkerSize', 8);
    plot(xlim, [baseline_level baseline_level], 'k:');
    set_y_axis(ax, depth(ok), baseline_level, M.is_log);
    text(0.03, 0.97, sprintf('\\rho = %.2f, p = %s', rho, p_string(p)), 'Units', 'normalized', ...
        'VerticalAlignment', 'top');
    xlabel('Seizure duration (s)'); ylabel(y_label); box off
    title(names{m}, 'FontWeight', 'normal');
    panel_letter(ax, letter(m, 1));

    % 2c. Age: scatter and Spearman correlation
    ax = subplot(3, n_cols, n_cols * (m - 1) + 2); hold on
    [rho, p, n] = spearman_test(age, depth);
    T = add_row(T, measures{m}, 'age', 'Spearman rho', n, rho, p);
    ok = ~isnan(age) & ~isnan(depth);
    plot(age(ok), depth(ok), 'o', 'MarkerFaceColor', light_red, 'MarkerEdgeColor', 'none', 'MarkerSize', 8);
    plot(xlim, [baseline_level baseline_level], 'k:');
    set_y_axis(ax, depth(ok), baseline_level, M.is_log);
    text(0.03, 0.97, sprintf('\\rho = %.2f, p = %s', rho, p_string(p)), 'Units', 'normalized', ...
        'VerticalAlignment', 'top');
    xlabel('Age (days)'); ylabel(y_label); box off
    panel_letter(ax, letter(m, 2));

    % 2d. Sex: male vs female, Mann-Whitney
    ax = subplot(3, n_cols, n_cols * (m - 1) + 3); hold on
    v_male   = depth(strcmp(sex, 'M') & ~isnan(depth));
    v_female = depth(strcmp(sex, 'F') & ~isnan(depth));
    [~, p] = mann_whitney(v_male, v_female);
    if M.is_log, est = median(v_male) / median(v_female); est_type = 'ratio of medians (M / F)';
    else,        est = median(v_male) - median(v_female); est_type = 'difference of medians (M - F)'; end
    T = add_row(T, measures{m}, 'sex', ['Mann-Whitney; ' est_type], numel(v_male) + numel(v_female), est, p);
    vals = {v_male, v_female};
    for k = 1:2
        plot(k + jitter_offsets(numel(vals{k})), vals{k}, 'o', 'MarkerFaceColor', light_red, ...
            'MarkerEdgeColor', 'none', 'MarkerSize', 8);
        if numel(vals{k}) >= 2
            [center, ci] = group_center_ci(vals{k}, M.is_log);
            plot(k + [-0.25 0.25], [center center], '-', 'Color', red, 'LineWidth', 3.5);
            plot([k k], ci, '-', 'Color', red, 'LineWidth', 2.5);
        end
    end
    plot([0.4 2.6], [baseline_level baseline_level], 'k:');
    yl = set_y_axis(ax, [v_male; v_female], baseline_level, M.is_log);
    significance_bracket(yl, p, M.is_log);
    xlim([0.4 2.6]); set(ax, 'XTick', 1:2, 'XTickLabel', {'Male', 'Female'}); box off
    ylabel(y_label);
    panel_letter(ax, letter(m, 3));

    % 2e. Seizure 1 vs seizure 2, same mice, Wilcoxon signed-rank on the
    %     paired differences (of log10 depth for ratios)
    ax = subplot(3, n_cols, n_cols * (m - 1) + 4); hold on
    d1 = depth; d2 = [seizures.(depth_field_s2)]';
    paired = ~isnan(d1) & ~isnan(d2);
    d1 = d1(paired); d2 = d2(paired);
    if M.is_log, diffs = log10(d2) - log10(d1); else, diffs = d2 - d1; end
    p = signrank_test(diffs);
    if M.is_log, est = 10^median(diffs); est_type = 'median ratio (2 / 1)';
    else,        est = median(diffs);    est_type = 'median difference (2 - 1)'; end
    T = add_row(T, measures{m}, 'seizure 1 vs 2', ['Wilcoxon signed-rank; ' est_type], sum(paired), est, p);
    for i = 1:numel(d1)
        plot([1 2], [d1(i) d2(i)], '-', 'Color', [0.6 0.6 0.6]);
    end
    plot(ones(size(d1)), d1, 'o', 'MarkerFaceColor', light_red, 'MarkerEdgeColor', 'none', 'MarkerSize', 8);
    plot(2 * ones(size(d2)), d2, 'o', 'MarkerFaceColor', light_red, 'MarkerEdgeColor', 'none', 'MarkerSize', 8);
    plot([0.6 2.4], [baseline_level baseline_level], 'k:');
    yl = set_y_axis(ax, [d1; d2], baseline_level, M.is_log);
    significance_bracket(yl, p, M.is_log);
    xlim([0.6 2.4]); set(ax, 'XTick', 1:2, 'XTickLabel', {'Seizure 1', 'Seizure 2'}); box off
    ylabel(y_label);
    panel_letter(ax, letter(m, 4));
end
set_fonts(f, opts.font_size);

%% 3. Save
print(f, fullfile(out_dir, [opts.file_name '.png']), '-dpng', '-r300');
print(f, fullfile(out_dir, [opts.file_name '.svg']), '-dsvg', '-painters');
write_results_csv(T, fullfile(out_dir, [opts.file_name '_stats.csv']));
for k = 1:numel(T)
    fprintf('%-12s %-15s n = %2d  estimate = %6.2f  p = %s  (%s)\n', T(k).measure, T(k).factor, T(k).n, ...
        T(k).estimate, p_string(T(k).p), T(k).test);
end
end

%% ------------------------------------------------------------------------
function T = add_row(T, measure, factor, test, n, estimate, p)
% Append one row to the statistics table
q = struct('measure', measure, 'factor', factor, 'test', test, 'n', n, 'estimate', estimate, 'p', p);
if isempty(T), T = q; else, T(end + 1) = q; end
end

function yl = set_y_axis(ax, v, baseline_level, is_log)
% y limits from the values and the baseline level, with room above for a
% bracket or text: log axis (labelled ticks) for ratios, linear for spike
% rate
v = [v(:); baseline_level];
if is_log
    yl = [min(v) / 1.25, max(v) * 1.9];
    use_log_axis(ax, 'Y', yl);
else
    data_range = max(max(v) - min(v), 1);
    yl = [min(v) - 0.08 * data_range, max(v) + 0.28 * data_range];
    ylim(yl);
end
end

function significance_bracket(yl, p, is_log)
% Bracket between x = 1 and x = 2 near the top of the axes, with p_stars
% above it
if is_log
    y_bar = yl(2) / 1.35; y_end = y_bar * 0.96; y_text = y_bar * 1.02;
else
    span = yl(2) - yl(1);
    y_bar = yl(2) - 0.14 * span; y_end = y_bar - 0.03 * span; y_text = y_bar + 0.01 * span;
end
plot([1 1 2 2], [y_end y_bar y_bar y_end], 'k-', 'LineWidth', 1);
text(1.5, y_text, p_stars(p), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
end
