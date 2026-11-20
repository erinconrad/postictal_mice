function T = make_spike_examples_figure(varargin)
% MAKE_SPIKE_EXAMPLES_FIGURE  Raw ECoG after seizure offset in
% randomly chosen DS seizure mice, with every spike detection marked
% (Figure S1: shows what the spike detector picks up). Reads the batch
% results (spike times) and the raw data (needs the data folder).
%
%   make_spike_examples_figure
%   make_spike_examples_figure('seed', 2)        % a different random draw
%
% Options (name-value pairs)
%   n_mice     number of mice; default 10
%   seed       random seed, so the same mice are drawn every run; default 1
%   start_s    start of the stretch, s after offset; default 60 (past the
%              deepest suppression, when spiking is usually back)
%   len_s      length of the stretch (s); default 15
%   ylim_uV    y range of every trace (uV); default [-500 500]
%   scale_uV   height of the scale bar (uV); default 200
%   file_name  default 'figureS1_spike_examples'
%   font_size  default 18
%
% Mice: drawn at random from the DS seizure mice in the primary cohort
% whose recording covers the whole stretch. Each row: notch-filtered ECoG
% (as analysed), in the same uV scale; red circles = detected spikes, at
% the detector's time (the largest raw deflection), drawn on the trace.
% Dotted vertical lines every 1 s.
% Spikes beyond the y range are marked at the edge. Grey shading = 10 s
% windows left out as artifact.
%
% Outputs in <output>/figures/: <file_name>.png (300 dpi) and .pdf, and
% <file_name>.csv (the mice shown and their number of detections).

%% 1. Settings and inputs
addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();
cfg = analysis_config();
opts = struct('n_mice', 10, 'seed', 1, 'start_s', 60, 'len_s', 15, 'ylim_uV', [-500 500], 'scale_uV', 200, ...
    'file_name', 'figureS1_spike_examples', 'font_size', 18);
for k = 1:2:numel(varargin)
    assert(isfield(opts, varargin{k}), 'Unknown option %s', varargin{k});
    opts.(varargin{k}) = varargin{k + 1};
end
out_dir = fullfile(cfg.out_root, 'figures');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
S = load(fullfile(cfg.out_root, 'postictal_batch', 'postictal_results.mat'), 'res', 'outs');

% Candidates: primary-cohort DS seizure recordings the batch processed,
% recorded at least to the end of the stretch
ok = find([S.res.in_primary] == 1 & strcmp({S.res.group}, 'DS seizure') & ...
    ~ismember({S.res.status}, {'error', 'skipped'}));
covers = arrayfun(@(i) S.outs{i}.dur_s >= S.res(i).sz_off + opts.start_s + opts.len_s, ok);
ok = ok(covers);
assert(numel(ok) >= opts.n_mice, 'Only %d DS seizure recordings cover the stretch', numel(ok));

% Random draw (fixed seed), then in spreadsheet order
rng(opts.seed);
chosen = sort(ok(randperm(numel(ok), opts.n_mice)));

%% 2. One row per mouse
rows = prepare_rows(cfg);
f = figure('Color', 'w', 'Position', [60 20 1400 160 * opts.n_mice + 120]);
row_h = 0.86 / opts.n_mice;                         % axes height, figure fraction
T = struct([]);
for k = 1:opts.n_mice
    i = chosen(k);
    r = S.res(i); o = S.outs{i};
    t0 = r.sz_off + opts.start_s;                   % stretch start (s from recording start)
    t1 = t0 + opts.len_s;

    % 2a. Notch-filtered ECoG, as in the batch
    L = load_row_ecog(rows([rows.sheet_row] == r.sheet_row), cfg.data_root, cfg.ecog_multi, cfg.notch);
    assert(isempty(L.err_msg) && isempty(L.skip_msg), 'Could not load row %d: %s%s', r.sheet_row, ...
        L.err_msg, L.skip_msg);
    sig = double(L.ecog(:));
    samples = (round(t0 * L.fs) + 1):min(numel(sig), round(t1 * L.fs));
    t_rel = (samples - 1) / L.fs - r.sz_off;        % s after offset

    ax = axes('Position', [0.10, 0.96 - k * row_h, 0.86, row_h * 0.92]); hold on
    yl = opts.ylim_uV;

    % 2b. Artifact windows (grey), the trace, and the detections
    for w = find(o.artifact(:)' & o.t_end(:)' > t0 & o.t_start(:)' < t1)
        patch([o.t_start(w) o.t_end(w) o.t_end(w) o.t_start(w)] - r.sz_off, yl([1 1 2 2]), ...
            [0.85 0.85 0.85], 'EdgeColor', 'none');
    end
    for t_line = ceil(opts.start_s):floor(opts.start_s + opts.len_s)   % 1 s markings
        plot([t_line t_line], yl, ':', 'Color', [0.45 0.45 0.45]);
    end
    plot(t_rel, sig(samples), 'k', 'LineWidth', 0.5);
    spike_t = o.spikes.t(:);
    spike_t = spike_t(spike_t >= t0 & spike_t <= t1);
    spike_y = sig(min(numel(sig), round(spike_t * L.fs) + 1));
    spike_y = min(max(spike_y, yl(1)), yl(2));      % off-scale spikes at the edge
    plot(spike_t - r.sz_off, spike_y, 'o', 'Color', [0.85 0.1 0.1], 'MarkerSize', 9, 'LineWidth', 1.5);

    xlim([opts.start_s, opts.start_s + opts.len_s]); ylim(yl);
    set(ax, 'YTick', [], 'YColor', 'none', 'Box', 'off');
    if k < opts.n_mice
        set(ax, 'XTick', [], 'XColor', 'none');
    else
        xlabel('Time after seizure offset (s)');
    end
    text(opts.start_s, 0, sprintf('%d  ', r.mouse_id), 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'middle');             % mouse ID, left of the trace
    q = struct('sheet_row', r.sheet_row, 'mouse_id', r.mouse_id, 'project', r.project, ...
        'start_s', opts.start_s, 'len_s', opts.len_s, 'n_detections', numel(spike_t));
    if isempty(T), T = q; else, T(end + 1) = q; end %#ok<AGROW>

    % 2c. Scale bar on the first row: opts.scale_uV, 1 s
    if k == 1
        x_bar = opts.start_s + opts.len_s - 1;
        y_bar = yl(1) * 0.9;
        plot([x_bar x_bar + 1], [y_bar y_bar], 'k', 'LineWidth', 2);
        plot([x_bar x_bar], y_bar + [0 opts.scale_uV], 'k', 'LineWidth', 2);
        text(x_bar + 0.5, y_bar, '1 s', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
        text(x_bar, y_bar + opts.scale_uV / 2, sprintf('%d \\muV ', opts.scale_uV), ...
            'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');
    end
end
annotation(f, 'textbox', [0.01 0.965 0.05 0.03], 'String', 'Mouse', 'EdgeColor', 'none', 'Margin', 1);
set(findall(f, '-property', 'FontSize'), 'FontSize', opts.font_size);

%% 3. Save
print(f, fullfile(out_dir, [opts.file_name '.png']), '-dpng', '-r300');
print(f, fullfile(out_dir, [opts.file_name '.pdf']), '-dpdf', '-painters', '-bestfit');
write_results_csv(T, fullfile(out_dir, [opts.file_name '.csv']));
fprintf('Mice shown: %s\n', strjoin(arrayfun(@(t) sprintf('%d (%d spikes)', t.mouse_id, t.n_detections), T, ...
    'UniformOutput', false), ', '));
end
