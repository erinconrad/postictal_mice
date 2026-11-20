function j = jitter_offsets(n)
% JITTER_OFFSETS  Horizontal offsets for n dots in a dot plot, spread
% evenly within +/- 0.175 (fractional parts of multiples of 0.618: the
% same every run, unlike random jitter)
j = (mod((1:n)' * 0.618, 1) - 0.5) * 0.35;
end
