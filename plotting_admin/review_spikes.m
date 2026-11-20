function review_spikes(reviewer, varargin)
% REVIEW_SPIKES  Blind spike marking to measure the spike detector's
% sensitivity and positive predictive value (spike_detector_performance.m).
%
%   review_spikes('EC')
%   review_spikes('EC', 'preload', true)   % load every recording first (slow
%                                          % once, then no waiting between pages)
%
%   reviewer : your initials. The session is saved after every change in
%              <output>/spike_review/spikes_<reviewer>.mat (pages' signals
%              in spikes_<reviewer>_signals.mat), so you can close the
%              window and run the same command to continue. A second
%              reviewer with the same seed gets the same pages in the same
%              order (for agreement between reviewers).
%
% Pages (chosen once, when the session is created, from opts.seed)
%   Every recording in the primary cohort (run_postictal_batch first)
%   contributes two 15 s pages:
%     baseline : start drawn at random (uniform) within the baseline period
%     post     : start drawn at random within 0-300 s after (pseudo-)offset
%                (the page lies entirely within 0-300 s)
%   All pages are shown in one random order, with no mouse, group or
%   baseline/post label, and without the detector's output, so the marking
%   is blind to condition and to the detector.
%
% Detector output: when a recording is first needed, it is loaded
% (notch-filtered, as in the batch) and the detector is run on the whole
% recording with cfg.spikes (analysis_config.m). All its detections are
% saved (R.recs(j).det_t), with each page's signal +/- 2 s, so
% spike_detector_performance.m can rerun the detector with other
% thresholds without the data.
%
% Marking: click every spike (one click per spike or spike-and-wave
% complex). The mark is placed at the largest deflection within 50 ms of
% the click (the same rule the detector uses to place its spikes). Click
% within 0.1 s of a mark to remove it.
%
% Keys (click an empty part of the window first if keys do nothing):
%   right / n   page done, next page        left / p   previous page
%   up / down   more / less gain            u          whole page unreadable (on/off)
%   g           first page not yet done     q          quit (saved)
%
% A recording is loaded from the data folder the first time one of its
% pages comes up (a few seconds on the server); keys and clicks are ignored
% until the page appears. 'preload', true loads them all at the start.

%% 1. Options, session file
opt = struct('seed', 1, 'page_s', 15, 'post_range_s', [0 300], 'pad_s', 2, 'preload', false);
for k = 1:2:numel(varargin), opt.(lower(varargin{k})) = varargin{k+1}; end
assert(ischar(reviewer) && ~isempty(reviewer), 'Give your initials, e.g. review_spikes(''EC'')');
addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();   % scripts folder and its subfolders
cfg = analysis_config();
out_dir = fullfile(cfg.shared_root, 'spike_review');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
mat_file = fullfile(out_dir, sprintf('spikes_%s.mat', reviewer));
sig_file = fullfile(out_dir, sprintf('spikes_%s_signals.mat', reviewer));

if exist(mat_file, 'file') == 2
    L = load(mat_file, 'R'); R = L.R;
    assert(isfield(R, 'design') && strcmp(R.design, 'blind_random_15s'), ...
        '%s is from the earlier version of review_spikes: rename or delete it to start a new session', mat_file);
    fprintf('Loaded %s: %d of %d pages done\n', mat_file, sum([R.pages.done]), numel(R.pages));
else
    R = new_session(cfg, opt, reviewer);
    save(mat_file, 'R');
    SEG = cell(numel(R.pages), 1); %#ok<NASGU>
    save(sig_file, 'SEG');
    fprintf('New session: %d recordings, %d pages of %g s, saved to %s\n', ...
        numel(R.recs), numel(R.pages), opt.page_s, mat_file);
end
L = load(sig_file, 'SEG'); SEG = L.SEG;

%% 2. Optionally load every recording now
if opt.preload
    for j = find(~[R.recs.loaded])
        [R, SEG] = load_recording(R, SEG, j, cfg);
    end
    save(mat_file, 'R'); save(sig_file, 'SEG');
end

%% 3. Window
fig = figure('Color', 'w', 'Position', [40 120 1500 560], 'NumberTitle', 'off', ...
    'Name', sprintf('Spike marking (%s)', reviewer), 'WindowKeyPressFcn', @on_key, ...
    'WindowButtonDownFcn', @on_click, ...
    'Interruptible', 'off', 'BusyAction', 'cancel');   % one key or click at a time; any
                                                       % pressed while busy is ignored
S = struct();
S.R = R; S.SEG = SEG; S.cfg = cfg; S.mat_file = mat_file; S.sig_file = sig_file;
S.ax = axes('Parent', fig, 'Position', [0.05 0.13 0.92 0.75]);
S.gain = 1000;                                       % half-height of the display (uV)
S.k = first_open(R);                                 % position in the display order
guidata(fig, S);
redraw(fig);
end

%% ------------------------------------------------------------------------
function R = new_session(cfg, opt, reviewer)
% Choose the pages (nothing is loaded yet)
B = load(fullfile(cfg.out_root, 'postictal_batch', 'postictal_results.mat'), 'res');
res = B.res;
use = find([res.in_primary] == 1 & strcmp({res.status}, 'ok'));
assert(~isempty(use), 'No primary-cohort recordings in the batch results');
rng(opt.seed);
R = struct('design', 'blind_random_15s', 'reviewer', reviewer, 'created', datestr(now), ...
    'opt', opt, 'det_opts', cfg.spikes);
recs = struct([]); pages = struct([]);
for j = 1:numel(use)
    r = res(use(j));
    q = struct('sheet_row', r.sheet_row, 'group', r.group, 'mouse_id', r.mouse_id, ...
        'sz_on', r.sz_on, 'sz_off', r.sz_off, 'fs', NaN, 'scale', NaN, 'det_t', zeros(0, 1), ...
        'loaded', false, 'error', '');
    if isempty(recs), recs = q; else, recs(end+1) = q; end %#ok<AGROW>
    % Allowed start ranges (s); the page must also leave pad_s before the
    % end of the recording
    last = r.dur_s - opt.pad_s - opt.page_s;
    seg = {'baseline', max(r.base_start_s, opt.pad_s), r.base_end_s - opt.page_s;
           'post', r.sz_off + opt.post_range_s(1), min(r.sz_off + opt.post_range_s(2) - opt.page_s, last)};
    for s = 1:2
        lo = seg{s, 2}; hi = seg{s, 3};
        if hi < lo
            warning('Row %d: no room for a %s page; skipped', r.sheet_row, seg{s, 1});
            continue
        end
        t0 = round((lo + rand * (hi - lo)) * 1000) / 1000;   % uniform, to the ms
        pg = struct('rec', j, 'segment', seg{s, 1}, 't0', t0, 't1', t0 + opt.page_s, 'seg_t0', NaN, ...
            'det_t', zeros(0, 1), 'marked_t', zeros(0, 1), 'unreadable', false, 'done', false);
        if isempty(pages), pages = pg; else, pages(end+1) = pg; end %#ok<AGROW>
    end
end
R.recs = recs; R.pages = pages;
R.order = randperm(numel(pages));                    % display order (blind to mouse and segment)
end

function [R, SEG] = load_recording(R, SEG, j, cfg)
% Load recording j, run the detector on the whole recording, and store all
% its detections, each of its pages' signal (+/- pad) and the detections
% within each page
persistent rows
if isempty(rows), rows = prepare_rows(cfg); end
x = rows([rows.sheet_row] == R.recs(j).sheet_row);
assert(numel(x) == 1, 'Row %d not found in the spreadsheet', R.recs(j).sheet_row);
fprintf('Loading recording %d of %d... ', j, numel(R.recs));
L = load_row_ecog(x, cfg.data_root, cfg.ecog_multi, cfg.notch);
R.recs(j).loaded = true;
if ~isempty(L.skip_msg) || ~isempty(L.err_msg)
    R.recs(j).error = [L.skip_msg L.err_msg];
    fprintf('failed: %s\n', R.recs(j).error);
    return
end
sp = detect_spikes(L.ecog, L.fs, R.det_opts);
R.recs(j).fs = L.fs; R.recs(j).scale = sp.scale; R.recs(j).det_t = sp.t;
pad = R.opt.pad_s;
for p = find([R.pages.rec] == j)
    a = max(1, round((R.pages(p).t0 - pad) * L.fs) + 1);
    b = min(numel(L.ecog), round((R.pages(p).t1 + pad) * L.fs));
    R.pages(p).seg_t0 = (a - 1) / L.fs;
    SEG{p} = single(L.ecog(a:b));
    R.pages(p).det_t = sp.t(sp.t >= R.pages(p).t0 & sp.t < R.pages(p).t1);
end
fprintf('done\n');
end

function k = first_open(R)
k = find(~[R.pages(R.order).done], 1);
if isempty(k), k = 1; end
end

%% ------------------------------------------------------------------------
function redraw(fig)
S = guidata(fig);
p = S.R.order(S.k);
if ~S.R.recs(S.R.pages(p).rec).loaded
    setappdata(fig, 'busy', true);
    title(S.ax, 'Loading the next recording... (keys and clicks are ignored until the page appears)');
    drawnow;
    try
        [S.R, S.SEG] = load_recording(S.R, S.SEG, S.R.pages(p).rec, S.cfg);
    catch ME
        setappdata(fig, 'busy', false);              % keep the window usable
        rethrow(ME);
    end
    save_all(S, true);
    guidata(fig, S);
    setappdata(fig, 'busy', false);
end
pg = S.R.pages(p); rc = S.R.recs(pg.rec);
ax = S.ax; cla(ax); hold(ax, 'on');
n_done = sum([S.R.pages.done]);
if ~isempty(rc.error)
    title(ax, sprintf('Page %d of %d: could not be loaded (%s). Press n to go on.', ...
        S.k, numel(S.R.pages), rc.error), 'Interpreter', 'none');
    return
end
x = double(S.SEG{p});
t = pg.seg_t0 + (0:numel(x) - 1)' / rc.fs;
in = t >= pg.t0 & t <= pg.t1;
G = S.gain;
if pg.unreadable
    W = pg.t1 - pg.t0;
    patch(ax, [0 W W 0], [-G -G G G], [1 0.9 0.9], 'EdgeColor', 'none');
end
for tm = pg.marked_t'                                % guide lines under the marks
    plot(ax, (tm - pg.t0) * [1 1], [-G 0.9 * G], '-', 'Color', [0.75 0.8 1]);
end
plot(ax, t(in) - pg.t0, x(in) - median(x(in)), 'k', 'LineWidth', 0.8);   % time from page start
if ~isempty(pg.marked_t)
    plot(ax, pg.marked_t - pg.t0, 0.92 * G * ones(numel(pg.marked_t), 1), 'v', 'Color', [0.1 0.3 0.9], ...
        'MarkerFaceColor', [0.1 0.3 0.9], 'MarkerSize', 9);
end
xlim(ax, [0 pg.t1 - pg.t0]); ylim(ax, [-G G]);
set(ax, 'YTick', [-G 0 G], 'YTickLabel', {sprintf('%d', -G), '0', sprintf('%d uV', G)}, 'TickDir', 'out');
xlabel(ax, 'Time from page start (s)');
title(ax, {sprintf('Page %d of %d (%d done)%s%s | spikes marked: %d', S.k, numel(S.R.pages), n_done, ...
    ternary(pg.done, ' | DONE', ''), ternary(pg.unreadable, ' | UNREADABLE', ''), numel(pg.marked_t)), ...
    'Click every spike (click a mark to remove it) | n / p: next / previous | up / down: gain | u: page unreadable | q: quit'}, ...
    'Interpreter', 'none', 'FontWeight', 'normal');
box(ax, 'off');
end

%% ------------------------------------------------------------------------
function on_click(fig, ~)
if isequal(getappdata(fig, 'busy'), true), return; end   % a recording is loading
S = guidata(fig);
p = S.R.order(S.k); pg = S.R.pages(p); rc = S.R.recs(pg.rec);
if ~isempty(rc.error) || ~rc.loaded, return; end
cp = get(S.ax, 'CurrentPoint'); tc = cp(1, 1) + pg.t0; yc = cp(1, 2);
yl = get(S.ax, 'YLim');
if tc < pg.t0 || tc > pg.t1 || yc < yl(1) || yc > yl(2), return; end
[dmin, m] = min(abs(pg.marked_t - tc));
if ~isempty(dmin) && dmin <= 0.1
    pg.marked_t(m) = [];                              % remove the nearest mark
else
    % Add a mark at the largest deflection within 50 ms of the click
    % (deflection from the median within +/- 0.5 s, as in detect_spikes.m)
    x = double(S.SEG{p});
    t = pg.seg_t0 + (0:numel(x) - 1)' / rc.fs;
    w = find(abs(t - tc) <= 0.05 & t >= pg.t0 & t < pg.t1);
    s = abs(t - tc) <= 0.5;
    if isempty(w), return; end
    [~, i] = max(abs(x(w) - median(x(s))));
    pg.marked_t = sort([pg.marked_t; t(w(i))]);
end
S.R.pages(p) = pg;
save_all(S, false); guidata(fig, S); redraw(fig);
end

function on_key(fig, evt)
if isequal(getappdata(fig, 'busy'), true), return; end   % a recording is loading
S = guidata(fig);
p = S.R.order(S.k);
switch evt.Key
    case {'rightarrow', 'n'}
        S.R.pages(p).done = true;
        save_all(S, false);
        if S.k < numel(S.R.order)
            S.k = S.k + 1;
        else
            fprintf('Last page. %d of %d done.\n', sum([S.R.pages.done]), numel(S.R.pages));
        end
    case {'leftarrow', 'p'}
        S.k = max(1, S.k - 1);
    case 'uparrow'
        S.gain = max(50, round(S.gain / 1.5));
    case 'downarrow'
        S.gain = round(S.gain * 1.5);
    case 'u'
        S.R.pages(p).unreadable = ~S.R.pages(p).unreadable;
        save_all(S, false);
    case 'g'
        S.k = first_open(S.R);
    case 'q'
        save_all(S, false); close(fig); return
    otherwise
        return
end
guidata(fig, S); redraw(fig);
end

function save_all(S, with_signals)
% The review (small) after every change; the signals only when they change
R = S.R; %#ok<NASGU>
save(S.mat_file, 'R');
if with_signals
    SEG = S.SEG; %#ok<NASGU>
    save(S.sig_file, 'SEG');
end
end

function v = ternary(c, a, b)
if c, v = a; else, v = b; end
end
