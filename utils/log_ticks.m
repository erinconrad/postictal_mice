function t = log_ticks(lim)
% LOG_TICKS  Tick values for a log axis with limits lim: 1-2-5 steps, or
% finer steps when the range is narrow (MATLAB labels only powers of 10
% by default). Used by use_log_axis.m.
%
%   t = log_ticks([0.2 3])
c = [0.01 0.02 0.05 0.1 0.2 0.5 1 2 5 10 20 50 100];
if lim(2) / lim(1) < 6, c = [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1 1.2 1.5 2 2.5 3 4 5 6 8 10]; end
t = c(c >= lim(1) & c <= lim(2));
if numel(t) > 8                                       % too many: keep every second tick,
    i1 = find(t == 1);                                % counting from the tick at 1
    if isempty(i1), i1 = 1; end
    keep = mod((1:numel(t)) - i1, 2) == 0;
    t = t(keep);
end
end
