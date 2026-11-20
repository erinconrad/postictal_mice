function [center, ci] = group_center_ci(x, is_log)
% GROUP_CENTER_CI  Group summary with a t-based 95% CI, on the plotted
% scale. Ratios (is_log true): mean and CI of log10(x), converted back
% with 10^ (geometric mean and its CI). Differences (spike rate): the
% ordinary mean and CI. NaNs are ignored.
x = x(~isnan(x));
if is_log, x = log10(x); end
n = numel(x);
center = mean(x);
half_width = tq95(n - 1) * std(x) / sqrt(n);
ci = center + [-half_width, half_width];
if is_log
    center = 10 ^ center;
    ci = 10 .^ ci;
end
end
