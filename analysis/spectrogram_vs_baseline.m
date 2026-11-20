function [t_mid, freqs, power_db] = spectrogram_vs_baseline(sig, fs, o, freq_range)
% SPECTROGRAM_VS_BASELINE  Power spectrum in each of the batch's 10 s
% windows (window_amplitude.m: o.t_start, o.t_end; Welch average of 2 s Hann segments, 50% overlap, as
% the batch computes band power), in dB relative to the mean baseline
% power at each frequency (baseline windows o.is_base, artifact-free).
% Artifact windows (o.artifact) are NaN. t_mid = window centres (s from
% recording start), freqs = frequencies (Hz) within freq_range. Used by
% make_figures.m (Figure 1B) and inspect_recording.m.
%
%   [t_mid, freqs, power_db] = spectrogram_vs_baseline(sig, fs, o, [1 30])
seg_n = round(2 * fs);
hann_w = 0.5 - 0.5 * cos(2 * pi * (0:seg_n - 1)' / seg_n);   % periodic Hann, as window_amplitude.m
f_all = (0:floor(seg_n / 2))' * fs / seg_n;
keep = f_all >= freq_range(1) & f_all <= freq_range(2);
freqs = f_all(keep);
n_win = numel(o.t_start);
power = nan(numel(freqs), n_win);
for w = 1:n_win
    if o.artifact(w), continue; end
    i0 = round(o.t_start(w) * fs) + 1;
    i1 = min(numel(sig), round(o.t_end(w) * fs));
    x = sig(i0:i1);
    starts = 1:round(seg_n / 2):(numel(x) - seg_n + 1);
    p = zeros(numel(f_all), 1);
    for s = starts
        seg = x(s:s + seg_n - 1);
        spec = abs(fft((seg - mean(seg)) .* hann_w)).^2;
        p = p + spec(1:numel(f_all));
    end
    power(:, w) = p(keep) / numel(starts);
end
baseline = mean(power(:, o.is_base & ~o.artifact), 2);
power_db = 10 * log10(power ./ baseline);
t_mid = (o.t_start + o.t_end) / 2;
end
