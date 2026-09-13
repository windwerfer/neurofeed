# Handoff — start monitor graph perf PR 4

| Field | Value |
|---|---|
| Date | 2026-09-13 |
| Branch | `refactor/monitor` (do not push, do not create a branch) |
| Status | **Start PR 4.** Plan is already on disk. Do not re-plan. |
| Parent | `f87b83d` — incremental spectrogram STFT columns |
| Series law | [handoff-monitor-perf.md](handoff-monitor-perf.md) |
| Product spec | [../monitor.md](../monitor.md) |

**Paste prompt** (this is what the next thread gets; this file is the brief):

```
Continue monitor graph perf on `refactor/monitor`. Do not push, do not
create a branch, do not open a GitHub PR. Implement ONLY PR4. Plan is
on disk — do not re-plan. Read `.ai/archive/handoff-monitor-perf-4.md`
and follow it. Parent is `f87b83d`.
```

---

You are on branch `refactor/monitor`. Do not push. Do not create a branch.
Do not open a GitHub PR.

Implement **ONLY** monitor graph perf **PR4**: Spectrogram heatmap bitmap
inside `SpectrogramPane`; `FilterQuality.none`; recording dashboard shares
the pane. Do **not** change STFT / `StftRing` (that is PR3). No goldens.

Read, in order:

1. This file
2. [handoff-monitor-perf.md](handoff-monitor-perf.md) — locked decisions + PR4 section
3. [../monitor.md](../monitor.md)
4. `lib/src/monitor/panes/spectrogram_pane.dart` (`SpectrogramPane`, `_drawHeatmap`, `colorFor`)
5. `lib/src/monitor/views/spectrogram_view.dart` (passes `columns` / mag; do not re-STFT)
6. `lib/src/monitor/views/recording_dashboard.dart` (`RecordingDashGraph.spectrogram` already uses `SpectrogramPane`)
7. `lib/src/monitor/dsp.dart` (`StftColumn`)
8. [../test-matrix.md](../test-matrix.md)
9. Skill `muse-verify`

Do not reopen frozen monitor chrome. Do not mix Crown Start, OSC-connect,
pipeline-contract Key Decisions, or v5/FRB work. Do not add FFT-size chrome.
Do not change hop or `kDefaultFftN`. Do not edit GraphShell / AppShell.

---

## Frozen (short)

- Appearance unchanged. No new chrome. No `FFT 1s ▾`, averaging, Spectrogram
  Bands strip, `SMOOTH` / `REAL TIME`. Same `colorFor` stops. Same `mag ▾`.
- Hidden graphs stay unmounted. EEG RAM stays 5 min. Caches stay warm.
- Hop stays `kStftHopSamples` (64). `n = 256`.
- STFT lives in `StftRing` / `stftColumns`. Do not move DSP into the pane.
- Recording-dashboard Spectrogram still calls `stftColumns` once per inspect
  range; it already shares `SpectrogramPane` — rasterize there so both paths
  get the bitmap.
- `ListenableBuilder` / GraphShell surgery is **PR5**, not this PR.

---

## What PR3 landed

Commit `f87b83d` — `perf(monitor): incremental spectrogram STFT columns`

- Helper `lib/src/monitor/cache/stft_ring.dart`: `columnsFor(buffer,
  electrodes, start, end, newest)`.
  - Same electrodes + same range → cached list.
  - Follow + start/end slid by one hop → `fft` one 256-pt window
    (`meanEegWindow` only for that slice), append, drop columns with
    `elapsed` left of the new visible start, new list identity so
    `shouldRepaint` still fires.
  - Else full `stftColumns` as before (Inspect pan, electrode set,
    window length).
- `spectrogram_view.dart` `_stft` delegates to the ring. `_onBuffer` hop
  throttle kept. View-local column cache removed.
- Recording dashboard still calls `stftColumns` (not packet-driven).
- Heatmap is still per-cell `drawRect` until this PR.
- Tests: `test/monitor/stft_ring_test.dart`.

Painting is still per-cell `drawRect` in `SpectrogramPanePainter._drawHeatmap`.

---

## PR4 scope

**Commit:** `perf(monitor): paint spectrogram from a bitmap`

### Do

- `SpectrogramPane`: StatefulWidget. On `columns` / mag / size change, write
  `Uint8List` BGRA, height = bins up to 60 Hz, width = `columns.length`
  (min 1). Color via existing `colorFor`. Upload with `decodeImageFromPixels`
  (or `ImageDescriptor.raw`). Dispose previous `ui.Image`.
- Painter: `canvas.drawImageRect` into the chart, `FilterQuality.none`.
  Grid / labels / colorbar stay as now.
- Empty / disconnected: keep the current solid background, no image.
- Recording dashboard uses this pane — no extra view code unless mag/size
  callbacks need a hook.
- Tests: `shouldRepaint` when columns/mag change; a unit test that a known
  column rasterizes a non-zero pixel if that is cheap. No goldens.
- Docs: one sentence in [../monitor.md](../monitor.md) (heatmap is a bitmap,
  `FilterQuality.none`). Add a new test file to [../test-matrix.md](../test-matrix.md)
  if you create one.

### Do not

- Per-cell `drawRect` on the live path.
- Async races: ignore out-of-date completions (generation counter).
- Change `mag ▾` behavior.
- Change `StftRing` / hop / `kDefaultFftN`.
- Goldens.
- `ListenableBuilder` / GraphShell surgery (PR5).
- Touch [../ui-map.md](../ui-map.md).
- Edit `sweep_buffer.dart` / `band_cache.dart` / the PR1 mixin /
  `split_pane_tick.dart` / `stft_ring.dart`.

### Files

| Path | Change |
|---|---|
| `lib/src/monitor/panes/spectrogram_pane.dart` | StatefulWidget + bitmap + `drawImageRect` |
| `test/monitor/spectrogram_pane_test.dart` | **new** if testable without pumping images |
| `.ai/monitor.md` | heatmap bitmap |
| `.ai/test-matrix.md` | add the new test if any |
| `.ai/archive/handoff-monitor-perf.md` | index: PR4 SHA |

### Resume pointers

| What | Where |
|---|---|
| Per-cell heatmap today | `spectrogram_pane.dart` `_drawHeatmap` `drawRect` |
| Color map | `SpectrogramPanePainter.colorFor` / `_stops` |
| Chart rect / gutters | `chartRect`, `yGutter`, `colorbarGutter`, `maxHz = 60` |
| Mag range | `magMin` / `magMax` from the view |
| Column payload | `StftColumn.elapsed` + `db` (`dsp.dart`) |
| Live columns | `spectrogram_view.dart` via `StftRing` |
| Dashboard columns | `recording_dashboard.dart` `stftColumns` once per range |
| shouldRepaint today | columns / mag / newest / viewport identity |

---

## Verify

Skill `muse-verify`. No `flutter run` unless asked.

```bash
flutter analyze lib/src

flutter test test/monitor/dsp_test.dart test/monitor/stft_ring_test.dart
```

Add `test/monitor/spectrogram_pane_test.dart` if the pane logic is testable
without pumping images; otherwise document the gap in test-matrix.

---

## When done

1. Commit on `refactor/monitor`:
   `perf(monitor): paint spectrogram from a bitmap`
   Do not push.
2. Update [handoff-monitor-perf.md](handoff-monitor-perf.md) index: PR4
   status landed + commit SHA; status line “Start PR 5”.
3. Write **paste-ready** [handoff-monitor-perf-5.md](handoff-monitor-perf-5.md)
   for PR5 (isolate graph paints from shell rebuilds; `select` on AppShell
   and live views; `RepaintBoundary`; `ListenableBuilder` around the plot
   only; hidden graphs stay unmounted). Same shape as this file: table,
   frozen, what PR4 landed, PR5 Do/Do not/files/tests/commit, resume
   pointers, “when done”.
4. Print a **short** paste prompt at the end of the turn (branch, PR5
   only, path to that file, parent SHA). Do not dump the whole file.
