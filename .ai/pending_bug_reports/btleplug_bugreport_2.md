# Bug Report 2 — BLE notification stream silently dies (JNI death spiral)

## Summary

After ~6 seconds of streaming, ALL BLE notifications (EEG, telemetry, accel, gyro)
stop arriving simultaneously while the BLE GATT connection remains active. The
event-forwarding Rust task is alive (confirmed by 5-second heartbeat logs) but
receives zero events from the muse-rs event channel. Reconnection without app
restart leaves the UI frozen because `forwarder_running = true` prevents a new
forwarder from spawning (since fixed by ForwarderGuard).

## Environment

- **Device:** TB336FU (Android 14 / API 34)
- **Headset:** Muse S Classic (firmware 2.2.5), battery 52% ("bp":52 in v1 JSON)
- **Rust:** 1.97.1, tokio multi-threaded runtime (default rt-multi-thread)
- **btleplug fork:** `windwerfer/btleplug` tag `0.12.0-muse-2`, patched with
  `get_env()` auto-attach fix (Bug 1)
- **jni crate:** `=0.19` (pinned to match btleplug)

## Symptoms

```
I/rust_lib_muse_ml::api::muse(11377): [muse] pkt/s: eeg=108 bands=4 ppg=0 telem=13 accel=22 gyro=23 ctrl=4 conn=1 other=0
I/rust_lib_muse_ml::api::muse(11377): [muse] pkt/s: eeg=84 bands=4 ppg=0 telem=10 accel=18 gyro=17 ctrl=0 conn=0 other=0
I/rust_lib_muse_ml::api::muse(11377): [muse] pkt/s: eeg=89 bands=4 ppg=0 telem=10 accel=18 gyro=18 ctrl=0 conn=0 other=0
I/rust_lib_muse_ml::api::muse(11377): [muse] pkt/s: eeg=87 bands=4 ppg=0 telem=10 accel=18 gyro=19 ctrl=0 conn=0 other=0
I/rust_lib_muse_ml::api::muse(11377): [muse] pkt/s: eeg=88 bands=4 ppg=0 telem=10 accel=18 gyro=18 ctrl=0 conn=0 other=0
I/rust_lib_muse_ml::api::muse(11377): [muse] pkt/s: eeg=85 bands=4 ppg=0 telem=10 accel=18 gyro=17 ctrl=0 conn=0 other=0
  ← data flows for ~6 seconds, then SILENCE
I/rust_lib_muse_ml::api::muse(11377): [muse] forwarder: alive (epoch=1, no events for 5s, eeg=65 telem=7 accel=13 gyro=13)
I/rust_lib_muse_ml::api::muse(11377): [muse] forwarder: alive (epoch=1, no events for 5s, eeg=0 telem=0 accel=0 gyro=0)
I/rust_lib_muse_ml::api::muse(11377): [muse] forwarder: alive (epoch=1, no events for 5s, eeg=0 telem=0 accel=0 gyro=0)
  ← repeats every 5s forever, eeg=0 telem=0
```

- Data flows normally for ~6 seconds (confirmed by `pkt/s` log showing eeg, telem,
  accel, gyro, bands)
- Then ALL event types stop simultaneously
- Forwarder heartbeat fires every 5s confirming the task is alive but `rx.recv()`
  returns no events
- muse-rs `Classic: notif #N` logs also stop — no raw BLE notifications arrive
  at the Rust level
- The BLE GATT connection is NOT dropped (device LED stays green, no disconnect event)
- No panic, no crash, no error message — silent death

## Root Cause

Three independent bugs in the btleplug notification stream polling pipeline
conspire to create a silent, self-sustaining failure:

### Bug 2a — `JSendStream::poll_next_internal` bypasses the auto-attach `get_env()` wrapper

**File:** `src/droidplug/jni_utils/stream.rs:133`

```rust
// BROKEN: uses raw JavaVM::get_env() — fails on detached threads
let env = self.vm.get_env()?;
```

The main `get_env()` wrapper in `jni/mod.rs` (added for Bug 1) handles
`ThreadDetached` by calling `attach_current_thread_permanently()`. But
`JSendStream::poll_next_internal` was never updated to use it — it calls
`self.vm.get_env()` directly, which returns `Err(JniCall(ThreadDetached))`
when polled from a tokio worker thread that hasn't been attached to the JVM.

This is an **oversight from the Bug 1 fix.** The `adapter.rs` and
`peripheral.rs` call sites were updated to use the wrapper, but the
`JSendStream` polling path (which runs on tokio worker threads when BLE
notifications arrive) was missed.

### Bug 2b — Pending Java exceptions are never cleared, poisoning all future JNI calls

**File:** `src/droidplug/jni_utils/stream.rs:44-69`

When `call_method_unchecked` (or any JNI call) fails because of a Java
exception, the exception remains **pending** on the `JNIEnv`. Every subsequent
JNI call on that thread immediately fails with:
```
Java exception was not cleared
```

The `jni` crate's `?` operator propagates the initial `Err`, but the pending
exception is never cleared. This means:
1. First JNI poll fails (e.g., `ThreadDetached` before Bug 2a fix, or a
   transient Java exception)
2. The exception stays pending on the JNIEnv
3. ALL subsequent JNI calls on that thread fail immediately
4. The stream returns `Err` forever

**No code in the polling path calls `exception_clear()` or `exception_describe()`.**

### Bug 2c — `filter_map(|item| item.ok())` silently drops errors AND creates an infinite loop

**File:** `src/droidplug/peripheral.rs:438`

```rust
.filter_map(|item| async { item.ok() });
```

1. **Silent drop:** `Err(...)` is converted to `None` by `.ok()` and discarded
   without any log. The developer has no way to diagnose why notifications
   stopped.
2. **Infinite loop:** The `FilterMap` combinator in `futures-rs` has an
   optimization: when the filter returns `None`, it re-polls the underlying
   stream **in the same `poll_next` call** (without yielding to the executor).
   If the error condition persists (Bug 2b ensures it does), this creates a
   **tight infinite loop consuming 100% CPU**, never allowing other tasks on
   the same runtime to run and never producing any notification events.

## Trigger condition

The bugs only manifest on **tokio's multi-threaded runtime** (`rt-multi-thread`),
because:

1. The runtime has multiple worker threads. Notification polling and event
   forwarding may run on different threads.
2. Worker threads that have never been attached to the JVM trigger
   `ThreadDetached` (Bug 2a).
3. Even with Bug 2a fixed (using auto-attach), any transient Java exception
   (e.g., from Android BLE stack calling back into Java during characteristic
   value extraction) triggers Bug 2b → Bug 2c loop.

On a single-threaded runtime, polling would always be on the same attached
thread, so Bug 2a would not trigger. Bug 2b could still trigger from a Java
exception, but Bug 2c's infinite loop would stall the entire runtime (single
worker thread) — noticeable as an app freeze, not silent death.

## Fix

All three files in `third_party/btleplug/` (`src/droidplug/` subtree).

### Fix 2a — Use auto-attach `get_env()` in `JSendStream`

**File:** `src/droidplug/jni_utils/stream.rs:133`

```rust
// BEFORE:
let env = self.vm.get_env()?;
// AFTER:
let env = super::super::jni::get_env()?;
```

### Fix 2b — Clear Java exceptions before/after JNI calls

**File:** `src/droidplug/jni_utils/stream.rs:44-49` (new method)

```rust
fn clear_java_exception(&self) {
    if self.env.exception_check().unwrap_or(false) {
        self.env.exception_describe().ok();
        self.env.exception_clear().ok();
    }
}
```

Called:
- Before `call_method_unchecked` (to clear any stale exception from a previous
  failed call on this thread)
- After `call_method_unchecked` or `.l()` returns `Err` (to prevent the
  exception from persisting)

### Fix 2c — Log stream errors instead of silent drop

**File:** `src/droidplug/peripheral.rs:438-446`

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

While this doesn't prevent the infinite loop (FilterMap still re-polls on
`None`), it makes the failure visible in logs. Combined with Fix 2b (exception
clearing), the transient error is cleared and subsequent polls succeed, so the
loop exits immediately.

## Verification

Before the fix, the log shows:
```
pkt/s: eeg=108 ...  ← data flows
                    ← silence (no error, no crash)
forwarder: alive (epoch=1, no events for 5s, eeg=0 telem=0 ...)
forwarder: alive (epoch=1, no events for 5s, eeg=0 telem=0 ...)
```

After the fix, streaming continues indefinitely without gaps. If the fix fails,
a `[btleplug] notification stream error:` log line appears before the silence.

## Related bugs

| Bug | File | Issue | Fix |
|-----|------|-------|-----|
| 1 | `QueueStream.java:31` | `pollNext` removes outside `synchronized` block → `NoSuchElementException` on concurrent poll | Remove inside `synchronized`, return a closure over the already-removed value |
| 2a | `stream.rs:133` | `JSendStream` uses raw `vm.get_env()` without auto-attach | Use `super::super::jni::get_env()` with auto-attach |
| 2b | `stream.rs:44-69` | Pending Java exceptions never cleared, poisoning future JNI calls | Add `clear_java_exception()` before/after JNI calls |
| 2c | `peripheral.rs:438` | `filter_map` silently drops errors and re-polls immediately | Log errors; exception clearing prevents persistent failure loop |

## Notes

- Bug 2 is fundamentally caused by the mismatch between tokio's multi-threaded
  runtime and JNI's thread-attachment model. Every tokio worker thread that
  performs JNI operations must be permanently attached to the JVM.
- The `FilterMap` re-poll behavior is correct per the `futures-rs` contract
  (it's an optimization for skipping items). The bug is that the underlying
  stream keeps returning errors instead of `Pending`.
- `exception_describe()` prints the Java exception stack trace to logcat,
  which helps diagnose the original cause of the JNI failure.
