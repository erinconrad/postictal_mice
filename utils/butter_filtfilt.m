function y = butter_filtfilt(x, fs, fc, type)
% BUTTER_FILTFILT  4th-order Butterworth low- or high-pass filter applied
% forward and backward (zero phase), with no toolbox. Replaces eegfilt /
% filtfilt in the spike detector.
%
%   y = butter_filtfilt(x, fs, fc, type)
%
%   x    : signal (vector)
%   fs   : sampling rate (Hz)
%   fc   : cut-off frequency (Hz), -3 dB per pass
%   type : 'low' or 'high'
%
% The filter is two biquad sections (RBJ cookbook formulas, bilinear
% transform with pre-warping) with Q = 0.5412 and 1.3066, which together
% give a 4th-order Butterworth response. Running it forward and backward
% doubles the attenuation and removes the phase shift. The ends are padded
% with a mirror image of the signal (up to 1 s) to reduce edge transients.
assert(fc > 0 && fc < fs / 2, 'Cut-off must be between 0 and fs/2');
col = iscolumn(x);
x = x(:);
n = numel(x);

% Mirror-image padding (as filtfilt does): 2*x(1) - x(pad+1:-1:2) at the start
np = min(n - 1, round(fs));
if np > 0
    xp = [2 * x(1) - x(np + 1:-1:2); x; 2 * x(end) - x(end - 1:-1:end - np)];
else
    xp = x;
end

Q = [1 / (2 * cos(pi / 8)), 1 / (2 * cos(3 * pi / 8))];   % 4th-order Butterworth pole pairs
w0 = 2 * pi * fc / fs;
for q = Q
    alpha = sin(w0) / (2 * q);
    switch type
        case 'low'
            b = [(1 - cos(w0)) / 2, 1 - cos(w0), (1 - cos(w0)) / 2];
        case 'high'
            b = [(1 + cos(w0)) / 2, -(1 + cos(w0)), (1 + cos(w0)) / 2];
        otherwise
            error('type must be ''low'' or ''high''');
    end
    a = [1 + alpha, -2 * cos(w0), 1 - alpha];
    b = b / a(1); a = a / a(1);
    xp = filter(b, a, xp);                          % forward
    xp = flipud(filter(b, a, flipud(xp)));          % backward
end
y = xp(np + 1:np + n);
if ~col, y = y'; end
end
