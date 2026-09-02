# Testing Guide

## Environment
- `adb`: `$HOME/android-sdk/platform-tools/adb`. SDK at `$HOME/android-sdk`.
- `flutter`: `$HOME/flutter/bin/flutter`. Rust Android targets + `cargo-ndk`.
- App package: `com.example.muse_ml`.
- Pick a device with `adb devices` / `flutter devices`. Do not hardcode a
  serial. CI Flutter pin is **3.41.7**; the sandbox image may be newer.

## The build/test loop (self-contained, no back-and-forth)
The agent runs this itself. Steps:

1. **Kill stale processes** (do NOT kill adb):
   ```bash
   ps aux | grep -iE "flutter|dart|gradle" | grep -v grep | grep -v defunct \
     | awk '{print $2}' | xargs -r kill -9
   ```
2. **Clear logcat and launch detached** (so the command returns):
   ```bash
   adb logcat -c
   cd /workspaces/flutter_muse_ml
   DEVICE=$(adb devices | awk 'NR==2 {print $1}')
   setsid flutter run --device-id "$DEVICE" > /tmp/opencode/flutter_run.log 2>&1 < /dev/null & disown
   ```
   App builds + launches in ~90–120s. Wait ~110s.
3. **Stop the run** (killing flutter frees the logcat stream):
   ```bash
   ps aux | grep -iE "flutter|dart|gradle" | grep -v grep | grep -v defunct \
     | awk '{print $2}' | xargs -r kill -9
   ```
4. **Dump and grep** (only works AFTER step 3; otherwise `-d` hangs):
   ```bash
   timeout 25 adb logcat -d -t 8000 > /tmp/opencode/lc.txt 2>&1
   grep -nE "\[muse\]|btleplug|JNI call failed|scan error|scan returned|ClassNotFound" /tmp/opencode/lc.txt
   ```

## What to look for
- `[muse] main entered` — app launched and `debugPrint` reaches logcat.
- `[muse] requestBlePermissions: result = granted, granted` — permission flow OK.
- `[muse] starting scan (manual rescan)` — Dart called Rust `scan()`.
- After a successful scan: `[muse] scan returned N device(s)` and the connect
  window's `scanMessage` shows `Found N device(s)`.
- Failure signatures seen historically:
  - `Droidplug has not been initialized` → btleplug not init'd from JNI.
  - `ClassNotFoundException: com.nonpolynomial.btleplug.android.impl.Adapter`
    → btleplug Java classes not bundled.
  - `AnyhowException(JNI call failed)` → worker thread not attached to JVM.

## Triggering a scan without a saved device
On fresh install there is no `lastDeviceId`, so `_init()` opens the connect
window but does NOT auto-scan. Tap **Rescan**, or (temporarily) call
`openConnectWindowAndScan();` at the end of `_init()` (`// TEMP-TEST`) and
revert after.

## On-screen diagnostics (no logcat needed)
`AppUiState.scanMessage` in `connect_window.dart`:
`Requesting BLE permissions…` → `Scanning…` → `Found N device(s)` (or
`Scan error: …`).

## Rust unit tests + model smoke tests (run in `rust/`)
- Session-format goldens: `cargo test --lib session_format`
  (full suite: `cargo test --lib`).
- Model smoke tests (`#[ignore]`d): `cargo test --lib -- --ignored`
  Needs `.local/luna-base-dl/LUNA_base.safetensors` and
  `.local/reve-base-dl/model.safetensors`. Tests rebuild
  `target/*-smoke/model.safetensors` each run.
- `reve-rs` / `luna-rs` / muse-rs / btleplug are git deps — `cargo build`
  needs GitHub. No submodule init required for the build
  (`third_party/` copies are reference only).

## Dart tests that hit the FFI (host build)
Tests that call Rust (e.g. `test/session_export_test.dart`,
`test/session_store_test.dart`) need the **host-built** library:

```bash
cargo build --manifest-path rust/Cargo.toml      # → rust/target/debug/librust_lib_muse_ml.so
flutter test                                      # tests init RustLib.init(externalLibrary: ...)
```

Without the `.so` the FFI never loads. Pure-Dart tests
(`feedback_pipeline_test.dart`, `user_protocol_builder_test.dart`,
`output_ids_test.dart`, `calibration_assets_test.dart`, streaming `*_test.dart`)
do not need it.

The PNG export rasterizer needs `TestWidgetsFlutterBinding.ensureInitialized()`
in `setUpAll`.

## Caveats
- `flutter analyze lib/src` must stay clean after Dart edits.
- Local `cargo check --target aarch64-linux-android` is UNRELIABLE in this
  sandbox (NDK clang permission denied). Trust `flutter run` for the real
  Rust compile.
- `flutter_rust_bridge` codegen must be re-run if the Rust FFI surface
  changes; commit `rust/src/frb_generated.rs` **and** `lib/src/rust/`.
- **Desktop `flutter run` loads `rust/target/release/`, not the debug
  bundle.** The generated loader
  (`kDefaultExternalLibraryLoaderConfig` in
  `lib/src/rust/frb_generated.dart`, `ioDirectory: 'rust/target/release/'`)
  opens that release `.so` from the project root. A stale release lib
  (built before the last codegen) causes
  `Bad state: Content hash on Dart side (…) is different from Rust side (…)`
  at `RustLib.init`, while `./muse_ml` from the bundle dir still works.
  **Fix:** `cargo build --release --manifest-path rust/Cargo.toml` (or
  delete the stale `.so`), then `flutter run`. Re-run after codegen;
  `flutter clean` / debug builds do not help.
