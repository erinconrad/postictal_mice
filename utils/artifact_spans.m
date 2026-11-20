function spans = artifact_spans(o)
% ARTIFACT_SPANS  [start end] (s from recording start) of each run of overlapping artifact
% windows (o.artifact, window_amplitude.m), one row per run
starts = o.t_start(o.artifact); ends = o.t_end(o.artifact);
spans = zeros(0, 2);
for k = 1:numel(starts)
    if ~isempty(spans) && starts(k) <= spans(end, 2)
        spans(end, 2) = max(spans(end, 2), ends(k));  % overlaps the previous run: extend it
    else
        spans(end + 1, :) = [starts(k) ends(k)];      %#ok<AGROW>
    end
end
end
