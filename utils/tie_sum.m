function s = tie_sum(v)
% sum over groups of tied values of (t^3 - t)
[~, ~, j] = unique(v(:));
t = accumarray(j, 1);
s = sum(t.^3 - t);
end
