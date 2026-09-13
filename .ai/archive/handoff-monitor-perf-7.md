# Handoff — start monitor graph perf PR 7

| Field | Value |
|---|---|
| Date | 2026-09-13 |
| Branch | `refactor/monitor` (do not push, do not create a branch) |
| Status | **Start PR 7.** Plan is already on disk. Do not re-plan. |
| Parent | `09bac0c` — downsample Raw EEG traces and idle the wipe ring |
| Series law | [handoff-monitor-perf.md](handoff-monitor-perf.md) |
| Product spec | [../monitor.md](../monitor.md) |

**Paste prompt** (this is what the next thread gets; this file is the brief):

```
Continue monitor graph perf on `refactor/monitor`. Do not push, do not
create a branch, do not open a GitHub PR. Implement ONLY PR7. Plan is
on disk — do not re-plan. Read `.ai/archive/handoff-monitor-perf-7.md`
and follow it. Parent is `09bac0c`.
```

---

You are on branch `refactor/monitor`. Do not push. Do not create a branch.
Do not open a GitHub PR.

Implement **ONLY** monitor graph perf **PR7**: sliding Welch and histogram
on Follow. Testable helpers; invalidate on Inspect / window / electrodes
/ µV-Hz range / disconnect. Not Spectrogram.

Read, in order:

1. This file
2. [handoff-monitor-perf.md](handoff-monitor-perf.md) — locked decisions + PR7 section
3. [../monitor.md](../monitor.md)
4. `lib/src/monitor/dsp.dart` (`welch`, `histogramCounts`, hop `n >> 1`, `n = 256`)
5. `lib/src/monitor/split_pane_tick.dart` (`HistogramTick` / `PsdTick` `recomputeEeg`)
6. `lib/src/monitor/views/histogram_view.dart` (`_onSweep`, `_onEpoch`, `_uvMenu`, electrode toggle)
7. `lib/src/monitor/views/psd_view.dart` (same pattern; Hz range)
8. `lib/src/monitor/cache/sweep_mean.dart` (`meanEegWindow` — optional reuse of `Float64List`)
9. `lib/src/monitor/cache/stft_ring.dart` (incremental pattern; **do not** change STFT)
10. [../test-matrix.md](../test-matrix.md)
11. Skill `muse-verify`

Do not reopen frozen monitor chrome. Do not mix Crown Start, OSC-connect,
pipeline-contract Key Decisions, or v5/FRB work. Do not add FFT-size chrome.
Do not edit GraphShell Record/Follow **look**. Do not keep hidden graphs alive.

---

## Frozen (short)

- Appearance unchanged. No new chrome. No `FFT 1s ▾`, averaging, Spectrogram
  Bands strip, `SMOOTH` / `REAL TIME`. Same Follow lead (Bands 1 s).
- Hidden graphs stay unmounted (`AppShell` `switch`, not `IndexedStack`).
- EEG RAM stays 5 min. Caches stay warm.
- Hop stays `kStftHopSamples` (64) for Spectrogram. Welch hop stays `n/2`
  (128). `n = 256`. Heatmap stays a bitmap (`FilterQuality.none`).
- Bands Follow ticker stays inside `TimeSeriesPane`. Do not lift it.
- Sliding STFT is **done** (PR3). Paint-tree isolation is **PR5**. Raw EEG
  downsample / wipe idle is **PR6**.

---

## What PR6 landed

Commit `09bac0c` — `perf(monitor): downsample Raw EEG traces and idle the wipe ring`

- `emitSweepTrace`: Follow and Inspect min/max per pixel column (two
  vertices per x). 2560 samples at width 100 → 200 path points. File-backed
  Inspect uses the same helper via `_sampleAt`.
- `_AxisLabelCache` reuses Y/X `TextPainter`s for the same string.
- `_syncAutoY` at most every 250 ms (4 Hz).
- `RawEegView.dispose` calls `sweepBuffer.setDisplayWindow(0)`. `initState`
  still sets the window and `resume()`. Only Raw EEG uses the wipe ring;
  `append` is RAM-only when the window is 0.
- Wipe **look** unchanged (vertical bar at `cursor % n`).
- Tests: `test/monitor/sweep_pane_test.dart`; window-0 cases in
  `sweep_buffer_test.dart`. No goldens.

---

## PR7 scope

**Commit:** `perf(monitor): sliding Welch and histogram on Follow`

### Do

- Testable helpers in `dsp.dart` (or `monitor/cache/sliding_spectrum.dart`):
  - **Sliding Welch:** ring of periodograms, hop `n/2` (128). On new
    samples ≥ hop, `fft` once, drop oldest in the T-second window,
    re-average. Match `welch()` on the same full buffer (tolerance on
    power bins).
  - **Sliding histogram:** 64 bins; add samples that enter, subtract those
    that leave. Match `histogramCounts` after a slide.
- Wire Follow-only in `psd_view` / `histogram_view` (via `PsdTick` /
  `HistogramTick` if that stays the seam). Invalidate (full recompute) on:
  Inspect enter/pan, window length, electrode set, µV/Hz range, disconnect.
- Reuse a `Float64List` for `meanEegWindow` output if easy (optional,
  same PR).

### Do not

- Sliding STFT (PR3 already did spectrogram). Do not edit `stft_ring.dart`.
- Changing Welch hop or 256-pt `n`.
- Using sliding while Inspect (PR2 already skips EEG DSP on Inspect
  sweep ticks; pan = full recompute).
- Change Histogram/PSD **visual** Follow (still last T seconds).
- IndexedStack / keep-alive hidden graphs.
- Goldens.
- Touch [../ui-map.md](../ui-map.md).
- Edit `band_cache.dart` / the PR1 mixin / Raw EEG downsample.
- Lift the Bands Follow ticker out of `TimeSeriesPane`.
- Incremental-FFT the recording dashboard (Inspect-only; keep one-shot
  `welch` / `histogramCounts`).

### Files

| Path | Change |
|---|---|
| `lib/src/monitor/dsp.dart` and/or `lib/src/monitor/cache/sliding_spectrum.dart` | sliding Welch + sliding histogram helpers |
| `lib/src/monitor/split_pane_tick.dart` | Follow uses sliding; Inspect/invalidate = full |
| `lib/src/monitor/views/histogram_view.dart` | wire invalidate on window / electrodes / µV / disconnect |
| `lib/src/monitor/views/psd_view.dart` | same for Hz range |
| `lib/src/monitor/cache/sweep_mean.dart` | optional `Float64List` reuse |
| `test/monitor/dsp_test.dart` and/or new sliding test | sine → same alpha peak as `welch`; histogram totals match |
| `test/monitor/histogram_pane_test.dart` | stay green |
| `.ai/monitor.md` | Follow sliding Welch / histogram |
| `.ai/test-matrix.md` | add the new test file if any |
| `.ai/archive/handoff-monitor-perf.md` | index: PR7 SHA |

### Resume pointers

| What | Where |
|---|---|
| Full Welch | `dsp.dart` `welch` — hop `n >> 1`, `n = 256` |
| Full histogram | `dsp.dart` `histogramCounts` — 64 bins, overflow dropped |
| Tick seam | `split_pane_tick.dart` `HistogramTick.recomputeEeg` / `PsdTick.recomputeEeg` |
| Inspect skip | `shouldRecomputeEegOnSweep` — already false in Inspect |
| Follow sweep tick | `histogram_view.dart` / `psd_view.dart` `_onSweep` |
| Inspect pan / window | `_onEpoch` → `_recomputeEeg` (full) |
| µV range | `histogram_view.dart` `_uvMenu` `onSelected` → `_recomputeEeg` |
| Hz range | `psd_view.dart` Hz menu → `_recomputeEeg` |
| Electrodes | `ElectrodeToggles` `onToggle` + `_syncMontage` in `build` |
| Disconnect | `ref.listen` connected → `_follow()`; series clear when `!connected` |
| Mean window alloc | `sweep_mean.dart` `meanEegWindow` new `Float64List` every call |
| STFT ring (leave) | `stft_ring.dart` |
| Dashboard one-shot | `recording_dashboard.dart` `welch` / `histogramCounts` |

---

## Verify

Skill `muse-verify`. No `flutter run` unless asked.

```bash
flutter analyze lib/src

flutter test \
  test/monitor/dsp_test.dart \
  test/monitor/histogram_pane_test.dart
```

Plus new sliding tests (sine → same alpha peak as `welch`; histogram
totals match after a slide).

Optional (human-asked only): Linux agent `POST /view` `histogram` then
`psd`. Skill `muse-run-linux`.

---

## When done

1. Commit on `refactor/monitor`:
   `perf(monitor): sliding Welch and histogram on Follow`
   Do not push.
2. Update [handoff-monitor-perf.md](handoff-monitor-perf.md) index: PR7
   status landed + commit SHA; status line “Start PR 8” (gated) **or**,
   if you already know the gate will not run this thread, still write
   the PR8 brief — the human decides whether to paste it.
3. Write **paste-ready** [handoff-monitor-perf-8.md](handoff-monitor-perf-8.md)
   for the **PR8 gate** (not a scheduled slice): only if a profile still
   shows wipe-ring copies or tmp `encodeSessionEvent` on the hot path.
   Do **not** pause `SweepBuffer` / `BandCache` on view change. Same
   shape as this file: table, frozen, what PR7 landed, PR8 Do/Do not
   (the gate table in the series law), files, “when done” → series
   complete / PR8 skipped if the gate does not fire.
4. Print a **short** paste prompt at the end of the turn (branch, PR8
   gate only, path to that file, parent SHA). Do not dump the whole file.
