# Bug Report 3 — QueueStream / SimpleFuture wake-after-close SIGSEGV (Android BLE)

| Field | Value |
|---|---|
| Status | Fixed on `bughunt/android_crashes` in both neurofeed (app Java) and `windwerfer/btleplug` rev `327de2cda7634248175414da093b019462252855`; Cargo pin updated; no muse tag yet |
| Date | 2026-09-22 |
| Severity | Critical (native crash) |
| Repro | Muse Classic + Record (sidebar → Bands); often within minutes; simulator unaffected |

## Symptom

`Fatal signal 11 (SIGSEGV)` on `binder:…` after sustained BLE notifications. Stack:

`BluetoothGattCallback.onCharacteristicChanged` → `Peripheral$Callback` → `QueueStream.add` → `Waker.wake` → `FnAdapter.call` → garbage `pc`.

Process uptime in one capture ~842 s. Logcat still showed healthy `[muse] pkt/s` until the fault.

## Root cause

Bundled Java (`android/app/src/main/java/io/github/gedgygedgy/rust/…`):

- `QueueStream.doEvent` copied `this.waker` **without clearing**, then called `wake()` outside the lock.
- Concurrent `pollNext` could `close()` that same `Waker` (drops Rust `FnAdapter` via `take_rust_field`) while the binder thread was still in `wake()` / `get_rust_field`.
- Same pattern in `SimpleFuture.wakeInternal`.

This is **not** Bug 2 (silent notification death / JNI exception loop). Same subsystem, different failure mode.

## Fix

Take-and-null under the lock before waking:

```java
waker = this.waker;
this.waker = null;
```

Applied in app sources and mirrored to `windwerfer/btleplug` branch `bughunt/android_crashes` (`327de2cd…`). neurofeed Cargo `[patch]` pins that rev. **Optional later:** cut a new muse tag once validated; do not merge to btleplug `main` yet.

## Why Record looked worse

Hypothesis: capture + FGS load slows Rust polling of the notification stream → more wake/close races. Screen-off may change binder scheduling; not required for the bug.
