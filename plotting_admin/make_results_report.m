function make_results_report(varargin)
% MAKE_RESULTS_REPORT  One HTML page with a draft of the Results text,
% every figure and the numbers behind it, all read from the analysis
% outputs (no numbers typed in by hand). Run after analyze_primary (all
% five measures), make_figures and spike_detector_performance.
%
% The draft Results text (section "Results text") fills in every number
% and chooses the wording that depends on the data (lower / higher,
% significant or not, which measures). The descriptions of the time
% courses are group medians per 30 s bin, not tests. Check the wording
% before using it.
%
%   make_results_report
%   make_results_report('embed_images', false)   % link the PNGs instead
%
% Options (name-value pairs)
%   file_name     default 'results_report.html', written to <output>/
%                 (Table 1 is also written to <output>/table1.csv)
%                 Also writes <output>/cohort_by_row.xlsx (and .csv): the cohort
%                 spreadsheet with columns saying how each row was used
%                 (write_cohort_spreadsheet.m)
%   reviewer      spike-marking reviewer for the detector validation
%                 (default 'EC': spike_review/performance_EC.csv)
%   embed_images  true (default): figures stored inside the HTML file, so
%                 it can be sent on its own; false: links to
%                 <output>/figures/*.png (smaller file, must stay beside
%                 the figures folder)
%
% Reads, from <output>/:
%   postictal_batch/postictal_results.mat     cohort counts, failed recordings
%   primary_analysis*/primary_analysis.mat    group summaries and tests (5 measures)
%   figures/figure1_example.csv               the example seizures (one row each)
%   figures/figure3_summary.csv, figures/figureS4_band_bins_summary.csv
%   figures/figureS1_spike_examples.csv, figures/figureS5_clinical_stats.csv
%   spike_review/performance_<reviewer>.csv   spike detector, test half
%   figures/*.png

%% 1. Settings and inputs
addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();
cfg = analysis_config();
opts = struct('file_name', 'results_report.html', 'embed_images', true, 'reviewer', 'EC');
for k = 1:2:numel(varargin)
    assert(isfield(opts, varargin{k}), 'Unknown option %s', varargin{k});
    opts.(varargin{k}) = varargin{k + 1};
end
fig_dir   = fullfile(cfg.out_root, 'figures');
windows_s = cfg.depth_windows_s;                     % 60 120 300
main_s    = cfg.depth_main_s;                        % 300

% Results per measure (analyze_primary.m): R.(measure) has pa, gs, stats, M
% The primary measures (amplitude, slowing = cfg.slowing, spiking), then the
% slowing ratio's two bands separately (Figure S3). Delta/theta and theta
% are added to the tables as a secondary reference if they were analysed.
slow_bands = strsplit(cfg.slowing, '_');             % e.g. delta, alpha
measures = [cfg.primary_measures, slow_bands];
for extra = {'delta_theta', 'theta'}
    [~, M] = measure_view([], extra{1});
    if ~ismember(extra{1}, measures) && exist(fullfile(cfg.out_root, M.out_dir, 'primary_analysis.mat'), 'file') == 2
        measures{end + 1} = extra{1}; %#ok<AGROW>
    end
end
band_txt = @(b) sprintf('%g&ndash;%g Hz', cfg.bands{strcmp(cfg.bands(:, 1), b), 2});   % from cfg.bands
greek = @(b) ['&' b ';'];                            % 'alpha' -> '&alpha;'
ratio_html = @(m) strjoin(cellfun(greek, strsplit(m, '_'), 'UniformOutput', false), '/');   % '&delta;/&alpha;'
names = cell(size(measures));
for m = 1:numel(measures)
    switch measures{m}
        case 'rms',        names{m} = 'Amplitude (RMS / baseline)';
        case 'spike_rate', names{m} = 'Spiking (spikes/min &minus; baseline)';
        case cfg.slowing,  names{m} = ['Slowing (' ratio_html(measures{m}) ' / baseline)'];
        otherwise
            if any(measures{m} == '_')               % another ratio (secondary)
                names{m} = [ratio_html(measures{m}) ' / baseline (secondary)'];
            else
                names{m} = sprintf('%s power (%s) / baseline', [upper(measures{m}(1)) measures{m}(2:end)], ...
                    band_txt(measures{m}));
            end
    end
end
R = struct();
for m = 1:numel(measures)
    [~, M] = measure_view([], measures{m});
    result_file = fullfile(cfg.out_root, M.out_dir, 'primary_analysis.mat');
    assert(exist(result_file, 'file') == 2, 'No %s: run analyze_primary(''%s'') first', result_file, measures{m});
    R.(measures{m}) = load(result_file);
end
B = load(fullfile(cfg.out_root, 'postictal_batch', 'postictal_results.mat'), 'res');
res = B.res;
example = read_results_csv(fullfile(fig_dir, 'figure1_example.csv'));
Q3 = read_results_csv(fullfile(fig_dir, 'figure3_summary.csv'));                 % Figure 3 bins
Q4 = read_results_csv(fullfile(fig_dir, 'figureS4_band_bins_summary.csv')); % frequency-band bins
T5 = read_results_csv(fullfile(fig_dir, 'figureS5_clinical_stats.csv'));          % clinical variables
spike_file = fullfile(fig_dir, 'figureS1_spike_examples.csv');
perf_file  = fullfile(cfg.shared_root, 'spike_review', sprintf('performance_%s.csv', opts.reviewer));
if exist(perf_file, 'file'), perf = read_results_csv(perf_file); else, perf = []; end
cond_file = strrep(perf_file, '.csv', '_by_condition.csv');    % baseline vs post-ictal accuracy
if exist(cond_file, 'file'), perf_cond = read_results_csv(cond_file); else, perf_cond = []; end

% html = the page, one cell per line
html = {'<!doctype html>', '<html lang="en">', '<head>', '<meta charset="utf-8">', ...
    '<meta name="viewport" content="width=device-width, initial-scale=1">', ...
    '<title>Post-ictal ECoG Results</title>', page_style(), '</head>', '<body>', ...
    '<h1>Results: post-ictal ECoG after hyperthermia-induced seizures</h1>', ...
    sprintf('<p class="sub">Generated %s by make_results_report.m from %s. Every number is read from the analysis outputs.</p>', ...
    datestr(now, 'yyyy-mm-dd HH:MM'), esc(cfg.out_root))};

%% 1b. Draft Results text (results_text, below)
html = [html, results_text(res, R, Q3, Q4, T5, perf, perf_cond, example, cfg)];

%% 2. Cohort
in_cohort = [res.in_primary] == 1;
analysed  = in_cohort & ~ismember({res.status}, {'error', 'skipped'});
groups = {'WT', 'DS no seizure', 'DS seizure'};
window_list = strjoin(arrayfun(@(w) sprintf('%g', w / 60), windows_s, 'UniformOutput', false), ' / ');
rows = cell(numel(groups), 4);
for g = 1:numel(groups)
    is_g = strcmp({res.group}, groups{g});
    pa = R.rms.pa(strcmp({R.rms.pa.group}, groups{g}));
    n_with_depth = arrayfun(@(w) sprintf('%d', sum(~isnan([pa.(sprintf('depth_0_%ds', w))]))), windows_s, ...
        'UniformOutput', false);
    rows(g, :) = {groups{g}, sprintf('%d', sum(in_cohort & is_g)), sprintf('%d', sum(analysed & is_g)), ...
        strjoin(n_with_depth, ' / ')};
end
html = [html, {'<h2>Cohort</h2>', ...
    ['<p>One recording per mouse: its first seizure, or, for a mouse that never had a seizure, its first ' ...
    'heating session. Seizures that ended in SUDEP and disputed seizures left out. Controls = WT and DS no ' ...
    'seizure mice that never had a seizure.</p>'], ...
    table_html({'Group', 'In cohort', 'Analysed', sprintf('With an amplitude depth, 0&ndash;%s min', window_list)}, rows)}];
% Pre-heating baseline actually used (baseline_period.m): median and range
% of its length, among the analysed recordings
base_len = [res(analysed).base_end_s] - [res(analysed).base_start_s];
failed_baseline = in_cohort & ~analysed & ~cellfun(@isempty, strfind({res.message}, 'baseline'));
html = [html, {sprintf(['<p>Pre-heating baseline: median %.0f s (range %.0f&ndash;%.0f s); %d of %d ' ...
    'recordings had less than %g s of recording before heating and used all of it (at least %g s, with at ' ...
    'least 10 artifact-free 10 s windows, was required; %d recording(s) excluded for too little ' ...
    'baseline).</p>'], median(base_len), min(base_len), ...
    max(base_len), sum(base_len < cfg.base_dur_s - 1e-6), numel(base_len), cfg.base_dur_s, cfg.base_min_s, ...
    sum(failed_baseline))}];
failed = res(in_cohort & ~analysed);
if ~isempty(failed)
    items = arrayfun(@(x) sprintf('<li>Mouse %d (%s, spreadsheet row %d): %s</li>', x.mouse_id, esc(x.group), ...
        x.sheet_row, esc(x.message)), failed, 'UniformOutput', false);
    html = [html, {'<p>Not analysed:</p>', '<ul>'}, items(:)', {'</ul>'}];
end

%% 2b. Mice without a depth value, by group, window and reason
% (analyze_primary.m: missing). Artifact windows and recording length are
% the same for every measure, so the counts should be too; checked here.
same_for_all = true;
for m = 2:numel(measures)
    same_for_all = same_for_all && isequal(R.(measures{m}).missing, R.rms.missing);
end
rows = {};
for k = 1:numel(R.rms.missing)
    q = R.rms.missing(k);
    window_min = sscanf(q.window, '0-%d s') / 60;     % '0-300 s' -> 5
    rows(end + 1, :) = {q.group, sprintf('0&ndash;%g min', window_min), sprintf('%d', q.n_analysed), ...
        sprintf('%d', q.n_with_depth), sprintf('%d', q.n_recording_ended), sprintf('%d', q.n_too_much_artifact)}; %#ok<AGROW>
end
if same_for_all
    note = 'The counts are the same for every measure.';
else
    note = 'Counts shown for amplitude; they differ between measures (see each measure''s missing_depth.csv).';
end
html = [html, {'<h2>Mice without a depth value</h2>', ...
    sprintf(['<p>Depth is not computed when the recording ends before the stretch does, or when fewer than ' ...
    'half of the 10 s windows in it are artifact-free. %s</p>'], note), ...
    table_html({'Group', 'Window after offset', 'Analysed', 'With a depth', 'Recording ended', 'Too much artifact'}, rows)}];

%% 3. Figure 1: example seizures, one column each
ex_txt = cell(1, numel(example));
for j = 1:numel(example)
    ex_txt{j} = sprintf('%s: mouse %d (%s, spreadsheet row %d), seizure %.0f s, amplitude %.2f &times; baseline over 0&ndash;1 min', ...
        sprintf('%c&ndash;%c', 'A' + 5 * (j - 1), 'A' + 5 * (j - 1) + 4), example(j).mouse_id, ...
        esc(example(j).project), example(j).sheet_row, example(j).sz_dur_s, example(j).depth_0_60s);
end
html = [html, {'<h2>Figure 1: example seizures</h2>', ...
    image_html(fullfile(fig_dir, 'figure1.png'), opts.embed_images, 560 * numel(example)), ...
    ['<p class="cap">' strjoin(ex_txt, '; ') '. In each column, from the top: raw ECoG, detected spikes ' ...
    'outside the seizure (green); spectrogram, power relative to baseline; amplitude, slowing and spiking ' ...
    'in 10 s windows (dots) and their 30 s moving average (line); yellow = seizure; grey = artifact. The ' ...
    'columns share every y axis and the colour scale.</p>']}];

%% 4. Spike detections (Figure S1)
if exist(spike_file, 'file')
    T = read_results_csv(spike_file);
    html = [html, {'<h2>Spike detections after offset (Figure S1)</h2>', ...
        image_html(fullfile(fig_dir, 'figureS1_spike_examples.png'), opts.embed_images), ...
        sprintf(['<p class="cap">Notch-filtered ECoG from %g to %g s after offset in %d randomly chosen DS ' ...
        'seizure mice; red circles = spike detections (%d in total, %d&ndash;%d per mouse); dotted lines ' ...
        'every 1 s.</p>'], T(1).start_s, T(1).start_s + T(1).len_s, ...
        numel(T), sum([T.n_detections]), min([T.n_detections]), max([T.n_detections]))}];
end

%% 5. DS seizure vs controls, every measure and window (Figure 2, S3)
html = [html, {'<h2>DS seizure vs controls (Figures 2 and S3)</h2>', ...
    image_html(fullfile(fig_dir, 'figure2.png'), opts.embed_images), ...
    image_html(fullfile(fig_dir, 'figureS3_slowing_bands.png'), opts.embed_images, 640), ...
    ['<p class="cap">Depth = the measure relative to the mouse''s pre-heating baseline, averaged over the ' ...
    'first N min after (pseudo-)offset. Group values: geometric mean (spiking: mean) with 95% CI. Effect: ' ...
    'DS seizure / controls as a ratio of geometric means (spiking: difference of means) with 95% CI, Welch ' ...
    't-test. p: Mann-Whitney U. At 0&ndash;' num2str(main_s / 60) ' min the three comparisons are the primary ' ...
    'hypotheses and are Bonferroni-corrected (corrected p in brackets; Figure 2''s asterisks use it); the other ' ...
    'windows and ' slow_bands{1} ' and ' slow_bands{2} ' separately (Figure S3) are secondary, uncorrected.</p>'], ...
    ['<p class="cap">' n_text(R.rms.missing, main_s, {'DS seizure', 'WT', 'DS no seizure'}) '</p>']}];
for w = windows_s
    rows = cell(numel(measures), 5);
    for m = 1:numel(measures)
        X = R.(measures{m});
        [sz, n_sz]     = group_text(X.gs, 'DS seizure', w, X.M.is_log);
        [ctrl, n_ctrl] = group_text(X.gs, 'controls', w, X.M.is_log);
        [effect, p]    = test_text(X.stats, w, 'DS seizure vs controls', X.M.is_log);
        rows(m, :) = {names{m}, sprintf('%s (%d)', sz, n_sz), sprintf('%s (%d)', ctrl, n_ctrl), effect, p};
    end
    html = [html, {sprintf('<h3>0&ndash;%g min after offset</h3>', w / 60), ...
        table_html({'Measure', 'DS seizure (n)', 'Controls (n)', 'Effect (95% CI)', 'p'}, rows)}];
end

%% 6. Control groups (Figure S2)
html = [html, {'<h2>WT vs DS no seizure (Figure S2)</h2>', ...
    image_html(fullfile(fig_dir, 'figureS2_control_groups.png'), opts.embed_images), ...
    ['<p class="cap">' n_text(R.rms.missing, main_s, {'WT', 'DS no seizure'}) ' p: Mann-Whitney U, uncorrected.</p>']}];
rows = cell(3, 5);
for m = 1:3
    X = R.(measures{m});
    [wt, n_wt]     = group_text(X.gs, 'WT', main_s, X.M.is_log);
    [dsno, n_dsno] = group_text(X.gs, 'DS no seizure', main_s, X.M.is_log);
    [effect, p]    = test_text(X.stats, main_s, 'DS no seizure vs WT', X.M.is_log);
    rows(m, :) = {names{m}, sprintf('%s (%d)', wt, n_wt), sprintf('%s (%d)', dsno, n_dsno), effect, p};
end
html = [html, {sprintf('<h3>0&ndash;%g min after offset</h3>', main_s / 60), ...
    table_html({'Measure', 'WT (n)', 'DS no seizure (n)', 'Effect, DS no seizure / WT (95% CI)', 'p'}, rows)}];

%% 7. Time course (Figures 3 and S4), with each band's power at selected bins
html = [html, {'<h2>Time course (Figures 3 and S4)</h2>', ...
    image_html(fullfile(fig_dir, 'figure3.png'), opts.embed_images), ...
    image_html(fullfile(fig_dir, 'figureS4_band_bins.png'), opts.embed_images, 700), ...
    '<p class="cap">30 s bins before onset and after offset; median and interquartile range across mice.</p>'}];
html = [html, {['<p class="cap">' bin_n_text(Q3) '</p>']}];
show_bins = [0 30 60 120 300 570];                   % bin start, s after offset
bands_q4 = unique({Q4.measure}, 'stable');           % the bands in Figure S4, in order
rows = cell(numel(show_bins), 1 + 2 * numel(bands_q4));
for b = 1:numel(show_bins)
    rows{b, 1} = sprintf('%g&ndash;%g s', show_bins(b), show_bins(b) + 30);
    col = 2;
    for band = bands_q4
        for grp = {'controls', 'DS seizure'}
            q = bin_row(Q4, band{1}, grp{1}, show_bins(b));
            if isempty(q) || isnan(q.median)
                rows{b, col} = '&ndash;';
            else
                rows{b, col} = sprintf('%.2f [%.2f&ndash;%.2f]', q.median, q.q25, q.q75);
            end
            col = col + 1;
        end
    end
end
band_head = {};
for band = bands_q4
    band_head = [band_head, {[band{1} ': controls'], [band{1} ': DS seizure']}]; %#ok<AGROW>
end
html = [html, {'<h3>Band power after offset (median [IQR], ratio to baseline)</h3>', ...
    table_html([{'Time after offset'}, band_head], rows)}];

%% 8. Seizure duration, age, sex, seizure 1 vs 2 (Figure S5)
rows = cell(numel(T5), 5);
for k = 1:numel(T5)
    m = strcmp(measures, T5(k).measure);
    rows(k, :) = {names{m}, esc(T5(k).factor), esc(T5(k).test), sprintf('%.2f (n = %d)', T5(k).estimate, T5(k).n), ...
        p_html(T5(k).p)};
end
html = [html, {'<h2>Seizure duration, age, sex, seizure 1 vs 2 (Figure S5)</h2>', ...
    image_html(fullfile(fig_dir, 'figureS5_clinical.png'), opts.embed_images), ...
    sprintf(['<p class="cap">DS seizure mice, depth over 0&ndash;%g min. Exploratory; p-values not corrected. ' ...
    '%s Seizure 1 vs 2: mice with a depth for both seizures (n in the table).</p>'], ...
    main_s / 60, n_text(R.rms.missing, main_s, {'DS seizure'})), ...
    table_html({'Measure', 'Factor', 'Test', 'Estimate', 'p'}, rows)}];

%% 9. The cohort spreadsheet: how each row was used (write_cohort_spreadsheet.m)
write_cohort_spreadsheet(res, R.rms.pa, cfg);

%% 10. Write
html = [html, {'</body>', '</html>'}];
out_file = fullfile(cfg.out_root, opts.file_name);
fid = fopen(out_file, 'w', 'n', 'UTF-8');
assert(fid > 0, 'Could not write %s', out_file);
fprintf(fid, '%s\n', html{:});
fclose(fid);
fprintf('Written to %s\n', out_file);
end

%% ------------------------------------------------------------------------
function html = results_text(res, R, Q3, Q4, T5, perf, perf_cond, example, cfg)
% Draft Results paragraphs (HTML), every number from the outputs
main_s = cfg.depth_main_s;
min_txt = sprintf('%g', main_s / 60);                % '5'
html = {'<h2>Results text (draft)</h2>', ['<p class="cap">Generated from the outputs below. Wording ' ...
    'that depends on the data (lower/higher, significant or not) is chosen by the script; time-course ' ...
    'statements are group medians per 30 s bin, not tests. Check before using.</p>']};

% --- Cohort ---------------------------------------------------------------
mouse = [res.mouse_id];
mice = unique(mouse);
is_ds_mouse  = arrayfun(@(m) any(strncmp({res(mouse == m).group}, 'DS', 2)), mice);
is_wt_mouse  = arrayfun(@(m) any(strcmp({res(mouse == m).group}, 'WT')), mice);
assert(~any(is_ds_mouse & is_wt_mouse), 'A mouse is listed as both WT and DS');
had_seizure  = arrayfun(@(m) any(strcmp({res(mouse == m).group}, 'DS seizure')), mice);
n_sz_rows = sum(strcmp({res.group}, 'DS seizure'));
analysed_row = [res.in_primary] == 1 & ~ismember({res.status}, {'error', 'skipped'});
in_final = arrayfun(@(m) any(analysed_row(mouse == m)), mice);

% Why each excluded mouse is out: its rows' exclusion reason (prepare_rows.m)
% or, if its chosen recording was not processed, the batch message
why = cell(size(mice));
for i = find(~in_final)
    r = res(mouse == mice(i));
    chosen = r([r.in_primary] == 1);
    if ~isempty(chosen)
        why{i} = processing_reason(chosen(1).message);
    else
        reason = r(1).exclude_reason;
        if ~isempty(strfind(reason, 'SUDEP'))
            why{i} = 'their first seizure ended in SUDEP';
        elseif ~isempty(strfind(reason, 'disputed'))
            why{i} = 'a second reviewer judged a seizure absent or uncertain';
        elseif ~isempty(strfind(reason, 'onset/offset'))
            why{i} = 'their first seizure had no onset/offset times';
        else
            why{i} = reason;
        end
    end
end
reasons = unique(why(~in_final));
reason_parts = cell(size(reasons));
for k = 1:numel(reasons)
    is_k = ~in_final & strcmp(why, reasons{k});
    reason_parts{k} = sprintf('%s because %s', ...
        genotype_split(sum(is_k & is_wt_mouse), sum(is_k & is_ds_mouse)), reasons{k});
end
final_rows = res(analysed_row);
n_final = @(g) sum(strcmp({final_rows.group}, g));
n_wt = n_final('WT'); n_dsno = n_final('DS no seizure'); n_dssz = n_final('DS seizure');

% Heating sessions of the final mice that are not their primary recording
other = res(ismember(mouse, mice(in_final)) & [res.in_primary] ~= 1);
reason_of = {other.exclude_reason};
n_later_sz  = sum(strncmp(reason_of, 'later seizure', 13));
n_nosz      = sum(strncmp(reason_of, 'no seizure', 10));
n_later_ctl = sum(strncmp(reason_of, 'later heating session', 21));
n_other     = numel(other) - n_later_sz - n_nosz - n_later_ctl;
session_parts = {};
if n_later_sz > 0,  session_parts{end + 1} = sprintf('%d later seizures', n_later_sz); end
if n_nosz > 0,      session_parts{end + 1} = sprintf(['%d sessions without a seizure in mice that had a ' ...
        'seizure in another session'], n_nosz); end
if n_later_ctl > 0, session_parts{end + 1} = sprintf('%d later heating sessions of control mice', n_later_ctl); end
if n_other > 0,     session_parts{end + 1} = sprintf('%d for other reasons', n_other); end

dur = [final_rows.sz_off] - [final_rows.sz_on];
is_sz_final = strcmp({final_rows.group}, 'DS seizure');
miss = R.rms.missing(strcmp({R.rms.missing.window}, sprintf('0-%d s', main_s)));
n_ended = sum([miss.n_recording_ended]); n_art = sum([miss.n_too_much_artifact]);
with_depth = @(groups) sum([miss(ismember({miss.group}, groups)).n_with_depth]);

p_cohort = sprintf(['The original cohort consisted of %d wild-type (WT) mice and %d DS mice, %d of whom had at ' ...
    'least one seizure, with %d heating sessions and %d seizures in total. %d mice were excluded: %s. The ' ...
    'final cohort was %d mice (%d WT, %d DS without a seizure, %d DS with a seizure; Table 1); the %d WT and DS ' ...
    'no-seizure mice together formed the control group. Within the final cohort, %d further heating ' ...
    'sessions were excluded from the primary analysis (%s), leaving one heating session per mouse. Median ' ...
    '(IQR) seizure duration was %s s, and median (IQR) pseudo-seizure duration in controls was %s s. A ' ...
    '%s-min post-ictal depth could be computed for %d DS seizure and %d control mice'], ...
    sum(is_wt_mouse), sum(is_ds_mouse), sum(had_seizure), numel(res), n_sz_rows, sum(~in_final), ...
    join_list(reason_parts), sum(in_final), n_wt, n_dsno, n_dssz, n_wt + n_dsno, numel(other), ...
    join_list(session_parts), med_iqr(dur(is_sz_final), '%.0f'), med_iqr(dur(~is_sz_final), '%.0f'), ...
    min_txt, with_depth({'DS seizure'}), with_depth({'WT', 'DS no seizure'}));
if n_ended + n_art > 0
    p_cohort = sprintf('%s; for %d it could not (recording ended before %s min: %d; too much artifact: %d). Together these formed our primary analysis cohort.', ...
        p_cohort, n_ended + n_art, min_txt, n_ended, n_art);
else
    p_cohort = [p_cohort '.'];
end
html = [html, {'<h3>Cohort</h3>', ['<p>' p_cohort '</p>']}, cohort_table(res, final_rows, R, cfg)];

% --- Spike detector -----------------------------------------------------------
if isempty(perf)
    p_spk = '(No spike_review/performance file: run spike_detector_performance.)';
else
    q = perf(strcmp({perf.thresholds}, 'chosen') & strcmp({perf.pages}, 'all'));
    qb = perf(strcmp({perf.thresholds}, 'chosen') & strcmp({perf.pages}, 'baseline'));
    p_spk = sprintf(['With the thresholds chosen on the tuning half (%g &times; the median and %g &micro;V), ' ...
        'the detector on the test half (%d animals; %d 15 s pages; %d marked spikes) had a sensitivity of %.2f ' ...
        '(95%% CI %.2f&ndash;%.2f) and a positive predictive value of %.2f (%.2f&ndash;%.2f), with %.2f false ' ...
        'detections per minute on baseline pages.'], q.tmul, q.absthresh, q.n_mice, q.n_pages, q.tp + q.fn, ...
        q.sensitivity, q.sens_ci_low, q.sens_ci_high, q.ppv, q.ppv_ci_low, q.ppv_ci_high, qb.fp_per_min);
    % Baseline vs post-ictal accuracy (spike_detector_performance step 4)
    if ~isempty(perf_cond)
        Cn = perf_cond;
        cs = Cn(strcmp({Cn.measure}, 'sensitivity')); cp = Cn(strcmp({Cn.measure}, 'ppv'));
        both_include_0 = cs.diff_ci_low <= 0 && cs.diff_ci_high >= 0 && cp.diff_ci_low <= 0 && cp.diff_ci_high >= 0;
        if both_include_0, verdict = 'did not differ between'; else, verdict = 'differed between'; end
        p_spk = sprintf(['%s Detection accuracy %s baseline and post-ictal pages (all %d animals; sensitivity ' ...
            '%.2f vs %.2f, difference %+.2f, 95%% CI %.2f to %.2f; positive predictive value %.2f vs %.2f, ' ...
            'difference %+.2f, 95%% CI %.2f to %.2f; bootstrap over animals).'], p_spk, verdict, cs.n_mice, ...
            cs.baseline, cs.post, cs.difference, cs.diff_ci_low, cs.diff_ci_high, ...
            cp.baseline, cp.post, cp.difference, cp.diff_ci_low, cp.diff_ci_high);
    else
        p_spk = [p_spk ' (Baseline vs post-ictal accuracy: rerun spike_detector_performance.)'];
    end
end
spike_csv = fullfile(cfg.out_root, 'figures', 'figureS1_spike_examples.csv');
if exist(spike_csv, 'file')
    T = read_results_csv(spike_csv);
    p_spk = sprintf(['%s Figure S1 shows the ECoG from %g to %g s after seizure offset in %d randomly ' ...
        'selected DS seizure mice, with the detections superimposed.'], p_spk, T(1).start_s, ...
        T(1).start_s + T(1).len_s, numel(T));
end
html = [html, {'<h3>Spike detector validation</h3>', ['<p>' p_spk '</p>']}];

% --- Post-ictal depth ---------------------------------------------------------
primary = cfg.primary_measures;                       % rms, cfg.slowing, spike_rate
slow_bands = strsplit(cfg.slowing, '_');              % e.g. delta, alpha
ratio_word = strjoin(slow_bands, '/');                % 'delta/alpha'
short   = {'amplitude', 'slowing', 'spiking'};
% Where each example's 0-1 min amplitude ranks among the DS seizure mice
sz_pa = R.rms.pa(strcmp({R.rms.pa.group}, 'DS seizure'));
d60 = [sz_pa.depth_0_60s]; d60 = d60(~isnan(d60));
ex_parts = cell(1, numel(example));
for j = 1:numel(example)
    rank_j = sum(d60 < example(j).depth_0_60s) + 1;
    ex_parts{j} = sprintf(['mouse %d (seizure %.0f s; amplitude %.2f &times; baseline over the first minute ' ...
        'after offset, the %s lowest of %d)'], example(j).mouse_id, example(j).sz_dur_s, ...
        example(j).depth_0_60s, ordinal(rank_j), numel(d60));
end
if numel(example) == 1
    p1 = sprintf(['Figure 1 shows an example seizure, %s, with its spectrogram and the amplitude, ' ...
        '%s ratio and spike rate over time.'], ex_parts{1}, ratio_word);
else
    words = {'two', 'three', 'four'};
    p1 = sprintf(['Figure 1 shows %s example seizures, %s, with their spectrograms and the amplitude, ' ...
        '%s ratio and spike rate over time (DS seizure group median over the first minute: %.2f).'], ...
        words{min(numel(example), 4) - 1}, join_list(ex_parts), ratio_word, median(d60));
end

% Control subgroups (Figure S2): WT relative to DS no seizure, uncorrected
sig = {}; ns = {};
sig_only_uncorrected = {}; sig_corrected = {}; ns_names = {};   % measure names, for the last sentence
for m = 1:3
    X = R.(primary{m});
    [mw, ~] = mw_row(X.stats, main_s, 'DS no seizure vs WT');
    wt = depth_values(X.pa, {'WT'}, main_s); dsno = depth_values(X.pa, {'DS no seizure'}, main_s);
    if mw.p < 0.05
        if median(wt) < median(dsno), dirn = 'lower'; else, dirn = 'higher'; end
        sig{end + 1} = sprintf(['significantly %s %s relative to baseline in WT mice (median (IQR) %s) than in ' ...
            'DS no-seizure mice (%s; Mann&ndash;Whitney p = %s uncorrected, %s after Bonferroni correction for ' ...
            'three measures)'], dirn, short{m}, med_iqr(wt, fmt_of(X.M)), med_iqr(dsno, fmt_of(X.M)), ...
            p_txt(mw.p), p_txt(min(1, 3 * mw.p))); %#ok<AGROW>
        if 3 * mw.p < 0.05
            sig_corrected{end + 1} = short{m}; %#ok<AGROW>
        else
            sig_only_uncorrected{end + 1} = short{m}; %#ok<AGROW>
        end
    else
        ns{end + 1} = sprintf('%s (p = %s)', short{m}, p_txt(mw.p)); %#ok<AGROW>
        ns_names{end + 1} = short{m}; %#ok<AGROW>
    end
end
% Why the subgroups were combined, from which differences survived correction
if ~isempty(sig_corrected)
    combine = sprintf(['Although the subgroups differed in %s after correction for three measures, they were ' ...
        'combined into one control group.'], join_list(sig_corrected));
elseif ~isempty(sig_only_uncorrected)
    combine = sprintf(['Because the subgroups differed only modestly in %s, not significantly after correction ' ...
        'for three measures'], join_list(sig_only_uncorrected));
    if ~isempty(ns_names)
        combine = sprintf('%s, and did not differ in %s', combine, strrep(join_list(ns_names), ' and ', ' or '));
    end
    combine = [combine ', they were combined into one control group.'];
else
    combine = 'Because the subgroups did not differ in any measure, they were combined into one control group.';
end
parts = {};
if ~isempty(sig), parts{end + 1} = join_list(sig); end
if ~isempty(ns), parts{end + 1} = ['no significant difference in ' join_list(ns)]; end
p2 = sprintf('Comparing the two control subgroups at 0&ndash;%s min after (pseudo-)offset showed %s (Figure S2). %s', ...
    min_txt, join_list(parts), combine);

% DS seizure vs controls (Figure 2), Bonferroni-corrected
labels = {'RMS amplitude', ['The ' ratio_word ' power ratio'], 'Spike rate'};
sentences = cell(1, 3); n_sig = 0;
for m = 1:3
    X = R.(primary{m});
    [mw, welch] = mw_row(X.stats, main_s, 'DS seizure vs controls');
    p_b = mw.p_bonferroni;
    sz = depth_values(X.pa, {'DS seizure'}, main_s); ctl = depth_values(X.pa, {'WT', 'DS no seizure'}, main_s);
    U = sscanf(mw.method, 'Mann-Whitney U = %f');
    if X.M.is_log
        scale_txt = 'as a ratio to baseline';
        effect = sprintf('ratio of geometric means %.2f, 95%% CI %.2f&ndash;%.2f', welch.estimate, welch.ci_low, welch.ci_high);
        up = welch.estimate > 1;
    else
        scale_txt = 'as the difference from baseline (spikes/min)';
        effect = sprintf('difference of means %.1f spikes/min, 95%% CI %.1f to %.1f', welch.estimate, welch.ci_low, welch.ci_high);
        up = welch.estimate > 0;
    end
    stat = sprintf('%s; Mann&ndash;Whitney U = %g, Bonferroni-corrected p = %s', effect, U, p_txt(p_b));
    if p_b < 0.05
        n_sig = n_sig + 1;
        if up, dirn = 'higher'; else, dirn = 'lower'; end
        sentences{m} = sprintf(['%s over the first %s min after offset, %s, was %s in DS seizure mice (median ' ...
            '(IQR) %s) than in controls (%s) (%s).'], labels{m}, min_txt, scale_txt, dirn, ...
            med_iqr(sz, fmt_of(X.M)), med_iqr(ctl, fmt_of(X.M)), stat);
    else
        sentences{m} = sprintf(['%s over the first %s min after offset, %s, did not differ significantly between ' ...
            'DS seizure mice (median (IQR) %s) and controls (%s) (%s).'], labels{m}, min_txt, scale_txt, ...
            med_iqr(sz, fmt_of(X.M)), med_iqr(ctl, fmt_of(X.M)), stat);
    end
end
if n_sig == 3
    lead = 'All three post-ictal measures differed between DS seizure mice and controls (Figure 2; controls measured from pseudo-seizure times).';
else
    lead = sprintf('%d of the three post-ictal measures differed between DS seizure mice and controls (Figure 2; controls measured from pseudo-seizure times).', n_sig);
end
p3 = [lead ' ' strjoin(sentences, ' ')];

% The slowing ratio's two bands separately (Figure S3), uncorrected
band_parts = cell(1, 2); bands = slow_bands;
for b = 1:2
    X = R.(bands{b});
    [mw, welch] = mw_row(X.stats, main_s, 'DS seizure vs controls');
    sz = depth_values(X.pa, {'DS seizure'}, main_s); ctl = depth_values(X.pa, {'WT', 'DS no seizure'}, main_s);
    vals = sprintf('median (IQR) %s vs %s; ratio of geometric means %.2f, 95%% CI %.2f&ndash;%.2f; p = %s', ...
        med_iqr(sz, '%.2f'), med_iqr(ctl, '%.2f'), welch.estimate, welch.ci_low, welch.ci_high, p_txt(mw.p));
    if mw.p < 0.05
        if welch.estimate < 1, dirn = 'lower'; else, dirn = 'higher'; end
        band_parts{b} = sprintf('%s power was %s in DS seizure mice than in controls (%s)', bands{b}, dirn, vals);
    else
        band_parts{b} = sprintf('%s power did not differ (%s)', bands{b}, vals);
    end
end
p4 = sprintf(['Analysed separately (secondary, uncorrected), %s, and %s (Figure S3).'], band_parts{1}, band_parts{2});
html = [html, {'<h3>Post-ictal depth</h3>', ['<p>' p1 ' ' p2 '</p>'], ['<p>' p3 ' ' p4 '</p>']}];

% --- Time course (Figures 3 and S4): group medians per 30 s bin ------------
post = @(Q, meas, grp) Q(strcmp({Q.measure}, meas) & strcmp({Q.group}, grp) & strcmp({Q.aligned_to}, 'offset') ...
    & ~isnan([Q.median]));
pre  = @(Q, meas, grp) Q(strcmp({Q.measure}, meas) & strcmp({Q.group}, grp) & strcmp({Q.aligned_to}, 'onset') ...
    & ~isnan([Q.median]));
bin_txt = @(q) sprintf('%g&ndash;%g min', q.bin_start_s / 60, q.bin_end_s / 60);
% Amplitude: first post-offset bin, the last bin before onset, recovery
a_post = post(Q3, 'rms', 'DS seizure'); a_pre = pre(Q3, 'rms', 'DS seizure');
a_last_pre = a_pre(end);                              % the 30 s before onset
at = @(t_s) a_post([a_post.bin_start_s] == t_s);
mid = [at(120), at(270)];                             % 2-2.5 and 4.5-5 min
mid_txt = strjoin(arrayfun(@(q) sprintf('%.2f at %s', q.median, bin_txt(q)), mid, 'UniformOutput', false), ', ');
t1 = sprintf(['In DS seizure mice, median amplitude relative to the pre-heating baseline was %.2f in the 30 s ' ...
    'before seizure onset, %.2f in the first 30 s after offset, %s, and %.2f at %s.'], a_last_pre.median, ...
    a_post(1).median, mid_txt, a_post(end).median, bin_txt(a_post(end)));
% Slowing and spiking: last bin, seizure vs control medians
t2_parts = {};
for meas = {cfg.slowing, 'spike_rate'}
    qs = post(Q3, meas{1}, 'DS seizure'); qc = post(Q3, meas{1}, 'controls');
    last = min(qs(end).bin_start_s, qc(end).bin_start_s);
    qs = qs([qs.bin_start_s] == last); qc = qc([qc.bin_start_s] == last);
    if strcmp(meas{1}, cfg.slowing)
        t2_parts{end + 1} = sprintf('%s ratio %.2f vs %.2f &times; baseline', ratio_word, qs.median, qc.median); %#ok<AGROW>
    else
        t2_parts{end + 1} = sprintf('spike rate %+.1f vs %+.1f spikes/min relative to baseline', qs.median, qc.median); %#ok<AGROW>
    end
end
t2 = sprintf('In the last bin (%s after offset), median values in DS seizure mice vs controls were: %s.', ...
    bin_txt(qs), join_list(t2_parts));
% Each band (Figure S4): bins where DS seizure median is below / above controls
bt = {};
for band = unique({Q4.measure}, 'stable')
    qs = post(Q4, band{1}, 'DS seizure'); qc = post(Q4, band{1}, 'controls');
    [common, is_, ic] = intersect([qs.bin_start_s], [qc.bin_start_s]);
    above = [qs(is_).median] > [qc(ic).median];
    k_cross = find(~above, 1, 'last') + 1;           % above controls from this bin on
    if all(~above)
        bt{end + 1} = sprintf('%s power was below the control median in every 30 s bin after offset', band{1}); %#ok<AGROW>
    elseif all(above)
        bt{end + 1} = sprintf('%s power was above the control median in every 30 s bin after offset', band{1}); %#ok<AGROW>
    elseif ~above(1) && ~isempty(k_cross) && k_cross <= numel(common)
        bt{end + 1} = sprintf(['%s power was below the control median in the first bin after offset ' ...
            '(%.2f vs %.2f &times; baseline) and above it from %g min after offset onward'], band{1}, ...
            qs(is_(1)).median, qc(ic(1)).median, common(k_cross) / 60); %#ok<AGROW>
    else
        bt{end + 1} = sprintf('%s power was below the control median in %d of %d bins after offset', band{1}, ...
            sum(~above), numel(above)); %#ok<AGROW>
    end
end
t3 = sprintf('By frequency band (Figure S4; absolute power relative to baseline), %s.', join_list(bt));
html = [html, {'<h3>Time course</h3>', ['<p>Time courses are shown in Figure 3 (group medians per 30 s bin). ' ...
    t1 ' ' t2 ' ' t3 '</p>']}];

% --- Clinical variables (Figure S5), uncorrected ---------------------------------
factors = {'seizure duration', 'age', 'sex', 'seizure 1 vs 2'};
context = {'with longer seizures', 'in older mice', 'in males than in females', ...
    'after the second seizure than after the first'};
f_label = {'Seizure duration', 'Age', 'Sex', 'First versus second seizure'};
up_word   = {'less amplitude suppression', 'more slowing', 'more spiking'};
down_word = {'more amplitude suppression', 'less slowing', 'less spiking'};
c_sent = cell(1, numel(factors));
for f = 1:numel(factors)
    sig = {}; trend = {}; p_all = {};
    for m = 1:3
        t = T5(strcmp({T5.measure}, primary{m}) & strcmp({T5.factor}, factors{f}));
        if isempty(t), continue; end
        if strncmp(t.test, 'Spearman', 8)
            up = t.estimate > 0; st = sprintf('&rho; = %.2f, n = %d, p = %s', t.estimate, t.n, p_txt(t.p));
        elseif ~isempty(strfind(t.test, 'ratio'))
            up = t.estimate > 1; st = sprintf('%s, n = %d, p = %s', test_name(t.test), t.n, p_txt(t.p));
        else
            up = t.estimate > 0; st = sprintf('%s, n = %d, p = %s', test_name(t.test), t.n, p_txt(t.p));
        end
        if up, w = up_word{m}; else, w = down_word{m}; end
        p_all{end + 1} = sprintf('%s p = %s', short{m}, p_txt(t.p)); %#ok<AGROW>
        if t.p < 0.05
            sig{end + 1} = sprintf('%s %s (%s)', w, context{f}, st); %#ok<AGROW>
        elseif t.p < 0.1
            trend{end + 1} = sprintf('%s %s (%s)', w, context{f}, st); %#ok<AGROW>
        end
    end
    if isempty(sig) && strcmp(factors{f}, 'seizure 1 vs 2')
        c_sent{f} = sprintf(['Depth after the first and the second seizure in the same mice did not differ ' ...
            'significantly for any measure (%s)'], strjoin(p_all, ', '));
    elseif isempty(sig)
        c_sent{f} = sprintf('%s was not significantly associated with any post-ictal depth measure (%s)', ...
            f_label{f}, strjoin(p_all, ', '));
    else
        c_sent{f} = sprintf('%s was associated with %s', f_label{f}, join_list(sig));
    end
    if ~isempty(trend)
        c_sent{f} = sprintf('%s, although there was a nonsignificant trend toward %s', c_sent{f}, join_list(trend));
    end
    c_sent{f} = [c_sent{f} '.'];
end
p_clin = sprintf(['We examined the association between clinical variables and post-ictal depth over the ' ...
    'first %s min in DS seizure mice (exploratory, uncorrected; Figure S5). %s'], min_txt, strjoin(c_sent, ' '));
html = [html, {'<h3>Association between clinical variables and post-ictal depth</h3>', ['<p>' p_clin '</p>']}];
html = strrep(html, 'p = &lt;', 'p &lt;');           % 'p = < 0.001' -> 'p < 0.001'
end

function html = cohort_table(res, final_rows, R, cfg)
% Table 1: the final cohort by group (DS seizure, controls, and the two
% control subgroups). Mouse-level rows (sessions, seizures, SUDEP) count
% every spreadsheet row of the cohort's mice, not only the analysed one.
% Also written to <output>/table1.csv for pasting into Word.
cols = {'DS seizure', {'DS seizure'}; 'Controls', {'WT', 'DS no seizure'}; ...
        'Controls: WT', {'WT'}; 'Controls: DS no seizure', {'DS no seizure'}};
main_s = cfg.depth_main_s;
pa = R.rms.pa;                                    % per-animal depths and second seizure (RMS)
labels = {};
vals = {};
for c = 1:size(cols, 1)
    q = final_rows(ismember({final_rows.group}, cols{c, 2}));   % analysed recording of each mouse
    mice = [q.mouse_id];
    all_rows = res(ismember([res.mouse_id], mice));            % every heating session of these mice
    n = numel(q);
    sex = upper(strtrim({q.sex}));
    n_f = sum(strcmp(sex, 'F')); n_m = sum(strcmp(sex, 'M')); n_unknown = n - n_f - n_m;
    per_mouse = @(v) arrayfun(@(m) sum(v([all_rows.mouse_id] == m)), mice);
    sessions = per_mouse(true(1, numel(all_rows)));
    seizures = per_mouse(strcmp({all_rows.group}, 'DS seizure'));
    sudep = per_mouse(strcmpi(strtrim({all_rows.sudep}), 'yes'));
    in_pa = ismember([pa.sheet_row], [q.sheet_row]);
    v = {};
    v{end + 1} = sprintf('%d', n);
    v{end + 1} = sprintf('%d (%.0f%%) / %d (%.0f%%)', n_f, 100 * n_f / n, n_m, 100 * n_m / n);
    if n_unknown > 0, v{end} = sprintf('%s; %d not recorded', v{end}, n_unknown); end
    v{end + 1} = sprintf('%d / %d', sum(strcmp({q.group}, 'WT')), sum(strncmp({q.group}, 'DS', 2)));
    v{end + 1} = med_range([q.age_days], '%.0f');
    v{end + 1} = med_range([q.sz_off] - [q.sz_on], '%.0f');
    v{end + 1} = med_range([q.base_end_s] - [q.base_start_s], '%.0f');
    v{end + 1} = sprintf('%d; %s', sum(sessions), med_range(sessions, '%.0f'));
    v{end + 1} = sprintf('%d; %s', sum(seizures), med_range(seizures, '%.0f'));
    v{end + 1} = sprintf('%d', sum(~isnan([pa(in_pa).s2_sheet_row])));
    v{end + 1} = sprintf('%d', sum(sudep > 0));
    v{end + 1} = sprintf('%d', sum(~isnan([pa(in_pa).(sprintf('depth_0_%ds', main_s))])));
    vals(:, c) = v'; %#ok<AGROW>
end
labels = {'Mice, n'; 'Sex, female / male, n (%)'; 'Genotype, WT / DS, n'; ...
    'Age at the analysed recording, days, median (range)'; ...
    'Seizure (controls: pseudo-seizure) duration, s, median (range)'; ...
    'Pre-heating baseline, s, median (range)'; ...
    'Heating sessions, total; per mouse, median (range)'; ...
    'Seizures, total; per mouse, median (range)'; ...
    'Mice with a usable second seizure (paired comparison), n'; ...
    'Mice with SUDEP in a later session, n'; ...
    sprintf('Mice with a %g-min post-ictal depth, n', main_s / 60)};
header = [{'Characteristic'}, cols(:, 1)'];
excluded = res(~ismember([res.mouse_id], [final_rows.mouse_id]));      % rows of mice not in the cohort
n_sudep_out = numel(unique([excluded(~cellfun(@isempty, strfind({excluded.exclude_reason}, 'SUDEP'))).mouse_id]));
html = {'<h3>Table 1. Cohort characteristics</h3>', table_html(header, [labels vals]), ...
    ['<p class="cap">One analysed recording per mouse (its first seizure, or for controls its first heating ' ...
    'session). Heating sessions, seizures and SUDEP count every session of these mice. Controls'' ' ...
    'pseudo-seizure times come from the spreadsheet. A usable second seizure: processed, with seizure ' ...
    'times and not ending in SUDEP; the paired comparison uses those with a depth for both seizures. ' ...
    sprintf('Not in the table: %d mice excluded because their first seizure ended in SUDEP.</p>', n_sudep_out)]};
% CSV copy (cells quoted; entities turned back into plain characters)
csv_file = fullfile(cfg.out_root, 'table1.csv');
fid = fopen(csv_file, 'w');
plain = @(x) strrep(strrep(x, '&ndash;', '-'), '"', '""');
fprintf(fid, '%s\n', strjoin(cellfun(@(x) ['"' plain(x) '"'], header, 'UniformOutput', false), ','));
for i = 1:numel(labels)
    row = [labels(i), vals(i, :)];
    fprintf(fid, '%s\n', strjoin(cellfun(@(x) ['"' plain(x) '"'], row, 'UniformOutput', false), ','));
end
fclose(fid);
end

function s = med_range(v, fmt)
% 'median (min-max)'
v = v(~isnan(v));
if isempty(v), s = '&ndash;'; return; end
s = sprintf([fmt ' (' fmt '&ndash;' fmt ')'], median(v), min(v), max(v));
end

function [mw, welch] = mw_row(stats, window_s, comparison)
% The Mann-Whitney and Welch rows of stats for one comparison and window
here = strcmp({stats.measure}, sprintf('depth 0-%d s', window_s)) & strcmp({stats.comparison}, comparison);
mw    = stats(here & strncmp({stats.method}, 'Mann-Whitney', 12));
welch = stats(here & strncmp({stats.method}, 'Welch', 5));
assert(numel(mw) == 1 && numel(welch) == 1, 'No %s rows for %d s: re-run analyze_primary', comparison, window_s);
end

function v = depth_values(pa, groups, window_s)
% Depths of the animals in these groups (NaNs dropped)
v = [pa(ismember({pa.group}, groups)).(sprintf('depth_0_%ds', window_s))];
v = v(~isnan(v));
end

function f = fmt_of(M)
% Number format for a measure's values in the text
if M.is_log, f = '%.2f'; else, f = '%.1f'; end
end

function s = med_iqr(v, fmt)
% 'median (q25-q75)'
v = v(~isnan(v));
if any(v < 0), sep = ' to '; else, sep = '&ndash;'; end   % '-0.2 to 0.9', '0.55-0.74'
s = sprintf([fmt ' (' fmt sep fmt ')'], median(v), quartile(v, 0.25), quartile(v, 0.75));
end

function s = p_txt(p)
% p for running text: '< 0.001', or 3 decimals below 0.1, else 2
if p < 0.001, s = '&lt; 0.001';
elseif p < 0.1, s = sprintf('%.3f', p);
else, s = sprintf('%.2f', p); end
end

function s = test_name(test)
% Short name of a test from figureS5_clinical_stats.csv
if strncmp(test, 'Mann', 4), s = 'Mann&ndash;Whitney';
elseif strncmp(test, 'Wilcoxon', 8), s = 'Wilcoxon signed-rank';
else, s = test; end
end

function s = genotype_split(n_wt, n_ds)
% '9 DS mice', '1 WT mouse', '3 mice (1 WT, 2 DS)'
plural = {'mouse', 'mice'};
if n_ds == 0
    s = sprintf('%d WT %s', n_wt, plural{1 + (n_wt ~= 1)});
elseif n_wt == 0
    s = sprintf('%d DS %s', n_ds, plural{1 + (n_ds ~= 1)});
else
    s = sprintf('%d mice (%d WT, %d DS)', n_wt + n_ds, n_wt, n_ds);
end
end

function s = ordinal(k)
% 1 -> '1st', 2 -> '2nd', 11 -> '11th', 23 -> '23rd'
suffix = {'th', 'st', 'nd', 'rd'};
if mod(k, 100) >= 11 && mod(k, 100) <= 13, s = sprintf('%dth', k); return; end
d = mod(k, 10);
if d >= 1 && d <= 3, s = sprintf('%d%s', k, suffix{d + 1}); else, s = sprintf('%dth', k); end
end

function s = join_list(c)
% 'a', 'a and b', 'a, b and c' (join_list({'slowing', 'spiking'}) = 'slowing and spiking')
if isempty(c), s = 'none';
elseif numel(c) == 1, s = c{1};
else, s = [strjoin(c(1:end - 1), ', ') ' and ' c{end}]; end
end

function q = bin_row(Q, measure, group, bin_start_s)
% One row of a bin summary (make_bin_figure.m), after offset
q = Q(strcmp({Q.measure}, measure) & strcmp({Q.group}, group) & strcmp({Q.aligned_to}, 'offset') ...
    & [Q.bin_start_s] == bin_start_s);
end

function [txt, n] = group_text(gs, group, window_s, is_log)
% One group's depth for one window from group_summary (analyze_primary.m):
% '0.59× (0.49–0.71)' for ratios, '+5.7 (3.9 to 7.5)' for spike rate
q = gs(strcmp({gs.group}, group) & strcmp({gs.window}, sprintf('0-%d s', window_s)));
n = q.n;
if is_log
    txt = sprintf('%.2f&times; (%.2f&ndash;%.2f)', q.center, q.ci_low, q.ci_high);
else
    txt = sprintf('%+.1f (%.1f to %.1f)', q.center, q.ci_low, q.ci_high);
end
end

function [effect, p] = test_text(stats, window_s, comparison, is_log)
% Effect size (Welch row) and Mann-Whitney p for one comparison and window
here = strcmp({stats.measure}, sprintf('depth 0-%d s', window_s)) & strcmp({stats.comparison}, comparison);
welch = stats(here & strncmp({stats.method}, 'Welch', 5));
mw    = stats(here & strncmp({stats.method}, 'Mann-Whitney', 12));
if is_log
    effect = sprintf('%.2f&times; (%.2f&ndash;%.2f)', welch.estimate, welch.ci_low, welch.ci_high);
else
    effect = sprintf('%+.1f/min (%.1f to %.1f)', welch.estimate, welch.ci_low, welch.ci_high);
end
p = p_html(mw.p);
if isfield(mw, 'p_bonferroni') && ~isnan(mw.p_bonferroni)
    p = sprintf('%s [Bonferroni %s]', p, p_html(mw.p_bonferroni));
end
end

function s = n_text(missing, window_s, groups)
% Caption sentence: how many mice of each group have a depth for this
% window, and how many analysed mice do not, by reason
q = missing(strcmp({missing.window}, sprintf('0-%d s', window_s)));
parts = {}; n_end = 0; n_art = 0;
for g = 1:numel(groups)
    r = q(strcmp({q.group}, groups{g}));
    parts{end + 1} = sprintf('%d %s', r.n_with_depth, groups{g}); %#ok<AGROW>
    n_end = n_end + r.n_recording_ended; n_art = n_art + r.n_too_much_artifact;
end
s = sprintf('0&ndash;%g min: n = %s.', window_s / 60, strjoin(parts, ', '));
if n_end + n_art > 0
    s = sprintf('%s Without a depth: %d (recording ended %d, too much artifact %d).', s, n_end + n_art, n_end, n_art);
end
end

function s = bin_n_text(Q)
% Caption sentence: range of n per 30 s bin after offset, per group, for
% the first measure in the summary (n is the same for every measure)
Q = Q(strcmp({Q.measure}, Q(1).measure) & strcmp({Q.aligned_to}, 'offset'));
parts = {};
for g = {'controls', 'DS seizure'}
    n = [Q(strcmp({Q.group}, g{1})).n];
    parts{end + 1} = sprintf('%s %d&ndash;%d', g{1}, min(n), max(n)); %#ok<AGROW>
end
s = sprintf(['Mice with a value per 30 s bin after offset: %s (fewer where recordings end or bins are ' ...
    'artifact; bins with fewer than 5 mice are not drawn).'], strjoin(parts, ', '));
end

function s = p_html(p)
% p-value for the page: 3 decimals, or e.g. 2 &times; 10<sup>-7</sup>
if p >= 0.001
    s = sprintf('%.3f', p);
else
    e = floor(log10(p));
    s = sprintf('%.0f &times; 10<sup>%d</sup>', p / 10^e, e);
end
end

function s = table_html(header, rows)
% HTML table: header = cell row of column titles, rows = cell matrix
s = ['<table><tr>' sprintf('<th>%s</th>', header{:}) '</tr>'];
for i = 1:size(rows, 1)
    s = [s '<tr>' sprintf('<td>%s</td>', rows{i, :}) '</tr>']; %#ok<AGROW>
end
s = [s '</table>'];
end

function s = image_html(png_file, embed, max_width_px)
% <img> for a figure: the PNG stored in the page (base64), or a link to it
% relative to the output folder. max_width_px (optional): display width
% limit for tall figures
if ~exist(png_file, 'file')
    s = sprintf('<p class="cap">(missing: %s)</p>', esc(png_file));
    return
end
[~, name, ext] = fileparts(png_file);
if embed
    fid = fopen(png_file, 'r'); bytes = fread(fid, Inf, '*uint8'); fclose(fid);
    src = ['data:image/png;base64,' base64_text(bytes)];
else
    src = ['figures/' name ext];
end
style = '';
if nargin > 2, style = sprintf(' style="max-width: %dpx"', max_width_px); end
s = sprintf('<img src="%s" alt="%s"%s>', src, name, style);
end

function t = base64_text(bytes)
% Base64 encoding of a uint8 vector (standard alphabet, = padding), written
% out so it needs no particular MATLAB version or Octave function
alphabet = ['A':'Z' 'a':'z' '0':'9' '+/'];
b = double(bytes(:));
n_pad = mod(-numel(b), 3);                         % 0, 1 or 2 bytes short of a multiple of 3
b = [b; zeros(n_pad, 1)];
groups = reshape(b, 3, []);                        % 3 bytes -> one 24-bit number
v = groups(1, :) * 65536 + groups(2, :) * 256 + groups(3, :);
six_bits = [floor(v / 262144); mod(floor(v / 4096), 64); mod(floor(v / 64), 64); mod(v, 64)];
t = alphabet(six_bits(:)' + 1);                    % 4 characters per 3 bytes
if n_pad > 0, t(end - n_pad + 1:end) = '='; end
end

function s = esc(s)
% Escape text for HTML
s = strrep(s, '&', '&amp;'); s = strrep(s, '<', '&lt;'); s = strrep(s, '>', '&gt;');
end

function s = page_style()
% Same look as the methods page
s = ['<style>' ...
    ':root { --text: #1d1d1f; --muted: #5f6368; --bg: #ffffff; --rule: #d9d9de; }' ...
    '@media (prefers-color-scheme: dark) { :root { --text: #e8e8ea; --muted: #a0a3a8; --bg: #17181a; --rule: #3a3b3f; } }' ...
    'body { background: var(--bg); color: var(--text); font: 17px/1.6 Georgia, "Times New Roman", serif;' ...
    ' max-width: 960px; margin: 0 auto; padding: 32px 16px 64px; }' ...
    'h1 { font-size: 1.6em; margin: 0 0 4px; }' ...
    'h2 { font-size: 1.2em; margin: 2em 0 0.4em; padding-bottom: 4px; border-bottom: 1px solid var(--rule); }' ...
    'h3 { font-size: 1em; font-style: italic; font-weight: normal; margin: 1.2em 0 0.3em; }' ...
    '.sub, .cap { color: var(--muted); font-size: 0.9em; }' ...
    'img { width: 100%; height: auto; background: #fff; margin: 0.6em 0; }' ...
    'table { border-collapse: collapse; width: 100%; font-size: 0.88em; margin: 0.6em 0 1em; }' ...
    'th, td { text-align: left; padding: 5px 8px; border-bottom: 1px solid var(--rule); vertical-align: top; }' ...
    '@media print { body { font-size: 11pt; max-width: none; } }' ...
    '</style>'];
end
