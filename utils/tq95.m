function t = tq95(df)
% TQ95  t value with 2.5% in each tail, for a 95% confidence interval with
% df degrees of freedom (via betainc; no toolbox).
t = fzero(@(x) betainc(df / (df + x^2), df / 2, 0.5) - 0.05, 2);
end
