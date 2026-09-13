# Muse ML

Companion app for Interaxon Muse EEG headsets. Flutter UI, Rust BLE stack
([muse-rs](https://github.com/windwerfer/muse-rs) `0.1.1`,
[btleplug](https://github.com/windwerfer/btleplug) `0.12.0-muse-5`).

## What it does

- **Connect** a Muse over BLE (Android). Debug mode adds a Simulator catalog.
  Neurosity Crown/Notion appear in the connect UI (OSC); **Start Session**
  for Crown is refused.
- **Live monitor** while connected: Bands, Raw EEG, Histogram, Spectrogram,
  PSD. Follow the live signal or Inspect recent history.
- **Record** from the graph bar. Saved recordings sit in the same History
  list as biofeedback sessions.
- **Biofeedback**: pick a program (or build one), 50 s silent calibration
  (or a staged AI sequence), then audio reward on a chosen EEG feature.
  Optional drowsiness **warning** (on-device REVE/LUNA or band-math delta)
  never changes the reward.
- **History**: sessions and recordings, notes, charts, export (PDF, CSV, EDF).
- **Streaming** to OSC, LSL, or BrainFlow while connected.

Preferences persist across restarts.

## Session files

Finished sessions and recordings are a single `.muse.feedback` file:

```
[68-byte header][WebP thumbnail][metadata JSON (zstd)][computed 1 Hz (zstd)][raw (zstd)]
```

History lists them from SQLite (`session_metadata.db`) so opening the list
does not parse every file. Settings → **Save files to folder** chooses the
directory; changing it **moves** existing files.

Byte layout: [README_feedback_format.md](README_feedback_format.md).
History cache: [README_history_cache.md](README_history_cache.md).
Export: [`.ai/export.md`](.ai/export.md). Pad fit:
[`.ai/headset-fit.md`](.ai/headset-fit.md).

## Status

Android 10+ **arm64-v8a only** (no x86 emulator, no 32-bit). Linux and
Windows builds exist in CI; iOS/macOS are not a current target.

Live monitor + connect-time recording is implemented. Crown *sessions*,
OSC discovery, and Athena extra optical channels are not.

## Quick start

```bash
flutter run
```

Tap the status bar to open **Connect**, then **Rescan** for a Muse.

Agent-oriented build/test notes (Linux audio, FFI, logcat):
[`.ai/testing-guide.md`](.ai/testing-guide.md). Internals index:
[`.ai/README.md`](.ai/README.md).

## Third-party notices

Credits and licenses: [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)
(also **Settings → About → Third-party notices**).
