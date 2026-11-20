function y = notch_line(x, fs, f0, n_harm, bw_hz)
% NOTCH_LINE  Remove mains (line) noise and its harmonics.
% No toolbox needed.
%
%   y = notch_line(x, fs)                    % 60, 120, 180 Hz, 2 Hz wide
%   y = notch_line(x, fs, 50)                % 50 Hz mains
%   y = notch_line(x, fs, 60, 5, 1)          % 5 harmonics, 1 Hz wide
%
%   x      : signal (column vector, or one signal per column)
%   fs     : sampling rate (Hz)
%   f0     : mains frequency (default 60 Hz)
%   n_harm : number of frequencies to notch: f0, 2*f0, ... (default 3).
%            Harmonics at or above fs/2 are skipped.
%   bw_hz  : -3 dB width of each notch in Hz for one pass (default 2); after
%            the forward and backward passes the -3 dB width is about
%            1.5 x bw_hz (3 Hz at 60 Hz)
%
% Each notch is a second-order IIR notch (biquad; coefficients from the
% Audio EQ Cookbook, R. Bristow-Johnson). It is run forwards and then
% backwards, which gives zero phase shift: no time delay, and features of
% the EEG stay where they were. Running it twice also doubles its depth in dB.
% Frequencies more than a few Hz from each notch pass through unchanged.

if nargin < 3 || isempty(f0),     f0 = 60;    end
if nargin < 4 || isempty(n_harm), n_harm = 3; end
if nargin < 5 || isempty(bw_hz),  bw_hz = 2;  end

y = double(x);
was_row = isrow(y);
if was_row, y = y(:); end                 % one signal as a row: filter it as a column
for h = 1:n_harm
    fc = h * f0;                          % frequency to remove
    if fc >= fs / 2, break, end
    % Biquad notch: zeros on the unit circle at fc, poles just inside it.
    % Q = centre frequency / bandwidth.
    w0 = 2 * pi * fc / fs;
    Q = fc / bw_hz;
    alpha = sin(w0) / (2 * Q);
    b = [1, -2 * cos(w0), 1];
    a = [1 + alpha, -2 * cos(w0), 1 - alpha];
    b = b / a(1); a = a / a(1);
    % Forward, then backward (zero phase)
    y = filter(b, a, y);
    y = flipud(filter(b, a, flipud(y)));
end
if was_row, y = y.'; end
end
