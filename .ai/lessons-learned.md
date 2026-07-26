# Lessons Learned

## Android BLE via btleplug — what we tried and why it was abandoned

**Context:** The app's BLE scan silently returned nothing. Logcat from the
Bluetooth stack showed no scan originating from `com.example.muse_ml`. The
failure was entirely on the Rust/btleplug side, not Dart.

### Attempt 1 — `btleplug::platform::init()` in Rust `init_app()`
- **Tried:** call `btleplug::platform::init()` inside `#[frb(init)] init_app()`.
- **Failed:** `init()` in this fork takes a `&JNIEnv` argument and must be
  called from a JNI context. `init_app()` runs from Dart with no `JNIEnv`
  available, and `flutter_rust_bridge` 2.11.1 does **not** expose
  `get_jvm()`/`get_env()`. Compile error: `this function takes 1 argument but 0
  arguments were supplied`.
- **Lesson:** frb 2.11.1 has no JVM access; you cannot init btleplug purely
  from Rust `init_app()` on Android. (Newer frb 2.12+ may add it, but the
  sandbox has no network to upgrade.)

### Attempt 2 — init from Kotlin `MainActivity.onCreate` (with `JNIEnv`)
- **Tried:** Added `external fun museAndroidInit()` to a custom
  `MainActivity.kt`, calling a Rust `extern "C"
  Java_com_example_muse_1ml_MainActivity_museAndroidInit(env)` that calls
  `btleplug::platform::init(&env)`. Added `btleplug` + `jni = "=0.19"` as
  direct deps (must match btleplug's own `jni 0.19`, not 0.21).
- **Result:** got past "Droidplug has not been initialized" — progress!
- **New failure:** `java.lang.ClassNotFoundException:
  com.nonpolynomial.btleplug.android.impl.Adapter`. btleplug's native-method
  registration needs its Java classes bundled in the APK.

### Attempt 3 — bundle btleplug's Java classes + `jni-utils`
- **Tried:** copied `btleplug/.../com/nonpolynomial/btleplug/android/impl/*.java`
  and the `io.github.gedgygedgy.rust.*` Java sources (found in the `jni-utils`
  cargo crate, since the SNAPSHOT Maven dep was unreachable) into
  `android/app/src/main/java/`.
- **Result:** classes load; init succeeds; scan starts.
- **New failure:** `AnyhowException(JNI call failed)` immediately on scan.

### Attempt 4 — diagnose the JNI failure (root cause found)
- **Found:** btleplug calls `global_jvm().get_env()` from a **tokio worker
  thread** (the scan runs off the Dart/UI thread). `JavaVM::get_env()` returns
  `JNI_EDETACHED` for threads not attached to the JVM, and the `jni` crate's
  `get_env()` does **not** auto-attach. Hence "JNI call failed".
- **Confirmed via:** verbose `jni` logs in logcat
  (`calling unchecked JavaVM method: GetEnv` on thread 14765) and the
  `muse_rs::muse_client: scan_all` line immediately preceding the error.

### Attempt 5 — patch btleplug to attach-on-demand
- **Tried:** vendored btleplug locally (`rust/vendor/btleplug`), added an
  attach-aware `get_env()` wrapper (`match get_env() { Ok(e) => e, Err(_) =>
  attach_current_thread() }`), replaced all `global_jvm().get_env()` calls, and
  wired it via `[patch.'https://github.com/eugenehp/btleplug.git']`.
- **Failed to compile cleanly** (a `match` arms type mismatch:
  `attach_current_thread()` returns an `AttachGuard`, not `JNIEnv`; also
  `[patch]` cannot carry a `branch` key). Was mid-fix when the approach was
  abandoned.
- **Why abandoned:** the whole stack (Kotlin glue + ~30 Java files + patched
  fork + JVM-attach hack on a non-standard btleplug fork) is fragile and
  high-maintenance. The user chose to instead use `flutter_blue_plus` for BLE
  and keep only muse-rs's protocol core in Rust.

## Things that DID work (keep these)
- **Diagnostic harness:** `debugPrint('[muse] …')` in `app.dart` and
  `connection_provider.dart`, plus an on-screen `scanMessage` field in
  `AppUiState` shown in `connect_window.dart`. `debugPrint` DOES reach logcat
  on this ZUI ROM (tag `flutter`), so `adb logcat | grep muse` is reliable.
- **Test loop (see testing-guide.md):** clear logcat, `flutter run` detached,
  wait ~100–120s, kill the flutter process (NOT adb), then
  `adb logcat -d | grep muse`. This avoids the back-and-forth.
- **Dart permission flow is correct:** `requestBlePermissions()` grants
  `bluetoothScan` + `bluetoothConnect` (location only on SDK ≤ 30). Confirmed
  `result = granted, granted` in logcat.

## Gotchas
- **Cargo `[patch]` silently skips on semver mismatch** — if the patched
  crate's `version` is `0.12.0` but the project requires `^0.11.8`, the patch
  is ignored with no warning. Always verify with `cargo tree`.
- **Never `pkill -f adb`** — it kills the adb server and wedges the shell.
  Kill only `flutter`/`dart`/`gradle` processes.
- **`flutter run` holds the logcat stream**, so `adb logcat -d` hangs (timeout)
  while the run is alive. Kill the flutter process first, then dump logcat.
- **NDK clang works from the sandbox** — `cargo check --target aarch64-linux-android`
  is now reliable (set `CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER`).
- **muse-rs protocol core is btleplug-free:** `parse.rs`, `protocol.rs`,
  `types.rs`, `lib.rs` have zero btleplug imports. Only `muse_client.rs` and
  `bin/` use btleplug — safe to delete in the fork.
- **`flutter_rust_bridge` 2.11.1 already enables `android_logger`** when the
  `log` feature is on, so plain `log::` calls print to logcat. The
  `enable_frb_rust_to_dart_logging!()` macro the user suggested does NOT exist
  in 2.11.1 (added later); not needed here.

## Outcome: btleplug fixed, no migration needed

**Decision:** The JNI fix works. We keep btleplug as the BLE transport for
consistency with `muse-rs`. The `flutter_blue_plus` migration (documented in
`architecture.md`) was the fallback plan and remains a good second choice.

## Session 2026-07-21 — btleplug JNI fix succeeds

After the pivot to `flutter_blue_plus` was decided, we came back to make
btleplug work. The `"JNI call failed"` error turned out to have a **second
root cause** masked by the first:

### The version trap that wasted hours
The local btleplug fork had `version = "0.12.0"` but the project depended on
`^0.11.8`. Cargo's `[patch]` silently ignored the patch because of the semver
mismatch — the unpatched upstream 0.11.8 was compiled instead. Switching to
`version = "0.11.8"` made the patch apply.

### The real fix
The upstream `get_env()` calls `global_jvm().get_env()` directly, which
returns `JNI_EDETACHED` on tokio worker threads. Our `get_env()` wrapper
falls back to `attach_current_thread_permanently()`, making every JNI call
work regardless of thread attachment state.

### Java API alignment
The Rust source was based on 0.12.0 but the bundled Java files were from
0.11.8. `JPeripheral::from_env_impl()` eagerly resolves all method IDs and
panics if any signature doesn't match. We added 5 missing Java methods,
fixed the `writeDescriptor` signature, added callback overrides, and created
`NoBluetoothAdapterException.java`.

### Result
Scan now works end-to-end. The `get_env` logs confirm both tokio worker
threads are detected detached and permanently attached on first JNI call.
No crashes or errors during scan.

### Relevant files
- `../../btleplug/src/droidplug/jni/mod.rs` — core `get_env()` patch
- `../../btleplug/src/droidplug/adapter.rs` — callers updated + logging
- `../../btleplug/src/droidplug/peripheral.rs` — callers updated
- `../../btleplug/src/droidplug/jni_utils/classcache.rs` — `.unwrap()` → `?`
- `../../btleplug/Cargo.toml` — version 0.12.0 → 0.11.8
- `android/app/src/main/java/.../Peripheral.java` — methods + callbacks added
- `android/app/src/main/java/.../NoBluetoothAdapterException.java` — new file
- `.ai/btleplug.md` — full fork documentation
- `.ai/bugreport.md` — structured report for upstream (Bug 1)

## Session 2026-07-26 — BLE notification stream death spiral (Bug 2)

### The problem
After ~6 seconds of streaming, ALL BLE notifications (EEG, telemetry, accel,
gyro) stopped simultaneously while the BLE connection remained active. The
forwarder task was alive (5-second heartbeat confirmed it) but `rx.recv()`
returned no events. No crash, no error log — silent death.

### Root cause
Three conspiring bugs in the btleplug notification polling path:

1. **`JSendStream::poll_next_internal`** used `self.vm.get_env()` (raw
   JavaVM::get_env) instead of the safe `droidplug::jni::get_env()` wrapper
   that auto-attaches detached threads. When a tokio worker thread polled the
   notification stream, `get_env()` failed with `ThreadDetached`.

2. **No Java exception clearing.** When `call_method_unchecked` failed, the
   Java exception stayed pending on the JNIEnv. ALL subsequent JNI calls on
   that thread failed with "Java exception was not cleared". A transient error
   became permanent.

3. **`filter_map(|item| item.ok())`** at peripheral.rs silently dropped stream
   errors. Worse, `FilterMap` re-polls the underlying stream immediately on
   `None`, creating an infinite tight loop at 100% CPU — no events flow but
   the task never dies.

### The trigger
The bugs only manifest on tokio's **multi-threaded runtime** because:
- Multiple worker threads can poll the same notification stream (Bug 1)
- Worker threads that haven't been attached to the JVM trigger ThreadDetached
  (Bug 2a)
- Even with auto-attach, a transient Java exception (e.g., from Android BLE
  stack calling back into Java) triggers Bug 2b → Bug 2c loop

### The fix
Three changes in `third_party/btleplug/src/droidplug/`:

| File | Change |
|------|--------|
| `jni_utils/stream.rs:133` | `self.vm.get_env()` → `super::super::jni::get_env()` (auto-attach) |
| `jni_utils/stream.rs:44-49` | New `clear_java_exception()` — clears pending Java exceptions before/after JNI calls |
| `peripheral.rs:438-446` | Log errors instead of silent `item.ok()` |

### Key lesson
**Every JNI call site in a multi-threaded tokio context must:**
1. Use the auto-attach `get_env()` wrapper (not raw `vm.get_env()`)
2. Clear pending Java exceptions after any JNI error
3. Log (don't silently drop) stream errors

### Relevant files
- `third_party/btleplug/src/droidplug/jni_utils/stream.rs` — Fix 2a + 2b
- `third_party/btleplug/src/droidplug/peripheral.rs` — Fix 2c
- `.ai/btleplug.md` — updated fork docs
- `.ai/btleplug_bugreport_2.md` — structured bug report for upstream
