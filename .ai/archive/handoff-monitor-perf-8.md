# Handoff — start monitor graph perf PR 8 (gated)

| Field | Value |
|---|---|
| Date | 2026-09-13 |
| Branch | `refactor/monitor` (do not push, do not create a branch) |
| Status | **Start PR 8 (gated).** Plan is already on disk. Do not re-plan. |
| Parent | `305099c` — sliding Welch and histogram on Follow |
| Series law | [handoff-monitor-perf.md](handoff-monitor-perf.md) |
| Product spec | [../monitor.md](../monitor.md) |

**Paste prompt** (this is what the next thread gets; this file is the brief):

```
Continue monitor graph perf on `refactor/monitor`. Do not push, do not
create a branch, do not open a GitHub PR. Implement ONLY PR8 if the
gate fires. Plan is on disk — do not re-plan. Read
`.ai/archive/handoff-monitor-perf-8.md` and follow it. Parent is
`305099c`.
```

---

You are on branch `refactor/monitor`. Do not push. Do not create a branch.
Do not open a GitHub PR.

**PR8 is a gate, not a scheduled slice.** Implement it only if a profile
still shows wipe-ring copies or tmp `encodeSessionEvent` on the hot path
after PR7. If the gate does not fire, mark the series complete / PR8
skipped and stop. Do not pause `SweepBuffer` / `BandCache` on view change.

Read, in order:

1. This file
2. [handoff-monitor-perf.md](handoff-monitor-perf.md) — locked decisions + PR8 section
3. [../monitor.md](../monitor.md)
4. `lib/src/monitor/cache/sweep_buffer.dart` (`setDisplayWindow`, `append` window-0 path)
5. `lib/src/monitor/views/raw_eeg_view.dart` (`dispose` → `setDisplayWindow(0)`)
6. `lib/src/session_v5/scratch_writer.dart` / recorder encode path (`encodeSessionEvent`)
7. Live-graph `appStateProvider.select` watches (PR5)
8. [../test-matrix.md](../test-matrix.md)
9. Skill `muse-verify`

Do not reopen frozen monitor chrome. Do not mix Crown Start, OSC-connect,
pipeline-contract Key Decisions, or v5/FRB work. Do not add FFT-size chrome.
Do not edit GraphShell Record/Follow **look**. Do not keep hidden graphs alive.

---

## Frozen (short)

- Appearance unchanged. No new chrome. No `FFT 1s ▾`, averaging, Spectrogram
  Bands strip, `SMOOTH` / `REAL TIME`. Same Follow lead (Bands 1 s).
- Hidden graphs stay unmounted (`AppShell` `switch`, not `IndexedStack`).
- EEG RAM stays 5 min. Caches stay warm. Do **not** pause `SweepBuffer` /
  `BandCache` on view change.
- Hop stays `kStftHopSamples` (64) for Spectrogram. Welch hop stays `n/2`
  (128). `n = 256`. Heatmap stays a bitmap (`FilterQuality.none`).
- Bands Follow ticker stays inside `TimeSeriesPane`. Do not lift it.
- Sliding Welch / histogram is **done** (PR7). Sliding STFT is **done**
  (PR3). Raw EEG downsample / wipe idle is **done** (PR6).

---

## What PR7 landed

Commit `305099c` — `perf(monitor): sliding Welch and histogram on Follow`

- `SlidingWelch` / `SlidingHistogram` in `cache/sliding_spectrum.dart`.
  Follow PSD waits for ≥ hop (`n/2` = 128) new samples, `fft` once, drops
  the oldest periodogram, re-averages. Follow Histogram adds samples that
  enter and subtracts those that leave. Both match `welch` /
  `histogramCounts` on the same window.
- `HistogramTick` / `PsdTick` `onSweep` uses sliding; `recomputeEeg` is
  full (Inspect pan, window, electrodes, µV/Hz, disconnect).
- `meanEegWindow` reuses a `Float64List` when `out` length matches.
- Recording dashboard stays one-shot `welch` / `histogramCounts`.
- Tests: `test/monitor/sliding_spectrum_test.dart`; split-pane tick
  Follow slide case. No goldens.

---

## PR8 scope (gate)

**Commit (only if the gate fires):** whatever the hot path requires,
still under the series law. No chrome.

### Gate

After PR7, if the human still sees CPU hog on **Bands** (cheap DSP) or on
**Feedback** (no graph), or DevTools CPU is dominated by
`encodeSessionEvent` / display-ring copies rather than painters:

| If hot | Do | Do not |
|---|---|---|
| Display ring while not on Raw EEG | Confirm PR6 `setDisplayWindow(0)` actually runs on every leave; fix leaks | New subscriber protocol |
| `SessionRecorder.writeEvent` / FFI encode | Profile; maybe coalesce raw flush (already 64 KiB). Last resort: skip encoding streams the user turned off (already `recordStreams`) | Stop tmp on graph switch; pause BandCache/SweepBuffer |
| Pad quality rebuilding something | PR5 `select` missed a watch — fix that | Smaller quality ring |

If the gate does not fire, set [handoff-monitor-perf.md](handoff-monitor-perf.md)
status to **series complete; PR8 skipped** and stop.

### Do not

- Pause `SweepBuffer` / `BandCache` on view change.
- Sliding STFT / Welch / histogram (already done).
- Changing Welch hop or 256-pt `n`.
- IndexedStack / keep-alive hidden graphs.
- Goldens.
- Touch [../ui-map.md](../ui-map.md).
- Lift the Bands Follow ticker out of `TimeSeriesPane`.

### Files

Depends on which row of the gate table fires. Likely:

| Path | Change |
|---|---|
| `lib/src/monitor/views/raw_eeg_view.dart` | confirm `setDisplayWindow(0)` on leave |
| `lib/src/monitor/cache/sweep_buffer.dart` | wipe-ring leak only if PR6 missed a path |
| recorder / `encodeSessionEvent` | only if FFI encode dominates |
| live-graph `select` watches | only if pad quality still rebuilds chrome |
| `.ai/monitor.md` | one sentence if a capture-path change landed |
| `.ai/archive/handoff-monitor-perf.md` | series complete, PR8 SHA or skipped |

### Resume pointers

| What | Where |
|---|---|
| Wipe idle | `RawEegView.dispose` → `sweepBuffer.setDisplayWindow(0)` |
| RAM-only append | `SweepBuffer.append` when `displayWindow == 0` |
| Tmp encode | `SessionRecorder.writeEvent` / `encodeSessionEvent` |
| Pad-quality watches | `AppShell` / live views `appStateProvider.select` |
| Sliding DSP (leave) | `cache/sliding_spectrum.dart` |
| STFT ring (leave) | `stft_ring.dart` |

---

## Verify

Skill `muse-verify`. No `flutter run` unless asked (a profile **is**
asked if you are deciding the gate).

```bash
flutter analyze lib/src
```

Plus the tests for whatever you touch. If the gate does not fire, no
code tests beyond the docs edit.

---

## When done

1. If the gate fired: commit on `refactor/monitor` describing the fix.
   Do not push. If it did not: no code commit required beyond docs
   (`series complete; PR8 skipped`).
2. Update [handoff-monitor-perf.md](handoff-monitor-perf.md) index: PR8
   landed + SHA **or** skipped. Status **series complete**.
3. Update [../active-task.md](../active-task.md) and [../README.md](../README.md)
   so this series is no longer “start PR 8”.
4. Do not write `handoff-monitor-perf-9.md`. Print that the series is
   complete (and whether PR8 ran).
