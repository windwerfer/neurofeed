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
- `flutter_rust_bridge` generated `rust/src/frb_generated.rs` is gitignored;
  Dart generated files are tracked.

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
