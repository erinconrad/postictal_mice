function cfg = analysis_config()
% ANALYSIS_CONFIG  Settings shared by every batch and analysis script, so
% they all use the same baseline, channel choice and primary cohort.
% Edit here, not in the individual scripts.
%
%   cfg = analysis_config()

p = project_paths();

%% Data
cfg.data_root = p.data;                       % holds WT, DS_seizure, DS_NOseizure
cfg.xlsx      = fullfile(cfg.data_root, 'postictal_EEG_combined.xlsx');
cfg.out_root  = p.output;                     % results (a subfolder if rescue_pseudo is off, below)
cfg.shared_root = p.output;                   % spike review: the same for every version

% Rows whose ECoG column lists two channels (e.g. '[3,4]'). Joanna: either
% channel is fine, so use the first.
%   'first' | 'bipolar' (first minus second) | 'skip'
cfg.ecog_multi = 'first';

%% Mains (60 Hz) noise
% Notch filter applied to every recording when it is loaded
% (load_row_ecog.m), before RMS and spectrograms. Some recordings pick up
% 60 Hz noise during heating (e.g. row 14, from ~243 s to ~455 s); without
% the filter it adds to the RMS only while it is present.
%   on     : true = filter, false = raw signal
%   f0     : mains frequency (Hz)
%   n_harm : notch f0, 2*f0, ... up to n_harm*f0
%   bw_hz  : width of each notch (Hz)
cfg.notch = struct('on', true, 'f0', 60, 'n_harm', 3, 'bw_hz', 2);

%% Artifact limit
% A 10 s window is artifact (left out) if any sample, after removing the
% window mean, exceeds this many uV. Seizure and post-ictal spikes can
% reach 1500-2000 uV, so 1500 dropped real signal; the amplifier saturates
% near 6400 uV. Used by run_postictal_batch and run_spectrogram_batch.
cfg.artifact_uV = 3000;

%% Depth windows after offset (analyze_primary.m, depth_window.m)
% Depth = the measure relative to baseline, averaged over the 10 s windows
% (every 5 s) that lie entirely within the first N s after offset.
% depth_windows_s: every window computed (stats.csv, results report);
% depth_main_s: the one used for Figures 2 and 5 and the supplements.
cfg.depth_windows_s = [60 120 300];
cfg.depth_main_s    = 300;

%% Primary outcomes (Bonferroni)
% The primary hypotheses: DS seizure vs controls, depth over 0 to
% depth_main_s, for each of these measures (Figure 2). Their Mann-Whitney
% p-values are Bonferroni-corrected for the number of measures listed
% (stats.csv column p_bonferroni; Figure 2's asterisks use it). Every other
% test is secondary and is reported uncorrected (p_bonferroni = NaN).
% Slowing = the delta/alpha power ratio (DAR), the standard human slowing
% index (JM/EC, Nov 24; previously delta/theta). Any '<band>_<band>' ratio
% works here, e.g. 'delta_theta'; every figure and text follows it.
cfg.slowing = 'delta_alpha';
cfg.primary_measures = {'rms', cfg.slowing, 'spike_rate'};

%% Frequency bands (band power per 10 s window, window_amplitude.m)
% Name, [low high) in Hz: the canonical (human) bands, non-overlapping
% (JM, Nov 24; previously theta 6-10 Hz). Slowing: cfg.slowing. Delta
% starts at 1 Hz, not 0.5: with 2 s segments the 0.5 Hz bin is a single
% cycle per segment and picks up slow drift. Gamma stops below the 60 Hz
% notch. delta and theta are required; all five are in Figure S4.
cfg.bands = {'delta', [1 4]; 'theta', [4 8]; 'alpha', [8 13]; 'beta', [13 30]; 'gamma', [30 55]};

% Band-pass for the RMS amplitude (Hz; window_amplitude.m). 1-30 Hz keeps
% the bands analysed and removes most movement and muscle activity, which
% contaminates the ECoG above ~30 Hz in the earlier recordings. The
% broadband RMS is kept in the results (log_rms_broadband) for comparison.
% [] = broadband.
cfg.rms_band = [1 30];

%% Spike detector (detect_spikes.m, adapted from clean_detector.m)
% Settings from clean_detector.m (human iEEG), except too_high_abs (1000 uV
% there; mouse post-ictal spikes are larger) and tmul / absthresh (19 / 100
% there), which were tuned against blind marking (review_spikes('EC'),
% spike_detector_performance('EC'), 2026-11-10): chosen on a random half of
% the mice; on the other half sensitivity 0.59, PPV 0.67.
%   tmul         height > tmul x median |7-30 Hz signal|, over the whole
%                recording and within +/- sur_time of the spike
%   absthresh    height > this (uV)
%   too_high_abs height < this (uV): larger = artifact
%   spkdur_ms    peak-to-peak duration range (ms)
%   lpf, hpf     band for the spike component (Hz)
cfg.spikes = struct('tmul', 12, 'absthresh', 150, 'too_high_abs', cfg.artifact_uV, ...
    'sur_time', 0.5, 'spkdur_ms', [15 200], 'lpf', 30, 'hpf', 7);

%% Baseline
% 'pre_heating': the base_dur_s before heating starts (default). If heating
%                started earlier than that, as much as there is, but at
%                least base_min_s.
% 'pre_onset'  : the base_dur_s ending base_gap_s before seizure onset
%                (the original definition).
cfg.base_mode  = 'pre_heating';
cfg.base_dur_s = 300;
cfg.base_min_s = 60;
cfg.base_gap_s = 60;      % 'pre_onset' only

%% Seizure times and excluded seizures
% Onset and offset come from the spreadsheet (Joanna's markings). The
% recordings below are left out because a second reviewer (EC, review of
% every recording, Nov 2026) disagreed about whether there was a seizure.
% Identified by mouse ID and recording date (yyyymmdd), so rows can move.
% A recording no longer in the spreadsheet is reported and skipped (the
% Nov 18 spreadsheet already leaves these three out).
cfg.excluded_seizures = {
    3154, 20241209, 'second reviewer: no seizure'
    3770, 20250211, 'second reviewer: no seizure'
    4566, 20251007, 'second reviewer: unsure'
    };

%% Session numbers corrected from the spreadsheet: mouse ID, recording date
% (yyyymmdd), heating session to use instead
cfg.session_corrections = {
    2575, 20240604, 2      % listed as session 1; a second heating 4 days after the first (JM, Nov 19)
    };

%% Which raw stream to use when a session folder holds more than one:
% mouse ID, recording date (yyyymmdd), stream number. Streams are numbered
% in folder order (Record Node, then experiment, then recording1,
% recording2, ...). Without an entry, a folder with two raw streams is an
% error (which one do the spreadsheet times refer to?).
% Projects left out entirely (spreadsheet "Project name"): their rows are
% dropped when the spreadsheet is read (prepare_rows.m), so they are not
% processed, not counted and not in any analysis.
cfg.excluded_projects = {
    'PPN GCaMP'            % technical problem with the recordings (JM, Nov 24)
    };

cfg.stream_choice = {
    2435, 20240417, 2      % two recordings in the folder; use the second (JM, Nov 20)
    };

%% Primary cohort: one recording per mouse (prepare_rows.m; other rows are
% still analysed, and flagged). A mouse that ever had a seizure contributes
% its first seizure (and is a DS seizure mouse); its other heating sessions
% are left out. A mouse that never had a seizure contributes its first
% heating session (and is a control). Mice are matched by ID alone.
cfg.exclude_sudep   = true;   % a first seizure that ended in SUDEP: leave the mouse out

% Controls without onset/offset times (no temperature data to match on).
% true : (the main analysis) give them pseudo-times from the seizure group
%        (prepare_rows.m):
%          onset  = heating start + median (onset - heating start)
%          offset = heating start + median (offset - heating start)
%        medians over the primary seizure mice. Rescued rows are flagged in
%        the results (pseudo_rescued = 1). Results go to <output>.
% false: leave them out (supplementary check). Results go to
%        <output>/without_rescued_controls, so the main results are kept:
%        re-run run_postictal_batch, analyze_primary (each measure) and
%        make_figures, then set this back to true.
cfg.rescue_pseudo = true;
if ~cfg.rescue_pseudo
    cfg.out_root = fullfile(p.output, 'without_rescued_controls');
end

%% Groups (cohort -> group label used in tables and figures)
cfg.groups = {'wt', 'WT'; 'DS_NOseizure', 'DS no seizure'; 'DS_seizure', 'DS seizure'};
end
