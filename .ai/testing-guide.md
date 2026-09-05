# Testing Guide

Spoken UI names: [ui-map.md](ui-map.md). Command matrix: [test-matrix.md](test-matrix.md).

## Linux agent loop (debug HTTP)

Drive the **same Riverpod notifiers** the UI uses (`lib/src/agent/`).
Not widget tests. Not OS clicks. Session smoke does **not** push
`FeedbackSessionView`. What to assert: [test-matrix.md](test-matrix.md).
Copy-paste: `.grok/skills/muse-run-linux/SKILL.md`. Spoken names:
[ui-map.md](ui-map.md).

Bind is compile-out unless `kDebugMode && MUSE_AGENT`.
`--dart-define=MUSE_AGENT=true` (also `1` / `yes` via `parseDartDefineFlag`).
Raw `bool.fromEnvironment` is true only for the string `true`. Process
`export MUSE_AGENT=…` does nothing. Profile/release compile it out.
Bind `127.0.0.1` only. Do not leave `MUSE_AGENT` on an Android `flutter run`.
HTTP never writes SharedPreferences (`persist: false`).

This sandbox often has `DISPLAY` unset. Wayland works
(`GDK_BACKEND=wayland`). If `flutter run -d linux` never prints
`[muse] agent-ready`, stop and report. Do not invent Xvfb. Do not kill
Pulse, X, Wayland, adb, or the Dart language-server.

1. Rebuild `rust/target/release/` after codegen (content-hash trap below).
2. `GDK_BACKEND=wayland flutter run -d linux --dart-define=MUSE_AGENT=true --dart-define=MUSE_DEBUG=true`
   with stdout in a file. Wait for `[muse] agent-listen 127.0.0.1:<port>`
   **and** `[muse] agent-ready`. Abort on `Content hash`. Parse the port;
   do not assume 17890 (range 17890–17899, then 0).
3. Connect a **startable Muse** simulator: `sim:muse-2` or `sim:muse-s`.
   Never `sim:crown-osc` / `sim:notion-osc` for a playing session.
   After connect, `GET /state` → `connected=true` and `scanMessage` is
   null (not leftover `Connecting… (attempt N)`).
4. `recordOnly` + duration 1 + `skipCalibration`. Grep
   `[feedback] phase=playing`. Always `POST /session/end` then
   `/session/reset`. Never `publishSession`.
5. Logs are the stdout file. `grep` anytime — do not `tail -f` as the wait.
   `debugPrint` does reach the `flutter run` log.

### API (loopback JSON)

`AgentCommands` in `lib/src/agent/agent_commands.dart`. Errors:
`{ok:false, error, message?}`. `POST /view` uses `AppView` **name**
(`rawEeg`, `bands`, `settings`, …).

| Verb | Body | Notes |
|---|---|---|
| `GET /health` | — | `{ok, version}` |
| `GET /state` | — | view, connected, device*, phase, protocol, duration, `audioInitFailed`, `scanMessage` |
| `POST /view` | `{view}` | `feedback`, `feedbackHistory`, `bands`, `rawEeg`, `spectrogram`, `psd`, `streaming`, `settings` |
| `POST /sidebar` | `{open:bool}` | |
| `POST /connect-window` | `{open, source?}` | `source`: `muse`/`neurosity`/`simulator`. `setConnectWindow` (not toggle). |
| `POST /connect` | `{id}` | Simulator catalog then scanned list. `persist: false`. 409 `connect_failed` / `busy`. |
| `POST /disconnect` | `{}` | `persist: false` (does not wipe human `lastDeviceId`). |
| `POST /session/select` | `{protocol}` | 412 `unknown_protocol`. |
| `POST /session/duration` | `{minutes}` | `persist: false`. Smoke uses `1`. |
| `POST /session/start` | `{skipCalibration}` | 412 not connected; 409 `crown_refused`. |
| `POST /session/pause\|resume\|end\|reset` | `{}` | end/reset are 200 no-ops if idle / not connected. **Always end+reset** after a smoke. |

### Agent gotchas

- HTTP does **not** prove a button’s `onPressed`. A dead Start button can
  still start via `/session/start`.
- Session UI is not mounted. Dashboard `pushReplacement` on `ended` will
  not run.
- Default duration is 15 min if you skip `/session/duration`.
- SoLoud init throw is caught → `audioInitFailed` + log; phase can still
  be `playing`. Audio silence in this container is N/A, not a failure.
- GTK at-spi / cursor-theme warnings on Linux are noise.
- `persist: false` means a human `lastDeviceId` (including Crown) can
  still autoconnect on the next launch.
- Widget / `integration_test` / Patrol / goldens stay deferred.
- Frozen: Crown Start refused; `DeviceKind` Muse\|Neurosity;
  connect-simulator-ux names.

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
`Scan error: …`). During connect it is `Connecting… (attempt N)`;
**cleared to null** when `connectTo` succeeds. Do not leave that copy
after a connected session.

## Rust unit tests + model smoke tests (run in `rust/`)
- Session-format goldens: `cargo test --lib session_format`
  (full suite: `cargo test --lib`).
- Simulator stream: `cargo test --lib simulator` (headset events, no
  derived DTOs, EEG std in the ≥80 quality band, Crown 8-ch / no PPG).
- Model smoke tests (`#[ignore]`d): `cargo test --lib -- --ignored`
  Needs `.local/luna-base-dl/LUNA_base.safetensors` and
  `.local/reve-base-dl/model.safetensors`. Tests rebuild
  `target/*-smoke/model.safetensors` each run.
- `reve-rs` / `luna-rs` / muse-rs / btleplug are git deps — `cargo build`
  needs GitHub. No submodule init required for the build
  (`third_party/` copies are reference only).

## Dart tests that hit the FFI (host build)
Tests that call Rust (e.g. `test/session_export_test.dart`,
`test/session_store_test.dart`, `test/session_computed_charts_test.dart`)
need the **host-built** library:

```bash
cargo build --manifest-path rust/Cargo.toml      # → rust/target/debug/librust_lib_muse_ml.so
flutter test                                      # tests init RustLib.init(externalLibrary: ...)
```

Without the `.so` the FFI never loads. Pure-Dart tests
(`connect_source_test.dart`, `feedback_pipeline_test.dart`,
`user_protocol_builder_test.dart`, `output_ids_test.dart`,
`calibration_assets_test.dart`, streaming `*_test.dart`,
`test/agent/*`, `app_ui_state_test.dart`)
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
