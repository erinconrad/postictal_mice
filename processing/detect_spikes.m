function sp = detect_spikes(x, fs, opts)
% DETECT_SPIKES  Spike detector for one ECoG channel. Adapted from
% clean_detector.m (C. Bermudez 2013; E. Conrad 2022; FC_toolbox) for
% single-channel mouse ECoG, with no toolbox.
%
%   sp = detect_spikes(x, fs, opts)
%
% Inputs
%   x    : ECoG (uV), one channel (notch-filtered on loading)
%   fs   : sampling rate (Hz)
%   opts : struct; any field left out takes its default (cfg.spikes in
%          analysis_config.m sets them for the batch):
%     tmul         19     height must exceed tmul x the median |filtered
%                         signal|, over the whole recording and within
%                         +/- sur_time of the spike
%     absthresh    100    and must exceed this (uV)
%     too_high_abs 3000   height and raw deflection must be below this
%                         (uV; larger = artifact)
%     sur_time     0.5    surround for the local threshold (s)
%     spkdur_ms    [15 200]  peak-to-peak duration range (ms)
%     lpf, hpf     30, 7  band for the spike component (Hz)
%     realign_s    0.15   spike time moved to the largest raw deflection
%                         within +/- this (s)
%     dedup_s      0.1    a spike within this of the previous one is a
%                         duplicate (s)
%     edge_s       0.05   spikes this close to either end are dropped (s)
%     scale        NaN    median |filtered signal| to use for the global
%                         threshold; NaN = compute from x. Set it when x is
%                         a segment of a longer recording (spike review),
%                         so the threshold matches the whole recording.
%
% Steps (as in clean_detector.m)
%   1. Remove the mean; low-pass at lpf, then high-pass at hpf (4th-order
%      Butterworth, zero phase: butter_filtfilt.m, instead of eegfilt).
%   2. For each polarity: find local peaks of the filtered signal (h, then
%      -h). Each pair of consecutive peaks at most spkdur_ms(2) apart, with
%      the trough between them, is a candidate; height = larger of the two
%      peak-to-trough drops; time = the trough.
%   3. Keep candidates with height > tmul x median|h| (whole recording),
%      > tmul x median|h| within +/- sur_time, > absthresh, < too_high_abs,
%      and duration > spkdur_ms(1).
%   4. Move each spike to the largest raw deflection (x minus the median of
%      x within +/- sur_time) within +/- realign_s.
%      Drop spikes whose raw deflection is too_high_abs or more (artifact).
%   5. Sort by time; drop duplicates (within dedup_s of the last spike
%      kept) and spikes within edge_s of either end.
%
% Changes from clean_detector.m (Erin's human iEEG detector)
%   - One channel: no multi-channel requirement (multi_channel_requirements2
%     needs at least 2 channels).
%   - too_high_abs: 3000 uV (was 1000 uV for human iEEG); post-ictal
%     spikes in these mice reach 1000-2000 uV. Also applied to the raw
%     deflection, as the artifact limit is (cfg.artifact_uV).
%   - Filters: Butterworth (no toolbox) instead of eegfilt's FIR filter.
%   - The duration check compares ms with ms (the original compared ms with
%     samples, which is the same only at 1000 Hz).
%   - Duplicates: compared with the last spike kept rather than the
%     previous candidate, so a train of spikes 60 ms apart keeps every
%     other spike rather than only the first.
%
% Output (struct)
%   t        spike times (s from recording start; sample k at (k-1)/fs)
%   idx      spike sample index
%   height   peak-to-trough height of the filtered spike (uV)
%   amp      raw deflection at the spike (uV, signed; minus surround median)
%   dur_ms   peak-to-peak duration (ms)
%   scale    median |filtered signal| used for the global threshold (uV)
%   opts     options used

%% Options
% these are default settings; the tmul and absthresh are overwritten by the
% opts file settings, reflecting the optimized parameters in my training
% loop
def = struct('tmul', 19, 'absthresh', 100, 'too_high_abs', 3000, 'sur_time', 0.5, ...
    'spkdur_ms', [15 200], 'lpf', 30, 'hpf', 7, 'realign_s', 0.15, 'dedup_s', 0.1, ...
    'edge_s', 0.05, 'scale', NaN);
if nargin < 3 || isempty(opts), opts = struct(); end
f = fieldnames(def);
for i = 1:numel(f)
    if ~isfield(opts, f{i}), opts.(f{i}) = def.(f{i}); end
end
x = double(x(:));
n = numel(x);
assert(~any(isnan(x)), 'detect_spikes: signal contains NaN');
empty = struct('t', zeros(0, 1), 'idx', zeros(0, 1), 'height', zeros(0, 1), 'amp', zeros(0, 1), ...
    'dur_ms', zeros(0, 1), 'scale', NaN, 'opts', opts);
if n < 3 * fs, sp = empty; return; end

%% 1. Spike component: 7-30 Hz
x = x - mean(x);
h = butter_filtfilt(butter_filtfilt(x, fs, opts.lpf, 'low'), fs, opts.hpf, 'high');
scale = opts.scale;
if isnan(scale), scale = median(abs(h)); end
thresh = opts.tmul * scale;                          % global threshold
max_dur = opts.spkdur_ms(2) * fs / 1000;             % samples

%% 2. Candidates, both polarities
cand = zeros(0, 3);                                  % [trough index, duration (samples), height]
for sgn = [1 -1]
    k = sgn * h;
    [pk, tr] = find_peaks_troughs(k);
    if numel(pk) < 2 || isempty(tr), continue; end
    i1 = find(diff(pk) <= max_dur);                  % consecutive peaks close enough
    p1 = pk(i1); p2 = pk(i1 + 1);
    % The trough between p1 and p2: peaks and troughs alternate, so it is
    % the first trough after p1
    j = interp1(tr, 1:numel(tr), p1, 'next');        % index of first trough > p1
    ok = ~isnan(j);
    p1 = p1(ok); p2 = p2(ok); v = tr(j(ok));
    ok = v < p2;
    p1 = p1(ok); p2 = p2(ok); v = v(ok);
    ht = max(k(p1) - k(v), k(p2) - k(v));
    keep = ht > thresh;
    cand = [cand; v(keep), p2(keep) - p1(keep), ht(keep)]; %#ok<AGROW>
end
if isempty(cand), sp = empty; sp.scale = scale; return; end

%% 3. Local threshold, absolute limits, duration
sur = round(opts.sur_time * fs);
keep = false(size(cand, 1), 1);
for i = 1:size(cand, 1)
    a = max(1, cand(i, 1) - sur); b = min(n, cand(i, 1) + sur);
    keep(i) = cand(i, 3) > opts.tmul * median(abs(h(a:b))) && ...
        cand(i, 3) > opts.absthresh && cand(i, 3) < opts.too_high_abs && ...
        cand(i, 2) * 1000 / fs > opts.spkdur_ms(1);
end
cand = cand(keep, :);
if isempty(cand), sp = empty; sp.scale = scale; return; end

%% 4. Realign to the largest raw deflection
re = round(opts.realign_s * fs);
amp = zeros(size(cand, 1), 1);
for i = 1:size(cand, 1)
    c = cand(i, 1);
    s_idx = max(1, c - sur):min(n, c + sur);
    w_idx = max(1, c - re):min(n, c + re);
    snap = x(w_idx) - median(x(s_idx));
    [~, m] = max(abs(snap));
    cand(i, 1) = w_idx(m);
    amp(i) = snap(m);
end
ok = abs(amp) < opts.too_high_abs;
cand = cand(ok, :); amp = amp(ok);
if isempty(cand), sp = empty; sp.scale = scale; return; end

%% 5. Sort, remove duplicates and spikes at the edges
[~, o] = sort(cand(:, 1));
cand = cand(o, :); amp = amp(o);
keep = true(size(cand, 1), 1);
last = -inf;
for i = 1:size(cand, 1)
    if cand(i, 1) - last < opts.dedup_s * fs
        keep(i) = false;
    else
        last = cand(i, 1);
    end
end
edge = round(opts.edge_s * fs);
keep = keep & cand(:, 1) > edge & cand(:, 1) <= n - edge;
cand = cand(keep, :); amp = amp(keep);

sp = empty;
sp.idx    = cand(:, 1);
sp.t      = (cand(:, 1) - 1) / fs;
sp.dur_ms = cand(:, 2) * 1000 / fs;
sp.height = cand(:, 3);
sp.amp    = amp;
sp.scale  = scale;
end

%% ------------------------------------------------------------------------
function [pk, tr] = find_peaks_troughs(s)
% Local maxima (pk) and minima (tr) of s, as FindPeaks.m (N. Hatoum 2005):
% flat stretches take the slope before them
ds = diff(s(:));
ds = [ds(1); ds];
z = find(ds(2:end) == 0) + 1;
for k = z'                                           % in order, so runs of zeros carry over
    ds(k) = ds(k - 1);
end
d2 = diff(sign(ds));
tr = find(d2 > 0);
pk = find(d2 < 0);
end
