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

## Next steps
1. On-device test pass (checklist in `.ai/feeback/todos.md`): calibration →
   auto-start, chimes + movement gating, volume dialog, target settings,
   recalibrate, persistence, `[atr]` ceiling/lockout logs, mid-session Muse
   power-off → watchdog → auto-reconnect.
2. If the reconnect test passes, remove the temporary `[muse] forwarder` debug
   logs or drop them to debug level.
3. v1.1 backlog: EEG artifact flag for EMG, percentile persistence, continuous
   EMA adaptation, multi-protocol presets, calibration audio variants (see
   `.ai/feeback/todos.md`).

## How to verify (see testing-guide.md)
Run `flutter run`, observe status bar shows correct battery % (from `bp`,
not fuel gauge). Confirm via `adb logcat | grep muse` that no unexpected
crashes or stream deaths occur. Use debug log level to see raw telemetry:
`adb logcat -s rust_lib_muse_ml:*:*:D`.
