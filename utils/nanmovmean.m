function y = nanmovmean(x, k)
% NANMOVMEAN  Centred moving mean over k points, ignoring NaN, shrinking
% at the edges (near an end, the mean is over the points available).
% For even k a box of k points can't be centred, so k+1 points are used
% with half weight on the two end points (same total width).
x = x(:); good = ~isnan(x); x0 = x; x0(~good) = 0;
ker = ones(k, 1);
if mod(k, 2) == 0, ker = [0.5; ones(k - 1, 1); 0.5]; end
s = conv(x0, ker, 'same'); c = conv(double(good), ker, 'same');
y = s ./ c; y(c == 0) = NaN;
end
