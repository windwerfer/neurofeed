# AGENTS.md — Muse ML (Flutter + Rust BLE headset app)

Global orientation for any AI agent or contributor working in this repo.

## Stack
- **Flutter 3.41.7** (stable), Dart (bundled). UI layer.
- **Rust** via `flutter_rust_bridge` **2.11.1** (pinned `=`, both Rust crate and Dart package).
  - Rust lib: `rust/` (crate `rust_lib_muse_ml`).
  - Generated bindings: `rust/src/frb_generated.rs` is **gitignored**; Dart generated files ARE tracked.
- **muse-rs** (`github.com/eugenehp/muse-rs.git` tag `0.1.0`, `default-features = false`) — Muse BLE protocol + transport.
- **btleplug** — forked at `github.com/windwerfer/btleplug` (tag `0.12.0-muse-3`), patched with `get_env()` → `attach_current_thread_permanently()` fallback for tokio JNI threads + notification death spiral fix. **Source base is upstream 0.12.0 but `Cargo.toml` version is pinned to `0.11.8`** — required for semver matching (see `.ai/btleplug.md`).
  - Referenced via `[patch]` on `eugenehp/btleplug.git` so that BOTH
    `rust_lib_muse_ml` and `muse-rs` use the same patched copy (single
    `GLOBAL_JVM` static). Swap `[patch]` to local path for debugging.
- **`jni = "=0.19"`** — pinned to match btleplug's own `jni` dependency.
  If either side upgrades, both must be upgraded together or you get
  link-time symbol conflicts.
- **Android**: NDK 27/28, Gradle 8.14, `targetSdkVersion = 36`.
- **Decision:** using btleplug (forked) for BLE transport — consistent with
  `muse-rs`. `flutter_blue_plus` was the fallback if the JNI fix had failed.
- **JNI glue**: Kotlin `MainActivity.museAndroidInit()` → Rust `extern "C"` → `btleplug::platform::init()`. btleplug Java sources under `android/app/src/main/java/com/nonpolynomial/btleplug/`. jni-utils Java at `io/github/gedgygedgy/rust/`.
- **iOS/macOS**: not the current target; BLE transport uses btleplug's CoreBluetooth path.

## Core rules (do / don't)
- **NEVER** assume a library is available — check `Cargo.toml` / `pubspec.yaml` first.
- **NEVER** commit secrets/keys.
- **NEVER** add code comments unless explicitly asked.
- Do not run `git` commit/push/PR unless explicitly requested.
- When editing Rust under `rust/src/api/`, run `flutter_rust_bridge` codegen if the FFI surface changes, then `cargo check --target aarch64-linux-android` is NOT reliable in this sandbox (see Testing Guide) — rely on `flutter run` for the real compile.
- `flutter analyze lib/src` must stay clean after edits.

## Docs (`.ai/`)
| File | Contents |
|------|----------|
| `btleplug.md` | btleplug fork changes — what, why, pitfalls (version, Java alignment) |
| `bugreport.md` | Structured bug report for upstream btleplug (3 sections + suggestions) |
| `btleplug_bugreport_2.md` | Bug report #2: BLE notification stream silently dies (JNI death spiral) — fixed in `0.12.0-muse-3` |
| `architecture.md` | Current and target architecture, module map |
| `lessons-learned.md` | Full history of JNI attempts, what worked/failed |
| `testing-guide.md` | Build/test loop for the device |
| `active-task.md` | Current development focus |

## Project layout
```
lib/src/                 # Flutter UI + Riverpod state
  connection_provider.dart  # AppStateNotifier: scan/connect state machine
  app.dart                 # main(), permission request
  connect_window.dart      # device list / rescan UI
  status_bar.dart, views/  # UI
rust/src/api/muse.rs    # FFI bridge: scan/connect/subscribe → MuseEvent stream
rust/src/connection.rs  # in-Rust state (active connection, device cache, sink)
android/app/src/main/java/
  com/nonpolynomial/btleplug/android/impl/  # btleplug Java classes
  io/github/gedgygedgy/rust/                # jni-utils Java sources
.ai/                     # project docs
third_party/muse-rs/    # local checkout of muse-rs (tag 0.1.0) — reference for protocol/parse debugging
third_party/btleplug/   # local checkout of our btleplug fork (tag 0.12.0-muse-3) — reference for JNI/init debugging
muse-rs (dep, GitHub)   # transport (btleplug) + protocol
btleplug (local, via [patch])  # patched fork; reference copy in third_party/btleplug/
```

## Where things live (for navigation)
- BLE scan/connect entry: `rust/src/api/muse.rs` (`scan`, `connect`, `subscribe_events`).
- JNI thread-attach patch: `../../btleplug/src/droidplug/jni/mod.rs` `get_env()`,
  plus callers in `adapter.rs` and `peripheral.rs`.
- btleplug Java init: `android/app/src/main/java/com/nonpolynomial/btleplug/android/impl/`.
- Kotlin init entry: `android/app/src/main/kotlin/com/example/muse_ml/MainActivity.kt`.
- Protocol decoders (pure, no BLE): inside muse-rs `parse.rs` / `protocol.rs` / `types.rs`.
- Permissions: `lib/src/app.dart` `requestBlePermissions()` (uses `permission_handler` + `device_info_plus` for sdk gating).
- Manifest BLE perms: `android/app/src/main/AndroidManifest.xml` (`BLUETOOTH_SCAN` w/ `neverForLocation`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION` capped `maxSdkVersion=30`).

## Known hot spots
- **Cargo `[patch]` version trap**: If the patched crate's `version` is semver-incompatible with the dependency constraint, Cargo silently ignores the patch. Our fork must stay at `version = "0.11.8"` even though the source is based on 0.12.0.
- **Android BLE init**: btleplug requires `btleplug::platform::init(&JNIEnv)` from a JNI context BEFORE any scan/connect, or it panics with `"Droidplug has not been initialized"`.
- **JNI `ThreadDetached`**: BLE ops run on tokio worker threads which aren't attached to the JVM. Our `get_env()` patch auto-attaches them.
- **Java/Rust API alignment**: The Rust code expects Java method signatures from btleplug 0.12.0. If upgrading either side, check `jni/objects.rs` vs the Java source files.
- **Auto-scan only on saved device**: on fresh launch with no `lastDeviceId`, `_init()` opens the connect window but does NOT scan. Scan only fires on Rescan button or autoconnect to a known device.
- **JNI trace spam**: The `jni` crate logs `trace!()` for every JNI call. `android_logger` filters at `Debug` level, but if it's initialized after another logger (e.g. flutter_rust_bridge), `init_once` fails silently and the filter doesn't apply. The fix: always call `log::set_max_level(log::LevelFilter::Debug)` after `init_once` as a fallback. See `rust/src/api/muse.rs:init_app()`.
- **QueueStream race condition**: `QueueStream.java:pollNext()` returned a lambda that called `this.result.remove()` **outside** the `synchronized` block. Two tokio workers could both poll the same stream, both see a non-empty queue, both get removal lambdas, and one would crash with `NoSuchElementException` when the other had already drained it. **Fix**: remove the value from the queue inside the synchronized block and return a closure over the already-removed value. See `android/app/src/main/java/io/github/gedgygedgy/rust/stream/QueueStream.java:31`.
