# btleplug Android — JNI `ThreadDetached` on tokio worker threads

## Section 1 — High-level summary

**Problem:** `scan_all` (and any BLE operation) fails with an opaque `"JNI call
failed"` error when btleplug runs on Android. The root cause is that
btleplug's Android backend calls `global_jvm().get_env()` directly, which
returns `JNI_EDETACHED` when called from a tokio worker thread. The `jni`
crate's `get_env()` does not auto-attach, and btleplug has no fallback.

**Fix:** Replace every `global_jvm().get_env()` call with a new `get_env()`
wrapper that falls back to `attach_current_thread_permanently()` when the
current thread is detached. This is a localised, one-function change — 5 call
sites in `adapter.rs` and 2 in `peripheral.rs` were updated to use the
wrapper instead of the raw JVM call.

**Files touched (Rust):** `jni/mod.rs` (new `get_env()` + diagnostics),
`adapter.rs`, `peripheral.rs` (callers), `classcache.rs` (`.unwrap()` → `?`
for robustness).

**Additional context:** The Java source files bundled in the APK were from
btleplug 0.11.8 while the Rust code had evolved to expect 0.12.0 Java APIs
(5 new methods, changed `writeDescriptor` signature, missing callback
overrides). These were added to match.

## Section 2 — Technical details

### Why `JNI_EDETACHED` happens

Android's BLE scanning is asynchronous — `startScan` returns immediately and
results arrive later via a `ScanCallback`. In btleplug's droidplug backend,
scan operations run on tokio's multi-threaded runtime. Tokio worker threads
are **not** attached to the JVM. When the runtime later processes JNI events
(e.g., `reportScanResult` native callback → Rust handler → JNI calls back
into Java), the thread calling `JavaVM::get_env()` is detached, producing
`JNI_EDETACHED`. The `jni` crate maps this to
`Err(Error::JniCall(JniError::ThreadDetached))`, which btleplug does not
handle — it propagates as a generic `"JNI call failed"`.

### Why `attach_current_thread_permanently()` is safe

`attach_current_thread_permanently()` attaches the current native thread to
the JVM permanently (it is never detached). This is appropriate because:

- Tokio worker threads are **long-lived** (they exist for the duration of the
  process). They are never pooled or recycled in a way that would leak
  attachments.
- The Android JVM implementation handles permanent attachments efficiently.
- There is no need to detach on cleanup — the JVM automatically handles
  daemon-thread-style attachments on process exit.

### Diagnosing the issue

Enable verbose JNI logging:
```bash
adb logcat -s btleplug rust_lib_muse_ml '*:V'
```

A detached thread shows:
```
W/btleplug::droidplug::jni: get_env: thread detached, attaching permanently
```

Without the patch, you see only:
```
V/jni::wrapper::java_vm::vm: calling unchecked JavaVM method: GetEnv
[no "attached OK" follows]
E/rust_lib_muse_ml::api::muse: [muse] scan_all failed: JNI call failed
```

### `[patch]` version trap

Cargo's `[patch]` section silently ignores the patch if the patched crate's
`Cargo.toml` `version` field does not satisfy the dependency's semver
constraint. Our fork had `version = "0.12.0"` while the project depends on
`^0.11.8` — the patch was silently skipped and the unpatched upstream was
used. This wasted significant debugging time. **Always verify**:

```bash
cargo tree -p btleplug --depth 0
# Must show your local path, not a git source
```

### Java source compatibility

The Rust code in the fork is based on upstream btleplug 0.12.0 (with patches),
but the Java sources bundled in our APK were from 0.11.8. This caused
`NoSuchMethodError` at runtime because `JPeripheral::from_env_impl()` eagerly
resolves **all** method IDs, including ones that don't exist in the older Java
class. The same issue applies to `classcache::find_add_class()` — it calls
`env.find_class(classname).unwrap()`, which panics if the class doesn't exist.

## Section 3 — Detailed changes

### File: `src/droidplug/jni/mod.rs` (core fix)

**Added:** `get_env()` — a module-level wrapper around
`global_jvm().get_env()` with automatic fallback:

```rust
pub(crate) fn get_env() -> Result<JNIEnv<'static>, ::jni::errors::Error> {
    match global_jvm().get_env() {
        Ok(env) => Ok(env),                                    // already attached
        Err(_) => global_jvm().attach_current_thread_permanently(), // attach on demand
    }
}
```

**Added:** `log::debug!` / `log::warn!` / `log::info!` instrumentation for
each branch to make the thread-attachment visible in logcat.

### File: `src/droidplug/adapter.rs` (callers)

**Changed:** 5 calls from `global_jvm().get_env()` → `get_env()`:
- `Adapter::new()` line 46
- `Adapter::report_scan_result()` line 66
- `Adapter::report_properties()` line 94 (via a helper)
- `Adapter::start_scan()` line 143
- `Adapter::stop_scan()` line 185

**Changed:** `start_scan()` now uses a match instead of `?` on
`call_method()` so JNI errors can be logged before propagating.

**Changed:** `try_block` closure restructured to return
`Result<Result<(), crate::Error>, jni::errors::Error>` — the original form
`env.call_method(...)?; Ok(Ok(()))` was preserved (not matched), so the inner
error type is correctly inferred as `crate::Error` from the `.catch()`
callbacks' return type `Ok(Err(crate::Error::...))`.

### File: `src/droidplug/peripheral.rs` (callers)

**Changed:** 2 calls from `global_jvm().get_env()` → `get_env()`:
- `Peripheral::from_env()` line 202
- `Peripheral::with_obj()` line 414

### File: `src/droidplug/jni_utils/classcache.rs` (panic → error)

**Changed:** `.unwrap()` on `env.find_class()` and
`env.new_global_ref()` → `?`:

```rust
// Before (panics if class not found):
env.new_global_ref(env.find_class(classname).unwrap()).unwrap();

// After (propagates as Result::Err):
let class = env.find_class(classname)?;
let gref = env.new_global_ref(class)?;
cache.insert(classname.to_owned(), gref);
```

### File: `Cargo.toml` (version compatibility)

**Changed:** `version = "0.12.0"` → `"0.11.8"` so the `[patch]` in the
consumer's `Cargo.toml` (`^0.11.8`) actually applies.

### Java: `Peripheral.java` (API alignment)

**Fixed:** `writeDescriptor(UUID, UUID, byte[], int)` → `(UUID, UUID, byte[])`
— the 4th `writeType` parameter was removed to match the 0.12.0 signature.

**Added methods** (all required by `JPeripheral::from_env_impl()` eager
method-ID resolution):
- `String getDeviceName()` — delegates to `BluetoothDevice.getName()`
- `Future<Integer> requestMtu(int)` — full implementation with command queue
- `int[] getConnectionParameters()` — returns `null` (best-effort)
- `boolean requestConnectionPriority(int)` — delegates to `BluetoothGatt`
- `Future<Integer> readRemoteRssi()` — full implementation with command queue

**Added callback overrides** (required for completion of above futures):
- `onDescriptorRead` in `Callback` and `CommandCallback`
- `onMtuChanged` in `Callback` and `CommandCallback`
- `onReadRemoteRssi` in `Callback` and `CommandCallback`
- `onConnectionUpdated` in `Callback` (informational only)

### Java: `NoBluetoothAdapterException.java` (new file)

```java
package com.nonpolynomial.btleplug.android.impl;
class NoBluetoothAdapterException extends BluetoothException {}
```

Referenced by `jni::init()` (via `classcache::find_add_class`) and by
`start_scan`'s `.catch()` block. Without this class, init panics with
SIGABRT.

## Suggestions for upstream

1. **Replace `global_jvm().get_env()` with the wrapper** — it's a drop-in
   replacement that adds no overhead on the happy path (already-attached
   thread) and gracefully handles detached threads. The change touches only
   3 files and is trivially maintainable.

2. **Consider `attach_current_thread_permanently()` vs
   `attach_current_thread()`** — The permanent variant is correct for tokio
   workers; the scoped guard (`AttachGuard`) would detach on drop, which
   is wrong for async tasks that yield across await points onto different
   threads.

3. **Use `?` instead of `.unwrap()` in `classcache.rs`** — This is a
   correctness fix independent of the thread-attach issue.

4. **Document the `[patch]` version pitfall** in a CONTRIBUTING or README
   note — it cost several hours of debugging.

5. **Make Java API version explicit** — The Rust code relies on specific
   Java method signatures; consider a version check or a CI step that
   validates Java/Rust API alignment.
