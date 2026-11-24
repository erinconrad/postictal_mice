function info = find_oe_stream(rec_folder, which)
% FIND_OE_STREAM  Locate the raw (unfiltered) acquisition-board recording
% inside an Open Ephys session folder.
%
%   info = find_oe_stream(rec_folder)
%   info = find_oe_stream(rec_folder, which)
%
%   rec_folder : session folder, e.g. .../DS_seizure/2024-02-27_11-53-07_1779
%   which      : optional; when the folder holds several raw streams, use
%                the which-th (folder order: Record Node, experiment,
%                recording1, recording2, ...; cfg.stream_choice). NaN or
%                omitted = there must be exactly one.
%
%   Looks in every "Record Node *" / experiment* / recording* folder for a
%   structure.oebin, and keeps the continuous streams that come from the
%   acquisition board AND contain headstage channels (named CH1, CH2, ...).
%   Newer Open Ephys versions also save a 1-channel 'memory_usage' stream
%   from the board; it has no CH channels and is ignored.
%
%   A stream counts as raw if every processor between the source and the
%   Record Node only passes data through unchanged (Merger, Splitter). A
%   Record Node placed after a Bandpass Filter etc. is skipped, because
%   those processors change the saved data.
%
%   Errors unless exactly one raw stream is found (e.g. two recordings in
%   one session would be ambiguous: which one do the spreadsheet times
%   refer to?), or 'which' picks one of them.
%
%   info fields: dat_file, record_node, n_chans, fs, bit_volts (1 x n_chans),
%                channel_names (cellstr), oebin

%% List the Record Node folders in this session
nodes = dir(fullfile(rec_folder, 'Record Node*'));
nodes = nodes([nodes.isdir]);
assert(~isempty(nodes), 'No "Record Node" folders in %s', rec_folder);

%% Check every stream in every Record Node
% Each Record Node can hold experiment*/recording* subfolders, each with a
% structure.oebin (a JSON file) describing what was saved there.
found = {};      % raw streams
skipped = {};    % descriptions of non-raw streams, for error messages
for n = 1:numel(nodes)
    node_dir = fullfile(rec_folder, nodes(n).name);
    oebins = dir(fullfile(node_dir, 'experiment*', 'recording*', 'structure.oebin'));
    for k = 1:numel(oebins)
        % Read the JSON description of this recording
        oebin = fullfile(oebins(k).folder, oebins(k).name);
        s = jsondecode(fileread(oebin));

        % "continuous" decodes to a struct array, or a cell array if the
        % streams have different fields
        cont = s.continuous;
        if ~iscell(cont), cont = num2cell(cont); end

        for c = 1:numel(cont)
            st = cont{c};
            % Acquisition board stream only (not e.g. a separate photometry device)
            if isempty(strfind(lower(st.folder_name), 'acquisition_board')), continue; end

            % Must contain headstage channels named CH<number> (skips the
            % board's 'memory_usage' stream and any other non-EEG stream)
            ch = st.channels;
            if ~iscell(ch), ch = num2cell(ch); end
            names = cellfun(@(x) x.channel_name, ch(:)', 'UniformOutput', false);
            if ~any(~cellfun(@isempty, regexp(names, '^CH\d+$', 'once'))), continue; end

            % The 'history' field lists the processors the signal went
            % through before being saved, e.g.
            %   raw:      'Acquisition Board -> Record Node'
            %   raw:      'OE FPGA Acquisition Board -> Merger -> Record Node'
            %   filtered: 'Acquisition Board -> ... Bandpass Filter -> ... -> Record Node'
            % Drop the first entry (the source) and the last (this Record
            % Node); whatever is left must be pass-through only.
            hist = ch{1}.history;
            steps = strtrim(strsplit(hist, '->'));
            middle = steps(2:end-1);
            is_raw = numel(steps) >= 2 && all(ismember(lower(middle), {'merger', 'splitter'}));
            desc = sprintf('%s (%s): %s', nodes(n).name, ...
                strrep(oebin, [rec_folder filesep], ''), hist);
            % Not raw: note it (for the error message) and move on
            if ~is_raw
                skipped{end+1} = desc; %#ok<AGROW>
                continue
            end

            % Raw stream found: record where its continuous.dat is and
            % how to read it (channel count, sampling rate, uV per bit,
            % channel names).
            % Folder name in the oebin ends with "/"; strip it
            stream_dir = regexprep(st.folder_name, '[/\\]+$', '');
            info = struct();
            info.dat_file      = fullfile(fileparts(oebin), 'continuous', stream_dir, 'continuous.dat');
            info.record_node   = nodes(n).name;
            info.n_chans       = st.num_channels;
            info.fs            = st.sample_rate;
            info.bit_volts     = cellfun(@(x) x.bit_volts, ch(:)');
            info.channel_names = names;
            info.oebin         = oebin;
            assert(numel(info.bit_volts) == info.n_chans, ...
                'num_channels (%d) does not match channel list (%d) in %s', ...
                info.n_chans, numel(info.bit_volts), oebin);
            found{end+1} = info; %#ok<AGROW>
        end
    end
end

%% Return the one raw stream (or the chosen one), or explain why not
if nargin >= 2 && ~isnan(which)
    assert(which >= 1 && which <= numel(found), 'Stream %d requested, but %s has %d raw stream(s)', ...
        which, rec_folder, numel(found));
    info = found{which};
    info.n_streams = numel(found);
elseif numel(found) == 1
    info = found{1};
elseif isempty(found)
    error('No raw acquisition-board stream in %s. Non-raw streams seen:\n  %s', ...
        rec_folder, strjoin(skipped, '\n  '));
else
    names = cellfun(@(x) x.dat_file, found, 'UniformOutput', false);
    error('%d raw streams in %s (multiple recordings?):\n  %s', ...
        numel(found), rec_folder, strjoin(names, '\n  '));
end
end
