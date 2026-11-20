function S = read_results_csv(csv_file)
% READ_RESULTS_CSV  Read a CSV written by write_results_csv.m back into a
% struct array, one element per row. Quoted values are text; empty values
% are NaN; everything else is a number.
%
%   S = read_results_csv(fullfile(out_dir, 'figureS5_clinical_stats.csv'))
fid = fopen(csv_file, 'r');
assert(fid > 0, 'Could not read %s', csv_file);
header = strsplit(strtrim(fgetl(fid)), ',');
S = struct([]);
line = fgetl(fid);
while ischar(line)
    if ~isempty(strtrim(line))
        vals = split_csv_line(line);
        row = struct();
        for k = 1:numel(header)
            v = '';
            if k <= numel(vals), v = vals{k}; end
            if numel(v) >= 2 && v(1) == '"'
                row.(header{k}) = strrep(v(2:end - 1), '""', '"');   % text
            elseif isempty(v)
                row.(header{k}) = NaN;
            else
                row.(header{k}) = str2double(v);
            end
        end
        if isempty(S), S = row; else, S(end + 1) = row; end %#ok<AGROW>
    end
    line = fgetl(fid);
end
fclose(fid);
end

function vals = split_csv_line(line)
% Split at commas that are not inside double quotes
vals = {};
start = 1; in_quotes = false;
for i = 1:numel(line)
    if line(i) == '"'
        in_quotes = ~in_quotes;
    elseif line(i) == ',' && ~in_quotes
        vals{end + 1} = line(start:i - 1); %#ok<AGROW>
        start = i + 1;
    end
end
vals{end + 1} = line(start:end);
end
