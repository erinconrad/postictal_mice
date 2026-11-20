function s = p_string(p)
% P_STRING  p-value as text: 3 decimals, or e.g. 2.1e-05 below 0.001
if p < 0.001, s = sprintf('%.1e', p); else, s = sprintf('%.3f', p); end
end
