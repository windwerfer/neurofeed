# Handoff — start monitor graph perf PR 6

| Field | Value |
|---|---|
| Date | 2026-09-13 |
| Branch | `refactor/monitor` (do not push, do not create a branch) |
| Status | **Start PR 6.** Plan is already on disk. Do not re-plan. |
| Parent | `b431604` — isolate graph paints from shell rebuilds |
| Series law | [handoff-monitor-perf.md](handoff-monitor-perf.md) |
| Product spec | [../monitor.md](../monitor.md) |

**Paste prompt** (this is what the next thread gets; this file is the brief):

```
Continue monitor graph perf on `refactor/monitor`. Do not push, do not
create a branch, do not open a GitHub PR. Implement ONLY PR6. Plan is
on disk — do not re-plan. Read `.ai/archive/handoff-monitor-perf-6.md`
and follow it. Parent is `b431604`.
```

---

You are on branch `refactor/monitor`. Do not push. Do not create a branch.
Do not open a GitHub PR.

Implement **ONLY** monitor graph perf **PR6**: downsample Raw EEG traces
(min/max per pixel) and idle the wipe ring when Raw EEG is unmounted.
Cache Y/X `TextPainter`s. Auto-Y ≤ 4 Hz. `RawEegView.dispose` calls
`setDisplayWindow(0)`.

Read, in order:

1. This file
2. [handoff-monitor-perf.md](handoff-monitor-perf.md) — locked decisions + PR6 section
3. [../monitor.md](../monitor.md)
4. `lib/src/monitor/panes/sweep_pane.dart` (`SweepPanePainter._drawTrace`, `_drawYLabels`, `_drawXLabels`, `_sampleAt`)
5. `lib/src/monitor/views/raw_eeg_view.dart` (`_syncAutoY`, `dispose`, `initState` `setDisplayWindow`)
6. `lib/src/monitor/cache/sweep_buffer.dart` (`setDisplayWindow`, `append` window-0 RAM-only path)
7. `lib/src/monitor/views/recording_dashboard.dart` (uses `SweepPane` — same downsample)
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
- EEG RAM stays 5 min. Caches stay warm.
- Hop stays `kStftHopSamples` (64). `n = 256`. Heatmap stays a bitmap
  (`FilterQuality.none`).
- Bands Follow ticker stays inside `TimeSeriesPane`. Do not lift it.
- Sliding Welch / histogram is **PR7**. Paint-tree isolation is **PR5** (done).

---

## What PR5 landed

Commit `b431604` — `perf(monitor): isolate graph paints from shell rebuilds`

- `AppShell` `select`s `currentView`, `sidebarOpen`, `connectWindowOpen`.
  Pad quality / battery do not rebuild the shell. Hidden views stay a
  `switch` (unmounted).
- Five live views `select` `status.connected`. Data-tick `setState` no
  longer hits the State that builds GraphShell.
- Plot panes wrap `RepaintBoundary`: `SweepPane`, `TimeSeriesPane`,
  `HistogramPane`, `PsdPane`, `SpectrogramPane`; strip wraps its pane too.
- Bands / Raw EEG: `ListenableBuilder` on `bandCache` / `sweepBuffer`
  around the plot only. Viewport / Y-scale still `setState` chrome.
- Histogram/PSD: `_primaryTick` vs `_stripTick` so EEG ticks do not
  rebuild the Bands strip (PCHIP). Spectrogram hop throttle pings `_plotTick`.
- Tests: `test/monitor/plot_isolation_test.dart` (GraphShell isolated
  from plot ticks; each pane has a `RepaintBoundary`). No goldens.

---

## PR6 scope

**Commit:** `perf(monitor): downsample Raw EEG traces and idle the wipe ring`

### Do

- `SweepPanePainter._drawTrace`: for Follow and Inspect, **min/max per pixel
  column** (two vertices per x, or a vertical tick). `n` samples must not
  become `n` `lineTo`s when `n > chart.width`.
- Cache `TextPainter`s for Y/X labels (same strings → no alloc every paint).
- `_syncAutoY`: at most every 250 ms (or 4 Hz), still using display/RAM
  samples as today.
- `RawEegView.dispose`: `sweepBuffer.setDisplayWindow(0)` after the view
  is gone. `initState` already sets the window and `resume()`. Document:
  only Raw EEG uses the wipe ring. (`append` already has a RAM-only path
  when window is 0.)
- Tests: painter/downsample helper — e.g. 2560 samples, width 100 →
  ≤ ~200 path points. Viewport freeze/resume tests still pass. New cases:
  `setDisplayWindow(0)` then `append` does not grow `display` / cursor wipe.

### Do not

- Change wipe **look** in Follow (still a vertical bar at `cursor % n`).
- Shared Y-scale semantics.
- File-backed Inspect path except it should use the same downsample.
- IndexedStack / keep-alive hidden graphs.
- Sliding Welch (PR7). Spectrogram STFT / bitmap (PR3–4).
- Goldens.
- Touch [../ui-map.md](../ui-map.md).
- Edit `band_cache.dart` / the PR1 mixin / `stft_ring.dart`.
- Lift the Bands Follow ticker out of `TimeSeriesPane`.

### Files

| Path | Change |
|---|---|
| `lib/src/monitor/panes/sweep_pane.dart` | min/max per pixel; cache Y/X `TextPainter`s |
| `lib/src/monitor/views/raw_eeg_view.dart` | Auto-Y ≤ 4 Hz; `dispose` `setDisplayWindow(0)` |
| `lib/src/monitor/cache/sweep_buffer.dart` | only if window-0 / display-idle tests need a hook (append already RAM-only at 0) |
| `test/monitor/sweep_buffer_test.dart` | window 0 does not grow display |
| new downsample test (or extend sweep pane test) | 2560 samples, width 100 → ≤ ~200 path points |
| `.ai/monitor.md` | wipe ring idle off Raw EEG; downsample |
| `.ai/test-matrix.md` | add the new test file if any |
| `.ai/archive/handoff-monitor-perf.md` | index: PR6 SHA |

### Resume pointers

| What | Where |
|---|---|
| Per-sample `lineTo` | `sweep_pane.dart` `SweepPanePainter._drawTrace` |
| Sample source Follow/Inspect/file | `_sampleAt` |
| Wipe bar | `_drawWipe` (`cursor % n`) — look frozen |
| Y labels alloc | `_drawYLabels` new `TextPainter` per tick |
| X labels alloc | `_drawXLabels` new `TextPainter` per tick |
| Auto-Y every build | `raw_eeg_view.dart` `_syncAutoY` (now inside plot `ListenableBuilder`) |
| Display window on enter | `RawEegView.initState` `setDisplayWindow(windowSamples)` + `resume` |
| Display window on leave | `RawEegView.dispose` — **add** `setDisplayWindow(0)` |
| RAM-only append | `sweep_buffer.dart` `append` when `_displayWindow == 0` |
| Recording dashboard SweepPane | `recording_dashboard.dart` — shares painter downsample |
| Default window on controller | `monitor_controller.dart` `SweepBuffer()..setDisplayWindow(defaultWindowSamples)` |

---

## Verify

Skill `muse-verify`. No `flutter run` unless asked.

```bash
flutter analyze lib/src

flutter test \
  test/monitor/viewport_controller_test.dart \
  test/monitor/sweep_buffer_test.dart
```

Plus a new downsample / wipe-idle test.

Optional (human-asked only): Linux agent `POST /view` `rawEeg`, then leave
for `bands`. Skill `muse-run-linux`.

---

## When done

1. Commit on `refactor/monitor`:
   `perf(monitor): downsample Raw EEG traces and idle the wipe ring`
   Do not push.
2. Update [handoff-monitor-perf.md](handoff-monitor-perf.md) index: PR6
   status landed + commit SHA; status line “Start PR 7”.
3. Write **paste-ready** [handoff-monitor-perf-7.md](handoff-monitor-perf-7.md)
   for PR7 (sliding Welch and histogram on Follow; testable helpers;
   invalidate on Inspect/window/electrodes; not Spectrogram). Same shape
   as this file: table, frozen, what PR6 landed, PR7 Do/Do not/files/tests/
   commit, resume pointers, “when done”.
4. Print a **short** paste prompt at the end of the turn (branch, PR7
   only, path to that file, parent SHA). Do not dump the whole file.
