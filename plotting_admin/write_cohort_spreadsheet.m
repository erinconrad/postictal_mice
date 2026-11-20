function write_cohort_spreadsheet(res, pa, cfg)
% WRITE_COHORT_SPREADSHEET  Copy of the cohort spreadsheet (cfg.xlsx) with
% three columns added after the last one, saying how each row was used.
% Called by make_results_report.m; can also be run on its own after
% analyze_primary:
%
%   cfg = analysis_config();
%   B = load(fullfile(cfg.out_root, 'postictal_batch', 'postictal_results.mat'), 'res');
%   A = load(fullfile(cfg.out_root, 'primary_analysis', 'primary_analysis.mat'), 'pa');
%   write_cohort_spreadsheet(B.res, A.pa, cfg)
%
%   res : batch results, one entry per spreadsheet row (postictal_results.mat)
%   pa  : per-animal results of analyze_primary (any measure; the 5-min
%         depth's availability and the second-seizure rows are the same
%         for every measure)
%
% Writes, in cfg.out_root:
%   cohort_by_row.xlsx  the spreadsheet with the three columns added (the
%                       original's rows, columns, formatting and formulas
%                       kept; MATLAB's writecell)
%   cohort_by_row.csv   sheet_row, mouse_id and the three columns
%
% Columns:
%   Analysis cohort        DS seizure | Control (WT) | Control (DS no
%                          seizure) | Paired comparison only (seizure 2) |
%                          Not used. Notes when the row is also seizure 1
%                          of the paired comparison, or a seizure-2 row
%                          is not in the paired test (no 5-min depth).
%   Why mouse excluded from the cohort   for mice with no analysed row:
%                          first seizure ended in SUDEP, disputed seizure,
%                          or why the chosen recording could not be processed
%   Why row excluded from the primary analysis   for other rows of
%                          cohort mice: later seizure, session without a
%                          seizure in a seizure mouse, later heating
%                          session of a control; for analysed rows with no
%                          5-min depth: why not

main_s = cfg.depth_main_s;
depth_field   = sprintf('depth_0_%ds', main_s);
missing_field = sprintf('missing_0_%ds', main_s);
s2_field      = sprintf('s2_depth_0_%ds', main_s);
ok = ~ismember({res.status}, {'error', 'skipped'});
final_mice = unique([res([res.in_primary] == 1 & ok).mouse_id]);
group_label = containers.Map({'DS seizure', 'WT', 'DS no seizure'}, ...
    {'DS seizure', 'Control (WT)', 'Control (DS no seizure)'});

n = numel(res);
cohort = repmat({''}, n, 1); why_mouse = repmat({''}, n, 1); why_row = repmat({''}, n, 1);
for i = 1:n
    r = res(i);
    if ~ismember(r.mouse_id, final_mice)
        % Mouse not in the cohort: why (its chosen recording failed, or its
        % rows' exclusion reason from prepare_rows.m)
        cohort{i} = 'Not used';
        mine = res([res.mouse_id] == r.mouse_id);
        chosen = mine([mine.in_primary] == 1);
        if ~isempty(chosen)
            why_mouse{i} = processing_reason(chosen(1).message);
        else
            why_mouse{i} = mine(1).exclude_reason;
        end
        why_row{i} = 'mouse not in the cohort';
    elseif r.in_primary == 1
        % The mouse's analysed recording
        p = pa([pa.sheet_row] == r.sheet_row);
        cohort{i} = group_label(r.group);
        if ~isnan(p.s2_sheet_row)
            cohort{i} = [cohort{i} '; also seizure 1 in the paired comparison'];
        end
        if ~isempty(p.(missing_field))
            why_row{i} = sprintf('in the cohort, but no %g-min depth: %s', main_s / 60, p.(missing_field));
        end
    else
        % Another session of a cohort mouse
        why_row{i} = r.exclude_reason;
        if ~ok(i)
            why_row{i} = sprintf('%s; also could not be processed (%s)', why_row{i}, processing_reason(r.message));
        end
        p = pa([pa.s2_sheet_row] == r.sheet_row);   % this row is a mouse's second seizure
        if isempty(p)
            cohort{i} = 'Not used';
        else
            cohort{i} = 'Paired comparison only (seizure 2)';
            if isnan(p.(s2_field))
                cohort{i} = sprintf('%s; no %g-min depth, so not in the paired test', cohort{i}, main_s / 60);
            elseif isnan(p.(depth_field))
                cohort{i} = sprintf('%s; seizure 1 has no %g-min depth, so not in the paired test', cohort{i}, main_s / 60);
            end
        end
    end
end
headers = {'Analysis cohort', 'Why mouse excluded from the cohort', 'Why row excluded from the primary analysis'};

% CSV (also a check when the xlsx cannot be written)
csv_file = fullfile(cfg.out_root, 'cohort_by_row.csv');
q = struct('sheet_row', num2cell([res.sheet_row]'), 'mouse_id', num2cell([res.mouse_id]'), ...
    'analysis_cohort', cohort, 'why_mouse_excluded', why_mouse, 'why_row_excluded', why_row);
write_results_csv(q, csv_file);

% xlsx: a copy of the spreadsheet with the columns added after its last column
xlsx_file = fullfile(cfg.out_root, 'cohort_by_row.xlsx');
if exist('writecell', 'file') ~= 2 && exist('writecell', 'builtin') ~= 5
    fprintf('writecell not available: wrote %s only\n', csv_file);
    return
end
C = read_sheet_cells(cfg.xlsx);
n_cols = find(~cellfun(@(x) all(ismissing(x)), C(1, :)), 1, 'last');   % last header column
copyfile(cfg.xlsx, xlsx_file, 'f');
% One block from row 1 (headers) to the last data row, written at once
block = repmat({''}, max([res.sheet_row]), 3);
block(1, :) = headers;
block([res.sheet_row], :) = [cohort why_mouse why_row];
first_col = col_letter(n_cols + 1);
writecell(block, xlsx_file, 'Range', [first_col '1']);
fprintf('Cohort by row: %s (columns %s-%s)\n', xlsx_file, first_col, col_letter(n_cols + 3));
end

function s = col_letter(k)
% Spreadsheet column letters: 1 -> A, 26 -> Z, 27 -> AA
s = '';
while k > 0
    s = [char('A' + mod(k - 1, 26)) s]; %#ok<AGROW>
    k = floor((k - 1) / 26);
end
end
