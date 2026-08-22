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
  **Not backward compatible** with v2/v3 files (pre-alpha, accepted). Dart
  events still arrive as doubles; only the on-disk layout changed.
- ✅ **Session format moved into Rust (single authority)** — `rust/src/api/
  session_format.rs` now owns the byte layout (commit `caaff10`). Dart no longer
  hand-encodes/parses: `SessionRecorder` → `encodeSessionEvent` +
  `sessionFrameBytes` (zstd v3), `SessionReader` → `sessionParseBody` (returns
  freezed `SessionData`/`BandsRecord`/…), `SessionContainer` → sync
  `containerEncodeBytes`/`containerParseHeadBytes`/`containerExtractBodyBytes`.
  The old `compress_block`/`decompress_block` FFI is removed (compression lives
  inside the format module). Header golden test pins the legacy quirk that the
  magic is an LE u64 of `"MUSEBIN\n"` (byte-reversed on disk). 25 unit tests
  cover golden wire layouts, f32-vs-f64 precision, malformed/truncated input,
  and hand-built frames. **Rule:** never touch the byte layout from Dart.
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

## Status — 2026-08-11 Update (REVE/LUNA model selector + dependency layout reorg)
- ✅ Model engine committed (`models: REVE + LUNA local model engine with selector UI`):
  Rust FFI `rust/src/api/reve.rs` (`model_load`/`model_unload`/`model_loaded`/
  `model_config_json`) + inference wrappers `rust/src/analysis/{reve,luna}.rs` over the
  `reve-rs`/`luna-rs` crates; Dart `lib/src/reve/` (ModelKind metadata, `ModelCache`
  download/import with SHA-256 verification, `ModelEngineNotifier`, selector + import UI).
  **No weights shipped** — LUNA downloads from HF, REVE is user-imported.
- ✅ Dependency layout reorg (two commits: `vendor:` + `models:`):
  - `vendor/rlx-cpu/` — vendored rlx-cpu moved out of `third_party/` (cleared default
    `blas` feature; wired via `[patch.crates-io]`); `/vendor/rlx-cpu/target/` gitignored.
  - `third_party/luna-rs` registered as a real submodule (`eugenehp/luna-rs`, pinned to
    upstream `main` `5025cea` — matches upstream HEAD, so fresh clones fetch it).
  - `.local/{luna-base-dl,reve-base-dl,reve-base}` — gated weights + abandoned fork moved
    out of `third_party/` into untracked embedded git repos; `.gitmodules` documents them
    with `ignore = all` + an invalid URL (smoke-test paths updated to `../.local/...`).
- ✅ Verified: `cargo test --lib` green (25 session-format tests), `cargo test --lib --
  --ignored` passes (`luna_smoke` + `reveal_smoke` run real inference on the `.local/`
  weights), `flutter analyze lib/src` clean.
## Status — 2026-08-17 Update (guardrail settings UI + feedback dialogs)
- ✅ **Guardrail gear dialog** (`feedback_session.dart`): scorer engine now a
  dropdown with green ✓ for installed models (band math always checked, no
  install needed) + the shared install bubble appears inline when a not-installed
  AI model is chosen; warning sound is a dropdown (soft bowl / bell chime /
  cough / alarm clock incl. continuous volume-ramped alarm / none — `GuardrailSound`),
  threshold is a 1 %-step percentile slider with live readout.
- ✅ **Target settings dialog**: dynamic-adapt toggle, gentle↔responsive slider
  (labels under the track ends), reward-threshold percentile slider (1 % steps,
  live `NN%` readout restored + drag bubble; default shown in the description text).
- ✅ **Dedup**: `ModelInstalledCheck` + `ModelInstallBubble` extracted into
  `lib/src/reve/model_selector.dart`, shared by the settings `AiEngineCard` and
  the guardrail dialog (card's own busy/progress/buttons deleted).
- ✅ **Pitfall recorded in AGENTS.md**: never put a `LayoutBuilder` inside
  dialog content — AlertDialog measures with `IntrinsicWidth` and
  `LayoutBuilder` can't return intrinsics (crash fixed in `bb51897`).
- ✅ Model engine is **git deps, not submodules** (`4534f19`) — the old CI
  submodule gap below is obsolete; no `git submodule update` needed to build.

## Status — 2026-08-18 Update (binaural + music feedback, guardrail per-protocol, connect window)
- ✅ **Binaural beats mode** (`6032e4e`): `BinauralBeatController`
  (`lib/src/audio/binaural_beat_controller.dart`) — two synth voices at a
  carrier/beat beat-frequency pair, reward-swelled like music; presets +
  carrier/beat sliders persisted in `Settings`. Guardrail warning is now a
  **5th volume channel** (master × channel, incl. the continuous volume-ramped
  alarm).
- ✅ **Music feedback sub-tile** (`4fc5169`): folder prompt with validation +
  shared `MusicSettingsPanel`/`pickMusicFolder`/`musicFolderLabel` bubble in
  `lib/src/views/music_settings_panel.dart` — same options as the Settings music
  card (don't fork it). Reset button added in `8b58229`, which also fixed the
  log-space slider bug (labels now show `label.round()` of the log-domain
  value; the old code wrote the log-domain number into the prefs — see
  "Range sliders are log-space" hot spot in AGENTS.md).
- ✅ **Guardrail per-protocol** (`018c303`): `ProtocolInfo.guardrailDefault`/
  `guardrailAllowed`/`guardrailFeedback` + `Settings.guardrailEnabledFor`; the
  eyes-open alertness protocol sets `guardrailAllowed: false` so the whole
  guardrail card is hidden there. Guardrail still only warns — it never
  modulates the reward.
- ✅ **Connect window** (`97d031a`): `ConnectOverlay` is a tap-anywhere barrier
  + device list/rescan panel; `FeedbackSessionView` hosts its own copy so the
  session screen can reconnect without leaving the session.
- ✅ **Binaural sub-tile ink fix** (`54641b3`): opaque `DecoratedBox` around a
  `ListTile` subtitle broke the Material ink assertion — styling moved onto the
  tile itself.
- ⏳ Binaural + music modes unverified on-device (TB336FU); reward-swell
  audibility and guardrail-muffle behavior need a listening pass.

## Status — 2026-08-18 Update (network streaming: OSC / LSL / BrainFlow)
- ✅ **Streaming tab** (`b010325`, `79a8ceb`, `bcae326`): one riverpod
  `StreamingController` subscribes to the Muse event stream, mixes per-group
  channels through `StreamingMixer` (per-channel queues → lockstep rows), and
  starts on connect / stops on disconnect. Three wire formats, all built from
  `StreamingConfig` derived from `Settings` (`osc`/`lsl`/`brainflow` keys):
  - **OSC**: unicast UDP, batched per-chunk `oscEncodeMessage` messages; IP
    auto-fills from the local subnet when unset.
  - **LSL**: `liblsl` pub package — auto-discovered, no IP/port.
  - **BrainFlow**: multicast UDP "Streaming Board" datagrams — raw LE f64
    doubles, no header, one datagram per batch of 3 samples. `eeg` = default
    preset (7 rows) on the configured port; `imu` = auxiliary preset (9 rows,
    52 Hz) on port+1 and `ppg` = ancillary preset (6 rows, 64 Hz) on port+2,
    both only when `separateGroups` is on. Wire-format reference:
    `third_party/brainflow/` (tag 5.9.0, registered in `.gitmodules`), NOT a
    build dep.
- ✅ **Indicators**: `StreamIndicator`/`StreamDot` (green live / amber armed)
  in the sidebar and status bar.
- ✅ **Tests**: `test/streaming_osc_test.dart` — end-to-end over real loopback
  UDP sockets (OSC encode/decode + BrainFlow datagram sizing); receiver drops
  datagrams that aren't exactly `batch_size × num_rows` doubles.
- ⏳ On-device verification pending (TB336FU): live EEG into real receivers
  (LSL Viewer, Pure Data/OSC, BrainFlow recorder) incl. IMU/PPG separate
  streams.

## Status — 2026-08-19 Update (audio stability setting + choice-time warning)
- ✅ **"Reduce audio stutter"** (`80a4e61`): `Settings.audioStableMode`
  (default on, Android-only) maps to SoLoud's `lowLatency` flag. `SoLoudEngine`
  now tracks the profile and exposes `reinit({required bool stable})`;
  `startCalibration` syncs the engine at every session start before anything
  plays. Rationale: flutter_soloud maps `lowLatency` to miniaudio's
  `ma_performance_profile`, but SoLoud always sets `periodSizeInFrames =
  bufferSize` (~46 ms), so the profile only matters on Android AAudio
  (`low_latency` → MMAP, conservative → legacy, ~+30–80 ms). No-op on
  desktop → the Settings card (`_AudioCard`) is only rendered on Android.
- ✅ **Music + AI guardrail warning moved to choice time**: the one-time
  stutter warning now fires via the shared `_maybeWarnMusicAiCpu` helper when
  the user *picks* the combination — choosing music while an AI scorer is
  active (`_FeedbackTile`) or choosing an AI scorer while music feedback is
  selected (`_GuardrailGearDialog`) — instead of at session start. Copy points
  to Settings → Audio → "Reduce audio stutter".
- ⏳ On-device verification pending (TB336FU): AAudio MMAP-vs-legacy latency
  difference (~0.1 s) and stutter behavior under music + AI guardrail; confirm
  the toggle applies at next session start.

## Status — 2026-08-19 Update (history multi-export, merged to main)
- ✅ **History multi-select + export** (branch `feature/session-export`, merged
  into `main` as `dbb611b`): long-press selection with a persistent
  Select-all/None/Export/Delete bar in `feedback_history.dart`. Export sheet
  offers 5 kinds per session:
  - **PDF** — vector A4 page (`session_pdf_export.dart` `buildPdfPage`, `pdf`
    pkg) reusing the dashboard chart data.
  - **PNG thumbnail** (the container's embedded PNG) and **PNG all** (bands +
    alpha-vs-theta + movement + HR charts, offscreen rasterized).
  - **CSV** — Mind Monitor format (band/EEG timestamps are ms epochs → divide
    by 1000 before flooring; capitalized band columns).
  - **EDF+** — raw EEG via new FFI `encodeEdfExport` (`rust/src/api/
    edf_export.rs`) backed by the hand-rolled writer crate
    `third_party/edf_export/` (path dep, golden byte-layout tests; TODO: push
    to user GitHub and switch to a git+tag dep).
- ✅ Exports land in `<root>/export/` (`<root>/export/<stem>/` for PNG-all);
  Android non-SAF history prompts a folder picker for that export only
  (`resolveExportStorage` → `SafSessionStorage.pickFolder()`).
- ✅ Chart prep extracted to `session_chart_data.dart` (`prepareChartData`),
  shared by the dashboard and both exporters so PNG/PDF match the screen.
- ✅ `SessionStore.delete(id)` + `SessionStorage` dir-aware
  `writeFile`/`writeFileAtomic`/`fileExists`/`delete`; Kotlin
  `resolveOrCreateDir` walks nested segments (e.g. `export/<stem>/`).
- ✅ **Bugs caught along the way** (all fixed, covered by tests): CSV bucketing
  used ms epochs as seconds; offscreen rasterizer missed
  `flushCompositingBits()`; EDF header fields are ASCII (test asserted binary);
  hand-typed 1×1 PNG had a wrong IDAT byte breaking container parsing.
- ✅ Verified: `flutter analyze lib/src` clean; 25 Dart tests green (7 new
  export E2E tests in `test/session_export_test.dart` — need the host-built
  Rust lib, see testing-guide.md); `cargo test --lib` 29 passed / 2 ignored.
- ⏳ On-device verification pending (TB336FU): export each format to a real
  folder/SAF location and open the results (PDF in a viewer, EDF+ in an EDF
  reader, CSV in a spreadsheet).

## Status — 2026-08-22 Update (SpO₂ blood oxygen + combined HR/SpO₂ chart)
- ✅ **SpO₂ from PPG IR+Red** (commit `4bc0300`): `compute_spo2()` in
  `rust/src/api/muse.rs` runs every 1 s on a 30 s window (1920 samples @ 64 Hz)
  using ratio-of-ratios (A=110, B=25 best-guess). Red channel (ch 2) buffered
  alongside IR (ch 1). Fixes: AC = proper std dev (`sqrt(sum/n)`), confidence
  scaled 20× so typical PPG AC/DC (1-5%) yields 0.2-1.0. HR window 8s → 30s.
  Emits `SpO2Dto` (confidence ≥ 0.3) → recorded as `RecordingStream.spo2` →
  decimated into `SessionOverview.spo2` (400 buckets).
- ✅ **Combined HR/SpO₂ chart** in session summary: dual Y-axis (left HR 40–200
  bpm, right SpO₂ 50–100%), avg lines (HR dashed deep red, SpO₂ dotted blue),
  legend toggles for both series. Settings toggle: `RecordingStream.spo2`.
  Export: SpO₂ chart (yMin=50, yMax=100).
- ✅ **Movement graph fixed bounds**: 0–1.5g (`fixedYMin: 0, fixedYMax: 1.5`).
- ✅ All tests pass: `cargo test --lib session_format` (30), `flutter analyze lib/src`.

## Next steps
- ✅ **Staged calibration clips never played on Linux** — `Unable to load
  asset: "assets/audio/calibration/grok-reve-artifacts-01.opus"` at first
  playback. Root cause: Flutter directory assets only bundle files **directly
  in the declared directory** (official docs), so collapsing the explicit
  subdir list back to a bare `assets/audio/` (regression in `469c031` of the
  `2f05247` fix) silently dropped `bell/`, `bowl/`, `calibration/`, `drone/`,
  `rain/` from the bundle — the manifest contained only the top-level
  `guardrail-*.opus` files. Every audio path in the app was affected, not just
  the REVE clips.
- ✅ Fixed: `pubspec.yaml` re-declares each audio subdirectory explicitly
  (`assets/audio/bell/`, `bowl/`, `calibration/`, `drone/`, `rain/`) alongside
  `assets/audio/` for the top-level guardrail sounds.
- ✅ **Regression guard**: `test/calibration_assets_test.dart` gained a test
  that walks `assets/audio/` and asserts every file is covered by a pubspec
  asset entry — would have failed at `469c031`.
- ✅ Verified: `flutter build bundle` regenerates the manifest with all subdir
  files (bundle tree matches the source tree byte-for-byte in size);
  `flutter analyze lib/src` clean; calibration test suite green.
- ⏳ On-device verification pending (TB336FU): staged REVE clips + single
  intros audible on Android (Android bundles the same manifest, so expect it
  to work; confirm once).

## Status — 2026-08-19 Update (SQLite metadata cache, merged to main)
- ✅ **History is now fluid on every open** — the per-session SAF prefix read +
  JSON decode on `list()` (which ran on app launch *and* each history click,
  and was worst on Android SAF) is replaced by a SQLite metadata cache
  (`lib/src/feedback/session_cache.dart`, commit `4486db1`).
- ✅ **Reconcile, not re-read**: `SessionStore.list()` does one
  `listFilesMeta()` (name + mtime — native `MainActivity.kt` method now
  returns `[{name, mtime}]`) + one `SELECT … WHERE storage_key=?`; unchanged
  files render straight from cached `metadata_json`. Changed/new files are
  backfilled in the background and `SessionListNotifier` (now an
  `AsyncNotifierProvider`, not a `FutureProvider`) re-reads the list → lazy
  two-stage emission, so the first history open stays instant even cold.
- ✅ Cache lives app-private: `<support>/cache/session_cache.sqlite` +
  thumbnails at `<support>/cache/thumbnails/<id>.png` (works for SAF, never
  writes into the SAF folder). Rows are namespaced by `storage_key` (sha256 of
  the folder location); `moveAllTo` re-namespaces them so folder changes keep
  cached metadata. Write-through on `publishSession`/`updateNotes`/`delete`;
  `cacheOverview()` folds a computed `SessionOverview` into cached metadata for
  legacy sessions (dashboard legacy branch).
- ✅ **Fault tolerance**: `SessionCache.open()` falls back to a no-op on any
  failure so history always degrades to plain file reads. `SessionStore` takes
  an injectable cache (tests use the real SQLite one).
- ✅ Verified: `flutter analyze lib/src` clean; 35 Dart tests green (6 new in
  `test/session_cache_test.dart` — also need the host-built Rust lib, see
  testing-guide.md); `cargo build` host lib rebuilt.
- ⏳ On-device verification pending (TB336FU): SAF history list speed + correct
  thumbnails/notes after reinstall (cache is app-private, files are the source
  of truth), and the `listFilesMeta` mtime path on a real folder.

## Next steps
0. On-device pass: download LUNA Base + LUNA Large, import REVE, verify load/unload,
   bad-hash rejection, progress UI, and model-switch persistence on the TB336FU.
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
6. On-device listening pass for binaural + music modes: reward-swell audibility,
   guardrail muffle, volume-channel math; tune `BinauralBeatController` voice
   parameters (carrier/beat mix, swell shape) against the TB336FU speakers.
7. On-device streaming verification: point real receivers at the phone (LSL
   Viewer, an OSC sink, BrainFlow recording) and confirm live EEG/bands/IMU/PPG
   arrive with sane rates; verify port+1/+2 IMU/PPG only appear when
   `separateGroups` is on.
8. On-device audio-profile pass: with the TB336FU speakers, toggle "Reduce
   audio stutter" and check for audible latency (~0.1 s) / dropout differences
   during music + AI guardrail; confirm the switch applies at the next session
   start (not mid-session).
9. On-device export pass: record a short session, export PDF/PNG/CSV/EDF+ to a
   real folder (and a SAF-picked folder) and open each result on the tablet;
   verify CSV column layout in a spreadsheet and EDF+ in an EDF reader
   (EEGlab/EDFbrowser). Push `third_party/edf_export` to user GitHub and switch
   `rust/Cargo.toml` to a git+tag dep once it proves out.

## How to verify (see testing-guide.md)
Run `flutter run`, observe status bar shows correct battery % (from `bp`,
not fuel gauge). Confirm via `adb logcat | grep muse` that no unexpected
crashes or stream deaths occur. Use debug log level to see raw telemetry:
`adb logcat -s rust_lib_muse_ml:*:*:D`.
