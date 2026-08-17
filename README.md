# muse_ml

Muse EEG headset companion app — Flutter + Rust via `flutter_rust_bridge`. Uses the [Rust Muse package eugenehp/muse-rs](https://github.com/eugenehp/muse-rs)

## Features

- **BLE scan + connect** to Muse S (Android), autoconnect to last device
- **Biofeedback sessions**: 90 s silent calibration → personalized ATR threshold → real-time audio feedback
  - Dual-layer audio: ambient background loop (drone/rain) + reward bowl chimes
  - Movement-gated rewards, dynamic adaptive target with lockout guards, in-flight recalibration
  - 5-channel volume control (master / background / feedback / intro / end bell)
  - Target settings: dynamic-target on/off, gentle↔responsive adaptation slider, reward-threshold percentile (1 % steps, live reading)
- **AI sleep guardrail**: on-device drowsiness scoring (REVE/LUNA models) with a configurable warning sound and threshold
  - Scorer engine picker (green ✓ for installed models, inline download/import in the dialog), band-math fallback without any model
  - Warning sounds: soft bowl / bell chime / cough / alarm clock (repeats with a volume ramp) / none; per-protocol guardrail toggle
- **Session dashboard**: bands/motion/pulse graphs, stats, notes, save/discard, sleep-guardrail drowsiness trace
- **Feedback history**: session list with thumbnails, re-open past sessions

All user preferences (volumes, sound, duration, target settings) persist across restarts.

## Session file format

Each finished session is a **single self-contained `.muse.feedback`** file:

```
[ PNG thumbnail ][ jsonLen u32 BE ][ metadata json ][ bodyLen u32 BE ][ frame body ]
```

- The leading PNG is the session thumbnail. Because PNG decoders stop reading at
  the `IEND` chunk, file managers on **Linux and macOS** render a real thumbnail
  from this file while ignoring the trailing data. Windows/Android show a generic
  icon.
- The `json` holds `SessionMetadata` (protocol, timings, sound, notes, stats).
- The `body` is the compressed frame stream parsed by `SessionReader`
  (see `lib/src/charts/session_reader.dart`).
- **History view is fast**: listing and thumbnails only read the small head
  (`readPrefix`) and never pull the large body. See
  `lib/src/feedback/session_container.dart`.

Sessions live in the chosen save folder (see Settings → *Save feedback to
folder*). Changing the folder **moves** (not copies) existing sessions.
Live recordings stream to a hidden `.cache/` subfolder and are only assembled
into the final `.muse.feedback` on save.

## Status

Feedback Phase I + the REVE/LUNA AI sleep guardrail are on `main` — **ready for
device testing** (see `.ai/feeback/todos.md` for the test checklist and what's next).

## Quick start

```bash
flutter run
```

Scan for nearby Muse headsets by tapping **Rescan**.

**Supported:** Android 10+ (API 29), 64-bit only (`arm64-v8a` / `x86_64`).
Older API levels would theoretically work but are untested.

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
                                    ↕ muse-rs 0.1.0
                                    ↕ btleplug 0.11.8 (patched)
                                    ↕ Android BLE (JNI)
```

BLE transport: [my btleplug fork](https://github.com/windwerfer/btleplug) from the original [deviceplug/btleplug](https://github.com/deviceplug/btleplug) (tag
`0.12.0-muse-3`). JNI thread-attach patch for tokio worker threads + BLE notification death spiral fix; see
`.ai/btleplug.md` for details.

## Project docs (`.ai/`)

| File | Contents |
|------|----------|
| `btleplug.md` | btleplug fork changes and pitfalls |
| `bugreport.md` | Bug report for upstream btleplug |
| `architecture.md` | Current and target architecture |
| `lessons-learned.md` | Full debug history |
| `testing-guide.md` | Build/test loop |
| `active-task.md` | Current development focus |
| `feeback/architecture.md` | Feedback system architecture (state machine, ATR engine, audio) |
| `feeback/todos.md` | Feedback dev todos + Phase I test checklist |

## Third-party notices

Credits and licenses for every bundled library, the REVE/LUNA model engine,
and the freesound audio assets live in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) (also visible in-app under
**Settings → About → Third-party notices**).
