function s = p_stars(p)
% P_STARS  Significance label for a figure: '***' p < 0.001, '**' p < 0.01,
% '*' p < 0.05, 'n.s.' otherwise ('' if p is NaN). The exact p-values are
% in the stats tables.
if isnan(p),      s = '';
elseif p < 0.001, s = '***';
elseif p < 0.01,  s = '**';
elseif p < 0.05,  s = '*';
else,             s = 'n.s.';
end
end
