# Handoff — start monitor graph perf PR 2

| Field | Value |
|---|---|
| Date | 2026-09-13 |
| Branch | `refactor/monitor` (do not push, do not create a branch) |
| Status | **Start PR 2.** Plan is already on disk. Do not re-plan. |
| Parent | `8ecfc65` — coalesce EEG/band cache notifies to vsync |
| Series law | [handoff-monitor-perf.md](handoff-monitor-perf.md) |
| Product spec | [../monitor.md](../monitor.md) |

Paste **this whole file** into the new thread.

---

You are on branch `refactor/monitor`. Do not push. Do not create a branch.
Do not open a GitHub PR.

Implement **ONLY** monitor graph perf **PR2**: Histogram/PSD Inspect skip
+ split recompute; cache pane outputs on State. Do **not** wrap panes in
`ListenableBuilder` yet (that is PR5).

Read, in order:

1. This file
2. [handoff-monitor-perf.md](handoff-monitor-perf.md) — locked decisions + PR2 section
3. [../monitor.md](../monitor.md)
4. `lib/src/monitor/views/histogram_view.dart`
5. `lib/src/monitor/views/psd_view.dart`
6. `lib/src/monitor/views/spectrogram_view.dart` (`_onBuffer` already skips Inspect)
7. `lib/src/monitor/dsp.dart` (`histogramCounts`, `welch`, `alphaPeakHz`)
8. `lib/src/monitor/panes/time_series_pane.dart` (`buildBandSeries`)
9. [../test-matrix.md](../test-matrix.md)
10. Skill `muse-verify`

Do not reopen frozen monitor chrome. Do not mix Crown Start, OSC-connect,
pipeline-contract Key Decisions, or v5/FRB work. Do not add a 20 Hz DSP
timer. Do not edit GraphShell / AppShell watchers.

---

## Frozen (short)

- Appearance unchanged. No new chrome. No `FFT 1s ▾`, averaging, Spectrogram
  Bands strip, `SMOOTH` / `REAL TIME`.
- Hidden graphs stay unmounted. EEG RAM stays 5 min. Caches stay warm.
- Histogram/PSD Follow is still last T seconds visually; just not 85×/s DSP.
- Inspect skip is **Histogram/PSD EEG DSP only**. Spectrogram already returns
  in `_onBuffer` while Inspect.
- Viewport pan still recomputes the **moved** window once.
- `#7` is real only if `build()` does **not** recompute both panes. Cache
  `_counts` / `_spectrum` / `_series` on State.
- `ListenableBuilder` / GraphShell surgery is **PR5**, not this PR.
- Sliding Welch / sliding histogram is **PR7**, not this PR.

---

## What PR1 landed

Commit `8ecfc65` — `perf(monitor): coalesce EEG/band cache notifies to vsync`

- Mixin `lib/src/monitor/cache/frame_coalesced_notify.dart` on
  `ChangeNotifier`. `notifyListenersCoalesced()` schedules at most one
  `SchedulerBinding` frame callback, then `notifyListeners()`. Skip
  schedule if `!hasListeners`. Immediate notify if no binding.
- `SweepBuffer.append` and `BandCache.appendBands` use it.
- `setDisplayWindow` / `freeze` / `resume` / `clear` stay immediate
  `notifyListeners()`.
- RAM/display writes stay synchronous. Wipe ring still written.
- Tests: `test/monitor/sweep_buffer_test.dart`.

Listeners on those caches already fire at vsync. PR2 still has to stop
`build()` from re-binning / re-Welch on every tick, and skip EEG DSP
while Inspect.

---

## PR2 scope

**Commit:** `perf(monitor): skip Inspect DSP and split histogram/PSD ticks`

### Do

- `histogram_view.dart` / `psd_view.dart`:
  - Fields for last `_counts` / `_spectrum`+`_peak` / `_series` (and the
    elapsed range they cover).
  - Split the shared `_onTick` (`setState` only) into per-source
    listeners:
    - `sweepBuffer`: if `_viewport.mode == inspect`, **return**. Else
      `meanEegWindow` + `histogramCounts` / `welch` + `setState`.
    - `bandCache`: `buildBandSeries` for the strip only + `setState`.
    - Epoch `_viewport`: recompute the **primary** pane (Inspect
      pan/window, Follow window-length).
    - Strip `_strip`: recompute **series** only.
  - `build()` must **read** those cached fields. Do not call
    `histogramCounts` / `welch` / `buildBandSeries` from `build()`.
  - Keep GraphShell, electrode chips, µV/Hz menus, hairlines, split
    layout, Follow/Inspect chrome as they are.
- Spectrogram: no change unless you notice Inspect still doing extra
  work (it already returns in `_onBuffer`).
- Recording dashboard Histogram/PSD are Inspect-only and not
  packet-driven — leave them.
- Tests: extend `test/monitor/histogram_pane_test.dart` **or** a small
  new tick-helper test. Prefer extracting
  `bool shouldRecomputeEeg({required ViewportMode mode})` only if it
  stays dumb — otherwise widget-free tests of a tiny `HistogramTick`
  object. Assert: after inspect, further `SweepBuffer.append` does not
  change cached counts; pan of epoch does. Add any new test file to
  [../test-matrix.md](../test-matrix.md).
- Docs: one sentence in [../monitor.md](../monitor.md) (Inspect does not
  re-Welch / re-bin).

### Do not

- `ListenableBuilder` / GraphShell surgery (PR5).
- Sliding Welch (PR7).
- Change Histogram/PSD **visual** Follow (still last T seconds).
- Skip display-ring writes (`setDisplayWindow(0)` is PR6).
- Touch [../ui-map.md](../ui-map.md).
- Edit `sweep_buffer.dart` / `band_cache.dart` / the PR1 mixin.

### Files

| Path | Change |
|---|---|
| `lib/src/monitor/views/histogram_view.dart` | cache `_counts` + `_series`; split listeners |
| `lib/src/monitor/views/psd_view.dart` | cache `_spectrum`/`_peak` + `_series`; split listeners |
| `test/monitor/histogram_pane_test.dart` and/or new tick-helper test | Inspect skip + epoch pan |
| `.ai/monitor.md` | Inspect does not re-Welch / re-bin |
| `.ai/test-matrix.md` | add a new test file if you create one |
| `.ai/archive/handoff-monitor-perf.md` | index: PR2 SHA |

### Resume pointers

| What | Where |
|---|---|
| Shared tick → `setState` only | `histogram_view.dart` / `psd_view.dart` `_onTick` |
| DSP in `build()` today | Histogram: `meanEegWindow` + `histogramCounts`; PSD: `welch` + `alphaPeakHz`; both: `buildBandSeries` |
| Spectrogram Inspect skip (do not copy unless needed) | `spectrogram_view.dart` `_onBuffer` |
| Viewport mode | `viewport_controller.dart` `ViewportMode.inspect` / `follow` |
| Epoch vs strip | `_viewport` (T-second EEG window) vs `_strip` (Bands context) |
| Strip series helper | `time_series_pane.dart` `buildBandSeries` |
| Mean EEG window | `cache/sweep_mean.dart` `meanEegWindow` |
| Sample-only tests | `test/monitor/histogram_pane_test.dart`, `dsp_test.dart` |

---

## Verify

Skill `muse-verify`. No `flutter run` unless asked.

```bash
flutter analyze lib/src

flutter test \
  test/monitor/histogram_pane_test.dart \
  test/monitor/dsp_test.dart \
  test/monitor/bands_context_strip_test.dart \
  test/monitor/viewport_controller_test.dart
```

Plus whatever new test file you add.

---

## When done

1. Commit on `refactor/monitor`:
   `perf(monitor): skip Inspect DSP and split histogram/PSD ticks`
   Do not push.
2. Update [handoff-monitor-perf.md](handoff-monitor-perf.md) index: PR2
   status landed + commit SHA; status line “Start PR 3”.
3. Write **paste-ready** [handoff-monitor-perf-3.md](handoff-monitor-perf-3.md)
   for PR3 (incremental Spectrogram STFT column ring in a testable helper;
   `spectrogram_view.dart` delegates; no bitmap paint yet). Same shape as
   this file: table, frozen, what PR2 landed, PR3 Do/Do not/files/tests/commit,
   resume pointers, “when done”.
4. Print that PR3 handoff in **one** fenced block at the end of the turn
   so it can be copied into the next thread.
