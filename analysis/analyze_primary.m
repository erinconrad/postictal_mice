function analyze_primary(measure)
% ANALYZE_PRIMARY  Post-ictal depth per animal and the group comparisons,
% for one measure. Primary cohort only: one recording per mouse, its first
% seizure or, for a mouse that never had one, its first heating session
% (prepare_rows.m). Run run_postictal_batch.m (or refresh_selection.m) first;
% the figure scripts read this function's output.
%
%   analyze_primary                  RMS (amplitude; post-ictal suppression)
%   analyze_primary('delta_alpha')   delta/alpha power ratio (slowing, cfg.slowing)
%   analyze_primary('spike_rate')    spike rate
%   analyze_primary('delta')         delta power (cfg.bands)
%   analyze_primary('alpha')         alpha power (cfg.bands)
%   analyze_primary('delta_theta'), analyze_primary('theta')   optional, secondary
%
% Depth (depth_window.m): the measure relative to the animal's own
% pre-heating baseline, averaged over the 10 s windows (every 5 s) that lie
% entirely within the first N s after (pseudo-)offset, for each N in
% cfg.depth_windows_s (60, 120, 300 s). Ratio measures: geometric mean /
% baseline geometric mean (0.5 = half of baseline); spike rate: spikes/min
% minus the baseline rate. Controls are measured from their pseudo-offset
% (matched on temperature, or on time since heating start when there is no
% temperature record; see analysis_config.m).
%
% Statistics, for each depth window:
%   DS seizure vs controls (WT and DS no seizure together)   (Figure 2)
%   DS no seizure vs WT    (are the two control groups alike?; Figure S2)
%   each by Mann-Whitney U (main test; figures show its p) and by Welch
%   t-test on log10 depth (spike rate: on the differences), which gives
%   the effect size: ratio of geometric means (spike rate: difference of
%   means) with its 95% CI.
%   Primary hypotheses (DS seizure vs controls, 0-5 min, for each measure in
%   cfg.primary_measures): the Mann-Whitney p is also Bonferroni-corrected
%   (stats.p_bonferroni = p x number of primary measures; NaN otherwise).
%
% Second seizure: for DS seizure animals with a later analysable seizure
% (the next one by date; not SUDEP, not disputed), the same depths for that
% seizure (pa.s2_depth_0_<N>s; make_covariate_figure.m compares them).
%
% Outputs in <output>/<M.out_dir>/ (primary_analysis for RMS,
% primary_analysis_<measure> otherwise):
%   per_animal.csv     one row per animal: group, sex, age, seizure duration,
%                      depth for each window, session-2 depth
%   group_summary.csv  per group and window: n, geometric mean (spike rate:
%                      mean) with 95% CI
%   stats.csv          every test
%   missing_depth.csv  per group and window: animals analysed, with a depth,
%                      and without one (recording ended / too much artifact)
%   primary_analysis.mat   pa, gs, stats, measure, M (for the figures)

%% 1. Settings and data
if nargin < 1 || isempty(measure), measure = 'rms'; end
addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();   % scripts folder and its subfolders
cfg = analysis_config();
[~, M] = measure_view([], measure);                   % name, labels, output folder
out_dir = fullfile(cfg.out_root, M.out_dir);
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
windows_s = cfg.depth_windows_s;                      % 60 120 300

% Batch results: res = one row per recording (spreadsheet info, status);
% outs = each recording's 10 s window values (window_amplitude.m)
S = load(fullfile(cfg.out_root, 'postictal_batch', 'postictal_results.mat'), 'res', 'outs');
processed = ~ismember({S.res.status}, {'error', 'skipped'});

% Primary cohort, recordings the batch could process
in_cohort = find([S.res.in_primary] == 1 & processed);
res  = S.res(in_cohort);
n    = numel(res);
group = {res.group}';
is_seizure = strcmp(group, 'DS seizure');
is_wt      = strcmp(group, 'WT');
is_dsno    = strcmp(group, 'DS no seizure');
assert(all(is_seizure | is_wt | is_dsno), 'Unknown group label in the batch results');
fprintf('Measure: %s\nPrimary cohort: WT %d, DS no seizure %d, DS seizure %d\n', measure, ...
    sum(is_wt), sum(is_dsno), sum(is_seizure));

%% 2. Depth per animal, for each window
% depth(i, w) = animal i's depth over the first windows_s(w) s after offset
% why_missing{i, w} = '' if there is a value, else why not (depth_window.m)
depth = nan(n, numel(windows_s));
why_missing = repmat({''}, n, numel(windows_s));
for i = 1:n
    o = measure_view(S.outs{in_cohort(i)}, measure); % this measure in value / base_value
    for w = 1:numel(windows_s)
        [depth(i, w), why_missing{i, w}] = depth_window(o, res(i).sz_off, windows_s(w));
    end
end
% missing = one row per group and window: animals analysed, with a depth,
% and without one by reason (recording ended / too much artifact). Mice the
% batch could not process at all are counted in make_results_report.m.
missing = struct([]);
for g = {'WT', 'DS no seizure', 'DS seizure'}
    for w = 1:numel(windows_s)
        in_g = strcmp(group, g{1});
        q = struct('group', g{1}, 'window', sprintf('0-%d s', windows_s(w)), 'n_analysed', sum(in_g), ...
            'n_with_depth', sum(in_g & ~isnan(depth(:, w))), ...
            'n_recording_ended', sum(in_g & strcmp(why_missing(:, w), 'recording ended')), ...
            'n_too_much_artifact', sum(in_g & strcmp(why_missing(:, w), 'too much artifact')));
        if isempty(missing), missing = q; else, missing(end + 1) = q; end %#ok<AGROW>
    end
end
for w = 1:numel(windows_s)
    m_w = missing(strcmp({missing.window}, sprintf('0-%d s', windows_s(w))));
    fprintf('Depth over 0-%g s: %d of %d animals have a value (no value: recording ended %d, too much artifact %d)\n', ...
        windows_s(w), sum([m_w.n_with_depth]), n, sum([m_w.n_recording_ended]), sum([m_w.n_too_much_artifact]));
end

%% 3. Second seizure: the same mice's next seizure
% For each DS seizure mouse, its seizure_number 2 recording (the next
% seizure by recording date; prepare_rows.m), if it was processed, has
% seizure times and did not end in SUDEP. Mouse = mouse ID.
depth_s2 = nan(n, numel(windows_s));
s2_row   = nan(n, 1);                                 % its spreadsheet row
is_s2 = processed & [S.res.seizure_number] == 2 & ~strcmpi(strtrim({S.res.sudep}), 'yes') & ...
    ~isnan([S.res.sz_on]) & ~isnan([S.res.sz_off]);
for i = find(is_seizure)'
    k = find(is_s2 & [S.res.mouse_id] == res(i).mouse_id, 1);
    if isempty(k), continue; end
    s2_row(i) = S.res(k).sheet_row;
    o = measure_view(S.outs{k}, measure);
    for w = 1:numel(windows_s)
        depth_s2(i, w) = depth_window(o, S.res(k).sz_off, windows_s(w));
    end
end
fprintf('Second seizure: %d of %d DS seizure mice have one\n', sum(~isnan(s2_row)), sum(is_seizure));

%% 4. Statistics
% Two comparisons per window; each gets a Mann-Whitney row and a Welch row
% (compare_groups, below). The first group named is the one in the
% numerator of the effect size (seizure / controls; DS no seizure / WT).
comparisons = {'DS seizure vs controls', is_seizure, is_wt | is_dsno
               'DS no seizure vs WT',    is_dsno,    is_wt};
stats = struct([]);
for w = 1:numel(windows_s)
    measure_name = sprintf('depth 0-%d s', windows_s(w));
    for c = 1:size(comparisons, 1)
        [name, in_a, in_b] = comparisons{c, :};
        stats = compare_groups(stats, depth(in_a, w), depth(in_b, w), measure_name, name, M.is_log);
    end
end

% Bonferroni: the Mann-Whitney p of a primary hypothesis (DS seizure vs
% controls, 0 to cfg.depth_main_s, a measure in cfg.primary_measures) times
% the number of primary measures, capped at 1; NaN for every other row
n_primary = numel(cfg.primary_measures);
for k = 1:numel(stats)
    stats(k).p_bonferroni = NaN;
    if ismember(measure, cfg.primary_measures) && strcmp(stats(k).comparison, 'DS seizure vs controls') ...
            && strcmp(stats(k).measure, sprintf('depth 0-%d s', cfg.depth_main_s)) ...
            && strncmp(stats(k).method, 'Mann-Whitney', 12)
        stats(k).p_bonferroni = min(1, n_primary * stats(k).p);
    end
end

%% 5. Group summary: n and geometric mean (spike rate: mean) with 95% CI
groups = {'WT', is_wt; 'DS no seizure', is_dsno; 'controls', is_wt | is_dsno; 'DS seizure', is_seizure};
gs = struct([]);
for k = 1:size(groups, 1)
    for w = 1:numel(windows_s)
        v = depth(groups{k, 2} & ~isnan(depth(:, w)), w);
        q = struct('group', groups{k, 1}, 'window', sprintf('0-%d s', windows_s(w)), 'n', numel(v), ...
            'center', NaN, 'ci_low', NaN, 'ci_high', NaN);
        if numel(v) >= 2
            [q.center, ci] = group_center_ci(v, M.is_log);
            q.ci_low = ci(1); q.ci_high = ci(2);
        end
        if isempty(gs), gs = q; else, gs(end + 1) = q; end %#ok<AGROW>
    end
end
if M.is_log, center_name = 'geometric mean'; else, center_name = 'mean'; end

% Print the summary and the tests
fprintf('\n%-15s %-8s %4s  %s [95%% CI]\n', 'group', 'window', 'n', center_name);
for k = 1:numel(gs)
    fprintf('%-15s %-8s %4d  %.2f [%.2f, %.2f]\n', gs(k).group, gs(k).window, gs(k).n, gs(k).center, ...
        gs(k).ci_low, gs(k).ci_high);
end
fprintf('\n%-14s %-24s %10s %20s %9s %9s  %s\n', 'measure', 'comparison', 'estimate', '95% CI', 'p', ...
    'p (Bonf.)', 'method');
for k = 1:numel(stats)
    fprintf('%-14s %-24s %10.2f [%7.2f, %7.2f] %9.3g %9.3g  %s\n', stats(k).measure, stats(k).comparison, ...
        stats(k).estimate, stats(k).ci_low, stats(k).ci_high, stats(k).p, stats(k).p_bonferroni, stats(k).method);
end

%% 6. Check: artifact windows by group
% Fraction of 10 s windows removed as artifact, in the baseline and in the
% first cfg.depth_main_s after offset. A group difference here could bias
% the depth.
fprintf('\nArtifact windows (%% of windows):\n%-15s %10s %14s\n', 'group', 'baseline', ...
    sprintf('0-%g s post', cfg.depth_main_s));
for k = [1 2 4]
    frac_base = []; frac_post = [];
    for i = find(groups{k, 2})'
        o = S.outs{in_cohort(i)};
        in_post = o.t_start >= res(i).sz_off & o.t_end <= res(i).sz_off + cfg.depth_main_s;
        frac_base(end + 1) = mean(o.artifact(o.is_base));          %#ok<AGROW>
        frac_post(end + 1) = mean(o.artifact(in_post));           %#ok<AGROW>
    end
    fprintf('%-15s %10.1f %14.1f\n', groups{k, 1}, 100 * mean(frac_base), 100 * mean(frac_post, 'omitnan'));
end

%% 7. Save
% Per-animal table: one row per animal, depth columns named depth_0_60s,
% depth_0_120s, depth_0_300s (and s2_depth_... for the second seizure)
pa = struct([]);
for i = 1:n
    q = struct();
    q.sheet_row      = res(i).sheet_row;
    q.group          = res(i).group;
    q.project        = res(i).project;
    q.mouse_id       = res(i).mouse_id;
    q.sex            = upper(strtrim(res(i).sex));
    q.age_days       = res(i).age_days;
    q.pseudo_rescued = res(i).pseudo_rescued;
    q.sz_dur_s       = res(i).sz_off - res(i).sz_on;
    for w = 1:numel(windows_s)
        q.(sprintf('depth_0_%ds', windows_s(w))) = depth(i, w);
    end
    for w = 1:numel(windows_s)
        q.(sprintf('missing_0_%ds', windows_s(w))) = why_missing{i, w};   % '' = has a value
    end
    q.s2_sheet_row   = s2_row(i);
    for w = 1:numel(windows_s)
        q.(sprintf('s2_depth_0_%ds', windows_s(w))) = depth_s2(i, w);
    end
    if isempty(pa), pa = q; else, pa(end + 1) = q; end %#ok<AGROW>
end
write_results_csv(pa,    fullfile(out_dir, 'per_animal.csv'));
write_results_csv(gs,    fullfile(out_dir, 'group_summary.csv'));
write_results_csv(stats, fullfile(out_dir, 'stats.csv'));
write_results_csv(missing, fullfile(out_dir, 'missing_depth.csv'));
save(fullfile(out_dir, 'primary_analysis.mat'), 'pa', 'gs', 'stats', 'missing', 'measure', 'M');
fprintf('\nWritten to %s\n', out_dir);
end

%% ------------------------------------------------------------------------
function stats = compare_groups(stats, a, b, measure_name, comparison, is_log)
% Two rows appended to stats: Mann-Whitney U (estimate: ratio of medians,
% or difference for spike rate) and Welch t-test (ratio of geometric means
% with 95% CI, or difference of means for spike rate). a, b = the two
% groups' depths (NaNs dropped).
a = a(~isnan(a)); b = b(~isnan(b));
sizes = sprintf('%d vs %d', numel(a), numel(b));

[U, p] = mann_whitney(a, b);
if is_log, est_type = 'ratio of medians';      est = median(a) / median(b);
else,      est_type = 'difference of medians'; est = median(a) - median(b); end
stats = add_row(stats, measure_name, comparison, est_type, est, [NaN NaN], p, ...
    sprintf('Mann-Whitney U = %.1f (%s)', U, sizes));

if is_log
    [d, ci, p] = welch_t(log10(a), log10(b));
    stats = add_row(stats, measure_name, comparison, 'ratio of geometric means', 10^d, 10.^ci, p, ...
        sprintf('Welch t-test on log ratio (%s)', sizes));
else
    [d, ci, p] = welch_t(a, b);
    stats = add_row(stats, measure_name, comparison, 'difference of means', d, ci, p, ...
        sprintf('Welch t-test (%s)', sizes));
end
end

function [d, ci, p] = welch_t(a, b)
% Welch two-sample t-test: difference of means a - b, its 95% CI, and the
% two-sided p (no toolbox)
na = numel(a); nb = numel(b);
if na < 2 || nb < 2, d = NaN; ci = [NaN NaN]; p = NaN; return; end
va = var(a) / na; vb = var(b) / nb;
d  = mean(a) - mean(b);
se = sqrt(va + vb);
df = (va + vb)^2 / (va^2 / (na - 1) + vb^2 / (nb - 1));
t  = d / se;
p  = betainc(df / (df + t^2), df / 2, 0.5);
ci = d + [-1 1] * tq95(df) * se;
end

function s = add_row(s, measure_name, comparison, estimate_type, est, ci, p, method)
% Append one row to the statistics table
q = struct('measure', measure_name, 'comparison', comparison, 'estimate_type', estimate_type, ...
    'estimate', est, 'ci_low', ci(1), 'ci_high', ci(2), 'p', p, 'method', method);
if isempty(s), s = q; else, s(end + 1) = q; end
end
