# muse_ml

Muse EEG headset companion app — Flutter + Rust via `flutter_rust_bridge`.
Protocol/transport: [muse-rs](https://github.com/eugenehp/muse-rs) patched to
[windwerfer/muse-rs](https://github.com/windwerfer/muse-rs) tag `0.1.1`.

## Features

- **BLE scan + connect** to Muse S (Android), autoconnect to last device;
  Neurosity Crown/Notion over OSC (connect UI only — sessions refused);
  Muse/Crown simulators
- **Biofeedback sessions**: 50 s silent calibration (or staged AI sequence) →
  personalized threshold on a chosen feature (ATR and other band ratios) →
  real-time audio feedback
  - Reward / guard / background as separate outputs (chimes, rain, music
    filter, binaural, warning sounds)
  - Movement-gated rewards, dynamic adaptive target with lockout guards,
    in-flight recalibration
  - 5 volume channels (master × background / feedback / intro / end bell /
    guardrail)
  - Custom programs via the protocol builder (same JSON type as the catalog)
- **AI sleep guardrail**: on-device drowsiness (REVE/LUNA) or band-math
  delta; warning only, never modulates the reward
- **Session dashboard + history**: graphs, stats, notes, save/discard,
  SQLite-backed list

All user preferences persist across restarts.

## Session file format

Each finished session is a **single self-contained `.muse.feedback`** file:

```
[68-byte header][WebP thumbnail][metadata JSON (zstd)][computed 1Hz (zstd)][raw (zstd)]
```

- The leading WebP thumbnail and zstd-compressed metadata are stored in the head for instant loading and thumbnail preview.
- The `json` holds `SessionMetadata` (protocol, timings, sound, notes, stats).
- Computed 1Hz frames provide decimated telemetry for fast charting and export.
- The raw section contains the compressed frame stream parsed by `SessionReader`
  (see `lib/src/charts/session_reader.dart`).
- **History view is fast**: listing and thumbnails load via SQLite
  (`session_metadata.db`, thumbnail BLOB) and v5 head reads.

Sessions live in the chosen save folder (see Settings → *Save feedback to
folder*). Changing the folder **moves** (not copies) existing sessions.
Live recordings stream to a hidden `.cache/` subfolder and are only assembled
into the final `.muse.feedback` on save.

## Status

See [`.ai/active-task.md`](.ai/active-task.md). On-device checklist:
[`.ai/feedback/todos.md`](.ai/feedback/todos.md).

## Quick start

```bash
flutter run
```

Scan for nearby Muse headsets by tapping **Rescan**.

**Supported:** Android 10+ (API 29), **arm64-v8a only** (no x86 emulator,
no 32-bit). Older API levels would theoretically work but are untested.

### Linux / dev-container audio

Audio uses **flutter_soloud**, whose Linux backend is ALSA. The dev-container
has no sound card and plays through the host's PulseAudio/PipeWire socket
(`PULSE_SERVER=unix:/tmp/pulse-socket`). That requires:

- `libasound2-plugins` + an active `/etc/alsa/conf.d/99-pulseaudio-default.conf`
  (the package ships it as `.example`; the Dockerfile `cp`s it) so ALSA's
  `default` PCM routes to PulseAudio.
- `TRY_SYSTEM_LIBS_FIRST=1` + `libopus-dev libogg-dev libvorbis-dev libflac-dev`
  when building, so flutter_soloud links the system Xiph codecs instead of its
  glibc-2.43-precompiled ones.

All of this is already in `.devcontainer/Dockerfile`. Verify playback with
`aplay -D default /tmp/beep.wav` (silent output usually means the ALSA → Pulse
routing above is missing, not that the app is broken).

## Debugging

```bash
# Rust + BLE logs
adb logcat -s btleplug rust_lib_muse_ml RustError

# Everything muse-related
adb logcat | grep -iE "scan_all|btleplug|muse"

# ATR adaptation diagnostics (10 s cadence + adapt events)
adb logcat | grep -E "\[atr\]|\[feedback\]|\[chime\]"
```

## Architecture

```
Flutter UI (lib/src/) ←─ FFI ──→ Rust (rust/src/api/muse.rs)
                                    ↕ muse-rs 0.1.1 (patched fork)
                                    ↕ btleplug 0.12.0-muse-5
                                    ↕ Android BLE (JNI)
```

BLE transport: [btleplug fork](https://github.com/windwerfer/btleplug) tag
`0.12.0-muse-5`. See [`.ai/btleplug.md`](.ai/btleplug.md) and
[`.ai/muse-rs.md`](.ai/muse-rs.md). Full map:
[`.ai/README.md`](.ai/README.md).

## Third-party notices

Credits and licenses for every bundled library, the REVE/LUNA model engine,
and the freesound audio assets live in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) (also visible in-app under
**Settings → About → Third-party notices**).
