function [o, m] = measure_view(o, measure)
% MEASURE_VIEW  Put one measure in the fields used by the analysis
% functions, so the same code analyses RMS, delta/theta and spike rate.
%
%   [o, m] = measure_view(o, measure)
%
%   o       : window_amplitude.m output for one recording ([] gives m only)
%   measure : 'rms' | 'spike_rate' | a band ('delta', 'theta', 'alpha',
%             'beta', 'gamma') | a band ratio '<band>_<band>' (e.g.
%             'delta_alpha', the slowing measure, cfg.slowing; 'delta_theta')
%
%   o.value       the measure per 10 s window (NaN = artifact):
%                   rms          log10 RMS (uV)
%                   delta_alpha  log10(delta power / alpha power), and
%                                likewise any '<band>_<band>' ratio
%                   spike_rate   spikes per minute
%                   delta, theta, alpha, beta, gamma
%                                log10 absolute power in the band (uV^2;
%                                cfg.bands), so a ratio to the baseline
%                                power in that band
%   o.base_value  its baseline mean. The analysis functions
%                 (depth_window.m, smoothed_timecourse.m)
%                 use value - base_value: a log10 ratio to baseline for rms
%                 and delta_theta, a difference (spikes/min) for spike_rate.
%                 The original fields (log_rms, base_mean, log_dt, ...) are
%                 left as they are.
%   o.is_log    true if the value is log10 (results are reported as ratios,
%               10^x), false for spike rate (reported as differences)
%
%   m (struct, the same for every recording)
%     name, is_log
%     direction  'below' if abnormal = below the control range (RMS:
%                suppression; theta); 'above' if abnormal = above it
%                (delta/theta: slowing; spike rate; delta)
%     label      axis label
%     out_dir    output folder name (analyze_primary.m)
switch measure
    case 'rms'
        m = struct('name', 'rms', 'is_log', true, 'direction', 'below', ...
            'label', 'RMS / baseline', 'out_dir', 'primary_analysis');
    case 'delta_theta'
        m = struct('name', 'delta_theta', 'is_log', true, 'direction', 'above', ...
            'label', '\delta/\theta / baseline', 'out_dir', 'primary_analysis_delta_theta');
    case 'spike_rate'
        m = struct('name', 'spike_rate', 'is_log', false, 'direction', 'above', ...
            'label', 'Spikes/min - baseline', 'out_dir', 'primary_analysis_spike_rate');
    case 'delta'
        m = struct('name', 'delta', 'is_log', true, 'direction', 'above', ...
            'label', '\delta power / baseline', 'out_dir', 'primary_analysis_delta');
    case 'theta'
        m = struct('name', 'theta', 'is_log', true, 'direction', 'below', ...
            'label', '\theta power / baseline', 'out_dir', 'primary_analysis_theta');
    case {'alpha', 'beta', 'gamma'}                   % Figure S4 (time course only)
        m = struct('name', measure, 'is_log', true, 'direction', 'below', ...
            'label', ['\' measure ' power / baseline'], 'out_dir', ['primary_analysis_' measure]);
    otherwise
        % A band-power ratio, '<band>_<band>' (slowing: above = abnormal)
        parts = strsplit(measure, '_');
        bands = {'delta', 'theta', 'alpha', 'beta', 'gamma'};
        assert(numel(parts) == 2 && all(ismember(parts, bands)), ['Unknown measure ''%s'' (rms, spike_rate, ' ...
            'a band, or a ratio such as delta_alpha)'], measure);
        m = struct('name', measure, 'is_log', true, 'direction', 'above', ...
            'label', sprintf('\\%s/\\%s / baseline', parts{1}, parts{2}), 'out_dir', ['primary_analysis_' measure]);
end
if isempty(o), return; end

switch measure
    case 'rms'
        o.value      = o.log_rms;
        o.base_value = o.base_mean;
    case 'spike_rate'
        assert(isfield(o, 'spike_rate'), 'Batch results have no spike rates: re-run run_postictal_batch.m');
        o.value      = o.spike_rate;
        o.base_value = o.base_spike_rate;
    case {'delta', 'theta', 'alpha', 'beta', 'gamma'}
        b = find(strcmp(o.band_names, measure));
        assert(numel(b) == 1, 'Batch results have no %s band: re-run run_postictal_batch.m', measure);
        o.value      = o.log_bp(:, b);
        o.base_value = o.base_bp(b);
    otherwise
        % Ratio of two bands: difference of their log10 powers. base_bp is
        % the mean over the same artifact-free baseline windows, so the
        % difference of the two means is the mean of the per-window ratio.
        parts = strsplit(measure, '_');
        b1 = find(strcmp(o.band_names, parts{1})); b2 = find(strcmp(o.band_names, parts{2}));
        assert(numel(b1) == 1 && numel(b2) == 1, 'Batch results have no %s band: re-run run_postictal_batch.m', measure);
        o.value      = o.log_bp(:, b1) - o.log_bp(:, b2);
        o.base_value = o.base_bp(b1) - o.base_bp(b2);
end
o.is_log = m.is_log;
end
