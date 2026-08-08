# Active Task

## Goal
Get a Muse BLE headset discovered and connected on **Android** so the app can
stream EEG/PPG/IMU/telemetry. The Dart UI and Rust FFI surface are in place;
the blocker was the **Android BLE transport layer**.

## Status — 2026-07-21
- ✅ Root cause #1 diagnosed: btleplug `JNI_EDETACHED` on tokio worker threads.
- ✅ Root cause #2 diagnosed: `[patch]` silently skipped due to semver mismatch.
- ✅ JNI fix applied: `get_env()` wrapper with `attach_current_thread_permanently()`
  fallback in `btleplug/src/droidplug/jni/mod.rs`.
- ✅ Java API alignment: added missing methods + `NoBluetoothAdapterException`.
- ✅ `classcache.rs` panic fixed: `.unwrap()` → `?`.
- ✅ **Scan works end-to-end without crashes** on Android.
- ✅ Fork published: `github.com/windwerfer/btleplug` tag `0.12.0-muse-3`.
- ✅ `Cargo.toml` updated to use remote tag (swap to local `../../btleplug` via
  `[patch]` for debugging — see `.ai/btleplug.md`).
- ✅ Docs: `.ai/btleplug.md`, `.ai/bugreport.md`, `.ai/btleplug_bugreport_2.md`, `.ai/lessons-learned.md` updated.

## Decision: keep btleplug
The JNI fix works — no migration to `flutter_blue_plus`. btleplug is
consistent with `muse-rs`'s native transport and avoids adding a Dart BLE
library + second FFI bridge. See `architecture.md` for the fallback plan.

## Status — 2026-07-26 Update
- ✅ Battery indicator fixed: `bp_override` from v1 response now correctly
  overrides raw fuel-gauge value in `TelemetrySnapshot.battery_level`.
  (No code change needed — was always working; the `info!` log in `map_event`
  misleadingly showed the raw value before override.)
- ✅ Raw telemetry log downgraded from `info!` to `debug!` to reduce noise.

## Status — 2026-07-27 Update
- ✅ Bug 2 (BLE notification death spiral) fully diagnosed and fixed:
  - Bug 2a: `JSendStream::poll_next_internal` bypassed auto-attach `get_env()` wrapper — fixed.
  - Bug 2b: Pending Java exceptions never cleared, poisoning all future JNI calls — fixed.
  - Bug 2c: `filter_map` silently dropped errors creating infinite loop — fixed with logging + exception clearing.
- ✅ Fork published as `0.12.0-muse-3` with all three fixes.
- ✅ `.ai/btleplug.md` updated with complete Batch 2 documentation.
- ✅ `.ai/btleplug_bugreport_2.md` added documenting the death spiral root cause analysis.

## Status — 2026-08-05 Update
- ✅ Phase I feedback feature merged to main and committed: 5-channel volume
  control, in-flight recalibrate, adaptive target guards, user target settings,
  full preference persistence.
- ✅ Feedback now auto-starts right after calibration (ready phase + manual
  Begin Feedback button removed); reward chimes play at full volume (no attack
  ramp — pre-play `setVolume(0)` + ramp was silently dropped by Android's audio
  stack).
- ✅ Forwarder reconnect robustness: 1 s poll switches to a newer connection's
  channel (≤1 s latency), 30 s silence watchdog emits `Disconnected` so the app
  auto-reconnects instead of sitting on a dead link. A `watch::changed()`-
  based wakeup caused a full-stream regression (see lessons-learned.md) and was
  reverted.
- ⏳ On-device verification in progress on the Lenovo TB336FU tablet:
  auto-start after calibration, chime audibility, mid-session disconnect →
  auto-reconnect → stream resumes.

## Status — 2026-08-07 Update (calibration signal gate redesign)
- ✅ Root-caused and fixed the calibration boot-loop from `muse.log`: after a
  baseline was captured, `_finishCalibration` re-checked `_allGreen`; a
  borderline/marginal pad flipped the gate → `_onAppState` discarded the
  finished baseline and re-ran the full 90 s calibration → loop (two baselines
  logged, feedback never started).
- ✅ **No gate after calibration**: `_finishCalibration` always calls
  `startPlaying()`. A finished baseline never re-locks on signal.
- ✅ **Gate before calibration** is now a 1 s `_gateTimer` requiring all 4 pads
  green for `greenStableSeconds` (3) continuously before the baseline starts.
- ✅ **Faulty-pad fallback**: a pad stuck non-green for `faultyPadSeconds` (20)
  while the frontal pads (`neededElectrodes=[1,2]` = AF7/AF8) are green is
  assumed faulty → inline "Continue anyway" bubble (tier A both frontal green;
  tier B ≥1 frontal "reduced accuracy").
- ✅ **Bad-signal handling during playing**: pauses (interrupted) only when ALL
  needed [1,2] pads dip below `signalCriticalThreshold` (40) for
  `badSignalPauseSeconds` (10); a rear pad (0/3) never blocks. A signal loss
  **never auto-ends** (no countdown); it resumes automatically once any needed
  pad is green again.
- ✅ **ATR autodrop**: `TargetStateAggregator.evaluate(quality)` drops
  per-pad (only pads ≥ `atrUsableSignalThreshold`=80 enter the AF7/AF8
  average); returns null if both frontal pads are bad → no feedback that sample.
- See the "Signal gate + autodrop model" bullet in `AGENTS.md`.

## Status — 2026-08-08 Update (session recording options + metadata)
- ✅ "Session recording" card in Settings: per-stream toggles for what a saved
  session includes (raw EEG, band powers, PPG, pulse, IMU, movement, peak
  alpha, telemetry). Default = all (backward compatible); stored via
  `Settings.recordStreams` (`record_streams` pref). SpO2 note added: blood
  oxygen is not a separate stream — only raw PPG optical channels exist.
- ✅ `SessionRecorder` filters events against `recordStreams` per event type
  (`session_recorder.dart`), so a disabled stream is simply absent from the
  `.muse` body. File format is self-describing (typed events), so no format
  version bump needed.
- ✅ Recorder tracks `channels` (electrode indices seen); surfaced via
  `FeedbackRecorder`/`FeedbackStateNotifier` and written into metadata.
- ✅ `SessionMetadata` now records `deviceName`, `deviceModel` (firmware tag
  "Classic"/"Athena"), `deviceId`, `recordedChannels` (labels, e.g.
  TP9/AF7/AF8/TP10), `recordedData` (stream names). Old files parse cleanly
  (missing keys → empty/null).
- ✅ History tile shows device model + `Nch TP9/…` line.
- ✅ Channel count is not hardcoded: an 8-electrode Crown works with zero
  format changes (electrode index is `i16`; names fall back to `CH{n+1}`).

## Status — 2026-08-08 Update (format v4 f32 + session overview)
- ✅ `.muse` body format bumped to **v4**: all float payloads (EEG/PPG/IMU/
  bands/movement/peak-alpha) now stored as **f32** instead of f64. Timestamps
  stay f64. Muse 12/14-bit and Crown 24-bit ADCs fit exactly in f32; f16 would
  lose them. Raw EEG drops ~8 KB/s→4 KB/s (~15 MB/hr raw → a few MB/hr zstd).
  **Not backward compatible** with v2/v3 files (pre-alpha, accepted). No FFI
  change — Dart events still arrive as doubles; only the on-disk layout moved.
- ✅ `SessionReader` only accepts v4; `_skipEeg/_skipImu/_skipPpg` counts and
  `_parseBands`/movement/peak-alpha reads updated to f32 widths.
- ✅ Bounded session overview: `lib/src/feedback/session_summary.dart`
  `SessionOverview` — decimates bands (per electrode), pulse, movement, and
  peak alpha into a fixed 400-bucket series regardless of session length, stored
  in the metadata JSON (`summary` key). History detail can render
  bands/HR/movement/peak without reading the `.muse` body. Computed at save in
  `FeedbackDashboardView._save` from `SessionData`; old files parse to null.

## Status — 2026-08-08 Update (per-pad line-noise fit + gesture detection)
- ✅ **Line-noise (fit) metric**: `BandsDto.line_noise_ratio` = fraction of
  spectral power in the 50/60 Hz mains bins (each averaged ±1 bin) of the
  existing per-second 256-point FFT (`hz_per_bin` = 1.0 → bins 50/60 exact).
  Zero new crates. Folded into `signalQuality` per-pad in
  `_maybeComputeSignalQuality`: ratios >~0.2 start to penalize, ~0.5 severe
  (cap −60%); `-1.0` sentinel until first Bands event.
- ✅ **Rust gesture detector**: `rust/src/analysis/gesture.rs` (`GestureDetector`,
  no DSP crates, all thresholds auto-adaptive EWMA). Blink = frontal pad (1,2)
  rectified-diff bin energy > `max(baseline×5, 100 µV)` w/ 500 ms refractory;
  jaw clench = posterior pad (0,3) gamma bursts > `baseline×3` (reuses per
  second FFT gamma); eye up/down = frontal−posterior mean shift
  `max(scale×2, 20 µV)` (experimental, default off). Fed raw EEG + gamma in the
  forwarder (`rust/src/api/muse.rs`), drains 1 Hz `MuseEventDto::Gestures`.
- ✅ **Dart wiring**: `_onGestures` gates the ATR clean-sample window (like the
  movement gate; `_sampleIsClean` requires both) and accumulates
  `GestureMarker`s only while `playing`: `doubleBlink` (≥2 in a report or two
  blink-seconds ≤2 s apart), `doubleClench` (two onsets ≤2 s), eye transitions
  (gated by `Settings.eyeMarkersEnabled`).
- ✅ **Metadata persistence**: markers persist under top-level metadata
  `gestures` (`SessionMetadata.gestures` / `GestureMarker` / `GestureType` in
  `session_store.dart`), written at save in `FeedbackDashboardView._save`; never
  in the `.muse` body (`encode_session_event` → empty record) and not a
  `RecordingStream`.
- ✅ **Settings toggles**: `eyeMarkersEnabled` (default off) + 
  `markersInFeedbackEnabled` (default on) with a "Gesture markers" card in
  Settings.
- ✅ `flutter_rust_bridge` codegen re-run; `flutter analyze lib/src` + `cargo check`
  clean; app built + launched on the TB336FU (streaming/scanning) — the adb
  link dropped mid-session, not a build failure.
- ⏳ **Thresholds unvalidated on real EEG**: `BLINK_*`/`CLENCH_*`/`EYE_*` constants
  in `gesture.rs` are initial guesses — need on-device tuning.

## Next steps
1. On-device test pass (checklist in `.ai/feeback/todos.md`): calibration →
   auto-start, chimes + movement gating, volume dialog, target settings,
   recalibrate, persistence, `[atr]` ceiling/lockout logs, mid-session Muse
   power-off → watchdog → auto-reconnect.
2. On-device gesture tuning: verify blink/clench double-marker timing and tune
   `BLINK_*`/`CLENCH_*`/`EYE_*` thresholds from logcat until double blinks and
   double clenches fire reliably without false positives; then decide if eye
   up/down becomes a live track.
3. If the reconnect test passes, remove the temporary `[muse] forwarder` debug
   logs or drop them to debug level.
4. v1.1 backlog: gesture marker log/rendering in history detail, percentile
   persistence, continuous EMA adaptation, multi-protocol presets, calibration
   audio variants (see `.ai/feeback/todos.md`).
5. v1.2 meta-block: Neurosity Crown 8-electrode support — channel labels are
   already metadata-driven; only the default channel-name list needs
   extending per device.

## How to verify (see testing-guide.md)
Run `flutter run`, observe status bar shows correct battery % (from `bp`,
not fuel gauge). Confirm via `adb logcat | grep muse` that no unexpected
crashes or stream deaths occur. Use debug log level to see raw telemetry:
`adb logcat -s rust_lib_muse_ml:*:*:D`.
