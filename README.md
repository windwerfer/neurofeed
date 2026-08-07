# muse_ml

Muse EEG headset companion app — Flutter + Rust via `flutter_rust_bridge`. Uses the [Rust Muse package eugenehp/muse-rs](https://github.com/eugenehp/muse-rs)

## Features

- **BLE scan + connect** to Muse S (Android), autoconnect to last device
- **Biofeedback sessions**: 90 s silent calibration → personalized ATR threshold → real-time audio feedback
  - Dual-layer audio: ambient background loop (drone/rain) + reward bowl chimes
  - Movement-gated rewards, dynamic adaptive target with lockout guards, in-flight recalibration
  - 5-channel volume control (master / background / feedback / intro / end bell)
  - Target settings: dynamic-target on/off + gentle↔responsive adaptation slider
- **Session dashboard**: bands/motion/pulse graphs, stats, notes, save/discard
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

Feedback feature — Phase I merged to `main`, **ready for device testing** (see
`.ai/feeback/todos.md` for the test checklist and what's next).

## Quick start

```bash
flutter run
```

Scan for nearby Muse headsets by tapping **Rescan**.

**Supported:** Android 10+ (API 29), 64-bit only (`arm64-v8a` / `x86_64`).
Older API levels would theoretically work but are untested.

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
