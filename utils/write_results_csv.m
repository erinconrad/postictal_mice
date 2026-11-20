function write_results_csv(res, csv_file)
% WRITE_RESULTS_CSV  Write a struct array as CSV, one row per element.
% Text is quoted; NaN numbers are left empty. (Avoids writetable so the
% same code runs in older MATLAB versions.)

% Header row: the struct's field names, comma-separated
f = fieldnames(res);
fid = fopen(csv_file, 'w');
assert(fid > 0, 'Could not write %s', csv_file);
fprintf(fid, '%s\n', strjoin(f', ','));
% One line per struct element. Each value is converted to text:
%   text   -> wrapped in double quotes (quotes inside are doubled, the
%             standard CSV escape, so commas in messages are safe)
%   NaN/[] -> empty
%   number -> up to 10 significant digits
for i = 1:numel(res)
    vals = cell(1, numel(f));
    for k = 1:numel(f)
        v = res(i).(f{k});
        if ischar(v)
            vals{k} = ['"' strrep(v, '"', '""') '"'];
        elseif isempty(v) || (isscalar(v) && isnan(v))
            vals{k} = '';
        else
            vals{k} = num2str(v, 10);
        end
    end
    fprintf(fid, '%s\n', strjoin(vals, ','));
end
fclose(fid);
end
