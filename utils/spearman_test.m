function [rho, p, n] = spearman_test(x, y)
% SPEARMAN_TEST  Spearman rank correlation, two-sided p (t approximation), with
% tied values given their average rank. Pairs with a NaN are dropped. No
% toolbox.
%
%   [rho, p, n] = spearman_test(x, y)
ok = ~isnan(x(:)) & ~isnan(y(:));
x = x(ok); y = y(ok); n = numel(x);
rho = NaN; p = NaN;
if n < 4, return; end
rx = avg_rank(x); ry = avg_rank(y);
rho = sum((rx - mean(rx)) .* (ry - mean(ry))) / sqrt(sum((rx - mean(rx)).^2) * sum((ry - mean(ry)).^2));
df = n - 2;
t = rho * sqrt(df / max(1 - rho^2, eps));
p = betainc(df / (df + t^2), df / 2, 0.5);
end
