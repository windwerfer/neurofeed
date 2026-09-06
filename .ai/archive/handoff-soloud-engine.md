# Handoff — SoLoud engine hardening (archived)

| Field | Value |
|---|---|
| Date | 2026-09-05 |
| Status | **Landed** on `fix/soloud-engine-hardening`. Spec remains [../audio-engine.md](../audio-engine.md). |
| Spec | [../audio-engine.md](../audio-engine.md) — **Key Decisions 1–10 are frozen. Do not reopen.** |
| Suggested branch | `fix/soloud-engine-hardening` from current `main` |
| Do not mix | Crown Start, OSC connect, pipeline-contract Key Decisions, v5 layout, new reward/guard ids, connect-dropdown, Athena optics |

Read the spec first. This file is implementer order, file list, and
pitfalls. The previous thread reviewed the engine, locked the leftover
muffle API, and stopped before editing Dart.

---

## What this project is doing

Muse ML feedback audio is flutter_soloud 4.1.7 behind `AudioService`.
PR 5 split background / reward / guard. The native backend
(`SoLoudEngine`) and the controllers were not finished to match:

- Rain reward uses `loadFile` on an **asset key** and does not loop.
- Bowl chimes never preload (`ChimeRewardOutput.start` is empty).
- Calibration clip await times out at 15 s (longest intros are longer).
- `FeedbackAudioController.dispose` deinits the **process** engine.
- `AudioService.setMusicMuffle` is leftover; `GuardLane` calls
  `RewardOutput.setMuffle`.

This thread: make the engine and wiring match the spec. One PR.

---

## Frozen decisions (repeat — do not reopen)

See spec Key Decisions 1–10. Short form:

1. Keep engine / `ModulatedVoice` / controllers / `RewardOutput` /
   `GuardOutput` / `AudioService`.
2. Engine owns init, deinit, epoch, bundled-asset cache. Controllers do
   not deinit.
3. AAudio profile reopens only at session start
   (`reopenIfProfileDiffers: true`).
4. Delete `setMusicMuffle` / `mufflesForWarning`. Keep
   `RewardOutput.setMuffle`. Background binaural muffle callback on
   **all five** reward outputs. Do **not** duck unmodulated background.
5. `ModulatedVoice.play` owns `looping`, stop-previous, filter order.
6. Bundled audio = `loadAsset`. User music = `loadFile`, uncached.
7. Chime preload in `start()`, not in `_triggerChime`.
8. Calibration timeout from `getLength + 2s` (floor 15, cap 90, 0 → 60).
9. Alarm first tick is immediate; pause stops the alarm.
10. One PR, steps below.

---

## Issue map (spec covers all of these)

| # | What | Step |
|---|---|---|
| 1 | Rain `loadFile` on asset path | 4 |
| 2 | Rain / `ModulatedVoice` not looping | 3–4 |
| 3 | Chime never preloaded | 4 |
| 4 | Calibration 15 s timeout | 4 |
| 5 | Cutoff applied to stale `source` | 3 |
| 6 | Alarm 2 s silent + volume on `_bellHandle` | 4 |
| 7 | `_chimeHandles` concurrent modification | 4 |
| 8 | `deinit` races / controller owns engine | 1, 5 |
| 9 | Music `dispose` / `load` / shuffle | 7 |
| 10 | `audioStableMode` only at session start, controllers ignore pref on first open | 1, 8 |
| 11 | Epoch cache without `disposeSource`; `_sourceFor` races | 2 |
| 12 | Pause does not stop alarm; leftover muffle API | 5–6 |
| 13 | Duplicate `stop`, stale comments, public fields, soft-bowl asset | 7, 9 |

---

## Current code (why it is messy)

| File | What is wrong |
|---|---|
| `soloud_engine.dart` | `deinit()` nulls `_inflight` and `unawaited`s native close. No asset cache. No `reopenIfProfileDiffers`. `throw lastError!`. |
| `feedback_audio_controller.dart` | Local `_sources` without dispose. `dispose` → `SoLoudEngine.deinit()`. `_triggerChime` requires a cache hit. Alarm `Timer.periodic` without an immediate play. `_safeHandle` always `remove`s from `_chimeHandles`. Calibration `.timeout(15s)`. |
| `rain_feedback_controller.dart` | `loadFile(rainAsset)` — asset key, not a file. `ModulatedVoice.play` without looping. Epoch change nulls Dart refs, leaks native source. |
| `modulated_voice.dart` | `play` does not stop the previous handle; `_applyCutoffImmediate` reads the old `source` field; `source`/`handle` public; no `looping`. |
| `music_controller.dart` | `dispose` only closes a stream. `load()` clears playlist under a live voice (settings panel). `toggleShuffle` does not reset `_position`. `listSync` unguarded. |
| `binaural_beat_controller.dart` | Epoch change drops Dart refs without `disposeSource`. |
| `audio_service.dart` | `setMusicMuffle` / `mufflesForWarning` unused. `stop` == `_stopChannels`. `onMuffleExtras` not passed to chime/none. `dispose` deinits via the feedback controller. |
| `reward_output.dart` | `ChimeRewardOutput.start` empty. `NoneRewardOutput.setMuffle` empty. |
| `guardrail_sound.dart` | `softBowl` still points at the generic bell; `guardrail-softBowl-01.opus` is in the bundle. |
| `feedback_state.dart` | `SoLoudEngine.ensureInit(stable: …)` duplicated instead of `AudioService.ensureReady`. |
| `test/soloud_engine_test.dart` | Covers init/fallback/inflight/profile switch/deinit flags only. No deinit-vs-inflight, no cache. |

`guard_lane.dart` is **correct**. Do not edit it.

---

## Implementer order

Do not skip ahead to rain/chime before the engine cache exists.

### Step 1 — Engine lifetime

`lib/src/audio/soloud_engine.dart` + `test/soloud_engine_test.dart`.

- `ensureInit({bool? stable, bool reopenIfProfileDiffers = false})`.
  If ready and profile differs: reopen only when the flag is true;
  otherwise return (keep the open device).
- `Future<void> deinit()`: await `_inflight` (ignore error), then
  `_close()`. Never assign `_inflight = null` before that wait.
- `_initWithFallback`: `throw lastError ?? StateError(...)`.
- Tests: existing ones plus inflight-vs-deinit, reopen flag true/false.

`resetForTest` must clear any new cache fields.

### Step 2 — Asset cache

Same file.

- `loadAsset(path, {required bool stream})` → in-flight map +
  `(epoch, path, stream)` cache, `autoDispose: false`.
- Epoch bump (successful open **or** `_close`) disposes cached sources.
- Inject load/dispose in `resetForTest` if that is the only way to unit
  test without the plugin. If injection gets large, test the map logic
  by extracting a tiny helper — do not mock `SoLoud.instance` globally.

Point `FeedbackAudioController._sourceFor` at `SoLoudEngine.loadAsset`.
Delete `_sources` / `_engineEpoch` on that controller.

### Step 3 — `ModulatedVoice`

`lib/src/audio/modulated_voice.dart`.

- `play(..., {bool looping = false})`.
- `stop()` previous handle first.
- Assign `_source` / `_handle` before biquad; apply cutoff to `src`,
  not a stale field.
- Fields private. Getter for handle if music’s `soundEvents` filter
  still needs it.

### Step 4 — User-audible bugs

- **Rain:** `SoLoudEngine.loadAsset(rainAsset, stream: true)` then
  `_voice.play(..., looping: true, activateFilter: true)`. Rethrow load
  failure after `debugPrint` so `playChannels` can set `audioInitFailed`.
- **Chime:** `FeedbackAudioController.preloadChime()` loads
  `bowlLowAsset` memory-mode. `ChimeRewardOutput.start()` calls it.
  `_triggerChime` stays a cache/hit play; keep the skip log.
- **Calibration:** `_playAndAwaitEnd` timeout = `getLength + 2s`,
  floor 15, cap 90, zero length → 60 s. On timeout, stop that handle
  and cancel the subscription.
- **Alarm:** play once immediately, then `Timer.periodic(2s)`.
  `setGuardrailVolume` writes `_alarmHandle`.
- **Prune:** `for (final h in List.of(_chimeHandles))`.
- **`_safeHandle`:** optional `onGone`; do not always touch
  `_chimeHandles`.

### Step 5 — Pause / dispose

- `AudioService.pause` → `_controller.stopWarningAlarm()` in addition
  to pausing loops. Resume: do nothing; `GuardLane` restarts if still
  over.
- `MusicController.dispose`: cancel `_endSub`, `stop()`,
  `disposeSource()`, close stream.
- `RainFeedbackController` / `BinauralBeatController`: dispose native
  sources, including on epoch change (do not just null refs).
- `FeedbackAudioController.dispose`: stop voices, do **not** deinit
  the engine.
- `AudioService.dispose`: `stop()`, controller disposes, then
  `unawaited(SoLoudEngine.deinit())`.

### Step 6 — Muffle leftover

- Delete `setMusicMuffle` and `mufflesForWarning`.
- `rewardOutputFor(..., onBackgroundBinauralMuffle: ...)` on **all**
  ids. `ChimeRewardOutput` / `NoneRewardOutput` call it from
  `setMuffle` and do not muffle their own one-shots.
- Music / rain / swell still muffle themselves, then the callback.
- Do not muffle the asset background loop. Do not edit
  `guard_lane.dart`.

### Step 7 — Music playlist + stop duplicate

- `toggleShuffle`: after moving current to index 0, `_position = 0`.
- `load()` if a voice is playing: `refreshSettings()` only, return
  `hasTracks`. Preview `loadMusic()` during a live music session must
  not rebuild `_tracks` under the handle.
- `listSync` in try/catch; on error log and return false.
- `playChannels` calls `stop()`; delete `_stopChannels`.

### Step 8 — Profile wiring

- `AudioService.ensureReady({bool reopenIfProfileDiffers = false})`.
- `feedback_state.dart` `startCalibration`:
  `_audio.ensureReady(reopenIfProfileDiffers: true)` instead of
  `SoLoudEngine.ensureInit(stable: …)`.
- Controllers may still `SoLoudEngine.ensureInit()` with no args
  (no-op if ready). Do not pass `stable` from controllers.

### Step 9 — Nits

- `GuardrailSound.softBowl` →
  `assets/audio/guardrail-softBowl-01.opus`.
- `assets/audio/README.md`: drop “unused placeholder”.
- Stale `MusicFeedbackController` comment in
  `feedback_audio_controller.dart`.
- No new comments unless a constraint is non-obvious (AGENTS.md).

### Step 10 — Verify + docs

```bash
flutter analyze lib/src
flutter test test/soloud_engine_test.dart test/output_ids_test.dart \
  test/feedback_pipeline_test.dart
```

Plus any new unit files you added. Skill `muse-verify` if you touch
more than audio.

Update [architecture.md](architecture.md) Audio paragraph: engine
owns cache + deinit; muffle is `RewardOutput.setMuffle`; profile
reopen at session start. Set this spec Status to Implemented. Move
this handoff to `archive/` when the PR is done.

Linux agent playback is **not** a gate (container has no reliable
ALSA assert). Optional: skip-cal `recordOnly` on sim and confirm
`audioInitFailed` is false.

---

## Files you will touch

```
lib/src/audio/soloud_engine.dart
lib/src/audio/modulated_voice.dart
lib/src/audio/feedback_audio_controller.dart
lib/src/audio/rain_feedback_controller.dart
lib/src/audio/music_controller.dart
lib/src/audio/binaural_beat_controller.dart
lib/src/audio/audio_service.dart
lib/src/audio/reward_output.dart
lib/src/audio/guardrail_sound.dart
lib/src/feedback/feedback_state.dart    # ensureReady only
assets/audio/README.md
test/soloud_engine_test.dart
test/* (new, only if injectable)
.ai/architecture.md
.ai/audio-engine.md                     # Status line
.ai/handoff-soloud-engine.md            # archive when done
```

Do **not** touch: `guard_lane.dart`, `output_ids.dart` (unless a one-line
comment), `calibration_clips.dart`, `pubspec.yaml`, FFI, JSON catalogs.

---

## Pitfalls

- **`loadFile` vs `loadAsset`:** `flutter_soloud` 4.1.7 `loadFile` is a
  filesystem path. It can appear to work in the Linux repo because
  `assets/audio/rain/…` exists on disk, and fail on Android. Rain
  **must** use `loadAsset`.
- **Looping is per handle.** Sharing one cached `AudioSource` for
  background rain and rain-reward is fine. `play(..., looping: true)`
  on the reward handle is what was missing.
- **Do not `SoLoudEngine.deinit` from a controller.** That is how
  background/music get their backend ripped out.
- **Do not duck the drone.** Frozen muffle policy. Only modulated
  reward + both binaural controllers.
- **Do not reopen the engine mid-session** because the stutter toggle
  changed. `reopenIfProfileDiffers` is session-start only.
- **Do not edit `guard_lane.dart`.** It already calls `setMuffle`.
- **`ChimeRewardOutput.start` must load.** `onSample` is sync; it
  cannot `await loadAsset`.
- **`play()` without `stop()` stacks voices** (rain `start` twice).
- **Native deinit is sync** (`SoLoud.instance.deinit()`). Still await
  `_inflight` first.
- **No comments that narrate the change.** AGENTS.md.
- **Do not commit / push** unless asked.

---

## Done when

- Issues 1–13 from the review are gone.
- `setMusicMuffle` / `mufflesForWarning` do not exist.
- `flutter analyze lib/src` clean.
- `flutter test test/soloud_engine_test.dart test/feedback_pipeline_test.dart`
  green.
- Spec Status is Implemented; architecture Audio paragraph matches.

---

## Prompt to start the implementer thread

> Continue from `.ai/handoff-soloud-engine.md`. Spec:
> `.ai/audio-engine.md` (Key Decisions frozen). One PR
> `fix/soloud-engine-hardening`: engine lifetime + asset cache, then
> `ModulatedVoice` looping/stop/cutoff, then rain `loadAsset`+loop, chime
> preload, calibration `getLength` timeout, alarm first tick, pause
> stops alarm, delete `AudioService.setMusicMuffle`, background binaural
> muffle on all five `RewardOutput`s. Do not duck unmodulated background.
> Do not edit `guard_lane.dart`. Do not reopen pipeline-contract or
> Crown Start. Do not commit unless I ask.
