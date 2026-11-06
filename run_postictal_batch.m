% run_postictal_batch.m
% Run postictal_recovery.m on every recording listed in the cohort
% spreadsheet. One results row per spreadsheet row, plus one figure per
% recording that ran.
%
% Run from anywhere; all other functions live in this scripts folder.
% Folders default to the project layout in project_paths.m:
%   <project>/data/MattisLab_postictal_EEG   input
%   <project>/output/postictal_batch         results
%
% Outputs in cfg.out_dir:
%   postictal_results.csv   one row per spreadsheet row (columns below)
%   postictal_results.mat   same table as a struct array, plus each full
%                           postictal_recovery output and the settings
%   figures/<mouse>_<date>_s<session>.png
%
% CSV columns:
%   sheet_row ... sz_off  copied from the spreadsheet (sheet_row = Excel row)
%   folder, record_node   session folder and Record Node that were used
%   status            recovered | not recovered | no suppression |
%                     indeterminate | skipped | error
%   early_ratio       RMS in the first 60 s after offset / baseline RMS
%   early_clean_frac  artifact-free fraction of that 60 s
%   rec_from_offset   recovery time, s after offset (blank if no suppression)
%   hold_clean_frac   artifact-free fraction of the 60 s hold check; low
%                     values mean recovery may mark the end of artifact
%   max_observable_s  if not recovered: latest time after offset a hold
%                     could have started (recovery is later than this)
%   base_clean_s      artifact-free baseline time (s, of 300)
%   base_rms_uV       baseline RMS (geometric mean, uV)
%   thresh_uV         threshold (uV)
%   message           reason for skipped/error, or a note (e.g. folder date
%                     differs from sheet date by 1 day)
%
% Sections:
%   1. Settings          folders, which rows to run, analysis options
%   2. Read spreadsheet  one struct per recording; make output folders
%   3. Run each row      for each recording: skip if it can't be analysed,
%                        otherwise find its folder and raw EEG file, load the
%                        ECoG channel, run postictal_recovery, save the figure.
%                        Any error is recorded for that row and the loop
%                        continues with the next one.
%   4. Save              results table as CSV and MAT
%   5. Summary           count of each status, printed to the command window

%% 1. Settings -- edit these
% Add this scripts folder to the path, then get the project folders
addpath(fileparts(mfilename('fullpath')));   % this scripts folder
p = project_paths();
cfg = struct();
cfg.data_root = p.data;                                          % holds WT, DS_seizure, DS_NOseizure
cfg.xlsx      = fullfile(cfg.data_root, 'postictal_EEG_combined.xlsx');
cfg.out_dir   = fullfile(p.output, 'postictal_batch');
cfg.save_figs = true;

% Spreadsheet rows to run, as Excel row numbers (row 1 = header); [] = all.
% E.g. 2:6 for a quick test before running everything.
cfg.rows_to_run = [];

% Rows whose ECoG column lists more than one channel (e.g. '[3,4]'):
%   'skip'    : do not analyse (default until we know what [3,4] means)
%   'bipolar' : first minus second channel (3 - 4)
%   'first'   : first channel only
cfg.ecog_multi = 'skip';

% Options passed to postictal_recovery (anything not set uses its defaults)
cfg.opts = struct();

%% 2. Read spreadsheet
% One struct per non-blank spreadsheet row (see read_cohort_sheet.m),
% optionally restricted to the rows listed in cfg.rows_to_run
rows = read_cohort_sheet(cfg.xlsx);
if ~isempty(cfg.rows_to_run), rows = rows(ismember([rows.sheet_row], cfg.rows_to_run)); end
fprintf('%d recordings in spreadsheet\n', numel(rows));

% Make the output folder (and figures subfolder). Figures are drawn
% invisibly so this also works on a server with no display.
if cfg.save_figs
    fig_dir = fullfile(cfg.out_dir, 'figures');
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
    set(0, 'DefaultFigureVisible', 'off');   % no windows on a headless server
elseif ~exist(cfg.out_dir, 'dir')
    mkdir(cfg.out_dir);
end

%% 3. Run each row
% res : one results struct per row (becomes the CSV)
% outs: full postictal_recovery output per row (saved in the MAT file)
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
    r.sz_on       = x.sz_on;
    r.sz_off      = x.sz_off;
    r.folder      = '';
    r.record_node = '';
    r.status      = '';
    r.early_ratio      = NaN;
    r.early_clean_frac = NaN;
    r.rec_from_offset  = NaN;
    r.hold_clean_frac  = NaN;
    r.max_observable_s = NaN;
    r.base_clean_s     = NaN;
    r.base_rms_uV      = NaN;
    r.thresh_uV        = NaN;
    r.message          = '';

    % Everything inside try...catch: if any step fails for this recording
    % (missing folder, bad file, too little baseline, ...), the error
    % message is stored in the results row and the loop moves on.
    try
        % Rows that cannot be analysed as specified
        if isnan(x.sz_on) || isnan(x.sz_off)
            r.status = 'skipped';
            r.message = 'no onset/offset times in spreadsheet';
        elseif isempty(x.ecog_ch)
            r.status = 'skipped';
            r.message = 'no ECoG channel in spreadsheet';
        elseif numel(x.ecog_ch) > 1 && strcmp(cfg.ecog_multi, 'skip')
            r.status = 'skipped';
            r.message = sprintf('ECoG channel %s: set cfg.ecog_multi to analyse', mat2str(x.ecog_ch));
        else
            % Find the session folder and the raw stream inside it
            [folder, note] = find_recording_folder(cfg.data_root, x.cohort, x.rec_datenum, x.mouse_id);
            r.folder = folder;
            r.message = note;
            info = find_oe_stream(folder);
            r.record_node = info.record_node;

            % Which channel(s) to load. Bipolar rows use the first two
            % listed channels; all others use the first one.
            switch cfg.ecog_multi
                case 'bipolar', ch = x.ecog_ch(1:min(2, end));
                otherwise,      ch = x.ecog_ch(1);
            end
            % Spreadsheet channel N = CH N, the Nth channel in the file;
            % check the name to be sure
            assert(all(strcmp(info.channel_names(ch), arrayfun(@(c) sprintf('CH%d', c), ch, 'UniformOutput', false))), ...
                'Channel %s in the file is named %s, expected CH%d', mat2str(ch), ...
                strjoin(info.channel_names(ch), ','), ch(1));
            % Load the channel(s) in uV, using the channel count, gain and
            % sampling rate read from structure.oebin
            sig = load_oe_channel(info.dat_file, ch, info.n_chans, info.bit_volts(ch), info.fs);
            % Bipolar: first channel minus second
            if size(sig, 2) == 2
                ecog = sig(:,1) - sig(:,2);
            else
                ecog = sig(:,1);
            end

            % Analysis: cfg.opts plus plotting on/off and a figure title
            % identifying the recording
            opts = cfg.opts;
            opts.plot = cfg.save_figs;
            opts.title_str = sprintf('%s | %s | mouse %d | %s session %d | ECoG %s', ...
                x.project, x.cohort, x.mouse_id, r.rec_date, x.session, mat2str(ch));
            out = postictal_recovery(ecog, info.fs, x.sz_on, x.sz_off, opts);
            outs{i} = out;

            % Copy the key numbers into the results row. log10 values are
            % converted back to uV (10^x).
            r.status           = out.status;
            r.early_ratio      = out.early_ratio;
            r.early_clean_frac = out.early_clean_frac;
            % A recovery time is meaningless without suppression, so leave
            % it blank for 'no suppression'. It is kept for 'indeterminate'
            % (first clean signal above threshold), but treat with care.
            if ~strcmp(out.status, 'no suppression')
                r.rec_from_offset = out.rec_from_offset;
                r.hold_clean_frac = out.hold_clean_frac;
            end
            r.max_observable_s = out.max_observable_s;
            r.base_clean_s     = out.base_clean_s;
            r.base_rms_uV      = 10^out.base_mean;
            r.thresh_uV        = 10^out.thresh;

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
% CSV for reading in Excel/R/Python; MAT keeps everything, including the
% full per-recording outputs (window times, amplitudes, artifact flags)
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
fprintf('Results written to %s\n', cfg.out_dir);
