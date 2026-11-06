function info = find_oe_stream(rec_folder)
% FIND_OE_STREAM  Locate the raw (unfiltered) acquisition-board recording
% inside an Open Ephys session folder.
%
%   info = find_oe_stream(rec_folder)
%
%   rec_folder : session folder, e.g. .../DS_seizure/2024-02-27_11-53-07_1779
%
%   Looks in every "Record Node *" / experiment* / recording* folder for a
%   structure.oebin, and keeps the continuous streams that come from the
%   acquisition board. A stream counts as raw if its channel history goes
%   straight from the source to the Record Node (one "->"). A Record Node
%   placed after a Bandpass Filter etc. has a longer history and is
%   skipped, because those processors change the saved data.
%
%   Errors unless exactly one raw stream is found (e.g. two recordings in
%   one session would be ambiguous: which one do the spreadsheet times
%   refer to?).
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

            % Channel list for this stream. The 'history' field lists the
            % processors the signal went through before being saved, e.g.
            %   raw:      'Acquisition Board -> Record Node'          (one '->')
            %   filtered: 'Acquisition Board -> ... Bandpass Filter -> ... -> Record Node'
            ch = st.channels;
            if ~iscell(ch), ch = num2cell(ch); end
            hist = ch{1}.history;
            n_arrow = numel(strfind(hist, '->'));
            desc = sprintf('%s (%s): %s', nodes(n).name, ...
                strrep(oebin, [rec_folder filesep], ''), hist);
            % Not raw: note it (for the error message) and move on
            if n_arrow ~= 1
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
            info.channel_names = cellfun(@(x) x.channel_name, ch(:)', 'UniformOutput', false);
            info.oebin         = oebin;
            assert(numel(info.bit_volts) == info.n_chans, ...
                'num_channels (%d) does not match channel list (%d) in %s', ...
                info.n_chans, numel(info.bit_volts), oebin);
            found{end+1} = info; %#ok<AGROW>
        end
    end
end

%% Return the one raw stream, or explain why there isn't exactly one
if numel(found) == 1
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
