# Post-ictal EEG suppression and recovery

MATLAB code that, for each seizure in a cohort spreadsheet, tests whether ECoG
amplitude is suppressed after seizure offset and, if so, when it returns to the
pre-ictal baseline.

## Folder layout

```
<project>/
  scripts/                          this repository
  data/MattisLab_postictal_EEG/     WT/, DS_seizure/, DS_NOseizure/, postictal_EEG_combined.xlsx
  output/                           created by the scripts
```

Paths are worked out from the location of `scripts/` (`project_paths.m`), so the
same code runs on any machine with this layout. If a machine keeps data or output
elsewhere, copy `local_paths_example.m` to `local_paths.m` and edit it;
`local_paths.m` is not tracked by git.

## Setup on a new machine

```bash
mkdir -p <project>/data <project>/output
cd <project>
git clone <repo-url> scripts
# put (or symlink) MattisLab_postictal_EEG inside data/
```

## Running the cohort

Edit the settings block at the top of `run_postictal_batch.m` if needed
(`rows_to_run`, `ecog_multi`, analysis options), then:

```bash
cd <project>/scripts
matlab -batch "run_postictal_batch"                                  # R2019a or later
nohup matlab -batch "run_postictal_batch" > ../output/batch_log.txt 2>&1 &   # long runs, survives logout
```

Outputs in `output/postictal_batch/`:

- `postictal_results.csv`: one row per spreadsheet row (status, early amplitude
  ratio, recovery time, clean-data fractions, folder and Record Node used, message)
- `postictal_results.mat`: the same, plus every recording's full output and the settings
- `figures/<mouse>_<date>_s<session>.png`

`status` is one of `recovered`, `not recovered`, `no suppression`, `indeterminate`
(too much artifact in the first 60 s after offset), `skipped` (e.g. no seizure
times in the spreadsheet) or `error` (reason in `message`).

## Method (defaults; see the header of `postictal_recovery.m`)

1. ECoG cut into 10 s windows every 5 s; amplitude = log10 RMS. Windows with any
   sample above 1500 uV are marked as artifact.
2. Baseline: the 5 min ending 60 s before seizure onset.
3. Threshold: mean - 2 SD of the 30 s-smoothed baseline log RMS (per recording).
4. Suppression: mean log RMS of the first 60 s after offset is below threshold.
   Indeterminate if less than half of that 60 s is artifact-free.
5. Recovery: first artifact-free window after offset with smoothed amplitude at
   or above threshold, such that every artifact-free window over the next 60 s
   also is (artifact windows skipped; at least half of the 60 s artifact-free).

## Files

| File | Purpose |
|---|---|
| `run_postictal_batch.m` | Run every spreadsheet row; write results table and figures |
| `postictal_recovery.m` | Suppression test, recovery time, figure for one recording |
| `read_cohort_sheet.m`, `read_sheet_cells.m` | Read the cohort spreadsheet |
| `find_recording_folder.m` | Spreadsheet row -> session folder (cohort, date, mouse ID) |
| `find_oe_stream.m` | Pick the raw (unfiltered) Record Node; channel count, gains, sampling rate |
| `load_oe_channel.m` | Read selected channels from `continuous.dat` |
| `write_results_csv.m` | Results struct -> CSV |
| `project_paths.m`, `local_paths_example.m` | Folder locations |
