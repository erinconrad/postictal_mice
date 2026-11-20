function r = avg_rank(v)
% Ranks 1..n, tied values get the mean of the ranks they span
[s, i] = sort(v(:));
r = zeros(numel(v), 1);
r(i) = 1:numel(v);
[u, ~, j] = unique(s);
for k = 1:numel(u)
    m = find(j == k);
    if numel(m) > 1, r(i(m)) = mean(m); end
end
end
