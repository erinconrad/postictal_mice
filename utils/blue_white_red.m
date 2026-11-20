function cmap = blue_white_red(n, clim)
% BLUE_WHITE_RED  Diverging colour map for colour limits clim: blue below 0 dB, white at
% exactly 0 dB (baseline), red above, even when clim is not symmetric
% (e.g. [-20 10]: the blue half then has twice as many steps as the red)
n_blue = round(n * -clim(1) / (clim(2) - clim(1)));
n_red  = n - n_blue;
fade_blue = linspace(0, 1, n_blue)';                % blue -> white
fade_red  = linspace(1, 0, n_red)';                 % white -> red
cmap = [fade_blue fade_blue ones(n_blue, 1); ones(n_red, 1) fade_red fade_red];
end
