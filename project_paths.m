function p = project_paths()
% PROJECT_PATHS  Folder locations, worked out from where this file lives.
%
%   p = project_paths()
%
%   Expected layout:
%     <project>/scripts                         this code (the git repository)
%     <project>/data/MattisLab_postictal_EEG    WT, DS_seizure, DS_NOseizure,
%                                               postictal_EEG_combined.xlsx
%     <project>/output                          results
%
%   p fields: root, scripts, data, output
%
%   If the data or output live somewhere else on a particular machine,
%   copy local_paths_example.m to local_paths.m and edit it. local_paths.m
%   is ignored by git, so each machine keeps its own.

% scripts = the folder this file is in; root = the folder above it
p.scripts = fileparts(mfilename('fullpath'));
p.root    = fileparts(p.scripts);
% Default data and output folders, inside the project folder
p.data    = fullfile(p.root, 'data', 'MattisLab_postictal_EEG');
p.output  = fullfile(p.root, 'output');

% Machine-specific overrides, if present
if exist(fullfile(p.scripts, 'local_paths.m'), 'file') == 2
    p = local_paths(p);
end
end
