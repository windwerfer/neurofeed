# Handoff — monitor graph draw-path perf

| Field | Value |
|---|---|
| Date | 2026-09-13 |
| Status | **Start PR 5.** Paste [handoff-monitor-perf-5.md](handoff-monitor-perf-5.md). |
| Branch | `refactor/monitor` (head `1ff3a9b` after PR4). Sequential local commits. Do not push, do not GitHub PR, do not new branch. |
| Product spec | [../monitor.md](../monitor.md) — **frozen**. This series does not add chrome. |
| Start here | [handoff-monitor-perf-5.md](handoff-monitor-perf-5.md) |

Do not reopen: pipeline-contract Key Decisions, Crown Start, Connect UX, v5
68-byte header. Do not add Spectrogram `FFT 1s ▾`, averaging, a Bands strip
on Spectrogram, or `SMOOTH` / `REAL TIME` Bands chrome.

Hidden graphs stay **unmounted** (`AppShell` `switch`, not `IndexedStack`).
EEG RAM stays 5 min. Caches stay warm across view switches.

---

## Why

Switching live graphs feels like a CPU hog because the **visible** view
rebuilds and runs DSP at EEG **packet** rate (~85/s Muse-4, ~2× on Crown-8),
not display rate. Off-screen graphs already dispose. Capture rings stay on
purpose.

Items **1–7** of the perf pass, plus **#8 only if a profile still shows it**
after PR7.

---

## How each thread works

1. Paste the handoff for **this** slice. Read it, then [../monitor.md](../monitor.md), then implement **only** that slice.
2. Verify: `flutter analyze lib/src` + the tests in the slice ([../test-matrix.md](../test-matrix.md); skill `muse-verify`). No `flutter run` unless the human asks.
3. Update [../monitor.md](../monitor.md) draw-path notes and [../test-matrix.md](../test-matrix.md) if you added a test file. **Do not** touch [../ui-map.md](../ui-map.md) unless on-screen copy/chrome actually changed (it should not).
4. **Commit** on `refactor/monitor` (message in the slice). Do not `git push`.
5. Write the **next** handoff to `handoff-monitor-perf-N.md`, refresh the index table below, print a **short** paste prompt (path to that file + parent SHA). The file is the brief; do not dump it into chat.

---

## Locked decisions (do not re-open)

1. **Coalesce at the cache, not per view.** `SweepBuffer.append` stays synchronous for RAM/display writes. `notifyListeners` is at most **once per vsync**. `freeze` / `resume` / `setDisplayWindow` / `clear` notify **immediately**.
2. **No second DSP clock in PR1.** Do not add a 15–20 Hz timer. Vsync is the cap. Sliding Welch/histogram (PR7) cuts work *per* tick later.
3. **`BandCache` coalesces too** (same mixin). Four 1 Hz electrode events in one burst → one notify.
4. **Inspect skip is Histogram/PSD only** for EEG DSP. Spectrogram already skips `_onBuffer` in Inspect. Viewport pan still recomputes the *moved* window once.
5. **`#7` is real only if `build()` does not recompute both panes.** Cache `_counts` / `_spectrum` / `_series` on State; each listener refreshes only its pane. ListenableBuilder (PR5) then stops rebuilding GraphShell.
6. **Spectrogram incremental STFT** lives in a testable helper, not only view fields. Full recompute on electrode set, window length, or Inspect range change. Follow: one new hop FFT, drop columns left of the visible start.
7. **Heatmap is a bitmap**, not per-cell `drawRect`. Rasterize inside `SpectrogramPane` so the recording dashboard shares it. `FilterQuality.none`.
8. **Raw EEG downsample is min/max per pixel** (preserve peaks). Auto-Y ≤ 4 Hz. `RawEegView.dispose` calls `setDisplayWindow(0)` so the wipe ring stops when that view is gone (`append` already has a RAM-only path for window 0).
9. **`#8` is a gate after PR7**, not a scheduled slice. Only if a profile still shows wipe-ring copies or tmp `encodeSessionEvent` on the hot path. Do **not** pause `SweepBuffer` / `BandCache` on view change.
10. **Appearance frozen.** Same traces, windows, chips, mag range, Follow lead. No new chrome.

---

## PR map

| PR | Thread | Items | Status | Commit |
|---|---|---|---|---|
| **1** | Coalesce cache notifies | #1 | **landed** | `8ecfc65` |
| **2** | Histogram/PSD tick policy | #2 + #7 | **landed** | `8cd0f6a` |
| **3** | Spectrogram column ring | #3 DSP | **landed** | `2833b0a` |
| **4** | Spectrogram bitmap | #3 paint | **landed** | `1ff3a9b` |
| **5** | Isolate the paint tree | #5 | **next** | — |
| **6** | Raw EEG painter | #6 | pending | — |
| **7** | Sliding Welch / histogram | #4 | pending | — |
| **8** | Capture extras | #8 | gated | — |

```
PR1 (coalesce)
  ├─ PR2 (hist/psd policy)
  │    └─ PR5 (paint isolation)  ← also wants PR1
  ├─ PR3 (stft ring) → PR4 (bitmap)
  └─ PR6 (raw eeg painter)
PR7 (sliding DSP) after 1+2
PR8 gated
```

Threads are **serial on one branch**, even where the graph allows parallelism.
Do not collapse 3+4. Do not start 7 before 1–2.

---

## PR1 — Coalesce `SweepBuffer` / `BandCache` notifies

**Commit:** `perf(monitor): coalesce EEG/band cache notifies to vsync`

Paste: [handoff-monitor-perf-1.md](handoff-monitor-perf-1.md)

### Do

- New mixin `lib/src/monitor/cache/frame_coalesced_notify.dart` on `ChangeNotifier`:
  - `notifyListenersCoalesced()`: if `_scheduled` return; else `_scheduled = true`, `SchedulerBinding.instance.scheduleFrameCallback` → clear flag + `notifyListeners()`, and `scheduleFrame()` / `ensureVisualUpdates()` so the callback actually runs.
  - If `!hasListeners`, do not schedule (RAM still updated by the caller).
  - If no binding (defensive), call `notifyListeners()` immediately.
- `SweepBuffer.append`: keep writes; replace `notifyListeners()` with `notifyListenersCoalesced()`.
- `BandCache.appendBands`: same.
- Immediate `notifyListeners()` on `setDisplayWindow`, `freeze`, `resume`, `clear`.
- Tests: `test/monitor/sweep_buffer_test.dart` (new). `TestWidgetsFlutterBinding.ensureInitialized()`. Many `append`s in one turn → **0** listener fires until `tester.pump()` / `binding.endOfFrame` → **exactly 1**. `freeze` after appends still notifies without waiting if you call freeze (immediate path). Existing `viewport_controller_test` / `histogram_pane_test` only read samples — must stay green without pumping.

### Do not

- Change view `addListener` / `setState` yet.
- Throttle DSP to 20 Hz.
- Skip display-ring writes here (that is PR6 via `setDisplayWindow(0)`).
- Import this mixin from outside `monitor/cache/`.

### Files

`sweep_buffer.dart`, `band_cache.dart`, new mixin, new test, `.ai/test-matrix.md` (add `sweep_buffer_test.dart` to the pure-Dart list), `.ai/monitor.md` one sentence: EEG notify is vsync-coalesced; RAM writes stay 256 Hz.

### Verify

`flutter analyze lib/src`

```bash
flutter test \
  test/monitor/sweep_buffer_test.dart \
  test/monitor/viewport_controller_test.dart \
  test/monitor/histogram_pane_test.dart \
  test/monitor/band_cache_test.dart \
  test/monitor/time_series_pane_test.dart
```

---

## PR2 — Histogram/PSD: Inspect skip + split recompute

**Commit:** `perf(monitor): skip Inspect DSP and split histogram/PSD ticks`

### Do

- `histogram_view.dart` / `psd_view.dart`:
  - Fields for last `_counts` / `_spectrum`+`_peak` / `_series` (and the elapsed range they cover).
  - `sweepBuffer` listener: if `_viewport.mode == inspect`, **return**. Else `meanEegWindow` + `histogramCounts` / `welch` + `setState`.
  - `bandCache` listener: `buildBandSeries` for the strip only + `setState`.
  - Epoch `_viewport` listener: recompute the **primary** pane (Inspect pan/window).
  - Strip `_strip` listener: recompute **series** only.
- Spectrogram: no change unless you notice Inspect still doing extra work (it already returns in `_onBuffer`).
- Tests: extend `test/monitor/histogram_pane_test.dart` **or** a small new tick-helper test. Prefer extracting `bool shouldRecomputeEeg({required ViewportMode mode})` only if it stays dumb — otherwise widget-free tests of a tiny `HistogramTick` object. Assert: after inspect, further `SweepBuffer.append` does not change cached counts; pan of epoch does.

### Do not

- ListenableBuilder / GraphShell surgery (PR5).
- Sliding Welch (PR7).
- Change Histogram/PSD **visual** Follow (still last T seconds; just not 85×/s).

### Files

`histogram_view.dart`, `psd_view.dart`, tests, `.ai/monitor.md` (Inspect does not re-Welch / re-bin).

### Verify

`flutter analyze lib/src`

```bash
flutter test \
  test/monitor/histogram_pane_test.dart \
  test/monitor/dsp_test.dart \
  test/monitor/bands_context_strip_test.dart \
  test/monitor/viewport_controller_test.dart
```

Plus whatever new test file you add.

---

## PR3 — Incremental Spectrogram STFT

**Commit:** `perf(monitor): incremental spectrogram STFT columns`

### Do

- New helper `lib/src/monitor/cache/stft_ring.dart` (prefer a file; `dsp.dart` is the FFT primitive):
  - Holds `List<StftColumn>`, last hop index, electrode set, start/end.
  - `columnsFor(buffer, electrodes, start, end, newest)`:
    - Inspect + same range + same electrodes → return cached.
    - Follow + same electrodes + start/end slid by hops → `fft` **one** new 256-pt window (`meanEegWindow` only for that slice), append, drop columns with `elapsed < start - hop`.
    - Else full `stftColumns` as today.
  - Hop stays `kStftHopSamples` (64). `n = 256`.
- `spectrogram_view.dart` `_stft` delegates to the ring. Keep `_onBuffer` hop throttle.
- Tests in `test/monitor/stft_ring_test.dart`: N hops of a sine → column count matches `stftColumns`; after one extra hop, **one** new column and the first dropped when the window slides; electrode-set change forces full rebuild (compare to a fresh ring).

### Do not

- Change `SpectrogramPane` painting (PR4).
- Add FFT-size chrome. Do not change hop or `kDefaultFftN`.
- Incremental-FFT the recording dashboard (it is not packet-driven). Dashboard still calls `stftColumns` once per inspect range.

### Verify

`flutter analyze lib/src`

```bash
flutter test test/monitor/dsp_test.dart test/monitor/stft_ring_test.dart
```

---

## PR4 — Spectrogram heatmap bitmap

**Commit:** `perf(monitor): paint spectrogram from a bitmap`

### Do

- `SpectrogramPane`: StatefulWidget. On `columns` / mag / size change, write `Uint8List` BGRA, height = bins up to 60 Hz, width = `columns.length` (min 1). Color via existing `colorFor`. Upload with `decodeImageFromPixels` (or `ImageDescriptor.raw`). Dispose previous `ui.Image`.
- Painter: `canvas.drawImageRect` into the chart, `FilterQuality.none`. Grid/labels/colorbar stay as now.
- Empty / disconnected: keep the current solid background, no image.
- Recording dashboard uses this pane — no extra view code unless mag/size callbacks need a hook.
- Tests: `shouldRepaint` when columns/mag change; a unit test that a known column rasterizes a non-zero pixel if that is cheap. No goldens.

### Do not

- Per-cell `drawRect` on the live path.
- Async races: ignore out-of-date completions (generation counter).
- Change mag ▾ behavior.

### Verify

`flutter analyze lib/src`

```bash
flutter test test/monitor/dsp_test.dart
```

Add a small `spectrogram_pane_test.dart` if the pane logic is testable without pumping images; otherwise document the gap in test-matrix.

---

## PR5 — Isolate the paint tree

**Commit:** `perf(monitor): isolate graph paints from shell rebuilds`

### Do

- `AppShell`: do **not** `watch` the whole `appStateProvider`. `select` `currentView`, `sidebarOpen`, `connectWindowOpen` (and whatever cinema still needs). Status bar already watches the rest.
- Five live graph views: `ref.watch(appStateProvider.select((s) => s.status.connected))` instead of the whole app state (pad quality must not rebuild PSD).
- Wrap each plot pane in `RepaintBoundary`: `SweepPane`, `TimeSeriesPane`, `HistogramPane`, `PsdPane`, `SpectrogramPane` (and the strip’s pane).
- Stop data-tick `setState` on the **State that builds GraphShell**. Pattern: `ListenableBuilder` (or equivalent) around **only** the plot. Toolbar / electrode chips rebuild on user input and on `monitorControllerProvider` (rare). Histogram/PSD: one builder on sweep-driven primary, one on band-driven strip (this is where #7 actually stops strip PCHIP on EEG ticks).
- Bands Follow ticker stays inside `TimeSeriesPane` (1 s lead). Do not lift it to the view.
- Keep `graph_shell_test.dart` green.

### Do not

- IndexedStack / keep-alive hidden graphs (hidden views must stay **unmounted**).
- Change cinema / Record controls beyond not rebuilding them at 60 Hz.

### Verify

`flutter analyze lib/src`

```bash
flutter test \
  test/monitor/graph_shell_test.dart \
  test/monitor/graph_cinema_test.dart \
  test/monitor/bands_context_strip_test.dart \
  test/app_ui_state_test.dart \
  test/monitor/time_series_pane_test.dart
```

Optional (human-asked only): Linux agent `POST /view` through `bands` → `rawEeg` → `histogram` → `psd` → `spectrogram`. Skill `muse-run-linux`.

---

## PR6 — Raw EEG painter

**Commit:** `perf(monitor): downsample Raw EEG traces and idle the wipe ring`

### Do

- `SweepPanePainter._drawTrace`: for Follow and Inspect, **min/max per pixel column** (two vertices per x, or a vertical tick). `n` samples must not become `n` `lineTo`s when `n > chart.width`.
- Cache `TextPainter`s for Y/X labels (same strings → no alloc every paint).
- `_syncAutoY`: at most every 250 ms (or 4 Hz), still using display/RAM samples as today.
- `RawEegView.dispose`: `sweepBuffer.setDisplayWindow(0)` after removing listeners. `initState` already sets the window and `resume()`. Document: only Raw EEG uses the wipe ring.
- Tests: painter/downsample helper — e.g. 2560 samples, width 100 → ≤ ~200 path points. Viewport freeze/resume tests still pass. New cases: `setDisplayWindow(0)` then `append` does not grow `display` / cursor wipe.

### Do not

- Change wipe **look** in Follow (still a vertical bar at `cursor % n`).
- Shared Y-scale semantics.
- File-backed Inspect path except it should use the same downsample.

### Verify

`flutter analyze lib/src`

```bash
flutter test test/monitor/viewport_controller_test.dart test/monitor/sweep_buffer_test.dart
```

Plus a new downsample / wipe-idle test.

---

## PR7 — Sliding Welch and histogram

**Commit:** `perf(monitor): sliding Welch and histogram on Follow`

### Do

- Testable helpers in `dsp.dart` (or `monitor/cache/sliding_spectrum.dart`):
  - **Sliding Welch:** ring of periodograms, hop `n/2` (128). On new samples ≥ hop, `fft` once, drop oldest in the T-second window, re-average. Match `welch()` on the same full buffer (tolerance on power bins).
  - **Sliding histogram:** 64 bins; add samples that enter, subtract those that leave. Match `histogramCounts` after a slide.
- Wire Follow-only in `psd_view` / `histogram_view`. Invalidate (full recompute) on: Inspect enter/pan, window length, electrode set, µV/Hz range, disconnect.
- Reuse a `Float64List` for `meanEegWindow` output if easy (optional, same PR).

### Do not

- Sliding STFT (PR3 already did spectrogram).
- Changing Welch hop or 256-pt n.
- Using sliding while Inspect (PR2 already skips; pan = full recompute).

### Verify

`flutter analyze lib/src`

```bash
flutter test test/monitor/dsp_test.dart test/monitor/histogram_pane_test.dart
```

Plus new sliding tests (sine → same alpha peak as `welch`; histogram totals match).

---

## PR8 — only if necessary

**Gate:** after PR7, if the human still sees CPU hog on **Bands** (cheap DSP) or on **Feedback** (no graph), or DevTools CPU is dominated by `encodeSessionEvent` / display-ring copies rather than painters:

| If hot | Do | Do not |
|---|---|---|
| Display ring while not on Raw EEG | Confirm PR6 `setDisplayWindow(0)` actually runs on every leave; fix leaks | New subscriber protocol |
| `SessionRecorder.writeEvent` / FFI encode | Profile; maybe coalesce raw flush (already 64 KiB). Last resort: skip encoding streams the user turned off (already `recordStreams`) | Stop tmp on graph switch; pause BandCache/SweepBuffer |
| Pad quality rebuilding something | PR5 `select` missed a watch — fix that | Smaller quality ring |

If the gate does not fire, set this file’s status to **series complete; PR8 skipped** and stop.

---

## Docs each PR may touch

| File | When |
|---|---|
| [../monitor.md](../monitor.md) | Draw-path notes (notify rate, Inspect DSP, STFT ring, bitmap, wipe idle). No new chrome names. |
| [../test-matrix.md](../test-matrix.md) | New `test/monitor/*.dart` files in the pure-Dart list. |
| [../active-task.md](../active-task.md) | Already points here. PR7/8: series complete. |
| This file | Index table: PR, commit, next. |
| `handoff-monitor-perf-N.md` | Paste-ready next thread. |
| [../ui-map.md](../ui-map.md) | **Only** if copy/chrome changed (should be never). |

---

## Out of scope (every thread)

- Crown Start, OSC-connect, pipeline-contract Key Decisions, v5 header/FRB, Android foreground service, Athena optics.
- Spectrogram `FFT 1s ▾`, averaging, Bands strip on Spectrogram, `SMOOTH` / `REAL TIME`.
- Keeping hidden graphs alive (`IndexedStack`).
- Growing EEG RAM past 5 min.
- `git push`, GitHub PR, new branch.

---

## Handoff file shape (every slice writes this for the next)

1. Table: date, branch `refactor/monitor`, status “start PR N”, parent commit SHA.
2. Frozen do-nots (short).
3. What PR N–1 landed (files, commit).
4. **PR N scope:** Do / Do not / files / tests / commit message (from this plan).
5. Resume pointers (symbols + paths).
6. “When done: commit, write `handoff-monitor-perf-(N+1).md`, print a short paste prompt.” Put a **Paste prompt** block at the top of that file.
