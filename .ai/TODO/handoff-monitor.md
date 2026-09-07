# Handoff — live monitor graphs + connect-time recording

| Field | Value |
|---|---|
| Date | 2026-09-07 |
| Spec | [../monitor.md](../monitor.md) — **frozen Key Decisions. Do not reopen.** |
| Branch | `refactor/monitor` (PR 0 `22cfd38`, PR 1a this commit). Suggested name was `feat/monitor-graphs`. |
| Cadence | **One PR per thread.** This file is the series map. Next is **PR 1b**. |
| Do not mix | Crown Start, OSC-connect, pipeline-contract Key Decisions, v5 68-byte header / FRB, Android foreground service, Athena optics, growing status-bar pads to 8. |

Read the spec first (`Key Decisions`, `File layout`, `PR Plan`, `Implementer protocol`). This file is implementer order, current-code pitfalls, and the **PR 1b** start. Do not re-design graphs, naming, or the lease.

---

## Paste this to start a new thread

**PR 1b (this thread):**

```
Implement monitor PR 1b only: tmp_ writer + exclusive capture lease.
Spec: .ai/monitor.md (frozen). Handoff: .ai/TODO/handoff-monitor.md (section “This thread — PR 1b”).
Kill AppStateNotifier.sessionRecorder. Connect starts tmp_$ts. Feedback acquireFeedbackLease. No GraphShell. No Record button. No PR 1c. Do not start PR 2.
```

**Later graph threads (2 / 3 / 4)** must paste an ASCII wireframe and wait before painters. See spec **Implementer protocol**.

---

## Landed

| PR | Commit / note |
|---|---|
| **0** | `22cfd38` — `lib/src/session_v5/` (writer, assemble, ComputedFrame, models). Prefix default `session`. Sidecar still `.metadata` JSONL. Thin re-exports at old paths. |
| **1a** | `MonitorController` constructed in `main()` after `appStateProvider.notifier`. Subscribes to broadcast `eventStream`, hydrates montage if already connected. Band ring in `monitor/cache/band_cache.dart` (1800). `bandNames`/`bandColors` in `charts/band_style.dart`. Pad quality is a 4-ch **1 s** ring in `connection_provider.dart`. `CaptureKind` exists but stays `idle`. `sessionRecorder` **still on AppState** — 1b kills it. `live_cache.dart` unused (delete in PR 2). `SweepEegView` untouched. |

---

## Series map (do not collapse)

| PR | Thread title | ASCII? | Depends |
|---|---|---|---|
| **0** | Extract `lib/src/session_v5/` | no | — |
| **1a** | `MonitorController` in `main()` + band cache; no disk | no | 0 |
| **1b** | `tmp_` writer + exclusive lease (kills dual `session_` writers) | no | 1a |
| **1c** | File-backed Inspect of tmp/recording `.raw` | no | 1b |
| **2** | GraphShell + N stacked **sweep** EEG panes; cancel add/remove | **yes** | 1b; prefer 1c first |
| **3** | Bands on GraphShell + electrode toggles | **yes** | 2 |
| **4** | Histogram + PSD + Spectrogram (`AppView.histogram` only) | **yes** (each view) | 2; ∥ 3 |
| **5a** | Record / Stop / assemble / 409 `recording_active` | no | 1b, 2 |
| **5b** | Crash recovery + `publish` into `session_metadata.db` (`kind`) | no | 5a |
| **6** | Unified History list + filter + Save files to folder | no | 5b |

Hide Record until 5a. Copy changes update `.ai/ui-map.md` in the same PR.

---

## Current code (why PR 1b exists)

| Piece | Where | After 1a |
|---|---|---|
| Connect writer | `AppStateNotifier.sessionRecorder` + `_startContinuousRecorder` | **still dual-owned.** `session_$ts`; `stop()` deletes; **ignores** `Settings.recordStreams` |
| Feedback writer | `FeedbackRecorder` → own `SessionRecorder` | second `session_$id` in the same scratch dir |
| Scratch writer | `lib/src/session_v5/scratch_writer.dart` | class `SessionRecorder`; `start(dir, {prefix = 'session'})`; sidecar **`.metadata` JSONL only** — no `.json` snapshot yet |
| Assemble | `lib/src/session_v5/assemble.dart` | `writeScratchV5(..., {prefix = 'session'})` |
| Monitor controller | `lib/src/monitor/monitor_controller.dart` | `main()` + hydrate; appends **bands only**; `CaptureKind.idle`; no disk |
| Band cache | `lib/src/monitor/cache/band_cache.dart` | 30 min / 1800; Bands view reads this |
| Pad quality | `connection_provider` `_PadQualityRing` | 4-ch, 1 s, skip `ch > 3` — **do not grow** |
| Crash recovery | `lib/src/feedback/crash_recovery.dart` | `session_*` only — **must stay that way** |
| Sweep EEG | `views/sweep_eeg_view.dart` + `charts/sweep_buffer.dart` | own `SweepBuffer` + `eventStream`. **Do not rewire** (PR 2) |
| `ComputedSampler` | `feedback/computed_sampler.dart` | **4-ch hardcoded.** Do not reuse for monitor |
| `GET /state` | `agent_commands.dart` `_stateJson` | no `captureKind` / `captureElapsedSeconds` yet |
| `live_cache.dart` | `lib/src/charts/live_cache.dart` | unused. Delete in PR 2, not 1b |

---

## This thread — PR 1b

**Title:** `Replace dual session_ writers with tmp_ capture lease`

**Do:** one exclusive `ScratchWriter`. Connect starts rolling `tmp_$ts`. Feedback `startCalibration` acquires the lease (discards tmp). Release only when the feedback writer is actually closed.

**Do not:** GraphShell, SweepEegView rewire, Record button, `recording_` prefix in live UI, file-backed Inspect (PR 1c), FFI, growing pad-quality to 8, assembling tmp, teaching feedback `crash_recovery.dart` about `tmp_` / `recording_`.

### Target files (new)

```
lib/src/monitor/recording/
  capture_lease.dart         # CaptureKind transitions; at most one open writer
  monitor_recorder.dart      # ScratchWriter prefix tmp (and recording later);
                             # Settings.recordStreams; 30 min silent rotate
  monitor_sampler.dart       # 1 Hz ComputedFrame; N = channelCount.toInt();
                             # zeroed GuardrailInfo / FeedbackInfo
  crash_recovery.dart        # stub: glob-delete leftover tmp_* on launch
                             # (recording_* recovery is PR 5b)
```

`CaptureKind` already lives in `monitor_state.dart`. Wire it from the lease — do not add a second enum.

### Kill dual writers

Remove from `AppStateNotifier`:

- `sessionRecorder`
- `_startContinuousRecorder()`
- `sessionRecorder.writeEvent` in `_onEvent`
- `sessionRecorder.stop()` on disconnect

Connect/disconnect ownership moves to `MonitorController`:

- `status.connected` true (event **or** hydrate-if-already-connected listen) **and** lease idle **and** feedback writer closed → start `tmp_$ts`
- disconnect / process exit while `tmp` → **discard, no prompt**

Keep the 4-ch 1 s `_PadQualityRing`. Keep `eventStream` broadcast.

### Lease (spec table — do not improvise)

`enum CaptureKind { idle, tmp, recording, feedback }` — already defined.

| From \ To | tmp | recording | feedback | idle |
|---|---|---|---|---|
| idle | connect, feedback writer closed | **not this PR** (Record is 5a) | `startCalibration` after `acquireFeedbackLease` | — |
| tmp | 30 min rotate: discard + new tmp | **not this PR** | session start: **discard tmp, no prompt** | disconnect: **discard, no prompt** |
| recording | forbidden | — | refused (5a) | 5a |
| feedback | **only when `!_recorder.isRecording`**, if still connected: restart tmp | Record hidden/disabled (5a) | — | writer closed |

**Do not key tmp-restart off `FeedbackPhase.idle`.** `end()` sets `ended` even when assemble fails.

**Do not release after a failed assemble.** `FeedbackRecorder.assembleScratchV5`:

- success → `cleanupTempFiles()` → `isRecording == false` → **release**; restart tmp if connected
- failure (`null`) → temps kept, `isRecording == true` → **stay `CaptureKind.feedback`**, no `tmp_*`

```dart
// FeedbackStateNotifier.end(), after assembleScratchV5:
if (!_recorder.isRecording) {
  await ref.read(monitorControllerProvider.notifier).releaseFeedbackLease();
}
// reset() / discardSession() already stop() the recorder, then:
await releaseFeedbackLease(); // idempotent
```

`startCalibration`: `acquireFeedbackLease()` first (after Crown refuse). On false, `debugPrint('[feedback] refusing Start: recording_active'); return;` — even though Record is hidden until 5a, the lease API must exist so a later Record path cannot open a second writer.

Feedback **may import the lease API only** (`monitorControllerProvider.notifier.acquireFeedbackLease` / `releaseFeedbackLease`). Do not import monitor caches, panes, or `device_montage.dart`. `buildSessionMetadata` still uses `DeviceConfig.forKind` → `electrodeNames`.

### tmp writer

`SessionRecorder.start` today: prefix default `session`, sidecar **`.metadata` JSONL**.

1b must add snapshot sidecar for monitor (spec Key Decision 10). Feedback stays JSONL:

```dart
Future<void> start(
  Directory dir, {
  String prefix = 'session',
  String? id,
  SidecarMode sidecar = SidecarMode.jsonl, // jsonl → .metadata; snapshot → .json
});
```

- tmp path: `$dir/tmp_$ts.{raw,computed,json}`
- Snapshot: sibling `tmp_$ts.json.tmp` then `rename` onto `tmp_$ts.json`. **Not** `.$id.json.tmp`. **Not** in-place `writeAsString`.
- `RecordingMetadata` JSON: `kind: "tmp"` or omit user-facing kind — tmp is **never assembled**. Need a complete `StreamsConfig` (ten keys; disabled = `enabled: false`, `rateHz: 0`) if you write the snapshot. Reuse `DeviceInfoV5` / `StreamsConfig` from `session_v5/models.dart`.
- Apply `Settings.recordStreams` to tmp (**behavior change** vs today’s all-streams connect dump). Call out in a short comment / log; do not add a second Settings card.
- 30 min silent rotate: discard tmp, start a new `tmp_$ts`, reset `captureStartedAtMs`.
- **Never** `writeScratchV5` on tmp. Never publish tmp.

`MonitorSampler` (do **not** reuse `ComputedSampler`):

- `bands`, `lineNoise`, `signalQuality` length = `config.channelCount.toInt()` (BigInt → int)
- Zeroed `GuardrailInfo` / `FeedbackInfo`
- `t` = seconds from **this** capture’s start (`captureStartedAtMs`)
- Gestures: copy latest 1 Hz names if present

Montage: `lastConnectedKind ?? DeviceKind.muse` → Muse-4 vs Crown-8 names already on `MonitorState` (`kMuseElectrodeNames` / `kCrownElectrodeNames`). `channelCount` is already `.toInt()` on that state.

### Launch glob-delete

`_CrashRecoveryWrapper` (`lib/src/app.dart`) currently only `showCrashRecoveryDialog` (`session_*`). After that (or before, order: **feedback first**, then monitor tmp delete):

- glob-delete leftover `tmp_*.raw` / `.computed` / `.json` in `scratchDirectory()`
- do **not** scan `recording_*` (PR 5b)
- do **not** extend `lib/src/feedback/crash_recovery.dart`

### Agent HTTP (1b slice only)

`GET /state`: add `captureKind` and `captureElapsedSeconds`. Do **not** reuse feedback `elapsedSeconds`. `persist: false` already. No `/record/*` (5a). No 409 `recording_active` (5a). Crown 409 stays `crown_refused`.

### Tests

```
test/monitor/capture_lease_test.dart
test/monitor/monitor_sampler_test.dart
```

Required cases:

1. Successful `end()` while still connected → `captureKind == tmp`
2. `assembleScratchV5` returns null → `captureKind` remains `feedback`, **no** `tmp_*` files
3. `reset()` / `discardSession()` after stop → lease released; tmp restarts if connected
4. Connect while idle → `tmp_$ts.{raw,computed,json}` (not `session_`)
5. Disconnect while tmp → files gone
6. Sampler: N-length arrays; `t` elapsed from capture start; zeroed guard/feedback
7. `StreamsConfig.fromJson` ten keys on the tmp sidecar

### PR 1b done when

- `AppStateNotifier.sessionRecorder` is gone
- At most one open scratch writer
- Connect writes `tmp_*` (Settings `recordStreams` applied)
- Feedback still writes `session_*` after `acquireFeedbackLease`
- Failed assemble does not start tmp
- Launch deletes leftover `tmp_*`
- No Record chrome, no GraphShell, no `lib/src/monitor/panes/`
- `flutter analyze lib/src` clean

### Verify (PR 1b)

```bash
flutter analyze lib/src
flutter test test/monitor/capture_lease_test.dart \
  test/monitor/monitor_sampler_test.dart \
  test/monitor/band_cache_test.dart
```

FFI not required unless you touch `writeScratchV5` (tmp is never assembled). Do **not** run FRB. Do **not** `cargo check --target aarch64-linux-android`.

---

## Next threads (do not start in PR 1b)

### PR 1c — file-backed Inspect (**required**)

Index framed `.raw` at flush boundaries; `getRange` prepends `sessionHeaderBytes()` then `sessionParseBody`. Until this lands, Inspect is SweepBuffer 5 min only — say so, do not claim 30 min.

### PR 2 — sweep EEG (ASCII first)

Paste ASCII of GraphShell + N stacked sweep panes (Follow/Inspect, 10 s window, green wipe, **no** Record yet, **no** electrode chips, no add/remove). Wait. Then move `sweep_buffer.dart` into `monitor/cache/`. Delete `graph_config.dart`, `eeg_dashboard.dart`, `eeg_chart.dart`, `sweep_eeg_view.dart` add/remove / `eeg_layout_*`. Default 10 s (`2560` samples). Placeholders: Muse-4 vs Crown-8 from `lastConnectedKind`.

### PR 3 / 4 — other graphs (ASCII first, each view)

Top-right depressed electrode labels → mean. Histogram new `AppView`. Keep `AppView.spectrogram`. FFT: Hamming 256-pt `1/N²`, edges 1–4 / 4–8 / 8–13 / 13–30 / 30–50.

### PR 5a / 5b / 6

Record/Stop, 409 `recording_active` on **`AgentCommands._start`** (there is no `_sessionStart`), Save/Discard, crash recovery for `recording_*` only, History filter All|Feedback|Recordings, sqlite `kind`, Settings **Save files to folder**.

---

## Isolation (every thread)

**Monitor may import:** `rust/api/{muse,session_format,device_config}.dart`, `connection_provider.dart` (status / `eventStream` / `lastConnectedKind`), `settings.dart`, `session_v5/`, `charts/{smooth_path,band_style}.dart`, `version.dart`, `feedback/session_storage.dart`.

**Monitor must not import:** `feedback_state.dart`, lanes, protocol, `session_store*.dart`, feedback `crash_recovery.dart`.

**Feedback must not import `lib/src/monitor/`** except the lease API (this PR). `buildSessionMetadata` uses `DeviceConfig.forKind` → `electrodeNames`, **not** `device_montage.dart`.

History list stays `lib/src/views/feedback_history.dart` (PR 6). Recording dashboard / Save-Discard live under `monitor/views/`.

---

## Pitfalls

- **Broadcast `eventStream`:** controller is already constructed in `main()` (1a). Do not move it to AppShell. Do not copy `StreamingController`.
- **`assembleScratchV5` failure** keeps `_rawFile` (`isRecording == true`). Releasing the lease and starting `tmp_` then is two writers again — the bug this PR exists to kill.
- **SAF** list/read/delete have **no** `dir:`. Do not publish into a `recordings/` child (and 1b does not publish at all).
- **`channelCount` is `BigInt`.** Always `.toInt()`.
- **SweepBuffer is the 5 min EEG ring** (still in `charts/`, used by SweepEegView). Do not add a LiveCache EEG ring. `live_cache.dart` is dead; leave it for PR 2.
- **tmp rotate** resets inspectable range (PR 1c). Record (5a) does not include pre-click bytes.
- Stale `rust/target/release/` breaks `flutter run` if you ever touch FFI (this series should not).
- `flutter analyze lib/src` after every Dart PR. No goldens / `integration_test`.
- Agent HTTP: `persist: false`. `GET /state` uses `captureKind` + `captureElapsedSeconds`, not feedback `elapsedSeconds`. Crown 409 stays `crown_refused`.
- Sidecar rename must be `prefix_$id.json.tmp` → `prefix_$id.json`. Feedback `.metadata` JSONL stays append-only.

---

## Docs when a PR lands

| When | Update |
|---|---|
| Any on-screen copy | `.ai/ui-map.md` in that PR |
| `AppView.histogram` (PR 4) | `.ai/test-matrix.md`, `.ai/testing-guide.md` `POST /view` |
| `/record/*` and 409 (PR 5a) | testing-guide |
| History label / Save files to folder (PR 6) | ui-map |
| Series complete | `.ai/architecture.md`, `.ai/README.md`; move this handoff to `.ai/archive/` |

Do not edit pipeline-contract or connect-simulator-ux.
