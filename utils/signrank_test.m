function [p, n] = signrank_test(d)
% SIGNRANK_TEST  Wilcoxon signed-rank test that paired differences d are
% centred on 0, two-sided. Zero differences are dropped; tied |d| get
% their average rank. Exact distribution for up to 25 non-zero
% differences, normal approximation (tie-corrected) above that. No toolbox.
%
%   [p, n] = signrank_test(d)     n = number of non-zero differences
d = d(:); d = d(~isnan(d));
if isempty(d), p = NaN; n = 0; return; end       % no pairs: no test
d = d(d ~= 0);
n = numel(d);
if n == 0, p = 1; return; end                     % every pair identical
r = avg_rank(abs(d));
W = sum(r(d > 0));                                % sum of ranks of positive differences
if n <= 25
    % Exact: every sign pattern equally likely under the null. Ranks are
    % whole or half numbers, so count sums in steps of 0.5 (r2 = 2 * rank).
    r2 = round(2 * r);
    tot = sum(r2);
    cnt = zeros(1, tot + 1); cnt(1) = 1;          % cnt(s+1) = number of patterns with sum s
    for k = 1:n
        cnt = cnt + [zeros(1, r2(k)) cnt(1:end - r2(k))];
    end
    pr = cnt / 2^n;
    w2 = round(2 * W);
    p = min(1, 2 * min(sum(pr(1:w2 + 1)), sum(pr(w2 + 1:end))));
else
    mu = n * (n + 1) / 4;
    [~, ~, j] = unique(abs(d)); t = accumarray(j, 1);
    sd = sqrt(n * (n + 1) * (2 * n + 1) / 24 - sum(t.^3 - t) / 48);
    z = (abs(W - mu) - 0.5) / sd;
    p = min(1, erfc(max(z, 0) / sqrt(2)));
end
end
