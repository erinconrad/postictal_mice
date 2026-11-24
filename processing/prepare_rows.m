function rows = prepare_rows(cfg)
% PREPARE_ROWS  Read the cohort spreadsheet and add the fields every script
% needs: group label, rescued pseudo-times for controls without times, and
% whether the row is the one recording its mouse contributes (and if not,
% why).
%
%   rows = prepare_rows(cfg)        cfg from analysis_config.m
%
%   Seizure onset/offset (sz_on, sz_off) are the spreadsheet's. Added fields:
%     group           'WT' | 'DS no seizure' | 'DS seizure' (cfg.groups)
%     is_seizure      true for the seizure group
%     is_sudep        true if the SUDEP column says yes for this recording
%                     (a property of the recording, not the mouse)
%     pseudo_rescued  true if onset/offset were filled in by the rescue
%     seizure_number  1 = the mouse's first seizure, 2 = its next one, ...
%                     (by recording date; NaN for other rows). Pairs for
%                     seizure 1 vs 2 come from this.
%     in_primary      true if this is the recording its mouse contributes
%     exclude_reason  why not ('' if in_primary). Rows can still fail later
%                     (missing folder, too little baseline, ...); those
%                     show up as status 'error' in the batch results.
%
%   Selection, one recording per mouse (mouse = mouse ID):
%     - a mouse with any seizure recording contributes its first seizure
%       (by recording date, then session), if that seizure is usable (not
%       SUDEP, has onset and offset); otherwise the mouse is left out. Its
%       other heating sessions are left out.
%     - a mouse that never had a seizure contributes its first heating
%       session, as a control.
%     - seizures in cfg.excluded_seizures (reviewers disagreed whether
%       there was a seizure) are left out, and so is the rest of that mouse.
%   Rows of projects in cfg.excluded_projects are dropped first, as if they
%   were not in the spreadsheet.

rows = read_cohort_sheet(cfg.xlsx);

%% 0. Projects left out entirely (cfg.excluded_projects)
if isfield(cfg, 'excluded_projects') && ~isempty(cfg.excluded_projects)
    drop = ismember(strtrim({rows.project}), cfg.excluded_projects);
    for p = cfg.excluded_projects(:)'
        is_p = strcmp(strtrim({rows.project}), p{1});
        fprintf('Excluded project %s: %d recordings (%d mice) dropped\n', p{1}, sum(is_p), ...
            numel(unique([rows(is_p).mouse_id])));
    end
    rows = rows(~drop);
end

%% 1. Group labels and flags
for i = 1:numel(rows)
    k = find(strcmpi(strtrim(rows(i).cohort), cfg.groups(:,1)), 1);
    if isempty(k)
        rows(i).group = rows(i).cohort;          % unknown cohort: keep its name
    else
        rows(i).group = cfg.groups{k, 2};
    end
    rows(i).is_seizure     = strcmpi(strtrim(rows(i).cohort), 'DS_seizure');
    rows(i).is_sudep       = strcmpi(strtrim(rows(i).sudep), 'yes');   % this recording
    rows(i).pseudo_rescued = false;
end

%% 1a. Session numbers corrected from the spreadsheet (cfg.session_corrections)
for k = 1:size(cfg.session_corrections, 1)
    [mouse_id, date_num, new_session] = cfg.session_corrections{k, :};
    i = find([rows.mouse_id] == mouse_id & [rows.rec_datenum] == yyyymmdd_to_datenum(date_num));
    if isempty(i)
        fprintf('Session correction mouse %d, %d: not in the spreadsheet\n', mouse_id, date_num);
    end
    [rows(i).session] = deal(new_session);
end

%% 1a2. Raw stream to use where a session folder holds more than one
%      (cfg.stream_choice; load_row_ecog.m passes it to find_oe_stream.m).
%      NaN = the folder must hold exactly one raw stream.
[rows.stream] = deal(NaN);
if isfield(cfg, 'stream_choice')
    for k = 1:size(cfg.stream_choice, 1)
        [mouse_id, date_num, stream] = cfg.stream_choice{k, :};
        i = find([rows.mouse_id] == mouse_id & [rows.rec_datenum] == yyyymmdd_to_datenum(date_num));
        if isempty(i)
            fprintf('Stream choice mouse %d, %d: not in the spreadsheet\n', mouse_id, date_num);
        end
        [rows(i).stream] = deal(stream);
    end
end

%% 1b. Seizures left out (cfg.excluded_seizures: reviewers disagreed on
%      whether there was a seizure), matched by mouse ID and recording
%      date. excluded_reason{i} = the reason, or ''.
excluded_reason = repmat({''}, 1, numel(rows));
for k = 1:size(cfg.excluded_seizures, 1)
    [mouse_id, date_num, why] = cfg.excluded_seizures{k, :};
    i = find([rows.mouse_id] == mouse_id & [rows.rec_datenum] == yyyymmdd_to_datenum(date_num));
    if isempty(i)
        fprintf('Excluded seizure mouse %d, %d: not in the spreadsheet\n', mouse_id, date_num);
    end
    excluded_reason(i) = {why};
end

%% 2. Each mouse's first seizure
% seizure_number counts each mouse's seizure recordings (not disputed) by
% recording date, then session. The first one is the mouse's primary
% recording if it is usable.
n = numel(rows);
[rows.seizure_number] = deal(NaN);
[rows.in_primary] = deal(false);
[rows.exclude_reason] = deal('');
is_disputed = ~cellfun(@isempty, excluded_reason);
has_times = @(k) ~isnan(rows(k).sz_on) && ~isnan(rows(k).sz_off);
mice = unique([rows.mouse_id]);
chosen = nan(size(mice));                          % row index each mouse contributes
mouse_reason = repmat({''}, size(mice));           % why a mouse contributes nothing
for m = 1:numel(mice)
    recs = find([rows.mouse_id] == mice(m));
    [~, order] = sortrows([[rows(recs).rec_datenum]' [rows(recs).session]']);
    recs = recs(order);                            % this mouse's recordings, in time order
    seizures = recs([rows(recs).is_seizure] & ~is_disputed(recs));
    for k = 1:numel(seizures), rows(seizures(k)).seizure_number = k; end
    if any(is_disputed(recs))
        mouse_reason{m} = sprintf('mouse has a disputed seizure (row %s)', ...
            strjoin(arrayfun(@num2str, [rows(recs(is_disputed(recs))).sheet_row], 'UniformOutput', false), ', '));
    elseif ~isempty(seizures)
        first = seizures(1);
        if cfg.exclude_sudep && rows(first).is_sudep
            mouse_reason{m} = sprintf('first seizure (row %d) ended in SUDEP', rows(first).sheet_row);
        elseif ~has_times(first)
            mouse_reason{m} = sprintf('first seizure (row %d) has no onset/offset times', rows(first).sheet_row);
        else
            chosen(m) = first;
        end
    else
        chosen(m) = recs(1);                       % never seized: first heating session (times checked in 4)
    end
end

%% 3. Optional rescue of controls without onset/offset times
% Reference values: the chosen first seizures (section 2) with a heating
% start time
if cfg.rescue_pseudo
    ref = chosen(~isnan(chosen));
    ref = ref([rows(ref).is_seizure] & ~isnan([rows(ref).heat_start]));
    lag_on  = median([rows(ref).sz_on]  - [rows(ref).heat_start]);   % heating start -> onset
    lag_off = median([rows(ref).sz_off] - [rows(ref).heat_start]);   % heating start -> offset
    fprintf('Pseudo-time rescue: onset = heating start + %.0f s, offset = heating start + %.0f s (from %d seizures)\n', ...
        lag_on, lag_off, numel(ref));
    for i = 1:n
        if ~rows(i).is_seizure && isnan(rows(i).sz_on) && ~isnan(rows(i).heat_start)
            rows(i).sz_on  = rows(i).heat_start + lag_on;
            rows(i).sz_off = rows(i).heat_start + lag_off;
            rows(i).pseudo_rescued = true;
        end
    end
end

%% 4. Primary flag and the reason every other row is left out
for m = 1:numel(mice)
    recs = find([rows.mouse_id] == mice(m));
    c = chosen(m);
    if ~isnan(c) && ~has_times(c)                   % control with no times, none rescued
        mouse_reason{m} = sprintf('first heating session (row %d) has no onset/offset times', rows(c).sheet_row);
        c = NaN;
    end
    for i = recs
        if i == c
            rows(i).in_primary = true;
        elseif is_disputed(i)
            rows(i).exclude_reason = excluded_reason{i};
        elseif ~isempty(mouse_reason{m})
            rows(i).exclude_reason = mouse_reason{m};
        elseif rows(c).is_seizure && rows(i).is_seizure
            rows(i).exclude_reason = sprintf('later seizure (mouse''s first seizure is row %d)', rows(c).sheet_row);
        elseif rows(c).is_seizure
            rows(i).exclude_reason = sprintf('no seizure (mouse''s first seizure is row %d)', rows(c).sheet_row);
        else
            rows(i).exclude_reason = sprintf('later heating session (mouse''s first is row %d)', rows(c).sheet_row);
        end
    end
end

% Summary, and a note for mouse IDs listed under more than one project
% (treated as one mouse)
g = {rows([rows.in_primary]).group};
fprintf('One recording per mouse: WT %d, DS no seizure %d, DS seizure %d\n', sum(strcmp(g, 'WT')), ...
    sum(strcmp(g, 'DS no seizure')), sum(strcmp(g, 'DS seizure')));
for m = 1:numel(mice)
    projects = unique(strtrim({rows([rows.mouse_id] == mice(m)).project}));
    if numel(projects) > 1
        fprintf('Mouse %d is listed under %s (treated as one mouse)\n', mice(m), strjoin(projects, ' and '));
    end
end
end

%% ------------------------------------------------------------------------
function d = yyyymmdd_to_datenum(date_num)
% 20240604 -> datenum of June 4, 2024
d = datenum(floor(date_num / 10000), mod(floor(date_num / 100), 100), mod(date_num, 100));
end
