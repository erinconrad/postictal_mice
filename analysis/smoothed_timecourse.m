function y = smoothed_timecourse(o, sz_on, sz_off, t_grid, k_sm)
% SMOOTHED_TIMECOURSE  One recording's measure relative to baseline (log10
% ratio for RMS and delta/theta, difference for spike rate), smoothed with
% a moving average and put on a time grid. Used for the line in Figure 1.
%
%   y = smoothed_timecourse(o, sz_on, sz_off, t_grid, k_sm)
%
%   o       : window_amplitude.m output, passed through measure_view.m
%             (t_win, value with NaN = artifact, base_value, opts.win_s)
%   sz_on, sz_off : seizure onset and offset (s from recording start)
%   t_grid  : times to return values at (s from recording start)
%   k_sm    : smoothing span in windows (30 s / 5 s step = 6)
%   y       : smoothed value - base_value at t_grid (linear interpolation
%             between window centres; NaN at artifact windows and outside
%             the recording)
%
% The moving average (centred, artifact windows ignored; nanmovmean.m) is
% taken separately before onset, during the seizure (not smoothed), and
% after offset, so seizure values don't leak into the values around it.
assert(isfield(o, 'value'), 'Pass the recording through measure_view.m first');
t_mid  = o.t_win(:);                              % window centres (s)
before = t_mid + o.opts.win_s / 2 <= sz_on;       % window ends before onset
after  = t_mid - o.opts.win_s / 2 >= sz_off;      % window starts after offset
during = ~before & ~after;
v = o.value(:) - o.base_value;                    % relative to baseline
v_smooth = nan(size(v));
v_smooth(before) = nanmovmean(v(before), k_sm);
v_smooth(after)  = nanmovmean(v(after),  k_sm);
v_smooth(during) = v(during);
v_smooth(isnan(v)) = NaN;                         % artifact windows stay empty
y = interp1(t_mid, v_smooth, t_grid, 'linear', NaN);
end
