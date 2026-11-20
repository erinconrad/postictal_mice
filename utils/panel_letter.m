function panel_letter(ax, letter)
% PANEL_LETTER  Bold panel letter (A, B, ...) above the top-left corner of
% the axes. Tagged so set_fonts.m can make it larger than the other text.
text(ax, -0.12, 1.04, letter, 'Units', 'normalized', 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', 'Tag', 'panel_letter');
end
