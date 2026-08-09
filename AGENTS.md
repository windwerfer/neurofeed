# AGENTS.md — Muse ML (Flutter + Rust BLE headset app)

Global orientation for any AI agent or contributor working in this repo.

## Stack
- **Flutter 3.41.7** (stable), Dart (bundled). UI layer.
- **Rust** via `flutter_rust_bridge` **2.11.1** (pinned `=`, both Rust crate and Dart package).
  - Rust lib: `rust/` (crate `rust_lib_muse_ml`).
  - Generated bindings: `rust/src/frb_generated.rs` is **gitignored** (commit `81a9f41` untracked it); Dart generated files ARE tracked.
- **muse-rs** (`github.com/eugenehp/muse-rs.git` tag `0.1.0`, `default-features = false`) — Muse BLE protocol + transport.
- **btleplug** — forked at `github.com/windwerfer/btleplug` (tag `0.12.0-muse-3`), patched with `get_env()` → `attach_current_thread_permanently()` fallback for tokio JNI threads + notification death spiral fix. **Source base is upstream 0.12.0 but `Cargo.toml` version is pinned to `0.11.8`** — required for semver matching (see `.ai/btleplug.md`).
  - Referenced via `[patch]` on `eugenehp/btleplug.git` so that BOTH
    `rust_lib_muse_ml` and `muse-rs` use the same patched copy (single
    `GLOBAL_JVM` static). Swap `[patch]` to local path for debugging.
- **`jni = "=0.19"`** — pinned to match btleplug's own `jni` dependency.
  If either side upgrades, both must be upgraded together or you get
  link-time symbol conflicts.
- **Android**: NDK 27/28, Gradle 8.14, `targetSdkVersion = 36`.
- **Decision:** using btleplug (forked) for BLE transport — consistent with
  `muse-rs`. `flutter_blue_plus` was the fallback if the JNI fix had failed.
- **JNI glue**: Kotlin `MainActivity.museAndroidInit()` → Rust `extern "C"` → `btleplug::platform::init()`. btleplug Java sources under `android/app/src/main/java/com/nonpolynomial/btleplug/`. jni-utils Java at `io/github/gedgygedgy/rust/`.
- **iOS/macOS**: not the current target; BLE transport uses btleplug's CoreBluetooth path.

## Core rules (do / don't)
- **NEVER** assume a library is available — check `Cargo.toml` / `pubspec.yaml` first.
- **NEVER** commit secrets/keys.
- **NEVER** add code comments unless explicitly asked.
- Do not run `git` commit/push/PR unless explicitly requested.
- When editing Rust under `rust/src/api/`, run `flutter_rust_bridge` codegen if the FFI surface changes, then `cargo check --target aarch64-linux-android` is NOT reliable in this sandbox (see Testing Guide) — rely on `flutter run` for the real compile.
- `flutter analyze lib/src` must stay clean after edits.
- Format changes land in `rust/src/api/session_format.rs`; keep `cargo test --lib session_format` green (golden wire-layout tests pin the byte format).

## Docs (`.ai/`)
| File | Contents |
|------|----------|
| `btleplug.md` | btleplug fork changes — what, why, pitfalls (version, Java alignment) |
| `bugreport.md` | Structured bug report for upstream btleplug (3 sections + suggestions) |
| `btleplug_bugreport_2.md` | Bug report #2: BLE notification stream silently dies (JNI death spiral) — fixed in `0.12.0-muse-3` |
| `architecture.md` | Current and target architecture, module map |
| `lessons-learned.md` | Full history of JNI attempts, what worked/failed |
| `testing-guide.md` | Build/test loop for the device |
| `release.md` | Release CI: per-platform workflows, keystore/secrets setup, F-Droid + reproducibility |
| `active-task.md` | Current development focus |

## Project layout
```
lib/src/                 # Flutter UI + Riverpod state
  connection_provider.dart  # AppStateNotifier: scan/connect state machine
  app.dart                 # main(), permission request
  connect_window.dart      # device list / rescan UI
  status_bar.dart, views/  # UI
lib/src/feedback/         # feedback session system (merged to main, Phase I)
  feedback_state.dart       # FeedbackStateNotifier: idle→calibrating→playing⇄paused→ended
  target_state.dart         # AtrEngine (threshold, dynamic adapt, in-flight recalibrate) + band aggregator
  live_stats.dart, protocol.dart, session_store.dart, feedback_recorder.dart
  session_storage.dart      # SessionStorage abstraction (FS + SAF), scratch dir, storage provider
  session_container.dart    # thin Dart wrapper over the Rust container format ([PNG][jsonLen][json][bodyLen][frames])
  session_summary.dart       # SessionOverview: 400-bucket decimated bands/pulse/motion/peak in metadata
lib/src/audio/            # just_audio: AudioService + FeedbackAudioController (5 volume channels)
rust/src/api/muse.rs    # FFI bridge: scan/connect/subscribe → MuseEvent stream + 1 Hz derived metrics
rust/src/api/session_format.rs  # SINGLE authority for .muse v4 + .muse.feedback byte layout (encode/parse/frames/container)
rust/src/analysis/gesture.rs  # GestureDetector (blink/clench/eye), auto-adaptive thresholds, no DSP crates
rust/src/connection.rs  # in-Rust state (active connection, device cache, sink)
android/app/src/main/java/
  com/nonpolynomial/btleplug/android/impl/  # btleplug Java classes
  io/github/gedgygedgy/rust/                # jni-utils Java sources
.ai/                     # project docs (feedback docs under .ai/feeback/)
.github/workflows/       # release CI per platform: release-android/linux/windows, repro-android, _build-apk (reusable)
scripts/package-linux.sh # deterministic tar.gz + best-effort AppImage packaging for release-linux
third_party/muse-rs/    # local checkout of muse-rs (tag 0.1.0) — reference for protocol/parse debugging
third_party/btleplug/   # local checkout of our btleplug fork (tag 0.12.0-muse-3) — reference for JNI/init debugging
muse-rs (dep, GitHub)   # transport (btleplug) + protocol
btleplug (via [patch], git tag 0.12.0-muse-3)  # patched fork; reference copy in third_party/btleplug/
```

## Where things live (for navigation)
- BLE scan/connect entry: `rust/src/api/muse.rs` (`scan`, `connect`, `subscribe_events`).
- JNI thread-attach patch: `../../btleplug/src/droidplug/jni/mod.rs` `get_env()`,
  plus callers in `adapter.rs` and `peripheral.rs`.
- btleplug Java init: `android/app/src/main/java/com/nonpolynomial/btleplug/android/impl/`.
- Kotlin init entry: `android/app/src/main/kotlin/com/example/muse_ml/MainActivity.kt`.
- Protocol decoders (pure, no BLE): inside muse-rs `parse.rs` / `protocol.rs` / `types.rs`.
- Permissions: `lib/src/app.dart` `requestBlePermissions()` (uses `permission_handler` + `device_info_plus` for sdk gating).
- Manifest BLE perms: `android/app/src/main/AndroidManifest.xml` (`BLUETOOTH_SCAN` w/ `neverForLocation`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION` capped `maxSdkVersion=30`).
- Feedback state machine: `lib/src/feedback/feedback_state.dart` (`FeedbackStateNotifier`, phases, interruption recovery).
- ATR engine (threshold, dynamic adapt, in-flight recalibrate): `lib/src/feedback/target_state.dart` (`AtrEngine`).
- Audio (dual-layer + 5 volume channels): `lib/src/audio/feedback_audio_controller.dart`, service in `lib/src/audio/audio_service.dart`.
- Gesture detection (blink / jaw clench / eye up-down): `rust/src/analysis/gesture.rs` (`GestureDetector`, auto-adaptive EWMA thresholds, no crates). Fed raw EEG + per-second FFT gamma in the forwarder (`rust/src/api/muse.rs`), emits 1 Hz `MuseEventDto::Gestures(GestureDto)`.
- Per-pad line-noise (fit/impedance proxy): `BandsDto.line_noise_ratio` (50/60 Hz mains power fraction of the existing per-second FFT), folded into `signalQuality` in `connection_provider.dart` `_maybeComputeSignalQuality`.
- Gesture markers persist in session **metadata** (`SessionMetadata.gestures`, `GestureMarker`/`GestureType` in `session_store.dart`); captured in `feedback_state.dart` `_onGestures`, written at save in `feedback_dashboard.dart` `_save`.
- Persisted prefs (volumes, sound, duration, target settings, gesture toggles): `lib/src/settings.dart` (`Settings`, SharedPreferences).
- Session storage abstraction (history in chosen folder; scratch in `.cache`; SAF on Android): `lib/src/feedback/session_storage.dart` (`SessionStorage`, `FileSystemSessionStorage`, `SafSessionStorage`, `resolveSessionStorage`, `sessionStorageProvider`). `SessionStore` is storage-backed; `sessionStoreProvider` is a `FutureProvider` derived from settings.
- Session file format (`.muse.feedback` = single self-contained file, PNG-first so Linux/macOS file managers thumbnail it; **Rust owns the layout**): `rust/src/api/session_format.rs` (`container_encode_bytes`/`container_parse_head_bytes`/`container_extract_body_bytes`/`container_head_read_limit`). Dart wrapper: `lib/src/feedback/session_container.dart` (`SessionContainer.encode`/`parseHead`/`extractBody`). Read sidecar-free: `SessionStore.list()`/`readPng()`/`readMuse()` read the head via `SessionStorage.readPrefix(name, limit)` and never pull the large body.
- **`.muse` body is format v4 (f32 floats), owned by Rust**: `session_format.rs` writes f32 payloads (EEG/PPG/IMU/bands/movement/peak-alpha) + f64 timestamps. Dart delegates: `SessionRecorder` (`lib/src/charts/session_recorder.dart`) buffers events and calls `encodeSessionEvent`/`sessionFrameBytes` (zstd v3); `SessionReader` (`lib/src/charts/session_reader.dart`) calls `sessionParseBody` and re-exports the generated `SessionData`/`BandsRecord`/… freezed records. Not backward compatible with v2/v3 f64 files (pre-alpha). Raw EEG ~4 KB/s (~15 MB/hr). Channel count is device-driven (`i16` electrode); an 8-ch Crown works with zero layout change.
- SAF folder picker + MethodChannel (`muse_ml/saf`): `android/app/src/main/kotlin/com/example/muse_ml/MainActivity.kt` (`getDir`/`ensureDir`/`writeFile`/`writeFileAtomic`/`readFile`/`readFilePrefix`/`deleteFile`/`listFiles`).
- Folder selection UI: `lib/src/views/settings_view.dart` (`file_selector` `getDirectoryPath` on desktop, `SafSessionStorage.pickFolder()` on Android).
- Release CI: `.github/workflows/` — see `.ai/release.md` (keystore secrets, F-Droid, reproducibility).
- Rust toolchain pin: `rust/rust-toolchain.toml` (kept in sync with `FLUTTER_VERSION`/`RUST_VERSION` in the workflows).

## Known hot spots
- **Session format is Rust-owned**: never edit the `.muse`/`.muse.feedback` byte layout in Dart. `rust/src/api/session_format.rs` is the single authority — `encode_session_event`, `sessionFrameBytes`, `sessionParseBody`, and the container fns; Dart (`session_recorder.dart`, `session_reader.dart`, `session_container.dart`) are thin FFI delegates. Some container fns are `#[frb(sync)]` so Dart keeps `headReadLimit`/`parseHead`/`extractBody` synchronous. When changing the wire format, extend `cargo test --lib session_format` goldens and regenerate bindings.
- **Cargo `[patch]` version trap**: If the patched crate's `version` is semver-incompatible with the dependency constraint, Cargo silently ignores the patch. Our fork must stay at `version = "0.11.8"` even though the source is based on 0.12.0.
- **Android BLE init**: btleplug requires `btleplug::platform::init(&JNIEnv)` from a JNI context BEFORE any scan/connect, or it panics with `"Droidplug has not been initialized"`.
- **JNI `ThreadDetached`**: BLE ops run on tokio worker threads which aren't attached to the JVM. Our `get_env()` patch auto-attaches them.
- **Java/Rust API alignment**: The Rust code expects Java method signatures from btleplug 0.12.0. If upgrading either side, check `jni/objects.rs` vs the Java source files.
- **Event forwarder reconnect + watchdog**: the forwarder (`rust/src/api/muse.rs`) polls `guard.events` every 1 s — a reconnect stores a fresh channel there, so it switches within ~1 s even if the old channel lingers. If a live connection produces no events for 30 s it emits `Disconnected` so the app reconnects (a dead BLE link often never delivers a disconnect event). **Never use `tokio::sync::watch::changed()` on a receiver cloned from an unpolled primary**: the clone inherits the primary's stale last-seen version and fires spuriously — commit `3078904` broke all streaming this way; fixed in `53e3e8f` by reverting to the 1 s poll.
- **Auto-scan only on saved device**: on fresh launch with no `lastDeviceId`, `_init()` opens the connect window but does NOT scan. Scan only fires on Rescan button or autoconnect to a known device.
- **JNI trace spam**: The `jni` crate logs `trace!()` for every JNI call. `android_logger` filters at `Debug` level, but if it's initialized after another logger (e.g. flutter_rust_bridge), `init_once` fails silently and the filter doesn't apply. The fix: always call `log::set_max_level(log::LevelFilter::Debug)` after `init_once` as a fallback. See `rust/src/api/muse.rs:init_app()`.
- **QueueStream race condition**: `QueueStream.java:pollNext()` returned a lambda that called `this.result.remove()` **outside** the `synchronized` block. Two tokio workers could both poll the same stream, both see a non-empty queue, both get removal lambdas, and one would crash with `NoSuchElementException` when the other had already drained it. **Fix**: remove the value from the queue inside the synchronized block and return a closure over the already-removed value. See `android/app/src/main/java/io/github/gedgygedgy/rust/stream/QueueStream.java:31`.
- **Epoch window is events, not seconds**: band events arrive ~10 Hz, so `AtrEngine.epochWindow = 300` ≈ 30 s of feedback. `successRate` stays null until the window fills (first adapt ~30 s in). A `success == 0.0` window triggers the circuit breaker → threshold resets to the baseline percentile.
- **Adaptive lockout guards**: ceiling = `baselineMean + 1.5·baselineStddev`, floor = baseline percentile; steps are responsiveness-derived (raise 1.01–1.03, lower 0.97–0.90). After an in-flight recalibrate the baseline is replaced, so the ceiling re-anchors automatically. Turn dynamic adapt off via the target-settings dialog for a fully static threshold.
- **In-flight recalibrate** (refresh icon during playing/paused): needs ≥ `minRecalibrateSeconds` (60) session time and ≥ `minRecalibrateSamples` (30) clean samples from the 90 s rolling buffer; replaces the baseline, resets the success window, plays a soft low bowl chime. Full silent recalibration is still available by starting a new session (Start Session → calibrating).
- **5 volume channels**: effective = master × channel (background / feedback / intro / end bell). Chimes start at full volume (no attack ramp); in-flight chime players skip `setVolume` re-apply (`_ramping` set). Values persist via `Settings`.
- **Persistence**: all user prefs flow through `Settings` (SharedPreferences); `settingsProvider` is overridden in `main()`. Sound + duration are restored into `FeedbackState` at notifier construction.
- **Storage resolution is async**: `sessionStorageProvider` (FutureProvider) derives from `settings.sessionFolder`. A `content://` value → `SafSessionStorage`; any other non-empty string → filesystem path; null/empty → default (`Documents/meditation feedback` on desktop, app documents on Android). `SessionStore` and `sessionListProvider` are also `FutureProvider`s — always use `ref.read(sessionStoreProvider.future)`.
- **SAF is history-only, never live**: live EEG streaming (88 pkt/s, 30 s flushes) always goes to scratch — `scratchDirectory()` is `root/.cache` for filesystem, app-private cache for SAF. SAF is only touched on Save via `SafSessionStorage` (one ContentResolver write per call). The recorder (FeedbackRecorder → SessionRecorder) always writes to scratch and the dashboard publishes the finished session into history on Save.
- **`.muse.feedback` is single-file, head-read on history**: `list()`/`readPng()` must only call `readPrefix(name, SessionContainer.headReadLimit)` and parse the container head — never `readFile` (it pulls the whole body). The history detail (`feedback_dashboard.dart`) renders from `SessionMetadata.summary` (`SessionOverview`, 400 buckets) when present — it only falls back to `readMuse()` (full body parse) for legacy sessions lacking a summary. When adding a summary field, put it in the metadata json, not a sidecar. The summary charts (Bands + Alpha-vs-Theta + Movement + HR) share one zoom viewport (`_ChartViewport`): drag to pan, pinch on touch, **ctrl/⌘+scroll on desktop** (plain wheel scrolls the page — gated via `HardwareKeyboard` in `_onSignal`), double-tap resets. Legend rows toggle each series (`_hidden` set). Bands/Alpha-vs-Theta use fixedY 0–1 (relative power) with numeric ticks — comparable across sessions; Movement/HR auto-scale.
- **Desktop default dir**: when `getApplicationDocumentsDirectory()` (Linux shells to `xdg-user-dir DOCUMENTS`) fails, fall back to `$HOME/Documents`, creating the folder chain on first recording — **never** fall back to `/tmp` or users won't find their files. Changing the save folder **moves** sessions (`SessionStore.moveAllTo`), it does not copy.
- **Signal gate + autodrop model** (`lib/src/feedback/`): the "how good the headband fit is" concept is a *list of 4 per-pad quality scores* (`AppUiState.signalQuality`, 0–100, from EEG std + `BandsDto.line_noise_ratio`), separate from the *bands data* actually used to compute ATR. Intention (reused by future feedback options):
  - **Before calibration**: all 4 pads must be green (`≥ signalGoodThreshold`) for `greenStableSeconds` (3) continuously, tracked by a 1 s `_gateTimer` in the notifier. Only the frontal program pads `neededElectrodes=[1,2]` (AF7/AF8) really matter; a pad stuck non-green for `faultyPadSeconds` (20) while AF7/AF8 are green ⇒ it's assumed faulty → show an inline "Continue anyway" bubble (tier A = both AF7+AF8 green "enough electrodes"; tier B = ≥1 "reduced accuracy").
  - **No gate after calibration**: `_finishCalibration` always calls `startPlaying()` — a finished baseline never re-locks on signal. There is no longer any signal check between "baseline done" and "feedback starts".
  - **Playing bad signal**: pauses (interrupted) only when all needed [1,2] pads go below `signalCriticalThreshold` (40) for `badSignalPauseSeconds` (10); a *rear* pad (0/3) going bad does NOT pause. A signal loss **never auto-ends** (no countdown); it resumes automatically once any needed pad is green again (`_hasNeededElectrode`).
  - **Autodrop in ATR**: `TargetStateAggregator.evaluate(quality)` (`lib/src/feedback/target_state.dart`) averages only the AF7/AF8 pads whose quality `≥ atrUsableSignalThreshold` (=80, kept in sync with `signalGoodThreshold`); a bad pad is dropped per-sample rather than corrupting the average. If BOTH AF7/AF8 are bad, `evaluate()` returns null → no feedback that sample.
- **Line-noise fit metric**: `BandsDto.line_noise_ratio` = fraction of total spectral power in the 50/60 Hz mains bins (each averaged over a ±1 bin window) of the per-second 256-point FFT (`compute_fft_bands` in `rust/src/api/muse.rs`; `hz_per_bin` = 1.0 so bins 50/60 are exact). Folded into `signalQuality` in `connection_provider.dart` `_maybeComputeSignalQuality`: ratios above ~0.2 start to penalize a pad, ~0.5 is severe (capped −60% of the std-derived score). `_lineNoise` uses a `-1.0` sentinel for "no Bands yet" (no penalty) and resets on disconnect.
- **Gesture detector** (`rust/src/analysis/gesture.rs`): all thresholds are auto-adaptive EWMA baselines — no per-user calibration. Blink = frontal pad (1,2) rectified-diff bin energy (125 ms bins) above `max(baseline×5, 100 µV)` with ~500 ms refractory; jaw clench = posterior pad (0,3) gamma bursts > `baseline×3` (gamma fed from the FFT once per second); eye up/down = frontal−posterior mean deviation > `max(scale×2, 20 µV)` — **experimental, off by default**. Baselines only adapt while quiet so a sustained clench/gaze doesn't become the new "normal". Tune `BLINK_*` / `CLENCH_*` / `EYE_*` constants once real-device data is available.
- **Gesture markers are metadata-only**: `MuseEventDto::Gestures` is never written to the `.muse` body (`encode_session_event` → empty record) and `GestureDto` is not a `RecordingStream`. `GestureMarker`s (type + session-offset seconds) accumulate in `FeedbackStateNotifier` only while `playing`, and persist under the top-level metadata `gestures` key (gated by `Settings.markersInFeedbackEnabled`; eye transitions additionally gated by `Settings.eyeMarkersEnabled`). `doubleBlink` = ≥2 blinks in one 1 Hz report or two blink-seconds ≤2 s apart; `doubleClench` = two clench onsets ≤2 s apart.
- **Blink/clench gate ATR cleanliness**: `_onGestures` stamps `_lastGestureAt`; `_sampleIsClean` (`feedback_state.dart`) requires BOTH the movement buffer and the gesture buffer to be ≥ `movementBuffer` (1 s) old — used for the calibration baseline samples and the rolling clean ATR window.
- **All session writes are crash-safe**: `SessionStore.publishSession`/`updateNotes`/`moveAllTo` (`session_store.dart`) all write via `SessionStorage.writeFileAtomic` (`session_storage.dart`). Filesystem = `.name.tmp` sibling + `rename()` (atomic on POSIX); SAF = native `writeFileAtomic` (`MainActivity.kt`) writes `name.mtmp`, deletes old, `renameDocument`, and `recoverDoc()` heals an interrupted swap — it runs on every read *and* during `listFiles` (a first pass heals any orphaned `.mtmp` so a recovered session reappears in listings; surviving `.mtmp` leftovers are skipped). The dashboard (`feedback_dashboard.dart`) shows a corner save chevron only when notes are dirty, a spinner while saving, and a brief check flash after; a `PopScope` intercepts back with an "Unsaved notes" Save/Stay/Discard dialog in the read-only history view.
