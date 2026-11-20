function [o, m] = measure_view(o, measure)
% MEASURE_VIEW  Put one measure in the fields used by the analysis
% functions, so the same code analyses RMS, delta/theta and spike rate.
%
%   [o, m] = measure_view(o, measure)
%
%   o       : window_amplitude.m output for one recording ([] gives m only)
%   measure : 'rms' | 'delta_theta' | 'spike_rate' | 'delta' | 'theta'
%
%   o.value       the measure per 10 s window (NaN = artifact):
%                   rms          log10 RMS (uV)
%                   delta_theta  log10(delta power / theta power)
%                   spike_rate   spikes per minute
%                   delta, theta log10 power in the band (uV^2; cfg.bands)
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
    otherwise
        error('Unknown measure ''%s'' (rms, delta_theta, spike_rate, delta or theta)', measure);
end
if isempty(o), return; end

switch measure
    case 'rms'
        o.value      = o.log_rms;
        o.base_value = o.base_mean;
    case 'delta_theta'
        assert(isfield(o, 'log_dt'), 'Batch results have no band power: re-run run_postictal_batch.m');
        o.value      = o.log_dt;
        o.base_value = o.base_dt;
    case 'spike_rate'
        assert(isfield(o, 'spike_rate'), 'Batch results have no spike rates: re-run run_postictal_batch.m');
        o.value      = o.spike_rate;
        o.base_value = o.base_spike_rate;
    case {'delta', 'theta'}
        b = find(strcmp(o.band_names, measure));
        assert(numel(b) == 1, 'Batch results have no %s band: re-run run_postictal_batch.m', measure);
        o.value      = o.log_bp(:, b);
        o.base_value = o.base_bp(b);
end
o.is_log = m.is_log;
end
