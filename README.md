# Post-ictal EEG suppression in Scn1a mice

MATLAB code for hyperthermia-induced seizures recorded with Open Ephys. It measures how the
ECoG after a seizure differs from the animal's own pre-heating baseline: in amplitude (RMS),
in slowing (delta/theta power) and in spike rate. DS mice with a seizure are compared with
controls (WT and DS mice without a seizure). No toolboxes are needed; MATLAB R2019a or later.

## Folder layout

```
<project>/
  scripts/                          this repository
  data/MattisLab_postictal_EEG/     WT/, DS_seizure/, DS_NOseizure/, postictal_EEG_combined.xlsx
  output/                           created by the scripts
```

Inside `scripts/`:

```
scripts/
  analysis_config.m   settings shared by every script
  setup_paths.m       puts the subfolders on the MATLAB path
  project_paths.m, local_paths_example.m
  processing/         spreadsheet + raw data -> per-recording window values (run_postictal_batch)
  analysis/           per-animal depth and group statistics (analyze_primary)
  plotting_admin/     figures, recording viewer, spike-detector check
  utils/              statistics, plotting and file helpers
```

Paths come from the location of `scripts/` (`project_paths.m`). If a machine keeps data or
output elsewhere, copy `local_paths_example.m` to `local_paths.m` and edit it; `local_paths.m`
is not tracked by git.

## Settings (`analysis_config.m`)

- **seizure times**: onset and offset from the spreadsheet (Joanna's markings). Seizures where a
  second reviewer (EC) disagreed about whether there was a seizure are left out
  (`cfg.excluded_seizures`, by mouse and date: mice 3154 and 3770, no seizure; 4566, unsure). The
  Nov 18 spreadsheet already leaves these out.
- **controls** are measured at pseudo-onset/offset times: the spreadsheet's temperature-matched
  times where there is a temperature record; otherwise heating start + the median heating-to-onset
  and heating-to-offset times of the seizure mice (`rescue_pseudo = true`, the main analysis).
  `false` leaves those controls out and writes everything to `output/without_rescued_controls/`.
- **primary cohort, one recording per mouse** (`prepare_rows.m`): a mouse that ever had a seizure contributes
  its first seizure (by recording date) and is a DS seizure mouse; its other heating sessions are left out.
  A mouse that never had a seizure contributes its first heating session, as a control. A mouse whose first
  seizure ended in SUDEP is left out. Mice are matched by ID alone (4616 and 4704 appear under two project
  names). The seizure 1 vs 2 comparison pairs the first seizure with the mouse's next one.
- **session_corrections**: session numbers corrected from the spreadsheet (mouse 2575, June 4: session 2).
- **baseline**: the 5 min before heating starts (at least 60 s if heating started earlier).
- **depth windows**: `depth_windows_s = [60 120 300]` (all computed); `depth_main_s = 300` is
  the one used in Figures 2 and 5 and the supplements.
- **primary_measures**: RMS, delta/theta and spike rate. DS seizure vs controls at 0-5 min for
  these three are the primary hypotheses; their Mann-Whitney p-values are Bonferroni-corrected
  (x 3). Every other test is secondary and uncorrected.
- **notch**: 60/120/180 Hz notch on every recording when it is loaded.
- **rms_band**: RMS on the ECoG band-passed to 1-30 Hz (`[]` = broadband).
- **bands**: delta 1-4, theta 6-10 Hz (slowing = delta/theta); alpha, beta, gamma also stored.
- **spikes**: spike detector settings (`detect_spikes.m`), tuned with `review_spikes`.
- **artifact_uV**: a 10 s window with any sample beyond 3000 uV is left out. A window whose signal is flat (all
  samples equal) stops the recording with an error instead, so it shows up as not analysed.

## How the measures are computed

Each recording is cut into 10 s windows every 5 s (`window_amplitude.m`): log10 RMS, log10 band
power, and spikes per minute in each window; windows with artifact are NaN. Each value is
expressed relative to the animal's baseline mean (`measure_view.m`): a ratio for RMS and band
power (0.5 = half of baseline), a difference for spike rate (spikes/min above baseline).

**Depth** over the first N s after offset (`depth_window.m`) is the mean of the 10 s windows that
lie entirely within [offset, offset + N], minus the baseline mean, on the log scale for ratios
(so a geometric-mean ratio). For 0-5 min this is 58 or 59 overlapping windows (those on the
recording's 5 s grid that start at or after offset and end by offset + 300 s). Blank if the recording ends first or fewer than half the
windows are artifact-free. Figure 3's 30 s bins use the same function.

## Workflow

```matlab
run_postictal_batch                 % 1. every recording -> output/postictal_batch
                                    %    (or refresh_selection: re-apply the cohort selection only, in seconds)
analyze_primary                     % 2. depth and group tests, one call per measure
analyze_primary('delta_theta')
analyze_primary('spike_rate')
analyze_primary('delta')
analyze_primary('theta')
make_figures                        % 3. every figure -> output/figures
spike_detector_performance('EC')    % (only if the spike marking or detector changed)
make_results_report                 % 4. output/results_report.html: Results text, figures, numbers
```

`run_postictal_batch` must be rerun whenever the spreadsheet, the seizure times, the exclusions or
the processing settings change. `analyze_primary` writes, per measure (`output/primary_analysis`
for RMS, `output/primary_analysis_<measure>` otherwise): `per_animal.csv` (depth at 1, 2 and 5
min; session-2 depth for DS seizure mice), `group_summary.csv`, `stats.csv` (DS seizure vs
controls and DS no seizure vs WT, Mann-Whitney and Welch with effect size and 95% CI;
`p_bonferroni` for the three primary hypotheses) and
`primary_analysis.mat`.

## Figures (`make_figures`)

| File | Content | Function |
|---|---|---|
| `figure1` | Example seizure: A raw ECoG (100 s before onset to 150 s after offset, spikes outside the seizure); B spectrogram relative to baseline with the delta and theta bands marked; C-E RMS, delta/theta and spike rate over the recording | `make_figures` |
| `figure2` | Depth 0-5 min, Control vs DS seizure; Bonferroni-corrected Mann-Whitney as asterisks | `make_depth_figure` |
| `figure3` | 30 s bins, 4 min before onset to 10 min after offset, median and IQR | `make_bin_figure` |
| `figureS1_spike_examples` | Raw ECoG, 60–75 s after offset, 10 random DS seizure mice, with every spike detection | `make_spike_examples_figure` |
| `figureS2_control_groups` | As Figure 2, WT vs DS no seizure, with effect sizes | `make_depth_figure` |
| `figureS3_delta_theta` | As Figure 2, delta and theta separately, with effect sizes | `make_depth_figure` |
| `figureS4_delta_theta_bins` | As Figure 3, delta and theta separately | `make_bin_figure` |
| `figureS5_clinical` | DS seizure mice, depth 0-5 min vs seizure duration and age (Spearman), sex (Mann-Whitney), seizure 1 vs 2 (paired, Wilcoxon signed-rank); 3 measures x 4 factors | `make_covariate_figure` |

Asterisks: * p < 0.05, ** p < 0.01, *** p < 0.001, n.s. otherwise; exact p-values are printed
and are in the CSV files. Time axes are in minutes. Each figure function can also be called on
its own with options (see the header of each file), e.g.
`make_depth_figure('window_s', 60, 'file_name', 'figure2_0-1min')`.

The example seizure in Figure 1 is chosen automatically (a DS seizure no longer than the median,
with at least 10 min recorded after offset, whose RMS depth is closest to the group median), or
set it with `make_figures('example_row', <spreadsheet row>)`.

## Other tools

| Script | What it does |
|---|---|
| `make_results_report` | One HTML page: a draft of the Results text (cohort, spike detector, depth, time course, clinical variables) with every number filled in from the outputs, then every figure and the tables behind it (`'embed_images', false` to link the PNGs instead) |
| `inspect_recording(row)` | Check one recording's measurements: a 10 s ECoG page that is exactly one analysis window (spike detections circled) with that window's batch values and the recording's depths, above the whole recording's spectrogram, RMS, delta/theta and spike rate (arrows: scroll / gain; o f h b: jump; click a lower panel to jump) |
| `view_recording(row)` | Scroll through one recording, 15 s at a time (arrows: scroll / gain; o/f: onset/offset; h: heating start) |
| `review_spikes('EC')` | Blind marking of spikes on random 15 s baseline and post-ictal pages |
| `spike_detector_performance('EC')` | Tunes `tmul`/`absthresh` on half the mice; sensitivity, PPV, F1 on the other half |

## Files

| Folder | File | Purpose |
|---|---|---|
| (top) | `analysis_config.m` | Shared settings |
| | `setup_paths.m`, `project_paths.m`, `local_paths_example.m` | Path setup and folder locations |
| processing | `run_postictal_batch.m` | Step 1: every spreadsheet row -> window values |
| | `prepare_rows.m` | Spreadsheet rows + group, exclusions, session corrections, control pseudo-times, and the one-recording-per-mouse selection (primary-cohort flag and reason) |
| | `refresh_selection.m` | Re-applies the selection to the saved batch results without reprocessing (stops if seizure times changed) |
| | `read_cohort_sheet.m`, `read_sheet_cells.m` | Read the cohort spreadsheet |
| | `window_amplitude.m` | One recording: windowed log RMS, band power, spike rate, artifact flags, baseline |
| | `detect_spikes.m` | Spike detector (from `clean_detector.m`) |
| | `load_row_ecog.m`, `find_recording_folder.m`, `find_oe_stream.m`, `load_oe_channel.m`, `notch_line.m`, `baseline_period.m` | Find and load the ECoG for a row |
| analysis | `analyze_primary.m` | Step 2 |
| | `measure_view.m` | Puts RMS, delta/theta, spike rate, delta or theta in the fields the other functions use |
| | `depth_window.m` | A measure relative to baseline over a stretch after offset (depth, bins) |
| | `smoothed_timecourse.m` | 30 s moving average for Figure 1 |
| | `spectrogram_vs_baseline.m` | Spectrogram in the batch windows, dB relative to baseline (Figure 1B, inspect_recording) |
| plotting_admin | `make_figures.m` and the `make_*_figure.m` functions | Step 3 |
| | `view_recording.m`, `review_spikes.m`, `spike_detector_performance.m` | Other tools |
| utils | `mann_whitney.m`, `spearman_test.m`, `signrank_test.m`, `tq95.m`, `avg_rank.m`, `tie_sum.m`, `nanmovmean.m` | Statistics |
| | `quartile.m` | Quantile without the Statistics Toolbox (median and IQR in figures and report) |
| | `group_center_ci.m`, `log_ticks.m`, `use_log_axis.m`, `p_stars.m`, `p_string.m`, `panel_letter.m`, `set_fonts.m`, `jitter_offsets.m`, `blue_white_red.m`, `artifact_spans.m` | Plotting helpers shared by the figure functions |
| | `butter_filtfilt.m`, `write_results_csv.m`, `read_results_csv.m` | Filter (spike detector and RMS band-pass); struct array <-> CSV |
