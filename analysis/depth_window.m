function [d, why_missing] = depth_window(o, t_start, len_s)
% DEPTH_WINDOW  A measure relative to baseline, averaged over a stretch of
% the recording: RMS ratio for RMS (or, with measure_view.m, the
% delta/theta or band-power ratio, or the spike-rate difference).
%
%   d = depth_window(o, t_start, len_s)
%   [d, why_missing] = depth_window(...)
%
%   o       : window_amplitude.m output for the recording, passed through
%             measure_view.m (value, base_value, is_log)
%   t_start : start of the stretch (s from recording start), e.g. the
%             (pseudo-)offset for post-ictal depth
%   len_s   : length of the stretch (s): [t_start, t_start + len_s]
%   d       : the mean over the 10 s windows (every 5 s, so they overlap)
%             that lie entirely within the stretch, artifact windows left
%             out, minus the baseline mean:
%               ratio measures: 10^(mean log10 value - baseline mean log10
%                 value), i.e. geometric mean / baseline geometric mean
%                 (0.5 = half of baseline)
%               spike rate (o.is_log false): mean spikes/min - baseline
%             NaN if the recording ends before the stretch does, or if
%             fewer than o.opts.min_clean_frac of the windows are
%             artifact-free.
%   why_missing : '' if d has a value, else 'recording ended' or
%             'too much artifact'
%
% Example: the 0-5 min depth uses the windows (on the recording's 5 s grid)
% that start at or after offset and end by offset + 300 s: 59 windows if
% offset falls on the grid, otherwise 58. Every moment of the 5 minutes
% falls in two windows, except near the ends, which fall in one.
% make_bin_figure.m uses the same function for its 30 s bins (5 or 4
% windows each).
assert(isfield(o, 'value'), 'Pass the recording through measure_view.m first');
d = NaN;
win_start = o.t_win(:) - o.opts.win_s / 2;
win_end   = o.t_win(:) + o.opts.win_s / 2;
if t_start + len_s > win_end(end) + o.opts.step_s   % recording ends first
    why_missing = 'recording ended';
    return
end
in_stretch = win_start >= t_start & win_end <= t_start + len_s;
v = o.value(in_stretch);                          % NaN = artifact
if any(in_stretch) && mean(~isnan(v)) >= o.opts.min_clean_frac
    d = mean(v(~isnan(v))) - o.base_value;
    if o.is_log, d = 10^d; end
    why_missing = '';
else
    why_missing = 'too much artifact';
end
end
