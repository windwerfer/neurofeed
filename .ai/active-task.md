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
- ✅ Fork published: `github.com/windwerfer/btleplug` tag `0.12.0-muse-2`.
- ✅ `Cargo.toml` updated to use remote tag (swap to local `../../btleplug` via
  `[patch]` for debugging — see `.ai/btleplug.md`).
- ✅ Docs: `.ai/btleplug.md`, `.ai/bugreport.md`, `.ai/lessons-learned.md` updated.

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

## Next steps
1. Long-duration streaming test (1h+) to verify notification death spiral fix.
2. PPG streaming — currently produces no events; check muse-rs `ppg` feature
   flag and `parse_athena_notification()` path.
3. Investigate EEG data integrity / verify sample alignment.

## How to verify (see testing-guide.md)
Run `flutter run`, observe status bar shows correct battery % (from `bp`,
not fuel gauge). Confirm via `adb logcat | grep muse` that no unexpected
crashes or stream deaths occur. Use debug log level to see raw telemetry:
`adb logcat -s rust_lib_muse_ml:*:*:D`.
