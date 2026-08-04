# Feedback System Architecture

## Overview
Biofeedback session system for Muse EEG headset. Protocols guide meditation
via real-time EEG metrics → audio feedback. Session data recorded, dashboard
displayed post-session, history browsable. **Status: Phase I merged to main,
ready for testing.**

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
Idle → Calibrating → Ready → Playing ⇄ Paused → Ended → Dashboard
                      └ interrupted (disconnect / bad signal, 10 s grace, auto-resume)
```
- Independent Riverpod provider, watches `appStateProvider` for signal quality
  and event stream.
- `Calibrating`: voice intro + 90 s silent baseline (movement-gated samples),
  percentile threshold from baseline.
- `Ready`: waiting for start or auto-start on 4 s all-green.
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
- **Reward chimes**: bowl pool (10 players) with soft 100 ms attack ramp;
  players reset on completion; movement gating (1 s buffer) blocks rewards.
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

## Navigation
- Sidebar for main views: Feedback, Feedback History, Bands, Raw EEG, ...
- Feedback flow uses Navigator.push (modal), not sidebar state
- Dashboard shown after session ends, full-screen overlay

## Recording model
Two parallel tracks:
1. **Continuous .muse** — raw EEG/PPG/IMU/telemetry (unchanged, for replay)
2. **Session .muse** — 1 Hz derived metrics + bands, aligned to feedback session
   lifecycle. Extended binary format with new type tags.

## Binary format (.muse) extensions
| Tag | Type | Rate | Fields |
|-----|------|------|--------|
| 1   | EEG | 256 Hz | timestamp, electrode, count, samples[f64] |
| 2   | Telemetry | ~1 Hz | timestamp, battery, fuel, temp |
| 3   | Accelerometer | ~52 Hz | timestamp, seq_id, count, xyz[f64] |
| 4   | Gyroscope | ~52 Hz | same |
| 5   | PPG | 64 Hz | timestamp, channel, count, samples[f64] |
| 6   | BANDS | 1 Hz | timestamp, electrode, delta, theta, alpha, beta, gamma |
| 7   | PULSE | 1 Hz | timestamp, bpm, confidence |
| 8   | MOVEMENT | 1 Hz | timestamp, score |
| 9   | PEAK_ALPHA | 1 Hz | timestamp, frequency, power |
