# NeuroFeed

Companion app for Interaxon Muse EEG headsets. Flutter UI, Rust BLE stack
([muse-rs](https://github.com/windwerfer/muse-rs) `0.1.1`,
[btleplug](https://github.com/windwerfer/btleplug) `0.12.0-muse-5`).

## What it does

- **Connect** a Muse over BLE (Android). Debug mode adds a Simulator catalog.
  Neurosity Crown/Notion appear in the connect UI (OSC) and run feedback
  sessions on the 8-channel montage (PO3/PO4 reward default).
- **Live monitor** while connected: Bands, Raw EEG, Histogram, Spectrogram,
  PSD. Follow the live signal or Inspect recent history.
- **Record** from the graph bar. Saved recordings sit in the same History
  list as biofeedback sessions.
- **Biofeedback**: pick a program (or build one), 50 s silent calibration
  (or a staged AI sequence), then audio reward on a chosen EEG feature.
  Optional drowsiness **warning** (on-device CBraMod Candle / optional REVE or band-math delta)
  never changes the reward.
- **History**: sessions and recordings, notes, charts, export (PDF, CSV, EDF).
- **Streaming** to OSC, LSL, or BrainFlow while connected.

Preferences persist across restarts.

## Session files

Finished sessions and recordings are a single `.neurofeed` file:

```
[68-byte header][WebP thumbnail][metadata JSON (zstd)][computed 1 Hz (zstd)][raw body]
```

History lists them from SQLite (`session_metadata.db`) so opening the list
does not parse every file. Settings → **Save files to folder** chooses the
directory; changing it **moves** existing files.

Byte layout: [README_feedback_format.md](README_feedback_format.md).
History cache: [README_history_cache.md](README_history_cache.md).
Export: [`.ai/export.md`](.ai/export.md). Pad fit:
[`.ai/headset-fit.md`](.ai/headset-fit.md).

## EEG signal conditioning

Headsets send RAW EEG unfiltered: it carries a DC offset (Crown ≈ −200 000 µV),
slow drift and mains hum. Left in, they would inflate the spread-based pad
quality score and leak into the bands. So before quality, bands, features and
charts, every channel of every device goes through the same filter: a 0.5 Hz
high-pass (2nd-order Butterworth; keeps delta) and a Q 10 mains notch at
50/100 or 60/120 Hz (−3 dB width ≈ 4 Hz, close to BrainFlow's 4 Hz-wide
band-stop, so small mains drift is still removed). Mains is detected
automatically as 50, 60 or none (no notch) and saved per headset, so the next
connect starts with the right notch. Each recording or session keeps the notch
it started with; if nothing is known yet, it notches both 50 and 60 Hz.
RAW is saved unfiltered so anyone can reprocess it with their own pipeline.
The file records both (`device.rawFiltering`, `device.conditioning`; see
[fileformat_v6](.ai/contracts/fileformat_v6.md)).

| Source | Stored RAW | Quality, bands, features | Charts |
|--------|------------|--------------------------|--------|
| Muse Classic / Athena | as received; no device filter¹ | conditioned | conditioned |
| Crown (OSC) | as received; unfiltered² | conditioned³ | conditioned |
| EDF / EDF+ import | as in file (resampled to 256 Hz if needed) | bands from conditioned RAW | conditioned |
| Mind Monitor CSV import | as in file⁴ (resampled to 256 Hz if needed) | Mind Monitor's band columns; from conditioned RAW only if the CSV has none | conditioned |

¹ Interaxon: only the 2014 Muse (MU-01) had a hardware notch, and only in some
presets; MU-02, and MU-01 in research presets, have no hardware filtering
([LibMuse NotchFrequency](https://siddhantattavar.com/libmuse/enumcom_1_1choosemuse_1_1libmuse_1_1_notch_frequency.html));
the Muse app / Muse-IO notch was an option. Muse 2 / Muse S are not listed.
Athena is not documented there and is assumed the same. The app uses presets
p21/p20/p50 (Classic) and p1045 (Athena). ADC anti-alias filtering is not
documented. ² [crown-reader](https://github.com/dmty/crown-reader) and
Neurosity's BrainFlow tutorial filter the OSC RAW themselves. ³ Unless pad
quality is set to the Crown's own values. ⁴ Whether Mind Monitor's notch
setting affects its recorded RAW is not documented. EDF export writes the
stored RAW with Prefiltering `HP:DC N:none`; an imported EDF's Prefiltering
is kept in `import.prefiltering`. OSC/LSL/BrainFlow streaming sends the
conditioned signal.

**Bands** use the common EEG / neurofeedback ranges (BrainFlow, Muse, OpenBCI
GUI, IFCN): delta 1–4, theta 4–8, alpha 8–13, beta 13–30, gamma 30–45 Hz,
lower edge inclusive, so each 1 Hz bin counts once and mains (≥ 45 Hz) never.
Every second a 256-sample Hamming window (as Muse, OpenBCI GUI, MNE) gives a
one-sided PSD; band power is its sum over the band (a 10 µV sine → 50 µV²).

## Status

Android 10+ **arm64-v8a only** (no x86 emulator, no 32-bit). Linux and
Windows builds exist in CI; iOS/macOS are not a current target.

Muse (Classic, Athena) and Crown (OSC, with LAN discovery) work for the live
monitor, recordings and feedback sessions. Athena's extra optical channels are
not implemented.

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
