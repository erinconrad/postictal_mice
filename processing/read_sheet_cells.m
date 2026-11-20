function C = read_sheet_cells(xlsx_file)
% READ_SHEET_CELLS  Raw cell array of the first sheet (needs MATLAB R2019a+).
% Kept separate so the parsing in read_cohort_sheet.m can be tested
% without Excel support.
assert(exist(xlsx_file, 'file') == 2, 'Spreadsheet not found: %s', xlsx_file);
% Every cell of the first sheet, as-is: numbers stay numbers, text stays
% text, date-formatted cells come back as datetime, blank cells as missing
C = readcell(xlsx_file);
end
