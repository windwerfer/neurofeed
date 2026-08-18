# Architecture

## Current architecture (as built)
```
Flutter UI (lib/src)
   │  Riverpod: AppStateNotifier (connection_provider.dart)
   ▼
flutter_rust_bridge 2.11.1  ── FFI ──►  Rust crate rust_lib_muse_ml (rust/src/api/muse.rs)
                                            │
                                            ▼
                                       muse-rs 0.1.0 (dep)
                                         ├─ transport: btleplug fork 0.11.8 (Android BLE)
                                         └─ protocol:  parse.rs / protocol.rs / types.rs
                                            (decode raw GATT bytes → MuseEvent)
```
- `scan()` / `connect()` / `subscribe_events()` are the Rust FFI entry points.
- `subscribe_events()` returns a `Stream<MuseEventDto>` that drives all UI.
- Session persistence runs through `rust/src/api/session_format.rs` (single
  authority for the `.muse` v4 body + `.muse.feedback` container byte layout).
  Dart `SessionRecorder`/`SessionReader`/`SessionContainer` are thin FFI
  delegates (`encodeSessionEvent`/`sessionFrameBytes`/`sessionParseBody` and
  the sync `container*` fns). See AGENTS.md "Known hot spots".
- Permissions: `requestBlePermissions()` in `app.dart` (permission_handler +
  device_info_plus, SDK-gated).

## Decision: keep btleplug (2026-07-21)

The btleplug JNI thread-attach fix succeeded — scan works end-to-end without
crashes. We are **keeping btleplug** as the BLE transport for consistency with
`muse-rs` (which uses btleplug natively). No migration to `flutter_blue_plus`.

### Fallback option (if btleplug hadn't worked)
If the JNI fix had failed, the plan was to replace the btleplug transport with
`flutter_blue_plus` (Dart) and keep only muse-rs's **protocol core** in Rust,
fed raw bytes over the FFI bridge:

```
Flutter UI (lib/src)
   │
   ├─ flutter_blue_plus (Dart)  ◄── scan / connect / discover / subscribe
   │        │  raw List<int> per characteristic notification
   │        ▼  (frb call: handle_notification(uuid, bytes))
   │
   └─ flutter_rust_bridge ──►  stripped muse-rs core (Rust)
                                  parse.rs / protocol.rs / types.rs
                                  handle_notification(uuid, bytes) -> Vec<MuseEvent>
                                  encode_command(cmd) -> Vec<u8>
                                             │
                                             ▼
                                  MuseEvent stream → UI (unchanged)
```

`flutter_blue_plus` handles Android BLE init natively and would have avoided
the Kotlin glue, bundled Java classes, JVM-attach patch, and patched fork.
It remains a good second choice if btleplug ever becomes unmaintainable.

## Signal quality, calibration gate, and ATR autodrop (feedback)
- Per-pad `signalQuality` (0–100, from EEG std over a 1 s window **plus a
  line-noise term**, `connection_provider.dart`) is the "fit" score — separate
  from the bands used for ATR. Line noise comes from `BandsDto.line_noise_ratio`
  (50/60 Hz mains power fraction of the existing per-second FFT); ratios above
  ~0.2 start to penalize a pad, ~0.5 is severe (up to −60%). `_lineNoise` keeps
  a `-1.0` sentinel until the first Bands event.
- Calibration gate: all 4 pads ≥ `signalGoodThreshold` for `greenStableSeconds`
  (3) continuous (1 s `_gateTimer`), then baseline. After baseline there is no
  signal gate → feedback always starts.
- Faulty pad (non-green for `faultyPadSeconds`=20 while frontal pads green) →
  inline "Continue anyway" fallback (tier A: both AF7/AF8; tier B: ≥1).
- Playing: pauses only when both needed pads < `signalCriticalThreshold` for
  `badSignalPauseSeconds`; never auto-ends; auto-resumes when a needed pad
  recovers.
- ATR autodrop: `TargetStateAggregator.evaluate(quality)` averages only pads
  ≥ `atrUsableSignalThreshold`; null if both frontal pads are bad.

## Gesture detection (blink / jaw clench / eye)
- `rust/src/analysis/gesture.rs` `GestureDetector` — no DSP crates, all
  thresholds auto-adaptive EWMA baselines. Fed raw EEG per packet + per-second
  FFT gamma in the forwarder (`rust/src/api/muse.rs`); drains 1 Hz into the new
  `MuseEventDto::Gestures` variant.
- Blink: frontal pads (1,2), 125 ms rectified-diff bin energy > `max(baseline×5,
  100 µV)`, ~500 ms refractory. Jaw clench: posterior pads (0,3) gamma bursts >
  `baseline×3`. Eye up/down: frontal−posterior mean shift > `max(scale×2,
  20 µV)` — experimental, off by default.
- In Dart: `_onGestures` gates the ATR clean-sample window (like the movement
  gate) and accumulates `GestureMarker`s (`doubleBlink`, `doubleClench`,
  `eyeUp`/`eyeDown`) only while `playing`. Markers persist in `SessionMetadata`.
  `gestures` (top-level metadata key), never in the `.muse` body.
- Settings toggles: `eyeMarkersEnabled` (eye track, default off) and
  `markersInFeedbackEnabled` (persist markers, default on).

## Feedback audio modes (flutter_soloud)
- One `AudioService` façade over SoLoud; `FeedbackAudioController` owns the
  volume stack (**5 channels**: master × background / feedback / intro / end
  bell / guardrail warning), calibration clips, and chimes.
- Feedback-sound modes (`Settings.feedbackSound`): **bowl chimes** (reward
  verdicts), **rain**, **music** (`MusicFeedbackController` — user folder
  played through a per-voice biquad low-pass, cutoff/invert/shuffle from the
  shared `MusicSettingsPanel` in `lib/src/views/music_settings_panel.dart`),
  **binaural** (`BinauralBeatController` — two synth voices at a carrier/beat
  beat-frequency pair), or none. Reward drives swell on music/binaural; the
  guardrail muffle ducks them when the warning sounds.
- Connect window: `ConnectOverlay` (`lib/src/connect_window.dart`) is a
  tap-anywhere barrier + device list/rescan panel; both `AppShell` and
  `FeedbackSessionView` host their own copy (session screen can reconnect
  without leaving the session).

## Network streaming (OSC / LSL / BrainFlow)
- One `StreamingController` (riverpod) subscribes to the Muse event stream,
  mixes per-group channels through `StreamingMixer` (per-channel queues →
  lockstep rows), and starts on connect / stops on disconnect. Three wire
  formats, all built from `StreamingConfig` derived from `Settings`
  (`osc`/`lsl`/`brainflow` keys):
  - **OSC** (`streaming_osc.dart`): unicast UDP, batched per-chunk messages via
    `oscEncodeMessage`; the IP auto-fills from the local subnet when unset.
  - **LSL** (`streaming_lsl.dart`): `liblsl` pub package, auto-discovered on the
    network — no IP/port needed.
  - **BrainFlow** (`streaming_brainflow.dart`): multicast UDP "Streaming Board"
    datagrams — raw little-endian f64 doubles, no header, one datagram per
    batch of 3 samples. `eeg` = default preset (7 rows) on the configured port;
    `imu` = auxiliary preset (9 rows) on port+1 and `ppg` = ancillary preset
    (6 rows) on port+2, both only when `separateGroups` is on. The receiver
    drops datagrams that aren't exactly `batch_size × num_rows` doubles.
    Reference for the wire format: `third_party/brainflow/` (tag 5.9.0), NOT a
    build dependency.
- `StreamIndicator`/`StreamDot` show live (green) / armed (amber) status in the
  sidebar and status bar. End-to-end verified over real loopback sockets in
  `test/streaming_osc_test.dart` (extend it when touching the wire formats).

## Local model engine (REVE / LUNA guardrail)
- Purpose: on-device drowsiness/artifact embeddings for the guardrail layer
  (the guardrail composes with the ATR reward engine but only warns — it never
  modulates the reward). Per-protocol wiring: `ProtocolInfo.guardrailDefault` /
  `guardrailAllowed` / `guardrailFeedback` + `Settings.guardrailEnabledFor`; the
  eyes-open alertness protocol sets `guardrailAllowed: false` so the guardrail
  gear card is hidden there. **The app ships no weights.**
- Rust: `rust/src/api/reve.rs` is the FFI surface (`model_load`/`model_unload`/
  `model_loaded`/`model_config_json`). `rust/src/analysis/{reve,luna}.rs` wrap the
  `reve-rs`/`luna-rs` crates (RLX CPU backend); scoring runs there from the event
  forwarder, not across FFI. `reve-rs`/`luna-rs` are **git deps** (reveal-rs at rev
  `9c8d856…` from upstream `eugenehp`, luna-rs at tag `v0.0.4-latent-embedding-fix`
  from the `windwerfer` fork); `[patch.crates-io]` points `rlx-cpu` at the vendored `vendor/rlx-cpu`
  (default `blas` feature cleared).
- Dart: `lib/src/reve/models.dart` (`ModelKind` — luna_base / luna_large / reve_base,
  each with SHA-256 + Hugging Face URLs + size), `model_engine.dart` (`ModelCache`
  downloads LUNA or imports REVE with SHA-256 verification, atomic `.part`+rename
  install, then `modelLoad`; `ModelEngineNotifier` drives the `ModelEngineState`),
  `model_selector.dart` (settings-backed picker with per-model availability badges),
  `reve_import.dart` (gated-file import), `reve_card.dart`.
- Files land in `<sessionFolder>/ai_models/<kind>/` as `config.json` (app-generated via
  `modelConfigJson`) + `model.safetensors`.
- Local dev only: `.local/{luna-base-dl,reve-base-dl}` hold the real weights used by the
  `#[ignore]`d smoke tests; `.local/reve-base` is an abandoned source fork. None are in
  git (embedded repos, documented in `.gitmodules` with `ignore = all` + invalid URL).

## muse-rs module map (for the fork)
| File | Role | Keep in fork? |
|------|------|---------------|
| `parse.rs` | byte decoders (pure) | ✅ keep |
| `protocol.rs` | UUIDs, command encode/decode (pure) | ✅ keep |
| `types.rs` | `MuseEvent`, `Eeg`, `Ppg`, `Imu`, `Telemetry` | ✅ keep |
| `lib.rs` | re-exports | ✅ keep (trim) |
| `muse_client.rs` | btleplug transport (scan/connect/subscribe) | ❌ delete |
| `bin/` | CLI using btleplug | ❌ delete |

## Key data types (crossing the bridge)
- `MuseEventDto` (freezed DTO) variants: `Connected`, `Disconnected`, `Eeg`,
  `Ppg`, `Telemetry`, `Accelerometer`, `Gyroscope`, `Control`, `Pulse`,
  `Movement`, `PeakAlpha`, `Gestures`.
- `BandsDto { electrode, timestamp, delta…gamma, line_noise_ratio }` — also the
  1 Hz carrier that feeds `AppStateNotifier._lineNoise`.
- `GestureDto { timestamp, blink_count, clench, eye }` — 1 Hz gesture report.
- `DeviceInfo { name, id }` — produced by scan, consumed by connect.
- `ConnectionStatus`, `TelemetrySnapshot` — UI state.

## Android specifics
- Manifest BLE perms: `BLUETOOTH_SCAN` (neverForLocation), `BLUETOOTH_CONNECT`,
  `ACCESS_FINE_LOCATION` (maxSdkVersion=30).
- `targetSdkVersion = 36`, NDK 27/28, Gradle 8.14.
- `flutter_rust_bridge` generated `rust/src/frb_generated.rs` and the Dart
  files under `lib/src/rust/` are both tracked in git (re-tracked in `7543478`:
  CI never runs codegen, so a fresh checkout must already contain
  `frb_generated.rs` or cargokit's `cargo build` fails with E0583). Regenerate
  with `flutter_rust_bridge_codegen generate` when the FFI surface changes.

## JNI thread-attach workaround (btleplug fork)

**Fixed 2026-07-21.** The btleplug fork at `github.com/windwerfer/btleplug`
(tag `0.12.0-muse-3`) includes a `get_env()` wrapper that auto-attaches
tokio worker threads to the JVM and fixes the BLE notification death spiral. Without this, every BLE JNI call from a
worker thread fails with `"JNI call failed"`.

Key insight: the `jni` crate's `JavaVM::get_env()` returns
`Err(JniCall(ThreadDetached))` for unattached threads and does not
auto-attach. The fix is a single function with a fallback to
`attach_current_thread_permanently()`.

See `.ai/btleplug.md` for the full patch documentation.
