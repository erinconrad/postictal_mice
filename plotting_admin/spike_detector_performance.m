function P = spike_detector_performance(reviewer, varargin)
% SPIKE_DETECTOR_PERFORMANCE  Sensitivity and positive predictive value of
% the spike detector against blind marking in review_spikes, with the
% thresholds chosen on one half of the mice and tested on the other.
%
%   P = spike_detector_performance('EC')
%   P = spike_detector_performance('EC', 'tmul', 8:2:24, 'absthresh', [50 100 150 200 300])
%
% Pages used: marked done in review_spikes, not flagged unreadable, and
% loaded without error. Reference spikes = your marks. A detection within
% tol_s (0.05 s) of a mark is a true positive (one-to-one, closest pairs
% first); detections are counted from the page start up to (not including)
% its end.
%
% Steps
%   1. Split the mice at random (split_seed) into a tuning half and a test
%      half, within each group, so both halves have every group.
%   2. Tuning half: rerun the detector on each page's stored signal (+/- 2
%      s; global threshold from the whole recording) for every combination
%      of tmul and absthresh (other settings from cfg.spikes); choose the
%      combination with the highest F1 (pooled over pages).
%   3. Test half: sensitivity, PPV and F1 for the chosen thresholds and for
%      the current cfg.spikes, overall, for baseline and post pages, and by
%      group; also false positives per minute on baseline pages.
%      95% CIs: bootstrap over mice (n_boot resamples of the test mice with
%      replacement; spikes within a mouse are not independent).
%   Also reported: the chosen thresholds' performance on all mice
%   together (optimistic, because half were used to choose them).
%
%   sensitivity = TP / (TP + FN)     PPV = TP / (TP + FP)
%   F1 = 2 TP / (2 TP + FP + FN)
%
% Outputs in <output>/spike_review/:
%   performance_<reviewer>_grid.csv    tuning half: every combination
%   performance_<reviewer>.csv         test half: chosen and current
%                                      thresholds, by stratum, with CIs
%   performance_<reviewer>.png         F1 on the tuning half
% P: struct with the chosen thresholds, the grid and the test results.
addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();   % scripts folder and its subfolders
cfg = analysis_config();
opt = struct('tmul', [8 10 12 14 16 19 22 25], 'absthresh', [50 100 150 200 300], 'tol_s', 0.05, ...
    'split_seed', 2, 'n_boot', 2000);
for k = 1:2:numel(varargin), opt.(lower(varargin{k})) = varargin{k+1}; end
out_dir = fullfile(cfg.shared_root, 'spike_review');
L = load(fullfile(out_dir, sprintf('spikes_%s.mat', reviewer)), 'R'); R = L.R;
assert(isfield(R, 'design') && strcmp(R.design, 'blind_random_15s'), 'Review file is from an earlier version of review_spikes');
L = load(fullfile(out_dir, sprintf('spikes_%s_signals.mat', reviewer)), 'SEG'); SEG = L.SEG;

%% Pages used
rec_ok = cellfun(@isempty, {R.recs.error}) & [R.recs.loaded];
use = find([R.pages.done] & ~[R.pages.unreadable] & rec_ok([R.pages.rec]));
assert(~isempty(use), 'No pages marked done yet: run review_spikes(''%s'')', reviewer);
mouse = [R.recs([R.pages(use).rec]).mouse_id]';   % mouse of each page used
grp   = {R.recs([R.pages(use).rec]).group}';
seg   = {R.pages(use).segment}';
fprintf('%d pages used (%d done, %d unreadable), %d mice, %d marked spikes\n', numel(use), ...
    sum([R.pages.done]), sum([R.pages.done] & [R.pages.unreadable]), numel(unique(mouse)), ...
    sum(arrayfun(@(p) numel(R.pages(p).marked_t), use)));

%% 1. Split mice into tuning and test halves, within each group
rng(opt.split_seed);
um = unique(mouse);
tune_m = [];
for g = unique(grp)'
    m = unique(mouse(strcmp(grp, g{1})));
    m = m(randperm(numel(m)));
    tune_m = [tune_m; m(1:floor(numel(m) / 2))]; %#ok<AGROW>
end
is_tune = ismember(mouse, tune_m);
fprintf('Tuning half: %d mice, %d pages; test half: %d mice, %d pages\n', numel(tune_m), sum(is_tune), ...
    numel(um) - numel(tune_m), sum(~is_tune));

%% 2. Grid on the tuning half
G = struct([]);
for tm = opt.tmul
    for ab = opt.absthresh
        c = page_counts(R, SEG, use(is_tune), tm, ab, opt.tol_s);
        q = summarize(sum(c, 1));
        q = cat_struct(struct('tmul', tm, 'absthresh', ab), q);
        if isempty(G), G = q; else, G(end+1) = q; end %#ok<AGROW>
    end
end
[~, b] = max([G.f1]);
best = G(b);
fprintf('\nTuning half: best F1 %.2f at tmul %g, absthresh %g (sensitivity %.2f, PPV %.2f)\n', ...
    best.f1, best.tmul, best.absthresh, best.sensitivity, best.ppv);
write_results_csv(G, fullfile(out_dir, sprintf('performance_%s_grid.csv', reviewer)));

%% 3. Test half, with bootstrap CIs over mice
T = struct([]);
setting = {'chosen', best.tmul, best.absthresh; 'current cfg.spikes', cfg.spikes.tmul, cfg.spikes.absthresh};
strata = {'all', true(size(use(:))); 'baseline', strcmp(seg, 'baseline'); 'post', strcmp(seg, 'post')};
for g = unique(grp)', strata(end+1, :) = {g{1}, strcmp(grp, g{1})}; end %#ok<AGROW>
fprintf('\nTest half (95%% CI, bootstrap over mice):\n');
fprintf('%-20s %-15s %5s %5s %5s %5s  %-18s %-18s %-18s %s\n', 'thresholds', 'pages', 'n', 'TP', 'FP', 'FN', ...
    'sensitivity', 'PPV', 'F1', 'FP/min');
for s = 1:size(setting, 1)
    c = zeros(numel(use), 3);
    c(~is_tune, :) = page_counts(R, SEG, use(~is_tune), setting{s, 2}, setting{s, 3}, opt.tol_s);
    for k = 1:size(strata, 1)
        sel = ~is_tune & strata{k, 2};
        if ~any(sel), continue; end
        q = summarize(sum(c(sel, :), 1));
        ci = boot_ci(c(sel, :), mouse(sel), opt.n_boot);
        mins = sum(sel) * R.opt.page_s / 60;
        r = struct('thresholds', setting{s, 1}, 'tmul', setting{s, 2}, 'absthresh', setting{s, 3}, ...
            'pages', strata{k, 1}, 'n_pages', sum(sel), 'n_mice', numel(unique(mouse(sel))), ...
            'tp', q.tp, 'fp', q.fp, 'fn', q.fn, ...
            'sensitivity', q.sensitivity, 'sens_ci_low', ci(1, 1), 'sens_ci_high', ci(1, 2), ...
            'ppv', q.ppv, 'ppv_ci_low', ci(2, 1), 'ppv_ci_high', ci(2, 2), ...
            'f1', q.f1, 'f1_ci_low', ci(3, 1), 'f1_ci_high', ci(3, 2), 'fp_per_min', q.fp / mins);
        if isempty(T), T = r; else, T(end+1) = r; end %#ok<AGROW>
        fprintf('%-20s %-15s %5d %5d %5d %5d  %s %s %s %6.2f\n', sprintf('%s (%g, %g)', setting{s, 1}, setting{s, 2}, setting{s, 3}), ...
            strata{k, 1}, sum(sel), q.tp, q.fp, q.fn, fmt_ci(q.sensitivity, ci(1, :)), fmt_ci(q.ppv, ci(2, :)), ...
            fmt_ci(q.f1, ci(3, :)), q.fp / mins);
    end
end
write_results_csv(T, fullfile(out_dir, sprintf('performance_%s.csv', reviewer)));

% Chosen thresholds on all mice (optimistic: half were used to choose them)
c = page_counts(R, SEG, use, best.tmul, best.absthresh, opt.tol_s);
q = summarize(sum(c, 1));
fprintf('\nChosen thresholds, all mice (optimistic): sensitivity %.2f, PPV %.2f, F1 %.2f\n', ...
    q.sensitivity, q.ppv, q.f1);
fprintf('To use them: set tmul = %g and absthresh = %g in cfg.spikes (analysis_config.m) and rerun run_postictal_batch.\n', ...
    best.tmul, best.absthresh);

%% F1 map (tuning half)
M = nan(numel(opt.absthresh), numel(opt.tmul));
for i = 1:numel(G), M(opt.absthresh == G(i).absthresh, opt.tmul == G(i).tmul) = G(i).f1; end
fig = figure('Color', 'w', 'Position', [100 100 700 450]);
imagesc(1:numel(opt.tmul), 1:numel(opt.absthresh), M); axis xy; colorbar;
set(gca, 'XTick', 1:numel(opt.tmul), 'XTickLabel', opt.tmul, 'YTick', 1:numel(opt.absthresh), ...
    'YTickLabel', opt.absthresh);
xlabel('tmul'); ylabel('absthresh (\muV)');
title(sprintf('F1, tuning half (%d pages); best: tmul %g, absthresh %g', sum(is_tune), best.tmul, best.absthresh));
for i = 1:size(M, 1)
    for j = 1:size(M, 2)
        text(j, i, sprintf('%.2f', M(i, j)), 'HorizontalAlignment', 'center', 'Color', 'w');
    end
end
print(fig, fullfile(out_dir, sprintf('performance_%s.png', reviewer)), '-dpng', '-r120');

P = struct('best', best, 'grid', G, 'test', T, 'tune_mice', tune_m, 'opt', opt);
end

%% ------------------------------------------------------------------------
function c = page_counts(R, SEG, pages, tmul, absthresh, tol)
% [TP FP FN] per page, detector rerun on the stored signal with these thresholds
c = zeros(numel(pages), 3);
for u = 1:numel(pages)
    p = pages(u); pg = R.pages(p); rc = R.recs(pg.rec);
    o = R.det_opts;
    o.tmul = tmul; o.absthresh = absthresh; o.scale = rc.scale;
    sp = detect_spikes(double(SEG{p}), rc.fs, o);
    d = pg.seg_t0 + sp.t;
    d = d(d >= pg.t0 & d < pg.t1);
    tp = match_count(pg.marked_t, d, tol);
    c(u, :) = [tp, numel(d) - tp, numel(pg.marked_t) - tp];
end
end

function tp = match_count(a, b, tol)
% One-to-one matches between times a and b within tol, closest pairs first
tp = 0;
if isempty(a) || isempty(b), return; end
D = abs(bsxfun(@minus, a(:), b(:)'));
while true
    [m, k] = min(D(:));
    if isempty(m) || m > tol, break; end
    [i, j] = ind2sub(size(D), k);
    tp = tp + 1;
    D(i, :) = inf; D(:, j) = inf;
end
end

function ci = boot_ci(c, mouse, n_boot)
% 95% percentile CIs for sensitivity, PPV and F1 (rows), resampling mice
um = unique(mouse);
cm = zeros(numel(um), 3);                             % counts per mouse
for i = 1:numel(um), cm(i, :) = sum(c(mouse == um(i), :), 1); end
v = nan(n_boot, 3);
for b = 1:n_boot
    s = sum(cm(randi(numel(um), numel(um), 1), :), 1);
    q = summarize(s);
    v(b, :) = [q.sensitivity, q.ppv, q.f1];
end
ci = nan(3, 2);
for k = 1:3
    x = sort(v(~isnan(v(:, k)), k));
    if numel(x) >= 20
        ci(k, :) = x(max(1, round([0.025 0.975] * numel(x))));
    end
end
end

function q = summarize(c)
q = struct('tp', c(1), 'fp', c(2), 'fn', c(3), 'sensitivity', c(1) / (c(1) + c(3)), ...
    'ppv', c(1) / (c(1) + c(2)), 'f1', 2 * c(1) / (2 * c(1) + c(2) + c(3)));
end

function s = fmt_ci(v, ci)
s = sprintf('%.2f [%.2f, %.2f]', v, ci(1), ci(2));
s = sprintf('%-18s', s);
end

function s = cat_struct(a, b)
s = a; f = fieldnames(b);
for i = 1:numel(f), s.(f{i}) = b.(f{i}); end
end
