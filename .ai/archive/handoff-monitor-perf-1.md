# Handoff — start monitor graph perf PR 1

| Field | Value |
|---|---|
| Date | 2026-09-13 |
| Branch | `refactor/monitor` (do not push, do not create a branch) |
| Status | **Start PR 1.** Plan is already on disk. Do not re-plan. |
| Parent | `b7680bd` — Bands Follow + in-pane chips |
| Series law | [handoff-monitor-perf.md](handoff-monitor-perf.md) |
| Product spec | [../monitor.md](../monitor.md) |

Paste **this whole file** into the new thread.

---

You are on branch `refactor/monitor`. Do not push. Do not create a branch.
Do not open a GitHub PR.

Implement **ONLY** monitor graph perf **PR1**: coalesce `SweepBuffer` and
`BandCache` `notifyListeners` to vsync.

Read, in order:

1. This file
2. [handoff-monitor-perf.md](handoff-monitor-perf.md) — locked decisions + PR1 section
3. [../monitor.md](../monitor.md)
4. `lib/src/monitor/cache/sweep_buffer.dart`
5. `lib/src/monitor/cache/band_cache.dart`
6. [../test-matrix.md](../test-matrix.md)
7. Skill `muse-verify`

Do not reopen frozen monitor chrome. Do not mix Crown Start, OSC-connect,
pipeline-contract Key Decisions, or v5/FRB work. Do not add a 20 Hz DSP
timer. Do not edit graph views.

---

## Frozen (short)

- Appearance unchanged. No new chrome. No `FFT 1s ▾`, averaging, Spectrogram
  Bands strip, `SMOOTH` / `REAL TIME`.
- Hidden graphs stay unmounted. EEG RAM stays 5 min. Caches stay warm.
- Coalesce **at the cache**, not per view. RAM/display **writes stay
  synchronous**. `notifyListeners` at most **once per vsync**.
- `freeze` / `resume` / `setDisplayWindow` / `clear` notify **immediately**.
- Wipe-ring skip is **PR6**, not this PR.

---

## Already done (plan thread)

- Series plan + index: [handoff-monitor-perf.md](handoff-monitor-perf.md)
- This paste file
- [../active-task.md](../active-task.md) already points at the perf series

Do not recreate those. After the commit, **update the index table** (PR1
status + SHA).

---

## PR1 scope

**Commit:** `perf(monitor): coalesce EEG/band cache notifies to vsync`

### Do

- New mixin `lib/src/monitor/cache/frame_coalesced_notify.dart` on
  `ChangeNotifier`:
  - `notifyListenersCoalesced()`: if already scheduled, return; else set a
    flag, `SchedulerBinding.instance.scheduleFrameCallback` → clear flag +
    `notifyListeners()`, and `scheduleFrame()` / `ensureVisualUpdates()` so
    the callback runs.
  - If `!hasListeners`, do not schedule (caller still writes RAM).
  - If no binding (defensive), `notifyListeners()` immediately.
- `SweepBuffer.append` and `BandCache.appendBands` use
  `notifyListenersCoalesced()`.
- `setDisplayWindow` / `freeze` / `resume` / `clear` stay immediate
  `notifyListeners()`.
- New `test/monitor/sweep_buffer_test.dart`:
  `TestWidgetsFlutterBinding.ensureInitialized()`. Many `append`s in one
  turn → **0** listener fires until `tester.pump()` (or `endOfFrame`) →
  **exactly 1**. Immediate path: `freeze` still notifies without pumping.
  Also cover `BandCache.appendBands` burst → one notify after pump.
- Existing `test/monitor/viewport_controller_test.dart` and
  `test/monitor/histogram_pane_test.dart` only read samples — must stay
  green **without** pumping.
- Docs: one sentence in [../monitor.md](../monitor.md) (EEG notify is
  vsync-coalesced; RAM writes stay 256 Hz). Add
  `test/monitor/sweep_buffer_test.dart` to the pure-Dart list in
  [../test-matrix.md](../test-matrix.md).

### Do not

- Change view `addListener` / `setState`.
- Throttle DSP to 20 Hz.
- Skip display-ring writes (`setDisplayWindow(0)` is PR6).
- Import the mixin from outside `monitor/cache/`.
- Touch [../ui-map.md](../ui-map.md).

### Files

| Path | Change |
|---|---|
| `lib/src/monitor/cache/frame_coalesced_notify.dart` | **new** mixin |
| `lib/src/monitor/cache/sweep_buffer.dart` | coalesced `append` |
| `lib/src/monitor/cache/band_cache.dart` | coalesced `appendBands` |
| `test/monitor/sweep_buffer_test.dart` | **new** |
| `.ai/monitor.md` | one draw-path sentence |
| `.ai/test-matrix.md` | add the new test |
| `.ai/archive/handoff-monitor-perf.md` | index: PR1 SHA |

### Resume pointers

| What | Where |
|---|---|
| EEG packet append + `notifyListeners` | `sweep_buffer.dart` `append` |
| Display window / freeze / resume / clear | same file, must stay immediate |
| Bands 1 Hz append | `band_cache.dart` `appendBands` |
| `ChangeNotifier` | `package:flutter/foundation.dart` |
| Frame callback | `package:flutter/scheduler.dart` `SchedulerBinding` |
| Sample-only tests (must not need pump) | `test/monitor/viewport_controller_test.dart`, `histogram_pane_test.dart` |

---

## Verify

Skill `muse-verify`. No `flutter run` unless asked.

```bash
flutter analyze lib/src

flutter test \
  test/monitor/sweep_buffer_test.dart \
  test/monitor/viewport_controller_test.dart \
  test/monitor/histogram_pane_test.dart \
  test/monitor/band_cache_test.dart \
  test/monitor/time_series_pane_test.dart
```

---

## When done

1. Commit on `refactor/monitor`:
   `perf(monitor): coalesce EEG/band cache notifies to vsync`
   Do not push.
2. Update [handoff-monitor-perf.md](handoff-monitor-perf.md) index: PR1
   status landed + commit SHA; status line “Start PR 2”.
3. Write **paste-ready** [handoff-monitor-perf-2.md](handoff-monitor-perf-2.md)
   for PR2 (Histogram/PSD Inspect skip + split recompute; cache pane
   outputs on State; **no** ListenableBuilder yet). Same shape as this
   file: table, frozen, what PR1 landed, PR2 Do/Do not/files/tests/commit,
   resume pointers, “when done”.
4. Print that PR2 handoff in **one** fenced block at the end of the turn
   so it can be copied into the next thread.
