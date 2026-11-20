function [base_start, base_end] = baseline_period(opts, sz_on)
% BASELINE_PERIOD  Start and end (s from recording start) of the baseline.
% Used by window_amplitude.m.
%
%   [base_start, base_end] = baseline_period(opts, sz_on)
%
%   opts.base_mode:
%     'pre_heating' : the opts.base_dur_s before heating starts
%                     (opts.heat_start). If heating started earlier than
%                     that, from the start of the recording; at least
%                     opts.base_min_s is required.
%     'pre_onset'   : the opts.base_dur_s ending opts.base_gap_s before
%                     seizure onset; the full length is required.

switch opts.base_mode
    case 'pre_heating'
        assert(isfield(opts, 'heat_start') && ~isempty(opts.heat_start) && ~isnan(opts.heat_start), ...
            'base_mode ''pre_heating'' needs opts.heat_start (heating start time, s)');
        base_end   = opts.heat_start;
        base_start = max(0, base_end - opts.base_dur_s);
        assert(base_end - base_start >= opts.base_min_s, ...
            'Only %.0f s before heating starts; at least %.0f s of baseline required', ...
            base_end - base_start, opts.base_min_s);
    case 'pre_onset'
        base_end   = sz_on - opts.base_gap_s;
        base_start = base_end - opts.base_dur_s;
        assert(base_start >= 0, ...
            'Recording has only %.0f s before the baseline end; %.0f s of baseline requested', ...
            base_end, opts.base_dur_s);
    otherwise
        error('opts.base_mode must be ''pre_heating'' or ''pre_onset''');
end
% The baseline must end before the seizure (or pseudo-seizure) starts
if ~isempty(sz_on) && ~isnan(sz_on)
    assert(base_end <= sz_on, 'Baseline ends at %.0f s, after onset at %.0f s (check heating start)', base_end, sz_on);
end
end
