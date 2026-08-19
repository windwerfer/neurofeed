# Testing Guide

## Environment
- Device attached: `adb devices` → `HA2A7MWP  device` (Lenovo/ZUI ROM, Mediatek).
- `adb`: `$HOME/android-sdk/platform-tools/adb`. SDK at `$HOME/android-sdk`.
- `flutter`: `$HOME/flutter/bin/flutter`. Rust Android targets + `cargo-ndk` installed.
- App package: `com.example.muse_ml`.

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
   setsid flutter run --device-id HA2A7MWP > /tmp/opencode/flutter_run.log 2>&1 < /dev/null & disown
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
- `[muse] main entered` — confirms app launched and `debugPrint` reaches logcat.
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
window but does NOT auto-scan. To exercise the scan path, **tap "Rescan"** in
the connect window, OR temporarily add `openConnectWindowAndScan();` at the end
of `_init()` (mark with `// TEMP-TEST`) and revert after.

## On-screen diagnostics (no logcat needed)
`AppUiState.scanMessage` is shown in `connect_window.dart`. It transitions:
`Requesting BLE permissions…` → `Scanning…` → `Found N device(s)` (or
`Scan error: …`). Use this to verify the scan result even if logcat is awkward.

## Rust unit tests + model smoke tests (run in `rust/`)
- Session-format goldens (must stay green — pins the `.muse` byte layout):
  `cargo test --lib session_format` (full suite: `cargo test --lib`).
- Model smoke tests (`#[ignore]`d — load real weights and run inference):
  `cargo test --lib -- --ignored`
  Needs the local-only weights present: `.local/luna-base-dl/LUNA_base.safetensors`
  and `.local/reve-base-dl/model.safetensors` (untracked embedded repos, not in git).
  The tests rebuild their `target/*-smoke/model.safetensors` symlink each run, so
  stale/dangling links are not an issue.
- `reve-rs`/`luna-rs` are git deps (`rust/Cargo.toml`: reveal-rs from upstream
  `eugenehp`, luna-rs from the `windwerfer` fork), so a fresh checkout needs
  network access to GitHub for `cargo build`/`cargo test`; no submodule init is
  required. (The `third_party/` copies are reference only.)

## Dart tests that hit the FFI (host build)
Some Dart tests call Rust over the bridge (e.g. `test/session_export_test.dart`
— session encode/parse, EDF+, offscreen PNG rasterization). They need the
**host-built** Rust library, not the Android one:
```bash
cargo build --manifest-path rust/Cargo.toml      # → rust/target/debug/librust_lib_muse_ml.so
flutter test                                      # tests init RustLib.init(externalLibrary: ...)
```
Without the .so the FFI never loads and the test fails at the first Rust call.
Notes:
- Only needed for tests that touch Rust; pure-Dart tests run without it.
- The offscreen rasterizer used by the PNG export also requires an initialized
  `RendererBinding` — the test does `TestWidgetsFlutterBinding.ensureInitialized()`
  in `setUpAll`.

## Caveats
- `flutter analyze lib/src` must stay clean after Dart edits.
- Local `cargo check --target aarch64-linux-android` is UNRELIABLE in this
  sandbox (NDK clang permission denied). Trust `flutter run` for the real Rust
  compile.
- `flutter_rust_bridge` codegen must be re-run if the Rust FFI surface changes,
  and the regenerated `rust/src/frb_generated.rs` plus `lib/src/rust/` must both
  be committed (they are tracked in git — a fresh checkout has no
  `frb_generated.rs` otherwise, which breaks CI's `cargo build` with E0583).
