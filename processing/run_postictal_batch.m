% run_postictal_batch.m
% Processing step: for every recording listed in the cohort spreadsheet,
% load the ECoG and compute windowed amplitude relative to baseline
% (window_amplitude.m): RMS, band power (delta/theta) and spike rate
% (detect_spikes.m). One results row per spreadsheet row, plus one figure
% per recording. No thresholds or recovery times here: those are computed
% across animals in analyze_primary.m from the window values saved below.
%
% Every row is analysed; the primary cohort (session, SUDEP, missing
% times) is flagged in the in_primary column for the analysis scripts.
% Shared settings (baseline, channel choice, primary cohort, pseudo-time
% rescue) are in analysis_config.m; the spreadsheet is read and flagged by
% prepare_rows.m; the ECoG channel is loaded by load_row_ecog.m.
%
% Output: <project>/output/postictal_batch
%
% Outputs in cfg.out_dir:
%   postictal_results.csv   one row per spreadsheet row (columns below)
%   postictal_results.mat   same table as a struct array (res), each
%                           recording's window values (outs, from
%                           window_amplitude.m; outs{i}.spikes = its
%                           detected spikes, from detect_spikes.m) and the
%                           settings (cfg)
%   figures/<mouse>_<date>_s<session>.png
%
% CSV columns:
%   sheet_row ... sz_off  copied from the spreadsheet (sheet_row = Excel row)
%   ecog_used         channel(s) analysed (first of two unless cfg.ecog_multi)
%   sex, age_days, heat_start   from the spreadsheet
%   group             WT | DS no seizure | DS seizure
%   pseudo_rescued    1 if onset/offset came from the rescue (analysis_config.m)
%   in_primary        1 if in the primary cohort (see analysis_config.m)
%   exclude_reason    why not (second reviewer: ..., heating session N,
%                     SUDEP, no onset/offset times)
%   base_start_s, base_end_s   baseline period used (s from recording start)
%   folder, record_node   session folder and Record Node that were used
%   status            ok | skipped | error
%   dur_s             recording length (s)
%   base_clean_s      artifact-free baseline time (s)
%   base_rms_uV       baseline RMS (geometric mean, uV)
%   ratio_<a>_<b>s    amplitude ratio to baseline from a to b s after offset
%                     (one column per row of cfg.post_bins_s); blank if the
%                     recording ends before b or the bin is mostly artifact.
%                     (for a quick look; the analyses use depth_window.m)
%   clean_<a>_<b>s    artifact-free fraction of that bin
%   dt_<a>_<b>s       delta/theta power ratio relative to baseline in that
%                     bin (the same way as ratio_<a>_<b>s)
%   n_spikes          spikes detected in the whole recording
%   spikes_base_per_min   baseline spike rate (per minute)
%   spikes_<a>_<b>s   spike rate (per minute) in that bin
%   message           reason for skipped/error, or a note (e.g. folder date
%                     differs from sheet date by 1 day)
%
% Sections:
%   1. Settings          folders, which rows to run, analysis options
%   2. Read spreadsheet  one struct per recording; make output folders
%   3. Run each row      for each recording: skip if it can't be analysed,
%                        otherwise find its folder and raw EEG file, load the
%                        ECoG channel, run window_amplitude, save the figure.
%                        Any error is recorded for that row and the loop
%                        continues with the next one.
%   4. Save              results table as CSV and MAT
%   5. Summary           count of each status, and analysed recordings per
%                        group in the primary cohort

%% 1. Settings
% Shared settings (folders, baseline, channel choice, primary cohort) come
% from analysis_config.m. The ones below are specific to this script.
addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();   % scripts folder and its subfolders
cfg = analysis_config();
cfg.out_dir   = fullfile(cfg.out_root, 'postictal_batch');
cfg.save_figs = true;

% Spreadsheet rows to run, as Excel row numbers (row 1 = header); [] = all.
% E.g. 2:6 for a quick test before running everything.
cfg.rows_to_run = [];

% Options passed to window_amplitude (anything not set uses its
% defaults). The baseline settings come from analysis_config.m.
cfg.opts = struct();
cfg.opts.base_mode  = cfg.base_mode;
cfg.opts.base_dur_s = cfg.base_dur_s;
cfg.opts.base_min_s = cfg.base_min_s;
cfg.opts.base_gap_s = cfg.base_gap_s;
cfg.opts.artifact_uV = cfg.artifact_uV;
cfg.opts.bands       = cfg.bands;
cfg.opts.rms_band    = cfg.rms_band;

% Bins after offset (s) for the amplitude-ratio columns, one row per bin
cfg.post_bins_s = [0 60; 60 120; 120 300; 300 600];
cfg.opts.post_bins_s = cfg.post_bins_s;

% CSV column name for each bin, e.g. ratio_0_60s
bin_names = arrayfun(@(k) sprintf('ratio_%d_%ds', cfg.post_bins_s(k,1), cfg.post_bins_s(k,2)), ...
    1:size(cfg.post_bins_s, 1), 'UniformOutput', false);
clean_names = strrep(bin_names, 'ratio_', 'clean_');
dt_names    = strrep(bin_names, 'ratio_', 'dt_');
spk_names   = strrep(bin_names, 'ratio_', 'spikes_');

%% 2. Read spreadsheet
% One struct per non-blank spreadsheet row, with group, primary-cohort
% flag and (optionally) rescued pseudo-times (prepare_rows.m), restricted
% to the rows listed in cfg.rows_to_run
rows = prepare_rows(cfg);
if ~isempty(cfg.rows_to_run), rows = rows(ismember([rows.sheet_row], cfg.rows_to_run)); end
fprintf('%d recordings in spreadsheet\n', numel(rows));

% Make the output folder (and figures subfolder). Figures are drawn
% invisibly so this also works on a server with no display.
if cfg.save_figs
    fig_dir = fullfile(cfg.out_dir, 'figures');
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
    old_vis = get(0, 'DefaultFigureVisible');   % restored at the end
    set(0, 'DefaultFigureVisible', 'off');   % no windows on a headless server
elseif ~exist(cfg.out_dir, 'dir')
    mkdir(cfg.out_dir);
end

%% 3. Run each row
% res : one results struct per row (becomes the CSV)
% outs: window_amplitude output per row (saved in the MAT file)
res  = struct([]);
outs = cell(numel(rows), 1);
for i = 1:numel(rows)
    % This row's spreadsheet values, and a short label used for the
    % figure file name and the progress line
    x = rows(i);
    label = sprintf('%d_%s_s%d', x.mouse_id, datestr(x.rec_datenum, 'yyyy-mm-dd'), x.session);

    % Results row, filled in as far as this recording gets. Every row has
    % the same fields (blank/NaN until set) so they can be stacked into a
    % table even when a row is skipped or fails.
    r = struct();
    r.sheet_row   = x.sheet_row;
    r.project     = x.project;
    r.cohort      = x.cohort;
    r.mouse_id    = x.mouse_id;
    r.rec_date    = datestr(x.rec_datenum, 'yyyy-mm-dd');
    r.session     = x.session;
    r.seizure     = x.seizure;
    r.sudep       = x.sudep;
    r.ecog_ch     = mat2str(x.ecog_ch);
    r.ecog_used   = '';                % channel(s) actually analysed
    r.sz_on       = x.sz_on;
    r.sz_off      = x.sz_off;
    r.sex         = x.sex;
    r.age_days    = x.age_days;
    r.heat_start  = x.heat_start;
    r.group       = x.group;
    r.pseudo_rescued = double(x.pseudo_rescued);
    r.seizure_number = x.seizure_number;
    r.in_primary     = double(x.in_primary);
    r.exclude_reason = x.exclude_reason;
    r.folder      = '';
    r.record_node = '';
    r.status      = '';
    r.dur_s            = NaN;
    r.base_start_s     = NaN;
    r.base_end_s       = NaN;
    r.base_clean_s     = NaN;
    r.base_rms_uV      = NaN;
    for b = 1:numel(bin_names), r.(bin_names{b}) = NaN; end
    for b = 1:numel(bin_names), r.(clean_names{b}) = NaN; end
    for b = 1:numel(bin_names), r.(dt_names{b}) = NaN; end
    r.n_spikes = NaN;
    r.spikes_base_per_min = NaN;
    for b = 1:numel(bin_names), r.(spk_names{b}) = NaN; end
    r.message          = '';

    % Everything inside try...catch: if any step fails for this recording
    % (missing folder, bad file, too little baseline, ...), the error
    % message is stored in the results row and the loop moves on.
    try
        % Find the folder and load the ECoG channel (load_row_ecog.m).
        % Rows that can't be analysed as specified come back with a
        % skip message and nothing loaded.
        L = load_row_ecog(x, cfg.data_root, cfg.ecog_multi, cfg.notch);
        if ~isempty(L.skip_msg)
            r.status = 'skipped';
            r.message = L.skip_msg;
        else
            r.folder      = L.folder;
            r.record_node = L.record_node;
            r.message     = L.note;
            if ~isempty(L.err_msg), error('%s', L.err_msg); end   % recorded by catch below
            ecog = L.ecog;
            ch   = L.ch;
            r.ecog_used = mat2str(ch);

            % Spikes in the whole recording (detect_spikes.m)
            sp = detect_spikes(ecog, L.fs, cfg.spikes);

            % Get RMS amplitude, delta, and theta: cfg.opts plus spike times, plotting on/off and a
            % figure title identifying the recording
            opts = cfg.opts;
            opts.spike_t = sp.t;
            opts.heat_start = x.heat_start;    % for the pre-heating baseline
            opts.plot = cfg.save_figs;
            opts.title_str = sprintf('%s | %s | mouse %d | %s session %d | ECoG %s', ...
                x.project, x.cohort, x.mouse_id, r.rec_date, x.session, mat2str(ch));
            out = window_amplitude(ecog, L.fs, x.sz_on, x.sz_off, opts);
            out.opts.spike_t = [];                % kept once, in out.spikes
            out.spikes = sp;
            outs{i} = out;

            % Copy the summary numbers into the results row (baseline RMS
            % converted from log10 uV back to uV)
            r.status       = 'ok';
            r.dur_s        = out.dur_s;
            r.base_start_s = out.base_start;
            r.base_end_s   = out.base_end;
            r.base_clean_s = out.base_clean_s;
            r.base_rms_uV  = 10^out.base_mean;
            for b = 1:numel(bin_names)
                r.(bin_names{b})   = out.bin_ratio(b);
                r.(clean_names{b}) = out.bin_clean_frac(b);
                r.(dt_names{b})    = out.bin_dt_ratio(b);
                r.(spk_names{b})   = out.bin_spike_rate(b);
            end
            r.n_spikes = numel(sp.t);
            r.spikes_base_per_min = out.base_spike_rate;

            % Save the figure as a PNG and close it (keeps memory use flat
            % over a long run)
            if cfg.save_figs
                print(gcf, fullfile(fig_dir, [label '.png']), '-dpng', '-r120');
                close(gcf);
            end
        end
    catch err
        % Record the error (multi-line messages joined with ' | ') and
        % close any figure left open by the failed run
        r.status  = 'error';
        r.message = strtrim(strrep(err.message, sprintf('\n'), ' | '));
        if cfg.save_figs && ~isempty(get(0, 'CurrentFigure')), close all; end
    end

    % Progress line, then add this row to the results
    fprintf('[%3d/%d] %-28s %-15s %s\n', i, numel(rows), label, r.status, r.message);
    if isempty(res), res = r; else, res(end+1) = r; end %#ok<SAGROW>
end

%% 4. Save
% CSV for reading in Excel/R/Python; MAT keeps everything, including each
% recording's window times, amplitudes and artifact flags
write_results_csv(res, fullfile(cfg.out_dir, 'postictal_results.csv'));
save(fullfile(cfg.out_dir, 'postictal_results.mat'), 'res', 'outs', 'cfg');

%% 5. Summary
% How many recordings ended in each status
st = {res.status};
fprintf('\nStatus counts:\n');
u = unique(st);
for k = 1:numel(u)
    fprintf('  %-15s %d\n', u{k}, sum(strcmp(st, u{k})));
end
% Primary cohort: analysed recordings per group
ok_p = [res.in_primary] == 1 & ~ismember({res.status}, {'error', 'skipped'});
fprintf('\nPrimary cohort, analysed:\n');
for k = 1:size(cfg.groups, 1)
    fprintf('  %-15s %d\n', cfg.groups{k, 2}, sum(ok_p & strcmp({res.group}, cfg.groups{k, 2})));
end
fprintf('Results written to %s\n', cfg.out_dir);

% Restore figure visibility so later figures in this MATLAB session show
if cfg.save_figs, set(0, 'DefaultFigureVisible', old_vis); end
