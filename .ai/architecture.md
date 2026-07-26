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
  `Ppg`, `Telemetry`, `Accelerometer`, `Gyroscope`, `Control`.
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
