function use_log_axis(ax, which, lim)
% USE_LOG_AXIS  Make the x or y axis logarithmic with labelled ticks
% (log_ticks.m) and set its limits.
%
%   use_log_axis(ax, 'Y', [0.2 3])
%   use_log_axis(ax, 'X', [0.5 2])
ticks  = log_ticks(lim);
labels = arrayfun(@(v) sprintf('%g', v), ticks, 'UniformOutput', false);
set(ax, [which 'Scale'], 'log', [which 'Tick'], ticks, [which 'TickLabel'], labels, [which 'Lim'], lim);
end
