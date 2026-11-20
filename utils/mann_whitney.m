function [U, p] = mann_whitney(a, b)
% Mann-Whitney U test, two-sided; normal approximation with tie and
% continuity correction (fine for groups of ~10 or more). No toolbox.
% U = U statistic of the first group (number of (a, b) pairs with a > b,
% ties counting 1/2).
a = a(:); b = b(:);
n1 = numel(a); n2 = numel(b); n = n1 + n2;
if n1 == 0 || n2 == 0, U = NaN; p = NaN; return; end   % a group is empty: no test
r = avg_rank([a; b]);
U = sum(r(1:n1)) - n1 * (n1 + 1) / 2;
mu = n1 * n2 / 2;
sd = sqrt(n1 * n2 / 12 * ((n + 1) - tie_sum([a; b]) / (n * (n - 1))));
z = (abs(U - mu) - 0.5) / sd;
p = min(1, erfc(max(z, 0) / sqrt(2)));
end
