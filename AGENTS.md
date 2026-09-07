# AGENTS.md — Muse ML (Flutter + Rust BLE headset app)

Global orientation. Maps and history live in [`.ai/README.md`](.ai/README.md).
Current work: [`.ai/active-task.md`](.ai/active-task.md).

## Stack
- **Flutter 3.41.7** in CI (`.github/workflows/` `FLUTTER_VERSION`). The
  sandbox image may be newer (currently 3.44.8) — do not bump the workflow
  pin without intending a release-toolchain change. Dart is bundled.
- **Rust** via `flutter_rust_bridge` **2.11.1** (pinned `=`, crate + Dart
  package + codegen CLI). Lib: `rust/` (`rust_lib_muse_ml`). Generated
  bindings `rust/src/frb_generated.rs` and `lib/src/rust/` are **both tracked**
  (commit `7543478`: CI never runs codegen; a missing `frb_generated.rs`
  breaks cargokit with `E0583`). Regenerate with
  `flutter_rust_bridge_codegen generate` when the FFI surface changes and
  commit both sides.
- **muse-rs** — depend on `eugenehp/muse-rs` tag `0.1.0`, **patched** to
  `windwerfer/muse-rs` tag `0.1.1` via
  `[patch.'https://github.com/eugenehp/muse-rs.git']`. See `.ai/muse-rs.md`.
- **btleplug** — `github.com/windwerfer/btleplug` tag **`0.12.0-muse-5`**,
  crate version **`0.12.0`** (must match `btleplug = "0.12.0"` or Cargo
  silently skips the patch). JNI `get_env()` auto-attach + notification death
  spiral fix. `[patch.crates-io]` so muse-rs's dep shares one
  `GLOBAL_JVM`/`GLOBAL_ADAPTER`. See `.ai/btleplug.md`.
- **`jni = "=0.19"`** — must match btleplug's `jni` or you get link-time
  symbol conflicts.
- **REVE + LUNA** (on-device drowsiness): git deps — `reve-rs` from upstream
  `eugenehp` rev `9c8d856…`, `luna-rs` from `windwerfer` tag
  `v0.0.4-latent-embedding-fix`. No weights shipped. FFI
  `rust/src/api/reve.rs`; inference `rust/src/analysis/{reve,luna}.rs`;
  Dart `lib/src/reve/`.
- **Feature pipeline** (implemented): Rust registry produces
  `MuseEventDto::Feature`; Dart `FeatureBus` → `RewardLane` / `GuardLane`.
  Copy in `assets/features.json`; electrodes in `rust/src/api/features.rs`.
  Guard **only warns**, never modulates reward. Frozen:
  `.ai/feedback/pipeline-contract.md`. **Crown Start is refused.**
- **Protocols** are JSON documents (`origin: catalog | user`). Catalog:
  `assets/protocols.json`. User: `user_protocol_store.dart` +
  `lib/src/views/protocol_builder.dart`. `ProtocolType` / `GuardrailMode`
  enums are gone — ids are strings; guard is a feature id (`band.delta` /
  `ai.drowsiness` / `none`).
- **Calibration** (`assets/calibrations.json` v2): `eyes-closed-01` /
  `eyes-open-01`, each with `single` (**50 s** silent baseline) and `staged`
  (artifacts / eyes-open / eyes-closed). AI model ready → staged; else single.
- **Android**: NDK 27/28, Gradle 8.14, `targetSdk` from Flutter, arm64-only
  (`abiFilters = ["arm64-v8a"]`).
- **JNI glue**: btleplug init from Dart **after** `RustLib.init()`. Kotlin
  `MainActivity` `ensureInitialized`; `connection_provider` calls
  `ensureBtleplugReady()` before scan/connect. Java under
  `android/app/src/main/java/com/nonpolynomial/btleplug/` and
  `io/github/gedgygedgy/rust/`.
- **iOS/macOS**: not the current target.
- **Windows**: CI-only (`release-windows.yml`). Committed
  `windows/CMakeLists.txt` (MSVC workaround); the rest is generated in CI.

## Core rules (do / don't)
- **NEVER** assume a library is available — check `Cargo.toml` / `pubspec.yaml` first.
- **NEVER** commit secrets/keys.
- **NEVER** add code comments unless explicitly asked.
- Do not run `git` commit/push/PR unless explicitly requested.
- When editing Rust under `rust/src/api/`, run `flutter_rust_bridge` codegen
  if the FFI surface changes (commit both generated sides).
  `cargo check --target aarch64-linux-android` is NOT reliable here — use
  `flutter run`. See `.ai/testing-guide.md`.
- `flutter analyze lib/src` must stay clean after edits.
- Format changes land in `rust/src/api/session_format.rs`; keep
  `cargo test --lib session_format` green.
- Do not reopen pipeline-contract Key Decisions. Do not unlock Crown sessions
  in the current series. Connect UX is frozen
  (`.ai/connect-simulator-ux.md`) — do not mix OSC-connect or Crown Start
  into it. `DeviceKind` is Muse | Neurosity only; do not restore Simulated*.
  Audio-engine Key Decisions (`.ai/audio-engine.md`) are frozen: do not duck
  unmodulated background; do not deinit SoLoud from a controller; do not
  restore `AudioService.setMusicMuffle`.
- If you change on-screen copy or primary chrome (status bar, sidebar, connect
  window, session Start/Pause/End), update `.ai/ui-map.md` in the same change.
  Glossary *mirrors* frozen connect/pipeline names; do not invent synonyms.
- Spoken UI names: `.ai/ui-map.md`. What to run: `.ai/test-matrix.md`. Linux
  agent drive: debug HTTP (`--dart-define=MUSE_AGENT=true`), skill
  `muse-run-linux`. How-to: `.ai/testing-guide.md` Linux agent.

## Docs
Index: [`.ai/README.md`](.ai/README.md). UI names: [`.ai/ui-map.md`](.ai/ui-map.md).
Tests: [`.ai/test-matrix.md`](.ai/test-matrix.md). Audio engine:
[`.ai/audio-engine.md`](.ai/audio-engine.md). Format/cache:
`README_feedback_format.md`, `README_history_cache.md`.
Queued (not this branch): [`.ai/TODO/`](.ai/TODO/) Athena optics raw stream.

## Project layout
```
lib/src/                    Flutter UI + Riverpod
  connection_provider.dart  AppStateNotifier: scan/connect
  connect_source.dart       ConnectSource + simulator catalog
  app.dart                  main(), permissions
  agent/                    debug loopback HTTP (`MUSE_AGENT`, compile-out)
  connect_window.dart       ConnectOverlay (every view with a status bar)
  settings.dart, status_bar.dart, version.dart
  views/                    session, history, dashboard, protocol_builder, streaming, …
    music_settings_panel.dart  shared music options — don't fork
lib/src/feedback/           session orchestrator + lanes
  feedback_state.dart       orchestrator (idle→calibrating→playing⇄paused→ended)
  reward_lane.dart / guard_lane.dart / feature_bus.dart / calibration_runner.dart
  target_state.dart         RatioEngine (FeedbackEngine): threshold, EMA, recalibrate
  protocol.dart / protocol_catalog.dart / user_protocol_store.dart
  feature_catalog.dart      assets/features.json copy
  computed_sampler.dart     1 Hz JSONL; t = seconds from recording start
  feedback_recorder.dart    scratch temps + assembleScratchV5
  session_assembler.dart    re-export of session_v5/assemble.dart
  crash_recovery.dart       leftover scratch v5 / three-temps
  session_store*.dart / session_sqlite.dart / session_metadata.dart
  session_export.dart / session_pdf_export.dart / session_chart_data.dart
lib/src/session_v5/         v5 writer / assemble / ComputedFrame / DeviceInfoV5
  assemble.dart             assembleV5Container, writeScratchV5(prefix:), placeholderWebP
  scratch_writer.dart       SessionRecorder (prefix default `session`)
  computed_frame.dart       Dart ComputedFrame (+ .freezed.dart)
  models.dart               DeviceInfoV5, StreamsConfig
lib/src/audio/              SoLoudEngine + AudioService, reward/guard/background
lib/src/reve/               model download/import/load UI
lib/src/streaming/          OSC / LSL / BrainFlow
lib/src/charts/             live EEG + SessionReader (writer is session_v5/)
rust/src/api/
  muse.rs, features.rs, device_config.rs, neurosity_osc.rs, simulator.rs
  reve.rs, session_format.rs, edf_export.rs
rust/src/analysis/          gesture, reve, luna, guardrail
assets/                     protocols.json, calibrations.json, features.json, audio/
.ai/                        project docs (see .ai/README.md)
```

## Where things live
- BLE: `rust/src/api/muse.rs` (`scan`, `connect`, `subscribe_events`).
- JNI attach: `third_party/btleplug/src/droidplug/jni/mod.rs` `get_env()`.
- Devices: `DeviceKind` is Muse | Neurosity (`device_config.rs`). Connect
  dropdown is Dart `ConnectSource` (`connect_source.dart`). Simulation is
  `simulate` + `sim:*` ids (`simulator.rs`), not extra kind variants.
  `connect_with_options(simulate: true)` calls `spawn_simulator` on the
  existing tokio runtime and emits headset events only (`Eeg` / `Ppg` /
  IMU / `Telemetry`). The event forwarder derives bands, features, pulse,
  SpO₂, quality — same as a live Muse. `DeviceSimulator` is Rust-only
  (`#[frb(ignore)]`). Crown OSC: `neurosity_osc.rs` (no discovery API yet).
- Feature registry: `rust/src/api/features.rs`. Dart bus/lanes as above.
- Session byte layout: `rust/src/api/session_format.rs` only. Dart is FFI.
- Session assemble: `lib/src/session_v5/assemble.dart`
  (`assembleV5Container`, `writeScratchV5`, `placeholderWebP`).
  Scratch writer: `lib/src/session_v5/scratch_writer.dart` (`SessionRecorder`).
  Old paths (`feedback/session_assembler.dart`, `charts/session_recorder.dart`,
  `feedback/computed_frame.dart`, `feedback/session_v5_models.dart`) re-export.
- Crash recovery: `lib/src/feedback/crash_recovery.dart` scans
  `scratchDirectory`, not `getTemporaryDirectory()/sessions`.
- History cache: `lib/src/feedback/session_sqlite.dart`
  (`session_metadata.db`, thumbnail BLOB). Reconcile in `session_store_core.dart`.
- SAF: MethodChannel `muse_ml/saf` in `MainActivity.kt`.
- Guard feature ids: `lib/src/feedback/guardrail_mode.dart` (string helpers,
  not an enum). Per-protocol prefs migrate from old `GuardrailMode.name`.
- Audio engine: `lib/src/audio/soloud_engine.dart` (init/deinit, epoch,
  bundled `loadAsset` cache). Session facade `audio_service.dart`.
  `RewardOutput.setMuffle` is the live muffle API (`guard_lane.dart`
  already calls it). Bundled files: `SoLoudEngine.loadAsset`. User music:
  `loadFile`, uncached. Spec: `.ai/audio-engine.md`.
- Audio outputs: `lib/src/audio/output_ids.dart`.
- Protocol builder: `lib/src/views/protocol_builder.dart`.
- Release CI: `.ai/release.md`. Toolchain: `rust/rust-toolchain.toml` (1.97.1)
  kept in sync with workflow `RUST_VERSION`.

## Known hot spots
- **Cargo `[patch]` version trap**: patched crate `version` must be
  semver-compatible with the dep. btleplug fork is `0.12.0` matching
  `btleplug = "0.12.0"`. **Do not pin the fork back to `0.11.8`.** Patch
  target is `crates-io` for btleplug; muse-rs patch target is the eugenehp
  git URL. See `.ai/btleplug.md`.
- **Vendored `rlx-cpu`** (`vendor/rlx-cpu-0.2.14`): `[patch.crates-io]`,
  default `blas` cleared. Keep `version = "0.2.14"` compatible with
  `rlx-runtime 0.2.14`.
- **Model engine is git deps, not submodules.** Workflows still init
  `third_party/reve-rs`/`luna-rs` as reference copies only.
- **Gated weights live in `.local/`**, never commit them. `#[ignore]`d smoke
  tests in `rust/src/analysis/{luna,reve}.rs`.
- **Session format is Rust-owned.** Never edit `.muse` / `.muse.feedback`
  layout in Dart. Some container fns are `#[frb(sync)]`.
- **Never put a `LayoutBuilder` inside dialog content** (AlertDialog +
  IntrinsicWidth). Use `Align` / `FractionallySizedBox`.
- **Model install UI is shared** (`lib/src/reve/model_selector.dart`) —
  don't fork it between settings and the guardrail dialog.
- **Range sliders for cutoffs are log-space**; the label is `label.round()`.
  Persist music cutoff on `onChangeEnd`, not every `onChanged` tick. Never
  copy a raw slider position into prefs or tests.
- **Don't wrap a bounded `DecoratedBox` around a `ListTile` subtitle**
  (Material ink assertion).
- **Connect overlay must exist in every view with a status bar**
  (`AppShell` and `FeedbackSessionView` each host one). Dropdown is Muse |
  Neurosity | Simulator (`ConnectSource`). Simulator only in Debug mode
  (`enable_simulated_devices`). Muse = BLE, keep Muse only. Neurosity =
  never BLE (empty OSC list is OK). Simulator = static catalog, no BLE,
  no OSC; hide Rescan. Debug off + Simulator selected → Muse. Ignore
  `sim:*` `lastDeviceId` when debug is off.
- **`DeviceKind` is two values** (Muse, Neurosity). FFI enum — regenerate
  FRB if it changes. `deviceKindIsCrown` is `kind == neurosity`. Crown
  Start is refused for real and simulated Crown/Notion.
- **Settings has no “AI sleep guardrail” card.** Guard is per-protocol in
  the builder + `Settings.guardFeatureFor`. Debug mode is the last card
  (after About).
- **flutter_soloud Linux Xiph libs are glibc-2.43-built** unless
  `TRY_SYSTEM_LIBS_FIRST=1` + system `libopus-dev` etc. (devcontainer and
  `release-linux.yml` already do this).
- **Container has no ALSA card** — `libasound2-plugins` +
  `/etc/alsa/conf.d/99-pulseaudio-default.conf` (copied from `.example` in
  the Dockerfile) or playback is silent.
- **Audio latency profile only matters on Android.** "Reduce audio stutter"
  (`Settings.audioStableMode`) is Android-only. Session start calls
  `AudioService.ensureReady(reopenIfProfileDiffers: true)` (falls back to
  low-latency if the conservative AAudio path cannot start). A Settings
  toggle does nothing until the next session start. Controllers may
  `SoLoudEngine.ensureInit()` with no args (no-op if ready).
- **Do not deinit SoLoud from a controller.** `FeedbackAudioController.dispose`
  must not call `SoLoudEngine.deinit`; `AudioService.dispose` is the only
  teardown. Bundled audio uses `SoLoudEngine.loadAsset`, never `loadFile`
  (rain used to `loadFile` an asset key — that fails on Android).
- **Muffle is `RewardOutput.setMuffle`.** Do not add `AudioService.setMusicMuffle`.
  Duck modulated reward + both binaural controllers. Do **not** duck
  unmodulated background (drone / static music / rain-as-background).
  Do not edit `guard_lane.dart` for muffle.
- **Flutter directory assets** only bundle files directly in the declared
  directory. `pubspec.yaml` lists every `assets/audio/` subdir. Guard:
  `test/calibration_assets_test.dart`.
- **Windows MSVC coroutine**: `windows/CMakeLists.txt` defines
  `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` for
  `permission_handler_windows`.
- **Android ships arm64-only.** No x86 emulator / armeabi-v7a.
- **Release version is tag-derived**, not `pubspec.yaml`. Logic in
  `release-{android,windows,linux}.yml`.
- **Android BLE init** must happen from JNI before scan or
  `"Droidplug has not been initialized"`.
- **Muse startup** uses `handle.start(true, false)` (commit `217cefe`).
  Classic `p50` enables PPG. Revert that commit if Classic stability
  regresses.
- **Simulator connect must `tokio::spawn` `DeviceSimulator::start`.** Do
  not drop the Future (the old std-thread bridge never ran). Do not emit
  derived `Bands` / Pulse / SpO₂ / Gestures from the sim — the forwarder
  owns those. EEG std must stay in `1..15` µV so pad quality ≥ 80.
  `cargo test --lib simulator`.
- **Athena optical ≠ Classic PPG.** muse-rs maps optical tags `0x34` /
  `0x35` **first 3 channels only** into `MuseEvent::Ppg` (as if they were
  ambient/IR/red) and **skips** `0x36` (16-ch). Extra fNIRS optodes are
  not in this app. Do not add them without Athena hardware. See
  `.ai/muse-rs.md`.
- **SpO₂** from PPG IR+Red in `compute_spo2()` (`muse.rs`, commit `4bc0300`).
  Classic 3-ch PPG only; Athena 8/16-ch optics are not a drop-in.
- **Event forwarder** polls `guard.events` every 1 s; 30 s silence →
  `Disconnected`. Never `watch::changed()` on a clone of an unpolled primary
  (commit `3078904` / fix `53e3e8f`).
- **Auto-scan only on saved device.** Fresh launch with no `lastDeviceId`
  opens the connect window but does not scan.
- **JNI trace spam**: call `log::set_max_level(Debug)` after
  `android_logger::init_once` (`muse.rs` `init_app()`).
- **QueueStream race**: `QueueStream.java:pollNext()` must remove inside
  `synchronized`.
- **Epoch window is wall-clock 75 s** (`RatioEngine.epochWindowSeconds`),
  not 300 events. `successRate` is null until the window fills. Zero-success
  window → circuit breaker resets to the baseline percentile.
- **In-flight recalibrate**: ≥ 60 s elapsed and ≥ 30 clean samples from the
  90 s rolling buffer.
- **Storage resolution is async** (`sessionStorageProvider` FutureProvider).
  Always `ref.read(sessionStoreProvider.future)`.
- **SAF is history-only.** Live recording always goes to scratch
  (`scratchDirectory()`).
- **Desktop default dir**: fall back to `$HOME/Documents`, never `/tmp`.
  Changing the save folder **moves** sessions (`moveAllTo`).
- **Signal gate**: before calibration, gate pads green for 3 s; after
  baseline, no re-lock. Playing pauses only when all gate pads are critical
  for 10 s; never auto-ends. Names in `gate_electrodes.dart`, default Muse
  AF7/AF8.
- **Line-noise**: `BandsDto.line_noise_ratio` from the 256-point FFT
  (50/60 Hz ±1 bin). Folded into Dart UI dots and Rust autodrop.
- **Gesture markers are metadata-only** (not a `RecordingStream`). Gated by
  `Settings.markersInFeedbackEnabled` / `eyeMarkersEnabled`.
- **Blink/clench gate cleanliness**: `_sampleIsClean` needs movement and
  gesture buffers ≥ 1 s old.
- **BrainFlow datagrams** that are not exactly `batch_size × num_rows`
  doubles are dropped by the receiver. Extend loopback tests when touching
  the wire format.
- **All session writes are crash-safe** (`writeFileAtomic`).
- **Band/EEG timestamps in the `.muse` body are ms epochs.** CSV bucketing
  divides by 1000 before flooring.
- **FFI-backed `flutter test` needs the host Rust lib**
  (`cargo build --manifest-path rust/Cargo.toml` first).
- **Stale `rust/target/release/` lib breaks `flutter run`** (content-hash
  mismatch). Rebuild release after codegen; debug/cargokit rebuilds are not
  loaded. See `.ai/testing-guide.md`.
- **`updateNotes` uses v5** (`containerEncodeV5`). There is no
  `SessionContainer` Dart wrapper anymore.
- **Assemble v5 at `end()`** into scratch (placeholder WebP) **before**
  `phase = ended`. Save `publishSession` to history; Discard deletes the
  scratch v5. One wrapper: `session_v5/assemble.dart`.
- **Crash recovery** scans `scratchDirectory` for leftover
  `session_*.muse.feedback` and orphan `.raw` / `.computed` / `.metadata`.
  Temps go through `writeScratchV5`. Never `decodeImage` on empty bytes.
- **ComputedSampler.t** is seconds from recording start, not unix epoch.
- **Charts** plot computed 1 Hz (`v5ExtractComputed` →
  `prepareChartDataFromComputed`). There is no `SessionOverview` /
  400-bucket `metadata.summary`. The list sparkline is the WebP thumbnail.
