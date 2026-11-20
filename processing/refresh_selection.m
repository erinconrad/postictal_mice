function refresh_selection()
% REFRESH_SELECTION  Re-apply the cohort selection (prepare_rows.m) to the
% saved batch results, without reprocessing any recording. Use it after a
% change that decides only which recording each mouse contributes (the
% selection rule, cfg.session_corrections, cfg.excluded_seizures, the
% SUDEP setting or a corrected SUDEP entry in the spreadsheet), not the
% signals or the seizure times.
%
%   refresh_selection
%
% Updates, in <output>/postictal_batch/postictal_results.mat and .csv, each
% row's group, session, seizure_number, SUDEP flag, in_primary and
% exclude_reason.
% Stops without changing anything if any row's onset or offset differs
% from the saved results, or rows were added or removed: then rerun
% run_postictal_batch, because the windows and depths depend on them.
% Afterwards run analyze_primary (all measures) and make_figures.

addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();
cfg = analysis_config();
batch_dir = fullfile(cfg.out_root, 'postictal_batch');
B = load(fullfile(batch_dir, 'postictal_results.mat'));
rows = prepare_rows(cfg);

% Check that the saved results are for the same rows and seizure times
assert(isequal(sort([B.res.sheet_row]), sort([rows.sheet_row])), ...
    'The spreadsheet rows differ from the saved batch results: rerun run_postictal_batch');
same = @(a, b) (isnan(a) && isnan(b)) || abs(a - b) < 1e-6;
for i = 1:numel(B.res)
    x = rows([rows.sheet_row] == B.res(i).sheet_row);
    assert(same(x.sz_on, B.res(i).sz_on) && same(x.sz_off, B.res(i).sz_off), ...
        'Row %d: seizure times differ from the saved batch results: rerun run_postictal_batch', x.sheet_row);
end

% Copy the selection fields
n_changed = 0;
for i = 1:numel(B.res)
    x = rows([rows.sheet_row] == B.res(i).sheet_row);
    if B.res(i).in_primary ~= x.in_primary, n_changed = n_changed + 1; end
    B.res(i).group          = x.group;
    B.res(i).session        = x.session;
    B.res(i).seizure_number = x.seizure_number;
    B.res(i).sudep          = x.sudep;
    B.res(i).in_primary     = double(x.in_primary);
    B.res(i).exclude_reason = x.exclude_reason;
end
save(fullfile(batch_dir, 'postictal_results.mat'), '-struct', 'B');
write_results_csv(B.res, fullfile(batch_dir, 'postictal_results.csv'));
fprintf('Selection refreshed: %d rows changed in or out of the primary cohort. Now run analyze_primary and make_figures.\n', ...
    n_changed);
end
