function [sig_uV, fs] = load_oe_channel(dat_file, chans, n_chans, bit_volts, fs)
% LOAD_OE_CHANNEL  Read channels from an Open Ephys binary continuous.dat file.
%
%   [sig_uV, fs] = load_oe_channel(dat_file, chans)
%   [sig_uV, fs] = load_oe_channel(dat_file, chans, n_chans, bit_volts, fs)
%
%   dat_file  : path to continuous.dat (int16, channels interleaved)
%   chans     : 1-based channel numbers to return (e.g. 8, or [3 4])
%   n_chans   : total channels in the file (default 24; take it from
%               structure.oebin, see find_oe_stream.m)
%   bit_volts : uV per bit, scalar or one value per entry of chans
%               (default 0.195 for headstage channels)
%   fs        : sampling rate in Hz (default 1000)
%
%   sig_uV    : samples x numel(chans), in uV
%
%   Only the requested channels are read (fread with a skip between
%   samples), so memory use does not grow with the number of channels.

%% Defaults for arguments not given
if nargin < 3 || isempty(n_chans),   n_chans   = 24;    end
if nargin < 4 || isempty(bit_volts), bit_volts = 0.195; end
if nargin < 5 || isempty(fs),        fs        = 1000;  end

%% Check inputs
assert(exist(dat_file, 'file') == 2, 'File not found: %s', dat_file);
assert(all(chans >= 1 & chans <= n_chans), 'Channel out of range (file has %d channels)', n_chans);
if isscalar(bit_volts), bit_volts = repmat(bit_volts, 1, numel(chans)); end
assert(numel(bit_volts) == numel(chans), 'bit_volts must be scalar or one per channel');

% Each sample of each channel is 2 bytes, so the file size must divide
% evenly into n_chans x 2 bytes. If not, n_chans is wrong.
d = dir(dat_file);
assert(mod(d.bytes, 2*n_chans) == 0, ...
    'File size (%d bytes) is not a multiple of %d channels x 2 bytes', d.bytes, n_chans);
n_samp = d.bytes / (2*n_chans);

%% Read each requested channel and convert to uV
sig_uV = zeros(n_samp, numel(chans));
fid = fopen(dat_file, 'r', 'ieee-le');
assert(fid > 0, 'Could not open %s', dat_file);
for k = 1:numel(chans)
    % Jump to the first sample of this channel, then read one int16 and
    % skip the other n_chans-1 channels (2 bytes each) before the next one
    fseek(fid, (chans(k) - 1) * 2, 'bof');
    x = fread(fid, n_samp, 'int16=>double', (n_chans - 1) * 2);
    assert(numel(x) == n_samp, 'Read %d samples, expected %d', numel(x), n_samp);
    sig_uV(:, k) = x * bit_volts(k);
end
fclose(fid);
end
