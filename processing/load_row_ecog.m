function L = load_row_ecog(x, data_root, ecog_multi, notch)
% LOAD_ROW_ECOG  Find and load the ECoG signal for one spreadsheet row.
% Used by run_postictal_batch.m and the figure and viewer functions.
%
%   L = load_row_ecog(x, data_root, ecog_multi)
%   L = load_row_ecog(x, data_root, ecog_multi, notch)
%
%   x          : one row from read_cohort_sheet.m
%   data_root  : folder holding the cohort folders (WT, DS_seizure, ...)
%   ecog_multi : what to do when the ECoG column lists two channels
%                ('skip', 'bipolar' = first minus second, 'first')
%   notch      : cfg.notch from analysis_config.m (fields on, f0, n_harm,
%                bw_hz). If given and notch.on is true, mains noise is
%                removed (notch_line.m). Omitted or [] = raw signal.
%
%   L fields:
%     skip_msg     non-empty if the row cannot be analysed as specified
%                  (no seizure times, no channel, two channels with 'skip');
%                  nothing is loaded in that case
%     ecog         ECoG signal in uV (column vector)
%     fs           sampling rate (Hz)
%     ch           channel number(s) used
%     folder       session folder
%     record_node  Record Node the raw data came from
%     note         note from the folder search (e.g. date off by one day)
%     err_msg      non-empty if finding or loading failed (missing folder,
%                  no raw stream, wrong channel name, ...). Fields filled in
%                  before the failure (e.g. folder) are kept, so the caller
%                  can record how far it got.

L = struct('skip_msg', '', 'err_msg', '', 'ecog', [], 'fs', NaN, 'ch', [], ...
    'folder', '', 'record_node', '', 'note', '');

%% 1. Rows that cannot be analysed as specified
if isnan(x.sz_on) || isnan(x.sz_off)
    L.skip_msg = 'no onset/offset times in spreadsheet';
    return
elseif isempty(x.ecog_ch)
    L.skip_msg = 'no ECoG channel in spreadsheet';
    return
elseif numel(x.ecog_ch) > 1 && strcmp(ecog_multi, 'skip')
    L.skip_msg = sprintf('ECoG channel %s: set cfg.ecog_multi to analyse', mat2str(x.ecog_ch));
    return
end

% Steps 2-4 inside try...catch: on failure, keep what was found so far
% and return the error message in L.err_msg
try
%% 2. Find the session folder and the raw stream inside it
[L.folder, L.note] = find_recording_folder(data_root, x.cohort, x.rec_datenum, x.mouse_id);
which = NaN;                                      % stream choice (cfg.stream_choice, prepare_rows.m)
if isfield(x, 'stream'), which = x.stream; end
info = find_oe_stream(L.folder, which);
L.record_node = info.record_node;
if ~isnan(which)
    L.note = strtrim(sprintf('%s raw stream %d of %d used (cfg.stream_choice)', L.note, which, info.n_streams));
end
L.fs = info.fs;

%% 3. Which channel(s) to load
% Bipolar rows use the first two listed channels; all others the first.
switch ecog_multi
    case 'bipolar', ch = x.ecog_ch(1:min(2, end));
    otherwise,      ch = x.ecog_ch(1);
end
L.ch = ch;
% Spreadsheet channel N = CH N, the Nth channel in the file; check the
% name to be sure
assert(all(strcmp(info.channel_names(ch), arrayfun(@(c) sprintf('CH%d', c), ch, 'UniformOutput', false))), ...
    'Channel %s in the file is named %s, expected %s', mat2str(ch), ...
    strjoin(info.channel_names(ch), ','), strjoin(arrayfun(@(c) sprintf('CH%d', c), ch, 'UniformOutput', false), ','));

%% 4. Load in uV (channel count, gain and sampling rate from structure.oebin)
sig = load_oe_channel(info.dat_file, ch, info.n_chans, info.bit_volts(ch), info.fs);
if size(sig, 2) == 2
    L.ecog = sig(:,1) - sig(:,2);   % bipolar: first minus second
else
    L.ecog = sig(:,1);
end

%% 5. Remove mains noise (optional)
if nargin >= 4 && ~isempty(notch) && notch.on
    L.ecog = notch_line(L.ecog, L.fs, notch.f0, notch.n_harm, notch.bw_hz);
end
catch err
    L.err_msg = err.message;
end
end
