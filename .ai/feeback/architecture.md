# Feedback System Architecture

## Overview
Biofeedback session system for Muse EEG headset. Protocols guide meditation
via real-time EEG metrics → audio feedback. Session data recorded, dashboard
displayed post-session, history browsable. **Status: Phase I + session summary
graphs + editable history notes merged to main.**

## Stack additions
- **just_audio** (pub) — audio playback (media_kit Linux backend; the
  `Failed to create file cache.` log is a non-fatal mpv disk-cache warning).
- `lib/src/feedback/` — state machine, ATR engine, session models, recorder
- `lib/src/audio/` — `AudioService` (facade) + `FeedbackAudioController` (players)
- `lib/src/views/` — feedback_list, feedback_session, feedback_history,
  feedback_dashboard
- Rust additions in `muse.rs` — pulse, movement, peak-alpha computation

## State machine (`FeedbackStateNotifier`)
```
Idle → Calibrating → Playing ⇄ Paused → Ended → Dashboard
                   └ interrupted (disconnect / bad signal, 10 s grace, auto-resume)
```
- Independent Riverpod provider, watches `appStateProvider` for signal quality
  and event stream.
- `Calibrating`: voice intro + 90 s silent baseline (movement-gated samples),
  percentile threshold from baseline.
- Auto-start: when calibration completes with all channels green, feedback
  starts immediately (no ready phase / start button).
- `Playing`/`Paused`: feedback active; `Interrupted` pauses session with grace
  countdown and auto-recovers on reconnect / signal recovery.
- `Ended`: navigate to dashboard.

## ATR target engine (`AtrEngine`)
- Target predicate: relative band power (alpha_rel > theta_rel), AF7/AF8 average.
- Baseline: sorted baseline samples → configured percentile (default p40) = threshold.
- Dynamic adaptation every 30 s over a 300-epoch (~30 s at 10 Hz) success window:
  - raise when success > 0.8, lower when < 0.4 — step sizes from a
    "responsiveness" setting (raise 1.01–1.03, lower 0.97–0.90).
  - **Clamped**: never above `baselineMean + 1.5·baselineStddev`, never below
    the baseline percentile.
  - **Circuit breaker**: a zero-success window resets the threshold to the
    baseline percentile immediately (no slow ratchet-down).
  - Can be fully disabled (static threshold) via the dynamic-target toggle.
- In-flight recalibrate: rebuilds the baseline from the last 90 s of clean
  (movement-free) session samples; requires ≥ 60 s elapsed and ≥ 30 clean
  samples; resets the success window and re-anchors the ceiling automatically.

## Audio (dual-layer, 5 volume channels)
- **Background**: ambient loop (Ambient Drone / Drone Loop / Rain), looped.
- **Reward chimes**: bowl pool (10 players) started at full feedback volume
  (no attack ramp); players reset on completion; movement gating (1 s buffer)
  blocks rewards.
- **Intro**: calibration voice (once per calibration).
- **End bell**: session end chime; also reused (at 0.6×) as the soft
  recalibrate cue.
- Effective volume = master × channel (background / feedback / intro / end
  bell). All persist via `Settings` (SharedPreferences) and restore on launch.

## Persistence (`Settings`)
User prefs: 5 volume channels, background sound, session duration,
dynamic-target toggle, responsiveness. `settingsProvider` overridden in
`main()`; `FeedbackStateNotifier` restores sound + duration and engine options
at construction.

## Data flow
```
Muse headset → BLE → muse-rs → Rust forwarder → MuseEventDto stream
                                                      ├─ Eeg → LiveCache
                                                      ├─ Bands → TargetStateAggregator → AtrEngine
                                                      ├─ Pulse → PulseBuffer
                                                      ├─ Movement → gating
                                                      └─ SessionRecorder (disk)
```
- Forwarder (rust/src/api/muse.rs): 1 s poll of `guard.events` — picks up a
  reconnect's fresh channel within ~1 s; emits `Disconnected` after 30 s of
  total silence (dead link without a disconnect event) so the app reconnects.

## Navigation
- Sidebar for main views: Feedback, Feedback History, Bands, Raw EEG, ...
- Feedback flow uses Navigator.push (modal), not sidebar state
- Dashboard shown after session ends, full-screen overlay

## Recording model
Two parallel tracks:
1. **Continuous .muse** — raw EEG/PPG/IMU/telemetry (unchanged, for replay)
2. **Session .muse** — 1 Hz derived metrics + bands, aligned to feedback session
   lifecycle. Extended binary format with new type tags.

## Binary format (.muse)
The byte layout is owned by Rust (`rust/src/api/session_format.rs`, format v4).
This table is descriptive; the encode/parse/frame/container fns there are the
authority, and Dart (SessionRecorder/SessionReader/SessionContainer) only
delegates over FFI. All float payloads are f32, timestamps f64, little-endian;
records are batched into zstd frames:
| Tag | Type | Rate | Fields |
|-----|------|------|--------|
| 1   | EEG | 256 Hz | timestamp, electrode, count, samples[f32] |
| 2   | Telemetry | ~1 Hz | timestamp, battery, fuel, temp |
| 3   | Accelerometer | ~52 Hz | timestamp, seq_id, count, xyz[f32] |
| 4   | Gyroscope | ~52 Hz | same |
| 5   | PPG | 64 Hz | timestamp, channel, count, samples[f32] |
| 6   | BANDS | 1 Hz | timestamp, electrode, delta, theta, alpha, beta, gamma |
| 7   | PULSE | 1 Hz | timestamp, bpm, confidence |
| 8   | MOVEMENT | 1 Hz | timestamp, score |
| 9   | PEAK_ALPHA | 1 Hz | timestamp, frequency, power |

The `.muse.feedback` container is single-file and PNG-first:
`[PNG][jsonLen u32 BE][json][bodyLen u32 BE][body]` (also Rust-owned).

## Session summary dashboard & editable notes
- The read-only history detail renders from `SessionOverview` (400-bucket
  decimated bands/pulse/movement/peak stored in the metadata `summary` key) —
  no `.muse` body read on the fast path; legacy files fall back to
  `SessionReader.readBytes`.
- Charts are zoom-synced (shared `_ChartViewport` in `feedback_dashboard.dart`):
  drag to pan, pinch on touch, **ctrl/⌘ + scroll on desktop** to zoom, double-tap
  to reset. Legend labels toggle each series on/off. Bands + Alpha-vs-Theta use a
  fixed 0–1 y-axis (relative power, comparable across sessions) with numeric
  ticks; Movement/Heart-rate stay auto-scaled.
- **Notes are editable in the history detail too**: a small save chevron appears
  in the corner of the notes field only while the text is dirty; a `PopScope`
  intercepts Back with "Unsaved notes — Save / Stay / Discard". Saves go through
  `SessionStore.updateNotes` → `SessionStorage.writeFileAtomic`.
- Crash-safe write: **every history write** (`publishSession`, `updateNotes`,
  `moveAllTo`) goes through `SessionStorage.writeFileAtomic`. Filesystem writes
  `.name.tmp` + atomic `rename()`; SAF (native `writeFileAtomic` in
  `MainActivity.kt`) writes `name.mtmp`, deletes the old target,
  `renameDocument` swap, with `recoverDoc()` healing an interrupted swap on
  every read *and* during `listFiles` (a first pass heals any orphaned `.mtmp`
  so a recovered session reappears in listings; surviving `.mtmp` leftovers are
  skipped).
