# btleplug fork — Android JNI thread-attach patch

## Purpose

Patch btleplug 0.12.0 (Rust) to survive the **JNI `ThreadDetached` error**
that occurs when BLE operations run on tokio worker threads instead of the
JVM-attached Dart/UI thread. Without this patch, every BLE scan fails with
`"JNI call failed"` — a silent, opaque error that bubbles up as an
`anyhow::Error` from `muse_rs::MuseClient::scan_all()`.

## Where is the fork

**Published:** `github.com/windwerfer/btleplug` tag `0.12.0-muse-5`
**Local copy:** `../third_party/btleplug/` — for development.

Referenced from `muse_ml/rust/Cargo.toml` via `[patch.crates-io]`.
Both `rust_lib_muse_ml` and `muse-rs` depend on `btleplug = "0.12.0"` from crates.io; the
`[patch.crates-io]` replaces ALL occurrences with our fork so there is only one copy
of btleplug (and its `GLOBAL_JVM`/`GLOBAL_ADAPTER` statics) linked:

```toml
btleplug = "0.12.0"

[patch.crates-io]
btleplug = { git = "https://github.com/windwerfer/btleplug.git", tag = "0.12.0-muse-5" }
```

**For local development,** swap the patch to a local path:
```toml
[patch.crates-io]
btleplug = { path = "../third_party/btleplug" }
```

**Version matching:** the fork crate `version` is `"0.12.0"`, matching
`btleplug = "0.12.0"` in `rust/Cargo.toml`. If those diverge by semver, Cargo
**silently ignores** `[patch.crates-io]` and you link unpatched crates.io
btleplug (two `GLOBAL_JVM` statics, JNI panics). An older note said to pin
the fork at `0.11.8` — that was for when the dep was `0.11.x`. Do not revert
the fork to `0.11.8` while the dep is `0.12.0`. The patch target must be
`crates-io`, not a git URL, so muse-rs's transitive dep is replaced too.

## Changes made

### Batch 1 (Bug 1: ThreadDetached + QueueStream race)

Files: `jni/mod.rs`, `adapter.rs`, `peripheral.rs`, `classcache.rs`, `java/`

#### 1a. `src/droidplug/jni/mod.rs` — `get_env()` with auto-attach

```rust
pub(crate) fn get_env() -> Result<JNIEnv<'static>, ::jni::errors::Error> {
    match global_jvm().get_env() {
        Ok(env) => Ok(env),
        Err(_) => global_jvm().attach_current_thread_permanently(),
    }
}
```

This is the core fix. When a tokio worker thread calls `get_env()`, the JVM
reports `JNI_EDETACHED`. The fallback permanently attaches the thread so all
subsequent JNI calls succeed.

Added `log::debug!` / `log::warn!` / `log::info!` calls around each branch
for diagnostics in logcat.

#### 1b. All callers — `global_jvm().get_env()` → `get_env()`

Files changed:
- `src/droidplug/adapter.rs` (5 call sites) — scan, start_scan, etc.
- `src/droidplug/peripheral.rs` (2 call sites) — notification mapping

The upstream code directly calls `global_jvm().get_env()` which cannot handle
detached threads. Every call site was replaced with the wrapper.

**Note: the `JSendStream` polling path (`jni_utils/stream.rs`) was MISSED in
this batch — see Bug 2a below.**

#### 1c. `src/droidplug/jni_utils/classcache.rs` — `.unwrap()` → `?`

The upstream uses `.unwrap()` on `find_class()`, which panics (SIGABRT) when
a Java class is missing from the classpath. Replaced with `?` so the error
propagates as a proper `Result`.

#### 1d. Java source files (`muse_ml/android/app/src/main/java/...`)

The Rust code is based on btleplug 0.12.0 but the bundled Java sources were
from 0.11.8. Missing additions:

| File | Reason |
|------|--------|
| `NoBluetoothAdapterException.java` | Referenced in `jni::init()` + `start_scan` catch block |
| `Peripheral.java` methods | `getDeviceName`, `requestMtu`, `getConnectionParameters`, `requestConnectionPriority`, `readRemoteRssi` — eagerly resolved by `JPeripheral::from_env_impl()` |
| `Peripheral.java` callbacks | `onDescriptorRead`, `onMtuChanged`, `onReadRemoteRssi`, `onConnectionUpdated` in `Callback`/`CommandCallback` |

`writeDescriptor` signature also changed between versions: 0.11.8 had
`(UUID, UUID, byte[], int)`, 0.12.0 expects `(UUID, UUID, byte[])`.

#### 1e. `QueueStream.java` — fix `pollNext` race condition

The `pollNext()` method returned a lambda that called `this.result.remove()`
**outside** the `synchronized` block. Two tokio workers could both poll the
same stream, both see a non-empty queue, both get removal lambdas, and one
would crash with `NoSuchElementException` when the other had already drained
the queue.

**Fix:** Remove the value from the queue inside the `synchronized` block and
return a closure over the already-removed value.
See `.ai/btleplug_bugreport_1.md`.

### Batch 2 (Bug 2: Notification death spiral)

Files: `jni_utils/stream.rs`, `peripheral.rs`

#### 2a. `src/droidplug/jni_utils/stream.rs:133` — `JSendStream` uses auto-attach `get_env()`

```rust
// BEFORE:
let env = self.vm.get_env()?;
// AFTER:
let env = super::super::jni::get_env()?;
```

The `JSendStream::poll_next_internal` method (which runs on tokio worker
threads when the notification stream is polled) was using `self.vm.get_env()`
directly instead of the safe wrapper. This meant that if a tokio worker thread
that had never been attached to the JVM polled the stream, `get_env()` would
fail with `ThreadDetached`.

This was an oversight from Batch 1 — the `adapter.rs` and `peripheral.rs`
call sites were updated, but the `JSendStream` polling path was missed.

#### 2b. `src/droidplug/jni_utils/stream.rs:44-49` — Clear Java exceptions on JNI errors

```rust
fn clear_java_exception(&self) {
    if self.env.exception_check().unwrap_or(false) {
        self.env.exception_describe().ok();
        self.env.exception_clear().ok();
    }
}
```

When a JNI call fails (e.g., `call_method_unchecked`, `.l()`), any pending
Java exception stays on the `JNIEnv`. ALL subsequent JNI calls on that thread
fail with `"Java exception was not cleared"`. This makes a transient error
permanent, causing the notification stream to return errors forever.

**Fix:** Call `clear_java_exception()` before `call_method_unchecked` (to
clear any stale exception) and in the error path of `call_method_unchecked`
and `.l()` (to prevent the exception from persisting).

#### 2c. `src/droidplug/peripheral.rs:438-446` — Log stream errors

```rust
// BEFORE:
.filter_map(|item| async { item.ok() });
// AFTER:
.filter_map(|item| async move {
    match item {
        Ok(item) => Some(item),
        Err(err) => {
            log::warn!("[btleplug] notification stream error: {err:?}");
            None
        }
    }
});
```

The original `.filter_map(|item| async { item.ok() })` silently drops all
stream errors via `.ok()`. Combined with Bug 2b (persistent JNI exception),
this creates an infinite loop in `FilterMap` — `None` causes immediate
re-poll, which returns the same error, ad infinitum — consuming 100% CPU and
producing zero events.

**Fix:** Log the error. The exception clearing in Fix 2b prevents persistent
errors, so the loop exits after one retry.

## How to test

```bash
cd muse_ml
flutter run
# In another terminal:
adb logcat -s btleplug rust_lib_muse_ml RustError
```

Expected logcat output for a successful scan:
```
D/btleplug::droidplug::jni: [btleplug] get_env called
W/btleplug::droidplug::jni: [btleplug] get_env: thread detached, attaching permanently
I/btleplug::droidplug::jni: [btleplug] get_env: attached permanently
D/btleplug::droidplug::adapter: [btleplug] start_scan begin
D/btleplug::droidplug::adapter: [btleplug] start_scan call_method OK
```

## What's NOT changed

- Public API (traits, types) — untouched
- Other platform backends (BlueZ, CoreBluetooth, WinRT)
- Java class structure or package names
- JNI native method registration
