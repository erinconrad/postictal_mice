function rows = read_cohort_sheet(xlsx_file)
% READ_COHORT_SHEET  One struct per recording from postictal_EEG_combined.xlsx.
%
%   rows = read_cohort_sheet(xlsx_file)
%
%   Columns are found by header text, so their order can change. Blank
%   rows (no mouse ID) are dropped. Fields:
%     sheet_row, project, cohort, mouse_id, rec_datenum, session, seizure,
%     sudep, heat_start, ecog_ch (vector, e.g. [3 4]), emg_ch, sz_on, sz_off
%   Missing numbers are NaN.
%
%   The recording date may be stored as a number (20240227), as an Excel
%   date, or as text; all three are converted to a datenum.

%% 1. Read every cell, and lower-case the header row for matching
C = read_sheet_cells(xlsx_file);
hdr = lower(cellfun(@cell2str, C(1, :), 'UniformOutput', false));

%% 2. Find each column by a piece of its header text
% e.g. 'ueo' finds 'UEO (1st seizure) - time (s)'. Stops with an error if
% a required column is missing.
col.project = find_col(hdr, 'project');
col.cohort  = find_col(hdr, 'cohort');
col.mouse   = find_col(hdr, 'mouse id');
col.date    = find_col(hdr, 'recording date', 'date');   % older sheets: 'date'
col.session = find_col(hdr, 'heating session');
col.heat    = find_col(hdr, 'heating start', '');         % optional
col.seizure = find_col(hdr, 'seizure?');
col.sudep   = find_col(hdr, 'sudep');
col.ecog    = find_col(hdr, 'ecog');
col.emg     = find_col(hdr, 'emg');
col.on      = find_col(hdr, 'ueo');
col.off     = find_col(hdr, 'off (last');

%% 3. One struct per data row (row 1 is the header)
% Each cell is converted with a helper below that copes with blanks,
% numbers stored as text, and so on.
rows = struct([]);
for r = 2:size(C, 1)
    % Rows without a mouse ID are blank or notes: skip them
    id = to_num(C{r, col.mouse});
    if isnan(id), continue; end
    x = struct();
    x.sheet_row   = r;
    x.project     = cell2str(C{r, col.project});
    x.cohort      = cell2str(C{r, col.cohort});
    x.mouse_id    = id;
    x.rec_datenum = to_datenum(C{r, col.date});
    x.session     = to_num(C{r, col.session});
    x.seizure     = cell2str(C{r, col.seizure});
    x.sudep       = cell2str(C{r, col.sudep});
    x.heat_start  = NaN;
    if ~isempty(col.heat), x.heat_start = to_num(C{r, col.heat}); end
    x.ecog_ch     = to_vec(C{r, col.ecog});
    x.emg_ch      = to_vec(C{r, col.emg});
    x.sz_on       = to_num(C{r, col.on});
    x.sz_off      = to_num(C{r, col.off});
    if isempty(rows), rows = x; else, rows(end+1) = x; end %#ok<AGROW>
end
end

%% ------------------------------------------------------------------------
%% Helper functions: convert one spreadsheet cell to the type needed
function c = find_col(hdr, key, fallback)
% Column whose header contains key. If none: try fallback (exact header
% match), or return [] if fallback is '' (optional column).
c = find(~cellfun(@isempty, strfind(hdr, key)), 1);
if isempty(c) && nargin > 2
    if isempty(fallback), return; end
    c = find(strcmp(hdr, fallback), 1);
end
assert(~isempty(c), 'No column header containing "%s"', key);
end

function b = is_blank(v)
% True for an empty cell: [], NaN, missing, or text that is only spaces
b = isempty(v) || (isnumeric(v) && isscalar(v) && isnan(v)) || ...
    isa(v, 'missing') || ((ischar(v) || isstring(v)) && isempty(strtrim(as_char(v))));
end

function s = cell2str(v)
% Cell -> text ('' if blank; numbers become their text form)
if is_blank(v), s = '';
elseif isnumeric(v) || islogical(v), s = num2str(v);
else, s = strtrim(as_char(v));
end
end

function n = to_num(v)
% Cell -> number (NaN if blank; text like '12.5' is converted)
if is_blank(v), n = NaN;
elseif isnumeric(v), n = double(v);
else, n = str2double(as_char(v));
end
end

function v = to_vec(x)
% 9 -> 9; '[3,4]' -> [3 4]
if is_blank(x), v = [];
elseif isnumeric(x), v = double(x(:)');
else, v = str2num(as_char(x)); %#ok<ST2NM>
end
end

function d = to_datenum(v)
% Cell -> MATLAB datenum (days since year 0), whichever way the date is
% stored: datetime, 20240227-style number, Excel day count, or text
if is_blank(v)
    d = NaN;
elseif isa(v, 'datetime')
    d = datenum(v);
elseif isnumeric(v) && v > 19000000        % 20240227
    y = floor(v / 10000); m = floor(mod(v, 10000) / 100); dd = mod(v, 100);
    d = datenum(y, m, dd);
elseif isnumeric(v)                         % Excel serial date
    d = v + datenum(1899, 12, 30);
else                                        % text
    d = datenum(as_char(v));
end
end

function c = as_char(v)
% Text or string -> char array
if ischar(v), c = v; else, c = char(string(v)); end
end
