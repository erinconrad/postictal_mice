function f = make_depth_figure(varargin)
% MAKE_DEPTH_FIGURE  Post-ictal depth, two groups, one panel per measure
% (Figure 2 and Figures S2, S3). Run analyze_primary for each measure
% shown first.
%
%   make_depth_figure                                     % Figure 2
%   make_depth_figure('compare', 'dsno_vs_wt', 'show_effect', true)       % S2
%   make_depth_figure('measures', {'delta', 'theta'}, ...
%       'names', {'Delta (1-4 Hz)', 'Theta (6-10 Hz)'}, 'show_effect', true)  % S3
%
% Options (name-value pairs)
%   measures     measure names (measure_view.m); default rms, delta_theta,
%                spike_rate
%   names        panel titles; default Amplitude, Slowing, Spiking
%   compare      'seizure_vs_controls' (default): Control (WT filled, DS no
%                seizure open) vs DS seizure
%                'dsno_vs_wt': WT vs DS no seizure
%   window_s     depth window after offset (s); default cfg.depth_main_s
%                (300 s = 0-5 min). Must be one of cfg.depth_windows_s.
%   show_effect  true: the effect size and its 95% CI under each panel
%                title (default false)
%   file_name    output file name (default 'figure2'); '' = don't save
%   font_size    default 20
%
% Values: each animal's depth (analyze_primary.m, pa.depth_0_<N>s): ratio
%   to baseline for ratio measures (log axis), spikes/min difference for
%   spike rate.
% Lines: geometric mean with 95% CI for ratios, mean with 95% CI for spike
%   rate (group_center_ci.m).
% Significance: Mann-Whitney U (analyze_primary.m, stats.csv), shown as
%   asterisks (p_stars.m: * < 0.05, ** < 0.01, *** < 0.001, n.s.). For the
%   primary hypotheses (Figure 2: a measure in cfg.primary_measures, DS
%   seizure vs controls, 0 to cfg.depth_main_s) the asterisks use the
%   Bonferroni-corrected p; elsewhere (S2, S3, other windows) the
%   uncorrected p. The exact p-values are printed in the command window
%   and are in stats.csv.
% Effect size (show_effect): the Welch rows of the same table: ratio of
%   geometric means (second group / first) for ratios, difference of means
%   for spike rate, with 95% CI.
%
% Outputs in <output>/figures/: <file_name>.png (300 dpi) and .pdf.

%% 1. Settings and inputs
addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();
cfg = analysis_config();
opts = struct();
opts.measures    = {'rms', 'delta_theta', 'spike_rate'};
opts.names       = {'Amplitude', 'Slowing', 'Spiking'};
opts.compare     = 'seizure_vs_controls';
opts.window_s    = cfg.depth_main_s;
opts.show_effect = false;
opts.file_name   = 'figure2';
opts.font_size   = 20;
for k = 1:2:numel(varargin)
    assert(isfield(opts, varargin{k}), 'Unknown option %s', varargin{k});
    opts.(varargin{k}) = varargin{k + 1};
end
assert(numel(opts.names) == numel(opts.measures), 'Give one name per measure');
assert(ismember(opts.window_s, cfg.depth_windows_s), 'window_s must be one of cfg.depth_windows_s');
out_dir = fullfile(cfg.out_root, 'figures');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
depth_field = sprintf('depth_0_%ds', opts.window_s);           % column in pa
stats_name  = sprintf('depth 0-%d s', opts.window_s);           % measure in stats
grey = [0.45 0.45 0.45]; red = [0.80 0.20 0.20];

% The two groups (x = 1 and x = 2): labels, the comparison's name in
% stats.csv, and the colour of the second group
switch opts.compare
    case 'seizure_vs_controls'
        group_labels    = {'Control', 'DS seizure'};
        comparison_name = 'DS seizure vs controls';
        col2 = red;
    case 'dsno_vs_wt'
        group_labels    = {'WT', 'DS no seizure'};
        comparison_name = 'DS no seizure vs WT';
        col2 = grey;
    otherwise
        error('compare must be ''seizure_vs_controls'' or ''dsno_vs_wt''');
end

%% 2. One panel per measure
n_panels = numel(opts.measures);
f = figure('Color', 'w', 'Position', [60 60 520 * n_panels 620]);
for m = 1:n_panels
    % 2a. This measure's per-animal depths (analyze_primary.m)
    [~, M] = measure_view([], opts.measures{m});
    result_file = fullfile(cfg.out_root, M.out_dir, 'primary_analysis.mat');
    assert(exist(result_file, 'file') == 2, 'No %s: run analyze_primary(''%s'') first', result_file, opts.measures{m});
    A = load(result_file, 'pa', 'stats');
    assert(isfield(A.pa, depth_field), '%s is from an older version: re-run analyze_primary(''%s'')', ...
        result_file, opts.measures{m});
    depth = [A.pa.(depth_field)]';
    group = {A.pa.group}';
    is_wt      = strcmp(group, 'WT') & ~isnan(depth);
    is_dsno    = strcmp(group, 'DS no seizure') & ~isnan(depth);
    is_seizure = strcmp(group, 'DS seizure') & ~isnan(depth);

    ax = subplot(1, n_panels, m); hold on

    % 2b. Dots (WT filled grey, DS no seizure open grey, DS seizure red)
    if strcmp(opts.compare, 'seizure_vs_controls')
        vals1 = depth(is_wt | is_dsno);               % x = 1: all controls
        vals2 = depth(is_seizure);                    % x = 2
        ctrl_is_wt = is_wt(is_wt | is_dsno);          % which controls are WT
        x1 = 1 + jitter_offsets(numel(vals1));
        h_wt   = plot(x1(ctrl_is_wt), vals1(ctrl_is_wt), 'o', 'MarkerFaceColor', grey + (1 - grey) * 0.3, ...
            'MarkerEdgeColor', 'none', 'MarkerSize', 8);
        h_dsno = plot(x1(~ctrl_is_wt), vals1(~ctrl_is_wt), 'o', 'MarkerFaceColor', 'w', ...
            'MarkerEdgeColor', grey, 'MarkerSize', 8, 'LineWidth', 1.2);
        plot(2 + jitter_offsets(numel(vals2)), vals2, 'o', 'MarkerFaceColor', red + (1 - red) * 0.4, ...
            'MarkerEdgeColor', 'none', 'MarkerSize', 8);
    else
        vals1 = depth(is_wt);
        vals2 = depth(is_dsno);
        plot(1 + jitter_offsets(numel(vals1)), vals1, 'o', 'MarkerFaceColor', grey + (1 - grey) * 0.3, ...
            'MarkerEdgeColor', 'none', 'MarkerSize', 8);
        plot(2 + jitter_offsets(numel(vals2)), vals2, 'o', 'MarkerFaceColor', 'w', 'MarkerEdgeColor', grey, ...
            'MarkerSize', 8, 'LineWidth', 1.2);
    end

    % 2c. Group centre (horizontal bar) and 95% CI (vertical line); dotted
    %     line = baseline (1 for ratios, 0 for spike rate)
    vals = {vals1, vals2}; colors = {grey, col2};
    for k = 1:2
        [center, ci] = group_center_ci(vals{k}, M.is_log);
        plot(k + [-0.25 0.25], [center center], '-', 'Color', colors{k}, 'LineWidth', 3.5);
        plot([k k], ci, '-', 'Color', colors{k}, 'LineWidth', 2.5);
    end
    if M.is_log, baseline_level = 1; else, baseline_level = 0; end
    plot([0.4 2.6], [baseline_level baseline_level], 'k:');

    % 2d. Mann-Whitney result as asterisks over a bracket (bracket_layout,
    %     below)
    S = A.stats;
    this_test = strcmp({S.measure}, stats_name) & strcmp({S.comparison}, comparison_name);
    mw = S(this_test & strncmp({S.method}, 'Mann-Whitney', 12));
    assert(numel(mw) == 1, 'No ''%s'' Mann-Whitney row for %s in the %s results: re-run analyze_primary(''%s'')', ...
        comparison_name, stats_name, opts.measures{m}, opts.measures{m});
    % A primary hypothesis (cfg.primary_measures, DS seizure vs controls,
    % 0 to cfg.depth_main_s) shows its Bonferroni-corrected p
    is_primary = ismember(opts.measures{m}, cfg.primary_measures) && strcmp(opts.compare, 'seizure_vs_controls') ...
        && opts.window_s == cfg.depth_main_s;
    if is_primary
        assert(isfield(mw, 'p_bonferroni') && ~isnan(mw.p_bonferroni), ...
            'No Bonferroni p for %s: re-run analyze_primary(''%s'')', opts.measures{m}, opts.measures{m});
        p_shown = mw.p_bonferroni;
        fprintf('%-12s %s, %s: Mann-Whitney p = %s, Bonferroni-corrected p = %s\n', opts.measures{m}, ...
            comparison_name, stats_name, p_string(mw.p), p_string(p_shown));
    else
        p_shown = mw.p;
        fprintf('%-12s %s, %s: Mann-Whitney p = %s (uncorrected)\n', opts.measures{m}, comparison_name, ...
            stats_name, p_string(mw.p));
    end
    [y_bar, y_end, y_text, yl] = bracket_layout([vals1; vals2], M.is_log);
    plot([1 1 2 2], [y_end y_bar y_bar y_end], 'k-', 'LineWidth', 1);
    text(1.5, y_text, p_stars(p_shown), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');

    % 2e. Axes and labels
    if M.is_log, use_log_axis(ax, 'Y', yl); else, ylim(yl); end
    xlim([0.4 2.6]); box off
    set(ax, 'XTick', 1:2, 'XTickLabel', group_labels);
    ylabel(sprintf('%s, 0-%g min', M.label, opts.window_s / 60));

    % 2f. Title; with show_effect, the effect size and CI on a second line
    if opts.show_effect
        welch = S(this_test & strncmp({S.method}, 'Welch', 5));
        if M.is_log
            effect = sprintf('ratio %.2f (95%% CI %.2f-%.2f)', welch.estimate, welch.ci_low, welch.ci_high);
        else
            effect = sprintf('difference %.1f/min (95%% CI %.1f to %.1f)', welch.estimate, welch.ci_low, welch.ci_high);
        end
        title({opts.names{m}, effect}, 'FontWeight', 'normal');
    else
        title(opts.names{m}, 'FontWeight', 'normal');
    end
    panel_letter(ax, char('A' + m - 1));
    if m == 1 && strcmp(opts.compare, 'seizure_vs_controls')
        legend([h_wt h_dsno], {'WT', 'DS no seizure'}, 'Location', 'southwest', 'Box', 'off');
    end
end
set_fonts(f, opts.font_size);

%% 3. Save
if ~isempty(opts.file_name)
    print(f, fullfile(out_dir, [opts.file_name '.png']), '-dpng', '-r300');
    print(f, fullfile(out_dir, [opts.file_name '.pdf']), '-dpdf', '-painters', '-bestfit');
end
end

%% ------------------------------------------------------------------------
function [y_bar, y_end, y_text, yl] = bracket_layout(v, is_log)
% Where to draw the significance bracket above the values v, and the y
% limits. y_bar = height of the horizontal bar; y_end = bottom of its two
% short ends; y_text = bottom of the asterisks; yl = y-axis limits.
% Log axis: positions are multiples of the values (equal steps on screen).
% Linear axis: positions are fractions of the data range.
if is_log
    y_bar  = max(v) * 1.25;
    y_end  = y_bar * 0.96;
    y_text = y_bar * 1.02;
    yl     = [min(v) * 0.8, y_bar * 1.4];
else
    data_range = max(max(v) - min(v), 1);
    y_bar  = max(v) + 0.10 * data_range;
    y_end  = y_bar - 0.04 * data_range;
    y_text = y_bar + 0.02 * data_range;
    yl     = [min(min(v), 0) - 0.05 * data_range, y_bar + 0.17 * data_range];
end
end
