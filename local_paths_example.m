function p = local_paths(p)
% LOCAL_PATHS  Machine-specific folder overrides (example).
%
% Only needed if this machine does not use the default layout in
% project_paths.m. To use: copy this file to local_paths.m in the same
% folder and edit. local_paths.m is in .gitignore, so it is never pushed
% and a git pull never overwrites it.
%
% Change only the fields you need, e.g.:
%
%   p.data   = '/mnt/bigdisk/MattisLab_postictal_EEG';
%   p.output = '/home/me/postictal_output';
end
