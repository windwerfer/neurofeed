# Handoff — start monitor graph perf PR 3

| Field | Value |
|---|---|
| Date | 2026-09-13 |
| Branch | `refactor/monitor` (do not push, do not create a branch) |
| Status | **Start PR 3.** Plan is already on disk. Do not re-plan. |
| Parent | `8cd0f6a` — skip Inspect DSP and split histogram/PSD ticks |
| Series law | [handoff-monitor-perf.md](handoff-monitor-perf.md) |
| Product spec | [../monitor.md](../monitor.md) |

**Paste prompt** (this is what the next thread gets; this file is the brief):

```
Continue monitor graph perf on `refactor/monitor`. Do not push, do not
create a branch, do not open a GitHub PR. Implement ONLY PR3. Plan is
on disk — do not re-plan. Read `.ai/archive/handoff-monitor-perf-3.md`
and follow it. Parent is `8cd0f6a`.
```

---

You are on branch `refactor/monitor`. Do not push. Do not create a branch.
Do not open a GitHub PR.

Implement **ONLY** monitor graph perf **PR3**: incremental Spectrogram STFT
column ring in a testable helper; `spectrogram_view.dart` delegates. Do **not**
change heatmap painting (that is PR4).

Read, in order:

1. This file
2. [handoff-monitor-perf.md](handoff-monitor-perf.md) — locked decisions + PR3 section
3. [../monitor.md](../monitor.md)
4. `lib/src/monitor/views/spectrogram_view.dart` (`_stft`, `_onBuffer`, `_columns`)
5. `lib/src/monitor/dsp.dart` (`stftColumns`, `fft`, `kStftHopSamples`, `kDefaultFftN`)
6. `lib/src/monitor/cache/sweep_mean.dart` (`meanEegWindow`)
7. `lib/src/monitor/panes/spectrogram_pane.dart` (read only — do not edit)
8. [../test-matrix.md](../test-matrix.md)
9. Skill `muse-verify`

Do not reopen frozen monitor chrome. Do not mix Crown Start, OSC-connect,
pipeline-contract Key Decisions, or v5/FRB work. Do not add FFT-size chrome.
Do not change hop or `kDefaultFftN`. Do not edit GraphShell / AppShell.

---

## Frozen (short)

- Appearance unchanged. No new chrome. No `FFT 1s ▾`, averaging, Spectrogram
  Bands strip, `SMOOTH` / `REAL TIME`.
- Hidden graphs stay unmounted. EEG RAM stays 5 min. Caches stay warm.
- Hop stays `kStftHopSamples` (64). `n = 256`.
- Inspect skip on `_onBuffer` already exists — keep it.
- Heatmap is still per-cell `drawRect` until **PR4**. Do not rasterize.
- Recording-dashboard Spectrogram is Inspect-only and not packet-driven —
  it still calls `stftColumns` once per inspect range. Do not incremental-FFT
  the dashboard.

---

## What PR2 landed

Commit `8cd0f6a` — `perf(monitor): skip Inspect DSP and split histogram/PSD ticks`

- `HistogramTick` / `PsdTick` in `lib/src/monitor/split_pane_tick.dart`.
  `shouldRecomputeEegOnSweep` is false in Inspect.
- `histogram_view.dart` / `psd_view.dart`: split `_onTick` into `_onSweep` /
  `_onBands` / `_onEpoch` / `_onStrip`. Cache `_counts` / `_spectrum`+`_peak`
  / `_series` on the tick. `build()` reads those fields.
- Sweep listener returns in Inspect (no re-bin / re-Welch). Epoch pan /
  window still recomputes the primary pane. Strip listener rebuilds series
  only.
- Tests: `test/monitor/split_pane_tick_test.dart`.
- Docs: Inspect does not re-Welch / re-bin.

Listeners still `setState` on the view State that builds GraphShell.
`ListenableBuilder` is **PR5**. Sliding Welch / histogram is **PR7**.

---

## PR3 scope

**Commit:** `perf(monitor): incremental spectrogram STFT columns`

### Do

- New helper `lib/src/monitor/cache/stft_ring.dart` (prefer a file; `dsp.dart`
  is the FFT primitive):
  - Holds `List<StftColumn>`, last hop index, electrode set, start/end.
  - `columnsFor(buffer, electrodes, start, end, newest)`:
    - Inspect + same range + same electrodes → return cached.
    - Follow + same electrodes + start/end slid by hops → `fft` **one** new
      256-pt window (`meanEegWindow` only for that slice), append, drop
      columns with `elapsed < start - hop`.
    - Else full `stftColumns` as today.
  - Hop stays `kStftHopSamples` (64). `n = 256`.
- `spectrogram_view.dart` `_stft` delegates to the ring. Keep `_onBuffer`
  hop throttle. Drop the view-local `_columns` / `_cachedElectrodes` /
  `_cachedStart` / `_cachedEnd` cache if the ring owns it.
- Tests in `test/monitor/stft_ring_test.dart`: N hops of a sine → column
  count matches `stftColumns`; after one extra hop, **one** new column and
  the first dropped when the window slides; electrode-set change forces full
  rebuild (compare to a fresh ring).
- Docs: one sentence in [../monitor.md](../monitor.md) (Follow STFT is
  incremental; Inspect / electrode / window-length still full recompute).
  Add the new test file to [../test-matrix.md](../test-matrix.md).

### Do not

- Change `SpectrogramPane` painting (PR4).
- Add FFT-size chrome. Do not change hop or `kDefaultFftN`.
- Incremental-FFT the recording dashboard.
- `ListenableBuilder` / GraphShell surgery (PR5).
- Touch [../ui-map.md](../ui-map.md).
- Edit `sweep_buffer.dart` / `band_cache.dart` / the PR1 mixin /
  `split_pane_tick.dart`.

### Files

| Path | Change |
|---|---|
| `lib/src/monitor/cache/stft_ring.dart` | **new** helper |
| `lib/src/monitor/views/spectrogram_view.dart` | `_stft` delegates to the ring |
| `test/monitor/stft_ring_test.dart` | **new** |
| `.ai/monitor.md` | incremental Follow STFT |
| `.ai/test-matrix.md` | add the new test |
| `.ai/archive/handoff-monitor-perf.md` | index: PR3 SHA |

### Resume pointers

| What | Where |
|---|---|
| Full STFT today | `dsp.dart` `stftColumns` |
| Hop / n | `kStftHopSamples` (64), `kDefaultFftN` (256) |
| View cache + Inspect short-circuit | `spectrogram_view.dart` `_stft` |
| Packet throttle (keep) | `spectrogram_view.dart` `_onBuffer` |
| Mean EEG slice | `cache/sweep_mean.dart` `meanEegWindow` |
| Pad before first column | `_stft` uses `kDefaultFftN / sampleRate` |
| Painter (do not edit) | `panes/spectrogram_pane.dart` |
| Dashboard (leave `stftColumns`) | `views/recording_dashboard.dart` |

---

## Verify

Skill `muse-verify`. No `flutter run` unless asked.

```bash
flutter analyze lib/src

flutter test test/monitor/dsp_test.dart test/monitor/stft_ring_test.dart
```

---

## When done

1. Commit on `refactor/monitor`:
   `perf(monitor): incremental spectrogram STFT columns`
   Do not push.
2. Update [handoff-monitor-perf.md](handoff-monitor-perf.md) index: PR3
   status landed + commit SHA; status line “Start PR 4”.
3. Write **paste-ready** [handoff-monitor-perf-4.md](handoff-monitor-perf-4.md)
   for PR4 (Spectrogram heatmap bitmap inside `SpectrogramPane`;
   `FilterQuality.none`; recording dashboard shares the pane; no goldens).
   Same shape as this file: table, frozen, what PR3 landed, PR4 Do/Do not/
   files/tests/commit, resume pointers, “when done”.
4. Print a **short** paste prompt at the end of the turn (branch, PR4
   only, path to that file, parent SHA). Do not dump the whole file.
