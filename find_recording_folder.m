function [folder, note] = find_recording_folder(data_root, cohort, rec_datenum, mouse_id)
% FIND_RECORDING_FOLDER  Session folder for one spreadsheet row.
%
%   [folder, note] = find_recording_folder(data_root, cohort, rec_datenum, mouse_id)
%
%   data_root   : folder containing the cohort folders (WT, DS_seizure, ...)
%   cohort      : spreadsheet cohort, matched to a folder name ignoring case
%                 ('wt' -> 'WT')
%   rec_datenum : recording date as a MATLAB datenum
%   mouse_id    : numeric mouse ID
%
%   Session folders are named YYYY-MM-DD_HH-MM-SS_<rest>, where <rest>
%   contains the mouse ID, possibly followed by text (e.g. 4336mutant,
%   3684het_seizure1). The ID must not be part of a longer number.
%
%   Exactly one folder with the same date and ID is required. If none
%   match on the date, folders one day either side are tried (a session
%   started before midnight and logged on the next day, or vice versa);
%   note then says so. Errors on no match or more than one match.

%% 1. Cohort folder (WT, DS_seizure, ...), matched ignoring case
d = dir(data_root);
d = d([d.isdir] & ~strncmp({d.name}, '.', 1));
hit = strcmpi({d.name}, strtrim(cohort));
assert(any(hit), 'No folder for cohort "%s" in %s', cohort, data_root);
cohort_dir = fullfile(data_root, d(find(hit, 1)).name);

%% 2. Read the date and check for the mouse ID in every session folder name
% Folder names look like 2024-02-27_11-53-07_1779 or
% 2025-02-11_13-22-10_3684het_seizure1: date, time, then the rest.
% id_pat matches the ID only when it is not part of a longer number, so
% mouse 1780 does not match a folder for mouse 17800.
s = dir(cohort_dir);
s = s([s.isdir] & ~strncmp({s.name}, '.', 1));
id_pat = sprintf('(^|[^0-9])%d([^0-9]|$)', mouse_id);
f_date = nan(numel(s), 1);
f_idok = false(numel(s), 1);
for i = 1:numel(s)
    % tok{1} = date part, tok{2} = everything after the time; folders
    % that don't follow this naming are ignored
    tok = regexp(s(i).name, '^(\d{4}-\d{2}-\d{2})_\d{2}-\d{2}-\d{2}_(.*)$', 'tokens', 'once');
    if isempty(tok), continue; end
    f_date(i) = datenum(tok{1}, 'yyyy-mm-dd');
    f_idok(i) = ~isempty(regexp(tok{2}, id_pat, 'once'));
end

%% 3. Pick the folder: same mouse ID and same date as the spreadsheet
% If none, allow a date one day either side (and say so in note).
note = '';
m = find(f_idok & f_date == floor(rec_datenum));
if isempty(m)
    m = find(f_idok & abs(f_date - floor(rec_datenum)) == 1);
    if ~isempty(m)
        note = 'folder date differs from sheet date by 1 day';
    end
end

%% 4. Exactly one match required; otherwise stop with an explanation
if isempty(m)
    error('No folder in %s for mouse %d on %s', cohort_dir, mouse_id, datestr(rec_datenum, 'yyyy-mm-dd'));
elseif numel(m) > 1
    error('%d folders in %s match mouse %d on %s: %s', numel(m), cohort_dir, mouse_id, ...
        datestr(rec_datenum, 'yyyy-mm-dd'), strjoin({s(m).name}, ', '));
end
folder = fullfile(cohort_dir, s(m).name);
end
