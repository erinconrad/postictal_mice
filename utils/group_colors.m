function c = group_colors()
% GROUP_COLORS  The group colours used by every figure (Joanna's scheme):
% red for DS seizure mice, black / dark grey for controls.
%
%   c = group_colors();
%
%   c.seizure        line colour, DS seizure (RGB 232 52 36)
%   c.control        line colour, controls (black)
%   c.seizure_dots   filled dots, DS seizure (a lighter red)
%   c.control_dots   filled dots, controls (dark grey); DS no seizure
%                    mice are open circles edged in c.control
%   c.fill_alpha     opacity of the IQR / CI shading drawn in the line
%                    colour (0.35: light red and mid grey, as in her figure)
c.seizure      = [232 52 36] / 255;
c.control      = [0 0 0];
c.seizure_dots = c.seizure + (1 - c.seizure) * 0.35;
c.control_dots = [0.35 0.35 0.35];
c.fill_alpha   = 0.35;
end
