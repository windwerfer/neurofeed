# AGENTS.md — Muse ML (Flutter + Rust BLE headset app)

Global orientation for any AI agent or contributor working in this repo.

## Stack
- **Flutter 3.41.7** (stable), Dart (bundled). UI layer.
- **Rust** via `flutter_rust_bridge` **2.11.1** (pinned `=`, both Rust crate and Dart package).
  - Rust lib: `rust/` (crate `rust_lib_muse_ml`).
  - Generated bindings: `rust/src/frb_generated.rs` and the Dart files under
    `lib/src/rust/` are **both tracked in git** (the Rust glue was re-tracked in
    commit `7543478`: nothing in CI runs `flutter_rust_bridge_codegen generate`,
    so a fresh checkout had no `frb_generated.rs` and cargokit's `cargo build`
    failed with `E0583`). Regenerate with `flutter_rust_bridge_codegen generate`
    whenever the FFI surface changes and commit **both** sides. Keep the codegen
    CLI, Rust crate, and Dart package pinned to the same `2.11.1`.
- **muse-rs** (`github.com/eugenehp/muse-rs.git` tag `0.1.0`, `default-features = false`) — Muse BLE protocol + transport.
- **btleplug** — forked at `github.com/windwerfer/btleplug` (tag `0.12.0-muse-3`), patched with `get_env()` → `attach_current_thread_permanently()` fallback for tokio JNI threads + notification death spiral fix. **Source base is upstream 0.12.0 but `Cargo.toml` version is pinned to `0.11.8`** — required for semver matching (see `.ai/btleplug.md`).
  - Referenced via `[patch]` on `eugenehp/btleplug.git` so that BOTH
    `rust_lib_muse_ml` and `muse-rs` use the same patched copy (single
    `GLOBAL_JVM` static). Swap `[patch]` to local path for debugging.
- **`jni = "=0.19"`** — pinned to match btleplug's own `jni` dependency.
  If either side upgrades, both must be upgraded together or you get
  link-time symbol conflicts.
- **REVE + LUNA local model engine** (AI sleep guardrail, layered): `reve-rs` + `luna-rs`
  (git deps — `reve-rs` from upstream `eugenehp` untouched, `luna-rs` from the `windwerfer`
  fork — RLX CPU backend) score drowsiness on-device
  from raw EEG. **No weights are shipped**: LUNA (Apache-2.0) downloads from HF with
  SHA-256 verification; REVE (gated) is user-imported. FFI: `rust/src/api/reve.rs`
  (`model_load`/`model_unload`/`model_loaded`/`model_config_json` +
  `guardrail_enable`/`guardrail_disable`/`guardrail_reset_anchors`/`guardrail_capture_anchor`/
  `guardrail_live_dim`); inference lives in
  `rust/src/analysis/{reve,luna}.rs`; cache + UI in `lib/src/reve/`.
  Protocols compose a reward engine (`RewardMetric`, ATR today) with the guardrail
  layer (`ProtocolInfo.guardrailDefault`/`guardrailAllowed`/`guardrailFeedback` +
  `Settings.guardrailEnabledFor`); the guardrail only warns, it never modulates
  the reward, and it is offered for every protocol except the eyes-open one
  (`guardrailAllowed: false`). Calibration definitions live in
  `assets/calibrations.json` (v2): each id (today `eyes-closed-01` /
  `eyes-open-01`) is an eye-state with **both** playable variants — `single`
  (one random intro + one silent baseline window) and `staged` (fixed 3-part
  guardrail sequence: artifacts / eyes-open challenge / eyes-closed rest).
  `assets/protocols.json` maps each protocol one-to-one to a calibration id
  (`calibration` field; every closed-eyes protocol uses `eyes-closed-01`,
  only `alertnessOpen` uses `eyes-open-01`). `CalibrationManifest.recipeFor`
  picks the variant by guardrail engine: **AI model ready → staged, band math
  / no guardrail → single** (`_stagedCalibrationIntent` in
  `feedback_state.dart`). Two protocols are
  **non-reward**: `recordOnly` (pure recording, calibration skippable via the
  "Start (skip calibration)" button — `startCalibration(skipCalibration:)`
  goes straight to playing) and `guardrailOnly` (3-stage guardrail
  calibration, warnings only, no feedback-sound selection — `hasReward: false`
  hides the feedback tile and gates the ATR reward path in `_onBands` while
  the guardrail layer keeps running).
- **Protocol copy lives in `assets/protocols.json`** (catchPhrase/title/
  subtitle/guideText/algorithmDescription/expectedDelay/`metadataDescription`
  — the scientific text recorded into every `.feedback` file's metadata) —
  the single editable text source, loaded via `protocolCatalogProvider`
  (`lib/src/feedback/protocol_catalog.dart`; `useProtocolCopy(ref, info)`
  reads JSON only — there is **no Dart fallback** and no generator/regenerate
  step; validate the asset with `flutter test test/calibration_assets_test.dart`,
  which checks every protocol's copy + `metadataDescription` + that its
  `calibration` id exists in `calibrations.json` with real audio files).
  Structure (colors, metrics, conditions, guardrail flags,
  `hasReward`, `calibrationSkippable`) stays in `ProtocolInfo`.
  The protocol list's
  "Recent" tile (3 most recent distinct protocols, catch name only) comes
  from `sessionListProvider`.
- **Android**: NDK 27/28, Gradle 8.14, `targetSdkVersion = 36`.
- **Decision:** using btleplug (forked) for BLE transport — consistent with
  `muse-rs`. `flutter_blue_plus` was the fallback if the JNI fix had failed.
- **JNI glue**: Kotlin `MainActivity.museAndroidInit()` → Rust `extern "C"` → `btleplug::platform::init()`. btleplug Java sources under `android/app/src/main/java/com/nonpolynomial/btleplug/`. jni-utils Java at `io/github/gedgygedgy/rust/`.
- **iOS/macOS**: not the current target; BLE transport uses btleplug's CoreBluetooth path.
- **Windows**: not a current dev target; built only by `release-windows.yml` CI. `windows/CMakeLists.txt` is committed (carries an MSVC workaround), but the rest of `windows/` is generated in CI via `flutter create --platforms=windows .`.

## Core rules (do / don't)
- **NEVER** assume a library is available — check `Cargo.toml` / `pubspec.yaml` first.
- **NEVER** commit secrets/keys.
- **NEVER** add code comments unless explicitly asked.
- Do not run `git` commit/push/PR unless explicitly requested.
- When editing Rust under `rust/src/api/`, run `flutter_rust_bridge` codegen if the FFI surface changes (then commit both `rust/src/frb_generated.rs` and the Dart files under `lib/src/rust/`); `cargo check --target aarch64-linux-android` is NOT reliable in this sandbox (see Testing Guide) — rely on `flutter run` for the real compile.
- `flutter analyze lib/src` must stay clean after edits.
- Format changes land in `rust/src/api/session_format.rs`; keep `cargo test --lib session_format` green (golden wire-layout tests pin the byte format).
- `reve-rs`/`luna-rs` are **git dependencies** (like `muse-rs`/`btleplug`): `reve-rs` from
  upstream `eugenehp/reve-rs` at rev `9c8d856…` (unchanged upstream), `luna-rs` from the
  `windwerfer` fork at tag `v0.0.4-latent-embedding-fix` (latent-embedding fix). `third_party/`
  keeps reference checkouts of both, but cargo fetches from GitHub directly — no submodule
  init is needed to build. Bump the tag/rev in `rust/Cargo.toml` when either advances.

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
  connect_window.dart      # ConnectOverlay: tap-anywhere barrier + device list / rescan UI
  status_bar.dart, views/  # UI
    views/music_settings_panel.dart  # shared music-feedback options (folder / cutoff / invert / shuffle) — used by Settings music card AND session bubble, don't fork it
lib/src/feedback/         # feedback session system (merged to main, Phase I)
  feedback_state.dart       # FeedbackStateNotifier: idle→calibrating→playing⇄paused→ended
  target_state.dart         # AtrEngine (threshold, dynamic adapt, in-flight recalibrate) + band aggregator
  live_stats.dart, protocol.dart, session_store.dart, feedback_recorder.dart
  session_storage.dart      # SessionStorage abstraction (FS + SAF), scratch dir, storage provider
  session_container.dart    # thin Dart wrapper over the Rust container format ([PNG][jsonLen][json][bodyLen][frames])
  session_summary.dart       # SessionOverview: 400-bucket decimated bands/pulse/motion/peak in metadata
  session_chart_data.dart   # shared chart preparation (SessionChartData/Stats) — used by the dashboard AND the exporters so PNG/PDF match the screen
  session_export.dart       # history multi-export: SessionExporter (CSV Mind Monitor / EDF+ / PNG thumbnail+charts via offscreen rasterizer), ExportChart painter, resolveExportStorage (Android non-SAF → pickFolder), writes under <root>/export/
  session_pdf_export.dart   # vector PDF per session (pdf pkg, pw.CustomPaint charts, buildPdfPage)
lib/src/audio/            # flutter_soloud (SoLoud engine): AudioService façade + FeedbackAudioController (chime/ambient) + MusicFeedbackController (folder via reward-driven low-pass) + GuardrailSound (warning-sound set incl. continuous volume-ramped alarm) + BinauralBeatController (two synth voices, carrier/beat beat-frequency pair, reward-swelled) + 3-stage calibration clips + SoLoudEngine (single-flight init, stable/low-latency profile, reinit for the "Reduce audio stutter" setting)
lib/src/reve/            # guardrail AI model engine: ModelKind metadata, ModelCache (SHA-256-verified download/import), ModelEngineNotifier, shared UI (ModelSelectorDropdown / ModelInstalledCheck / ModelInstallBubble — reused by the guardrail dialog) + settings AiEngineCard + gated-file import
lib/src/streaming/      # network streaming tab: StreamingController (riverpod, subscribes to the Muse event stream, mixes per-group channels, starts on connect / stops on disconnect), StreamingMixer (per-channel queues → lockstep rows), OscStreamer (unicast UDP, batched per-chunk messages, `oscEncodeMessage`), LslStreamer (via the `liblsl` pub package — auto-discovered, no IP/port), BrainflowStreamer (multicast UDP "Streaming Board" datagrams, default + auxiliary IMU + ancillary PPG presets; separate-groups mode streams IMU/PPG on port+1/+2), StreamingConfig built from Settings (osc/lsl/brainflow keys; OSC IP auto-filled from the local subnet), StreamIndicator/StreamDot (green live / amber armed badge in sidebar + status bar); tested end-to-end over real loopback sockets in test/streaming_osc_test.dart
rust/src/api/muse.rs    # FFI bridge: scan/connect/subscribe → MuseEvent stream + 1 Hz derived metrics
rust/src/api/reve.rs    # model FFI: model_load / model_unload / model_loaded / model_config_json + guardrail_enable/disable/reset_anchors/capture_anchor/live_dim
rust/src/api/session_format.rs  # SINGLE authority for .muse v4 + .muse.feedback byte layout (encode/parse/frames/container)
rust/src/api/edf_export.rs  # EDF+ FFI wrapper: encode_edf_export (parsed SessionData → EDF+ bytes, sample-rate estimate, gap-fill, calibration/gesture annotations)
rust/src/analysis/gesture.rs  # GestureDetector (blink/clench/eye), auto-adaptive thresholds, no DSP crates
rust/src/analysis/{reve,luna}.rs  # RLX CPU inference wrappers over reveal-rs/luna-rs; #[ignore]d smoke tests need .local/ weights
rust/src/connection.rs  # in-Rust state (active connection, device cache, sink)
android/app/src/main/java/
  com/nonpolynomial/btleplug/android/impl/  # btleplug Java classes
  io/github/gedgygedgy/rust/                # jni-utils Java sources
.ai/                     # project docs (feedback docs under .ai/feeback/)
.github/workflows/       # release CI per platform: release-android/linux/windows, repro-android, _build-apk (reusable)
scripts/package-linux.sh # deterministic tar.gz + best-effort AppImage packaging for release-linux
third_party/muse-rs/    # local checkout of muse-rs (tag 0.1.0) — reference for protocol/parse debugging
third_party/btleplug/   # local checkout of our btleplug fork (tag 0.12.0-muse-3) — reference for JNI/init debugging
third_party/{reve-rs,luna-rs}/  # reference checkouts of the model-engine forks — cargo builds from the git deps in rust/Cargo.toml
third_party/brainflow/  # reference checkout of brainflow (tag 5.9.0) — NOT a build dep; only for the Muse "Streaming Board" wire format (exact datagram size, f64 LE doubles, no header, batch=3 samples/packet)
third_party/edf_export/ # local EDF+ writer crate (path dep in rust/Cargo.toml) — hand-rolled EDF+ writer with golden byte-layout tests; TODO: push to user GitHub and switch to a git+tag dep
vendor/rlx-cpu/         # committed vendored copy of rlx-cpu 0.2.13 (patched: no default `blas`), wired via [patch.crates-io]
.local/                 # LOCAL-ONLY, never committed: luna-base-dl/, reve-base-dl/ (gated model weights), reve-base/ (abandoned fork). Each is an embedded git repo with no remote — see .gitmodules (`ignore = all`, invalid URL) + smoke-test paths `rust/src/analysis/{luna,reve}.rs`
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
- Connect window: `ConnectOverlay` (`lib/src/connect_window.dart`) is a tap-anywhere barrier + device list/rescan panel; both `AppShell` (main view) and `FeedbackSessionView` (session route) host their own copy so the session screen can reconnect without leaving the session.
- Feedback state machine: `lib/src/feedback/feedback_state.dart` (`FeedbackStateNotifier`, phases, interruption recovery).
- ATR engine (threshold, dynamic adapt, in-flight recalibrate): `lib/src/feedback/target_state.dart` (`AtrEngine`).
- Audio (dual-layer + 5 volume channels incl. guardrail warning): `lib/src/audio/feedback_audio_controller.dart`, service in `lib/src/audio/audio_service.dart`; music feedback (user folder through a reward-driven low-pass filter) in `lib/src/audio/music_feedback_controller.dart` (`MusicFeedbackController`, per-voice biquad, EMA slew, guardrail muffle); binaural option in `lib/src/audio/binaural_beat_controller.dart` (`BinauralBeatController`, two synth voices, carrier/beat beat-frequency pair, reward-swelled). Engine profile + reinit in `lib/src/audio/soloud_engine.dart` (`SoLoudEngine.ensureInit`/`reinit`/`deinit`): conservative ("Reduce audio stutter") vs low-latency, synced from `Settings.audioStableMode` at every session start (Android only).
- Gesture detection (blink / jaw clench / eye up-down): `rust/src/analysis/gesture.rs` (`GestureDetector`, auto-adaptive EWMA thresholds, no crates). Fed raw EEG + per-second FFT gamma in the forwarder (`rust/src/api/muse.rs`), emits 1 Hz `MuseEventDto::Gestures(GestureDto)`.
- Per-pad line-noise (fit/impedance proxy): `BandsDto.line_noise_ratio` (50/60 Hz mains power fraction of the existing per-second FFT), folded into `signalQuality` in `connection_provider.dart` `_maybeComputeSignalQuality`.
- Gesture markers persist in session **metadata** (`SessionMetadata.gestures`, `GestureMarker`/`GestureType` in `session_store.dart`); captured in `feedback_state.dart` `_onGestures`, written at save in `feedback_dashboard.dart` `_save`.
- Session metadata records the full repro context (`session_store.dart`): `SessionCalibration` (v2) carries the calibration `calibrationId` + the immutable `calibrationJson` snapshot (both variants, from `assets/calibrations.json` at session time), the baseline statistics, the per-phase clip timings, and `recalibrations` (every in-flight recalibrate with its timestamp + new baseline stats — appended in `feedback_state.dart` `recalibrate()`); `SessionMetadata.metadataDescription` is the protocol's scientific text from `assets/protocols.json`; `SessionMetadata.sessionSettings` (`SessionSettings`) snapshots the session-affecting settings (dynamic adapt, responsiveness, baseline percentile, guardrail engine/band-math, warning threshold + sound, music/binaural options, gesture-marker toggles) — captured in `feedback_dashboard.dart` `_captureSessionSettings`.
- Persisted prefs (volumes, sound, duration, target settings, gesture toggles, music folder/cutoff/invert/shuffle, binaural preset/carrier/beat, audio-stable mode): `lib/src/settings.dart` (`Settings`, SharedPreferences).
- Session storage abstraction (history in chosen folder; scratch in `.cache`; SAF on Android): `lib/src/feedback/session_storage.dart` (`SessionStorage`, `FileSystemSessionStorage`, `SafSessionStorage`, `resolveSessionStorage`, `sessionStorageProvider`). `SessionStore` is storage-backed; `sessionStoreProvider` is a `FutureProvider` derived from settings.
- Session file format (`.muse.feedback` = single self-contained file, PNG-first so Linux/macOS file managers thumbnail it; **Rust owns the layout**): `rust/src/api/session_format.rs` (`container_encode_bytes`/`container_parse_head_bytes`/`container_extract_body_bytes`/`container_head_read_limit`). Dart wrapper: `lib/src/feedback/session_container.dart` (`SessionContainer.encode`/`parseHead`/`extractBody`). Read sidecar-free: `SessionStore.list()`/`readPng()`/`readMuse()` read the head via `SessionStorage.readPrefix(name, limit)` and never pull the large body.
- **`.muse` body is format v4 (f32 floats), owned by Rust**: `session_format.rs` writes f32 payloads (EEG/PPG/IMU/bands/movement/peak-alpha) + f64 timestamps. Dart delegates: `SessionRecorder` (`lib/src/charts/session_recorder.dart`) buffers events and calls `encodeSessionEvent`/`sessionFrameBytes` (zstd v3) — filtered per-stream by `Settings.recordStreams`; `SessionReader` (`lib/src/charts/session_reader.dart`) calls `sessionParseBody` and re-exports the generated `SessionData`/`BandsRecord`/… freezed records. Not backward compatible with v2/v3 f64 files (pre-alpha). Raw EEG ~4 KB/s (~15 MB/hr). Channel count is device-driven (`i16` electrode); an 8-ch Crown works with zero layout change.
- History multi-export (PDF / PNG / CSV / EDF+): `lib/src/feedback/session_export.dart` (`SessionExporter` — CSV Mind Monitor / EDF+ via `encodeEdfExport` / PNG thumbnail+charts via the offscreen rasterizer / PDF delegation; `resolveExportStorage` → Android non-SAF prompts `SafSessionStorage.pickFolder()` for that export only), `lib/src/feedback/session_pdf_export.dart` (`buildPdfPage`, `pdf` pkg), shared chart prep in `session_chart_data.dart`; EDF+ writer crate at `third_party/edf_export/` (path dep) + FFI wrapper `rust/src/api/edf_export.rs`.
- SAF folder picker + MethodChannel (`muse_ml/saf`): `android/app/src/main/kotlin/com/example/muse_ml/MainActivity.kt` (`getDir`/`ensureDir`/`writeFile`/`writeFileAtomic`/`readFile`/`readFilePrefix`/`deleteFile`/`listFiles`).
- Folder selection UI: `lib/src/views/settings_view.dart` (`file_selector` `getDirectoryPath` on desktop, `SafSessionStorage.pickFolder()` on Android).
- Local model engine (AI sleep guardrail): FFI in `rust/src/api/reve.rs` (`model_load`/`model_unload`/`model_loaded`/`model_config_json` + `guardrail_*`); inference wrappers in `rust/src/analysis/{reve,luna}.rs`; Dart download/import/verify/load in `lib/src/reve/model_engine.dart` (`ModelCache`, `ModelEngineNotifier`), model metadata in `lib/src/reve/models.dart` (`ModelKind`), shared UI in `lib/src/reve/model_selector.dart` (`ModelSelectorDropdown` with green installed-checks, `ModelInfoBlock`, `ModelInstallBubble` download/import bubble), settings card in `lib/src/reve/reve_card.dart` (`AiEngineCard`), gated-file import in `lib/src/reve/reve_import.dart`.
- Feedback session dialogs (`lib/src/views/feedback_session.dart`): target settings (dynamic adapt toggle, gentle↔responsive slider, reward-threshold percentile slider), guardrail gear (scorer-engine dropdown w/ installed checks + inline download bubble, warning-sound dropdown, warning-threshold slider), music sub-tile + bubble (drop-in `MusicSettingsPanel`/`pickMusicFolder`/`musicFolderLabel` from `lib/src/views/music_settings_panel.dart` — same options as the Settings music card), binaural sub-tile, volume + duration dialogs. The guardrail gear is per-protocol: `ProtocolInfo.guardrailAllowed` off (eyes-open) hides the whole card. Music + AI guardrail is allowed with a one-time stutter warning that fires **at choice time** via the shared `_maybeWarnMusicAiCpu` helper (picking music while an AI scorer is active, or an AI scorer while music is selected) — pointing at Settings → Audio → "Reduce audio stutter".
- Release CI: `.github/workflows/` — see `.ai/release.md` (keystore secrets, F-Droid, reproducibility).
- Rust toolchain pin: `rust/rust-toolchain.toml` (kept in sync with `FLUTTER_VERSION`/`RUST_VERSION` in the workflows).

## Known hot spots
- **Never put a `LayoutBuilder` inside dialog content**: AlertDialog sizes its content via `IntrinsicWidth`, and `LayoutBuilder` cannot return intrinsic dimensions — every such widget throws `LayoutBuilder does not support returning intrinsic dimensions` when the dialog opens (commit `bb51897` fixed this in the percentile sliders). Position against a fraction of the width with `Align`/`FractionallySizedBox` instead.
- **Model install UI is shared, don't fork it**: the guardrail gear dialog and the settings `AiEngineCard` use the same `ModelInstalledCheck`/`ModelInstallBubble` widgets (`lib/src/reve/model_selector.dart`) — one owns the download/import/progress state, the other renders it. The scorer-engine dropdown shows green checks for installed models and always-checks band math (the no-AI fallback engine).
- **Range sliders are log-space for cutoffs, but the label shows a rounded value**: `_MusicSettingsDialog` maps the 220–16000 Hz slider range to log space (`2220^(x/120)`), so dragging feels proportional and the cutoff label is `label.round()`. When copying a cutoff into the code (e.g. tests or hardcoded presets), compute it via the same formula or copy the `label.round()` from the running UI — never copy a raw slider position or a log-domain value directly.
- **Don't wrap a bounded `DecoratedBox` around a `ListTile`'s `subtitle` (Material ink assertion)**: commit `54641b3` fixed `feedback_session.dart`'s `_MusicTile` — an opaque `DecoratedBox` inside the tile's `subtitle` broke the subtitle text style and could trigger the `No Material widget found` ink assertion on hover. Put the styling on the tile itself (e.g. `ListTile(shape: ...)`) and wrap custom tiles in `Material` if they take a `thumbColor`.
- **The connect overlay must exist in every view with a status bar**: `ConnectOverlay` provides both the indicator and the tap-to-interrupt barrier — `AppShell` (main view) and `FeedbackSessionView` (session route) each host their own copy. Forgetting it in a new view leaves the session screen unable to reconnect mid-session.
- **flutter_soloud Linux Xiph libs are glibc-2.43-built**: the plugin bundles precompiled `libopus.so.0`/`libogg`/`libvorbis`/`libflac` that fail to load on Debian trixie/Ubuntu 24.04 (`version GLIBC_2.43 not found` when opening `libflutter_soloud_plugin.so`). Build with `TRY_SYSTEM_LIBS_FIRST=1` and `libopus-dev libogg-dev libvorbis-dev libflac-dev` installed (devcontainer + `release-linux.yml` already do this) so CMake links the system Xiph libs instead. On a fresh checkout remember the env var, or the sound engine crashes at first play.
- **Container has no ALSA card — route ALSA default → PulseAudio**: flutter_soloud's Linux backend is ALSA, but the devcontainer has no `/dev/snd` and plays through the host PipeWire socket (`PULSE_SERVER=unix:/tmp/pulse-socket`, mounted in `devcontainer.json`). That only works if (1) `libasound2-plugins` is installed (provides the `pulse` ALSA device) and (2) `/etc/alsa/conf.d/99-pulseaudio-default.conf` exists — the package ships it as `.example` only, so the Dockerfile `cp`s it. Without these you get `ALSA lib ... Unknown PCM default` and **silent playback** (the engine falls back to the NULL backend). Verify with `aplay -D default /tmp/beep.wav`.
- **The audio latency profile only matters on Android**: flutter_soloud maps `lowLatency` to miniaudio's `ma_performance_profile`, but SoLoud always sets `periodSizeInFrames = bufferSize` (2048 ≈ 46 ms), so the profile is a no-op on desktop (WASAPI/CoreAudio consult it only when periodSize==0). Only Android AAudio differs: `low_latency` → MMAP, conservative → legacy path (~+30–80 ms latency, not 200 ms). That's why the "Reduce audio stutter" switch (`Settings.audioStableMode`, default on) is rendered only on Android (`settings_view.dart` `_AudioCard`) and synced via `SoLoudEngine.reinit` at session start in `startCalibration` — safe because controllers keep file paths, not engine handles, and nothing is playing yet.
- **Windows build / MSVC coroutine**: only `windows/CMakeLists.txt` is committed for the Windows build — the rest of `windows/` is generated each CI run by `flutter create --platforms=windows .` (release-windows.yml), which *preserves* existing files. That file carries `add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)`: MSVC 14.50+/VS 2026 turns `<experimental/coroutine>` into a hard error (`C2338`/`STL1011`), and `permission_handler_windows` 0.2.1 still pulls it in via `/await` under C++17 (Baseflow#1534). Keep the file in sync with Flutter's `windows.tmpl/CMakeLists.txt.tmpl` when bumping the pinned Flutter version; drop the define once permission_handler ships a C++20 build.
- **Android ships arm64-only**: `defaultConfig.ndk.abiFilters = ["arm64-v8a"]` in `android/app/build.gradle.kts` restricts every Android build (debug/release, APK and AAB) to arm64; release workflows also pass `--target-platform android-arm64` and only install the `aarch64-linux-android` Rust target. Keeps the F-Droid/Play artifact ~27 MB instead of a ~65 MB universal. Consequence: x86/x86_64 emulators and 32-bit (armeabi-v7a) devices cannot install it. The AAB (`muse_ml-<ver>.aab`) is for Play Store only — F-Droid never receives AABs, only the APK.
- **Release version is tag-derived**: asset names and the APK's `--build-name`/`--build-number` come from the release tag, not `pubspec.yaml`. Base version = everything before the first `-`/`_` (tag `0.0.11-feedback-01` → `0.0.11`); APK build number = trailing digits of the channel suffix (→ `1`); an empty tag (build-only dispatch) falls back to pubspec. Logic lives in the "Get version" step of `release-{android,windows,linux}.yml` (android resolves it once in a `version` job feeding `_build-apk.yml`). Keep the copies in sync.
- **Session format is Rust-owned**: never edit the `.muse`/`.muse.feedback` byte layout in Dart. `rust/src/api/session_format.rs` is the single authority — `encode_session_event`, `sessionFrameBytes`, `sessionParseBody`, and the container fns; Dart (`session_recorder.dart`, `session_reader.dart`, `session_container.dart`) are thin FFI delegates. Some container fns are `#[frb(sync)]` so Dart keeps `headReadLimit`/`parseHead`/`extractBody` synchronous. When changing the wire format, extend `cargo test --lib session_format` goldens and regenerate bindings.
- **Cargo `[patch]` version trap**: If the patched crate's `version` is semver-incompatible with the dependency constraint, Cargo silently ignores the patch. Our fork must stay at `version = "0.11.8"` even though the source is based on 0.12.0.
- **Vendored `rlx-cpu`** (`vendor/rlx-cpu`): `[patch.crates-io]` replaces crates.io `rlx-cpu` with our copy, which clears the default `blas` feature (its `build.rs` would hard-link OpenBLAS on x86_64 hosts and break Windows/Linux release builds). Keep `version = "0.2.13"` semver-compatible with the `rlx 0.2` constraint or the patch is silently ignored (same trap as btleplug).
- **Model engine is git deps, not submodules**: `reve-rs`/`luna-rs` are fetched by cargo from GitHub (`rust/Cargo.toml`: luna @ tag `v0.0.4-latent-embedding-fix` on the `windwerfer` fork, reveal @ rev `9c8d856…` on upstream `eugenehp`) — same pattern as `muse-rs`/`btleplug`, so a fresh clone needs no submodule init to build. The workflows still init `third_party/reve-rs`/`luna-rs` after checkout, but that is only for reference copies now.
- **Gated weights live in `.local/`, never commit them**: LUNA/REVE weights + the abandoned `reve-base` source sit under `.local/` as embedded git repos with no remote (untracked, NOT gitignored so agents can still see them). `.gitmodules` documents them with `ignore = all` + an invalid URL so `git submodule update --init` fails loudly instead of fetching. The `#[ignore]`d smoke tests (`rust/src/analysis/{luna,reve}.rs`) read `../.local/...`; run with `cargo test --lib -- --ignored`.
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
- **Network streaming wire formats** (`lib/src/streaming/`): OSC is unicast UDP with batched per-chunk `oscEncodeMessage` messages (per-channel groups in lockstep via `StreamingMixer`); LSL runs through the `liblsl` pub package (auto-discovered, no IP/port); BrainFlow speaks the "Streaming Board" format — **raw little-endian IEEE-754 doubles, no header, one datagram per batch of 3 samples** (`BrainflowStreamer.batchSize`). Presets are separate multicast streams on their own ports: `eeg` = default preset 7 rows (package_num, 4×EEG, UNIX-seconds timestamp, marker) on the configured port; `imu` = auxiliary preset 9 rows (package_num, accel/gyro xyz, timestamp, marker) on port+1 and `ppg` = ancillary preset 6 rows (package_num, ambient/infrared/red, timestamp, marker) on port+2 — the latter two only when `separateGroups` is on. The receiver **drops datagrams that aren't exactly `batch_size × num_rows` doubles**, so batch size must match the preset or the stream dies silently — extend `test/streaming_osc_test.dart`-style loopback E2E tests when touching it.
- **All session writes are crash-safe**: `SessionStore.publishSession`/`updateNotes`/`moveAllTo`/`delete` (`session_store.dart`) all write via `SessionStorage.writeFileAtomic` (`session_storage.dart`). Filesystem = `.name.tmp` sibling + `rename()` (atomic on POSIX); SAF = native `writeFileAtomic` (`MainActivity.kt`) writes `name.mtmp`, deletes old, `renameDocument`, and `recoverDoc()` heals an interrupted swap — it runs on every read *and* during `listFiles` (a first pass heals any orphaned `.mtmp` so a recovered session reappears in listings; surviving `.mtmp` leftovers are skipped). The dashboard (`feedback_dashboard.dart`) shows a corner save chevron only when notes are dirty, a spinner while saving, and a brief check flash after; a `PopScope` intercepts back with an "Unsaved notes" Save/Stay/Discard dialog in the read-only history view.
- **Export writers share the dashboard charts**: `SessionExporter.chartsFor` (`session_export.dart`) feeds `prepareChartData` (`session_chart_data.dart`) to both the PNG rasterizer and the PDF (`session_pdf_export.dart`) so exported charts match the screen. Exports always land in `<root>/export/` (`<root>/export/<stem>/` for PNG-all); Android non-SAF history prompts `SafSessionStorage.pickFolder()` for that export only (`resolveExportStorage`). The offscreen rasterizer (`rasterizeChart`/`_renderOffscreen`) builds its own `BuildOwner`/`PipelineOwner`/`RenderView` — it requires an initialized `RendererBinding` (`runApp`, or `TestWidgetsFlutterBinding.ensureInitialized()` in tests), a `flushCompositingBits()` between layout and paint, and `pipelineOwner.rootNode = null` before `dispose()`.
- **Band/EEG timestamps in the `.muse` body are ms epochs**: CSV bucketing must divide by 1000 before flooring (`(b.timestamp / 1000).floor()`); EEG packets use the same ms convention (`EegSampleRecord.timestamp`). Mind Monitor CSV column order is `TimeStamp, Delta..Gamma per channel, RAW per channel` with capitalized band names; the header row has 5 band columns per channel — tests index `lines[1]` = second 0.
- **FFI-backed `flutter test` needs the host Rust lib**: `test/session_export_test.dart` (and any future Dart test that calls Rust) initializes `RustLib.init(externalLibrary: ExternalLibrary.open('${Directory.current.path}/rust/target/debug/librust_lib_muse_ml.so'))`. Build it first with `cargo build --manifest-path rust/Cargo.toml` (host target), then `flutter test`. Without the .so the FFI never loads and the test fails at the first call.
