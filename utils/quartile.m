function y = quartile(v, p)
% QUARTILE  Quantile p (0-1) of v with MATLAB's prctile definition, no
% toolbox: sorted values at positions (i - 0.5) / n, linear interpolation,
% ends clamped. NaNs are ignored; NaN if v has no values.
%
%   q25 = quartile(v, 0.25); q75 = quartile(v, 0.75);
v = sort(v(~isnan(v(:)))); n = numel(v);
if n == 0, y = NaN; return; end
x = ((1:n)' - 0.5) / n;
if p <= x(1), y = v(1); elseif p >= x(end), y = v(end); else, y = interp1(x, v, p); end
end
