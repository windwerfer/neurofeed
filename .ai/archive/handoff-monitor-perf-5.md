# Handoff — start monitor graph perf PR 5

| Field | Value |
|---|---|
| Date | 2026-09-13 |
| Branch | `refactor/monitor` (do not push, do not create a branch) |
| Status | **Start PR 5.** Plan is already on disk. Do not re-plan. |
| Parent | `1ff3a9b` — paint spectrogram from a bitmap |
| Series law | [handoff-monitor-perf.md](handoff-monitor-perf.md) |
| Product spec | [../monitor.md](../monitor.md) |

**Paste prompt** (this is what the next thread gets; this file is the brief):

```
Continue monitor graph perf on `refactor/monitor`. Do not push, do not
create a branch, do not open a GitHub PR. Implement ONLY PR5. Plan is
on disk — do not re-plan. Read `.ai/archive/handoff-monitor-perf-5.md`
and follow it. Parent is `1ff3a9b`.
```

---

You are on branch `refactor/monitor`. Do not push. Do not create a branch.
Do not open a GitHub PR.

Implement **ONLY** monitor graph perf **PR5**: isolate graph paints from
shell rebuilds. `select` on AppShell and the five live views; wrap plot
panes in `RepaintBoundary`; `ListenableBuilder` around the plot only so
data ticks do not rebuild GraphShell. Hidden graphs stay **unmounted**.

Read, in order:

1. This file
2. [handoff-monitor-perf.md](handoff-monitor-perf.md) — locked decisions + PR5 section
3. [../monitor.md](../monitor.md)
4. `lib/src/app.dart` (`AppShell` `ref.watch(appStateProvider)`, `switch` on `currentView`)
5. Five live views: `lib/src/monitor/views/{bands,raw_eeg,histogram,psd,spectrogram}_view.dart`
6. Panes: `sweep_pane.dart`, `time_series_pane.dart`, `histogram_pane.dart`, `psd_pane.dart`, `spectrogram_pane.dart`, `bands_context_strip.dart`
7. `lib/src/monitor/graph_shell.dart` (chrome; do not restyle)
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
- Sliding Welch / histogram is **PR7**. Raw EEG downsample is **PR6**.

---

## What PR4 landed

Commit `1ff3a9b` — `perf(monitor): paint spectrogram from a bitmap`

- `SpectrogramPane` is a `StatefulWidget`. On columns / mag / connected
  change it writes BGRA (`rasterizeSpectrogramBgra`), height = bins with
  Hz in `[0, 60)`, width = column count. `decodeImageFromPixels`;
  generation counter drops stale uploads; previous `ui.Image` is disposed.
- Painter `canvas.drawImageRect` into the chart, `FilterQuality.none`.
  Grid / labels / colorbar unchanged. Empty / disconnected: solid
  background, no image.
- Recording dashboard already used `SpectrogramPane` — no extra view code.
- Tests: `test/monitor/spectrogram_pane_test.dart` (`shouldRepaint`,
  known-column BGRA pixels). No goldens.
- STFT / `StftRing` untouched.

Listeners still `setState` on the view State that builds GraphShell.
That is this PR.

---

## PR5 scope

**Commit:** `perf(monitor): isolate graph paints from shell rebuilds`

### Do

- `AppShell`: do **not** `watch` the whole `appStateProvider`. `select`
  `currentView`, `sidebarOpen`, `connectWindowOpen` (and whatever cinema
  still needs from app state — cinema itself is `GraphCinema.of`, not
  pad quality). Status bar already watches the rest.
- Five live graph views: `ref.watch(appStateProvider.select((s) =>
  s.status.connected))` instead of the whole app state (pad quality must
  not rebuild PSD / Spectrogram / …).
- Wrap each plot pane in `RepaintBoundary`: `SweepPane`, `TimeSeriesPane`,
  `HistogramPane`, `PsdPane`, `SpectrogramPane` (and the strip’s pane).
- Stop data-tick `setState` on the **State that builds GraphShell**.
  Pattern: `ListenableBuilder` (or equivalent) around **only** the plot.
  Toolbar / electrode chips rebuild on user input and on
  `monitorControllerProvider` (rare). Histogram/PSD: one builder on
  sweep-driven primary, one on band-driven strip (this is where #7
  actually stops strip PCHIP on EEG ticks).
- Bands Follow ticker stays inside `TimeSeriesPane` (1 s lead). Do not
  lift it to the view.
- Keep `graph_shell_test.dart` green.

### Do not

- IndexedStack / keep-alive hidden graphs (hidden views must stay
  **unmounted**).
- Change cinema / Record controls beyond not rebuilding them at 60 Hz.
- Change STFT / bitmap / hop / `kDefaultFftN`.
- Sliding Welch (PR7). Raw EEG min/max downsample (PR6).
- Goldens.
- Touch [../ui-map.md](../ui-map.md).
- Edit `sweep_buffer.dart` / `band_cache.dart` / the PR1 mixin /
  `stft_ring.dart`.

### Files

| Path | Change |
|---|---|
| `lib/src/app.dart` | `select` on AppShell |
| `lib/src/monitor/views/bands_view.dart` | `select` connected; ListenableBuilder around plot |
| `lib/src/monitor/views/raw_eeg_view.dart` | same |
| `lib/src/monitor/views/histogram_view.dart` | same; split builders primary vs strip |
| `lib/src/monitor/views/psd_view.dart` | same; split builders primary vs strip |
| `lib/src/monitor/views/spectrogram_view.dart` | same |
| `lib/src/monitor/panes/{sweep,time_series,histogram,psd,spectrogram}_pane.dart` | `RepaintBoundary` |
| `lib/src/monitor/panes/bands_context_strip.dart` | `RepaintBoundary` on the strip pane |
| `.ai/monitor.md` | paint tree isolated from shell |
| `.ai/test-matrix.md` | add a new test if any |
| `.ai/archive/handoff-monitor-perf.md` | index: PR5 SHA |

### Resume pointers

| What | Where |
|---|---|
| AppShell full watch | `app.dart` `_AppShellState.build` `ref.watch(appStateProvider)` |
| Hidden graphs unmounted | `app.dart` `switch (state.currentView)` |
| Connect overlay / sidebar | `_buildContent` / `_buildSidebar` use `AppUiState` |
| Cinema | `GraphCinema` inherited; AppShell `appViewIsGraph` + `GraphCinema.of` |
| Live views full app watch | `ref.watch(appStateProvider)` then `app.status.connected` |
| Data-tick setState → GraphShell | `_onTick` / `_onBuffer` / `_onSweep` / `_onBands` / `_onEpoch` / `_onStrip` |
| Histogram/PSD split ticks | `split_pane_tick.dart`; views still `setState` on the shell State |
| GraphShell Record chrome | `graph_shell.dart` watches `monitorControllerProvider` |
| Bands Follow ticker | `time_series_pane.dart` (keep) |
| Strip widget | `bands_context_strip.dart` `BandsContextStrip` / `HistogramPsdSplit` |
| Spectrogram bitmap (leave) | `spectrogram_pane.dart` |

---

## Verify

Skill `muse-verify`. No `flutter run` unless asked.

```bash
flutter analyze lib/src

flutter test \
  test/monitor/graph_shell_test.dart \
  test/monitor/graph_cinema_test.dart \
  test/monitor/bands_context_strip_test.dart \
  test/app_ui_state_test.dart \
  test/monitor/time_series_pane_test.dart
```

Optional (human-asked only): Linux agent `POST /view` through `bands` →
`rawEeg` → `histogram` → `psd` → `spectrogram`. Skill `muse-run-linux`.

---

## When done

1. Commit on `refactor/monitor`:
   `perf(monitor): isolate graph paints from shell rebuilds`
   Do not push.
2. Update [handoff-monitor-perf.md](handoff-monitor-perf.md) index: PR5
   status landed + commit SHA; status line “Start PR 6”.
3. Write **paste-ready** [handoff-monitor-perf-6.md](handoff-monitor-perf-6.md)
   for PR6 (Raw EEG min/max per pixel; cache Y/X `TextPainter`s; Auto-Y
   ≤ 4 Hz; `RawEegView.dispose` `setDisplayWindow(0)`). Same shape as
   this file: table, frozen, what PR5 landed, PR6 Do/Do not/files/tests/
   commit, resume pointers, “when done”.
4. Print a **short** paste prompt at the end of the turn (branch, PR6
   only, path to that file, parent SHA). Do not dump the whole file.
