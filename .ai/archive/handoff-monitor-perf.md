# Handoff — monitor graph draw-path perf

| Field | Value |
|---|---|
| Date | 2026-09-13 |
| Status | **Series complete.** Archived. Do not start a new perf PR from this file. |
| Spec | [../monitor.md](../monitor.md) — **frozen**. No new chrome. |
| Branch | `refactor/monitor` (PR1 `8ecfc65` … PR7 `ccc36b0`). |
| Product series | [handoff-monitor.md](handoff-monitor.md) (PRs 0–7; product PR 8 cancelled). |

PRs **1–7 landed**. **PR 8 skipped** — gate did not fire (no profile of
wipe-ring copies or tmp `encodeSessionEvent` dominating after PR7). Do not
pause `SweepBuffer` / `BandCache` on view change. Hidden graphs stay
unmounted (`AppShell` `switch`, not `IndexedStack`).

Live spec: [../monitor.md](../monitor.md).

---

## Landed

| PR | Items | Commit |
|---|---|---|
| **1** | Coalesce `SweepBuffer` / `BandCache` `notifyListeners` to vsync | `8ecfc65` |
| **2** | Histogram/PSD Inspect skip + split recompute ticks | `8cd0f6a` |
| **3** | Incremental Spectrogram STFT column ring | `2833b0a` |
| **4** | Spectrogram heatmap bitmap (`FilterQuality.none`) | `dd6d58b` |
| **5** | Isolate graph paints from shell rebuilds | `b431604` |
| **6** | Raw EEG min/max downsample; idle wipe ring on leave | `09bac0c` |
| **7** | Sliding Welch / histogram on Follow | `ccc36b0` |
| **8** | Capture extras (wipe copies / `encodeSessionEvent`) | **skipped** |

---

## Do not reopen

- Spectrogram `FFT 1s ▾`, averaging, Bands strip on Spectrogram, `SMOOTH` /
  `REAL TIME` Bands chrome.
- `IndexedStack` / keep-alive hidden graphs.
- Growing EEG RAM past 5 min. Pause caches on view change.
- Changing Welch hop (`n/2`) or live FFT `n = 256`.
- Lifting the Bands Follow ticker out of `TimeSeriesPane`.
