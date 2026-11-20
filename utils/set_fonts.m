function set_fonts(fig, font_size)
% SET_FONTS  All text in the figure font_size points; panel letters
% (panel_letter.m) 6 points larger.
set(findall(fig, '-property', 'FontSize'), 'FontSize', font_size);
set(findall(fig, 'Tag', 'panel_letter'), 'FontSize', font_size + 6);
end
