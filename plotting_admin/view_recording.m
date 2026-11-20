function view_recording(sheet_row, varargin)
% VIEW_RECORDING  Scroll through a recording, 15 s at a time.
%
%   view_recording(sheet_row)
%   view_recording(sheet_row, 'channels', 'all', 'win_s', 10, 'start_s', 500)
%   view_recording(sheet_row, 'notch', false)   % start with the notch off
%
%   sheet_row : Excel row number of the recording in the cohort
%               spreadsheet (row 1 = header), e.g. 7 for mouse 1779
%
%   Options (name, value):
%     'channels' : 'sheet' (default) = the ECoG and EMG channels listed in
%                  the spreadsheet; 'all' = every headstage channel
%                  (CH1, CH2, ...); or a vector of channel numbers, e.g. [7 8]
%     'win_s'    : window length in seconds (default 15)
%     'start_s'  : first window start, s from recording start (default:
%                  30 s before seizure onset)
%     'xlsx'     : spreadsheet (default: postictal_EEG_combined.xlsx in the
%                  data folder from project_paths.m)
%     'notch'    : true / false: start with the 60 Hz notch filter on or off
%                  (default: on if cfg.notch.on in analysis_config.m; the
%                  filter settings also come from cfg.notch)
%
%   Keys (click on the figure first so it has keyboard focus):
%     right / left arrow : next / previous window
%     up / down arrow    : increase / decrease gain
%     o / f              : jump to seizure onset / offset
%     h                  : jump to heating onset
%     t                  : go to a time (s) typed in a dialog
%     + / -              : longer / shorter window
%     l                  : 60 Hz notch filter on / off (60, 120, 180 Hz, as in
%                          the analysis; display only)
%
%   The seizure (onset to offset from the spreadsheet) is shaded red.
%   Heating onset (spreadsheet) is a dotted blue line labelled "heating on".
%   Each trace has its median over the window removed, so traces stay
%   centred on their own line whatever their DC offset.

%% 1. Options
opt = struct('channels', 'sheet', 'win_s', 15, 'start_s', [], 'xlsx', '', 'notch', []);
for k = 1:2:numel(varargin)
    opt.(lower(varargin{k})) = varargin{k+1};
end
addpath(fileparts(fileparts(mfilename('fullpath')))); setup_paths();   % scripts folder and its subfolders
p = project_paths();
cfg = analysis_config();
if isempty(opt.notch), opt.notch = cfg.notch.on; end
if isempty(opt.xlsx), opt.xlsx = fullfile(p.data, 'postictal_EEG_combined.xlsx'); end

%% 2. Find the recording for this spreadsheet row
rows = read_cohort_sheet(opt.xlsx);
x = rows([rows.sheet_row] == sheet_row);
assert(~isempty(x), 'No recording on spreadsheet row %d', sheet_row);
folder = find_recording_folder(p.data, x.cohort, x.rec_datenum, x.mouse_id);
info   = find_oe_stream(folder);

%% 3. Channels to show, and their labels
if ischar(opt.channels) && strcmp(opt.channels, 'sheet')
    ch = [x.ecog_ch(:)' x.emg_ch(:)'];
    labels = [arrayfun(@(c) sprintf('ECoG CH%d', c), x.ecog_ch(:)', 'UniformOutput', false), ...
              arrayfun(@(c) sprintf('EMG CH%d',  c), x.emg_ch(:)',  'UniformOutput', false)];
    [ch, first] = unique(ch, 'stable');
    labels = labels(first);
elseif ischar(opt.channels) && strcmp(opt.channels, 'all')
    ch = find(~cellfun(@isempty, regexp(info.channel_names, '^CH\d+$', 'once')));
    labels = info.channel_names(ch);
else
    ch = opt.channels(:)';
    labels = info.channel_names(ch);
end
assert(~isempty(ch), 'No channels to show');

%% 4. Load the channels (uV)
fprintf('Loading %d channel(s) from %s ...\n', numel(ch), folder);
sig = load_oe_channel(info.dat_file, ch, info.n_chans, info.bit_volts(ch), info.fs);
dur = size(sig, 1) / info.fs;
% Notch-filtered copy (each channel), so the l key can switch instantly
n = cfg.notch;
sig_notch = notch_line(sig, info.fs, n.f0, n.n_harm, n.bw_hz);

%% 5. Viewer state, stored in the figure
S = struct();
S.sig_raw   = sig;
S.sig_notch = sig_notch;
S.notch_on  = logical(opt.notch);
S.sig     = sig;
if S.notch_on, S.sig = sig_notch; end
S.fs      = info.fs;
S.dur     = dur;
S.labels  = labels;
S.win     = opt.win_s;
S.sz_on   = x.sz_on;
S.sz_off  = x.sz_off;
S.heat    = x.heat_start;                          % heating onset (s; NaN if not in the sheet)
S.name    = sprintf('%s | %s | mouse %d | %s s%d', x.project, x.cohort, x.mouse_id, ...
    datestr(x.rec_datenum, 'yyyy-mm-dd'), x.session);
% First window: 30 s before onset, or the start of the recording
if ~isempty(opt.start_s)
    S.t0 = opt.start_s;
elseif ~isnan(x.sz_on)
    S.t0 = x.sz_on - 30;
else
    S.t0 = 0;
end
% Initial spacing between traces: 8 x the typical signal SD, estimated
% robustly (median absolute deviation) from up to 60 s of the start
n_est = min(size(sig, 1), round(60 * info.fs));
mad_sd = 1.4826 * median(abs(bsxfun(@minus, sig(1:n_est, :), median(sig(1:n_est, :)))));
S.spacing = 8 * max(median(mad_sd), eps);

fig = figure('Color', 'w', 'Position', [80 80 1400 250 + 120 * numel(ch)], ...
    'Name', S.name, 'NumberTitle', 'off', 'KeyPressFcn', @on_key);
setappdata(fig, 'S', S);
redraw(fig);
end

%% ------------------------------------------------------------------------
function on_key(fig, evt)
% Keyboard handler: update the window start, gain or window length, then redraw
S = getappdata(fig, 'S');
switch evt.Key
    case 'rightarrow', S.t0 = S.t0 + S.win;
    case 'leftarrow',  S.t0 = S.t0 - S.win;
    case 'uparrow',    S.spacing = S.spacing / 1.5;   % more gain = traces taller
    case 'downarrow',  S.spacing = S.spacing * 1.5;
    case 'o', if ~isnan(S.sz_on),  S.t0 = S.sz_on  - S.win / 3; end
    case 'f', if ~isnan(S.sz_off), S.t0 = S.sz_off - S.win / 3; end
    case 'h', if ~isnan(S.heat),   S.t0 = S.heat   - S.win / 3; end
    case 't'
        a = inputdlg('Go to time (s from recording start):', 'Go to', 1, {sprintf('%.0f', S.t0)});
        if ~isempty(a) && ~isnan(str2double(a{1})), S.t0 = str2double(a{1}); end
    case {'equal', 'add', 'plus'},       S.win = S.win * 1.5;    % '+' key
    case {'hyphen', 'subtract', 'minus'}, S.win = max(1, S.win / 1.5);
    case 'l'                                         % notch on / off
        S.notch_on = ~S.notch_on;
        if S.notch_on, S.sig = S.sig_notch; else, S.sig = S.sig_raw; end
    otherwise, return
end
setappdata(fig, 'S', S);
redraw(fig);
end

function redraw(fig)
% Draw the current window: one trace per channel, stacked top to bottom
S = getappdata(fig, 'S');
S.t0 = min(max(S.t0, 0), max(0, S.dur - S.win));   % keep inside the recording
setappdata(fig, 'S', S);

i0 = floor(S.t0 * S.fs) + 1;
i1 = min(size(S.sig, 1), i0 + round(S.win * S.fs) - 1);
t  = ((i0:i1)' - 1) / S.fs;
nch = size(S.sig, 2);
offsets = (nch - 1:-1:0) * S.spacing;              % first channel on top

figure(fig); clf; ax = axes('Position', [0.10 0.10 0.86 0.80]); hold(ax, 'on');

% Seizure shading (only the part inside this window)
yl = [-S.spacing, offsets(1) + S.spacing];
if ~isnan(S.sz_on) && S.sz_off > t(1) && S.sz_on < t(end)
    a = max(S.sz_on, t(1)); b = min(S.sz_off, t(end));
    patch([a b b a], yl([1 1 2 2]), [1 0.85 0.85], 'EdgeColor', 'none');
end
% Onset / offset lines
if ~isnan(S.sz_on) && S.sz_on >= t(1) && S.sz_on <= t(end)
    plot([S.sz_on S.sz_on], yl, 'r--', 'LineWidth', 1);
end
if ~isnan(S.sz_off) && S.sz_off >= t(1) && S.sz_off <= t(end)
    plot([S.sz_off S.sz_off], yl, 'r--', 'LineWidth', 1);
end
% Heating onset: dotted blue line with a label at the top
if ~isnan(S.heat) && S.heat >= t(1) && S.heat <= t(end)
    plot([S.heat S.heat], yl, ':', 'Color', [0 0.3 0.8], 'LineWidth', 1.5);
    text(S.heat, yl(2), ' heating on', 'Color', [0 0.3 0.8], 'VerticalAlignment', 'top', 'Interpreter', 'none');
end

% Traces, each centred on its own line
for k = 1:nch
    y = S.sig(i0:i1, k);
    plot(t, y - median(y) + offsets(k), 'k', 'LineWidth', 0.5);
end

% Scale bar at the right edge: half a trace spacing (label gives its size in uV)
xs = t(end) - 0.02 * S.win;
plot([xs xs], [-0.9 -0.4] * S.spacing, 'b-', 'LineWidth', 3);
text(xs - 0.01 * S.win, -0.65 * S.spacing, sprintf('%.0f uV', S.spacing / 2), ...
    'HorizontalAlignment', 'right', 'Color', 'b', 'Interpreter', 'none');

set(ax, 'YTick', fliplr(offsets), 'YTickLabel', fliplr(S.labels), 'TickDir', 'out');
xlim([t(1) t(1) + S.win]); ylim(yl);
xlabel('Time from recording start (s)');
% Plain-text title (no TeX), so underscores in project names print as-is
if S.notch_on, ns = 'notch ON'; else, ns = 'notch off'; end
title({S.name, sprintf('%.1f - %.1f s   |   %.0f uV between traces   |   %s   |   left/right: scroll, up/down: gain, o/f: onset/offset, h: heating on, t: go to, +/-: window length, l: notch', ...
    t(1), t(1) + S.win, S.spacing, ns)}, 'Interpreter', 'none');
box off
set(findall(fig, '-property', 'FontSize'), 'FontSize', 12);
end
