function setup_paths()
% SETUP_PATHS  Put the scripts folder and its subfolders on the MATLAB path.
%
%   setup_paths()
%
% Run once per MATLAB session from the scripts folder (every main script
% also calls it, so running a script by its full path works too):
%   processing/      data -> per-recording window values (run_postictal_batch, ...)
%   analysis/        per-animal depth and group statistics (analyze_primary)
%   plotting_admin/  figures, recording viewer, spike-detector check
%   utils/           statistics, plotting and file helpers
root = fileparts(mfilename('fullpath'));
addpath(root);
for sub = {'processing', 'analysis', 'plotting_admin', 'utils'}
    addpath(fullfile(root, sub{1}));
end
end
