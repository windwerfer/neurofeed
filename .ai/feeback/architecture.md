# Feedback System Architecture

## Overview
Biofeedback session system for Muse EEG headset. Protocols guide meditation
via real-time EEG metrics → audio feedback. Session data recorded, dashboard
displayed post-session, history browsable.

## Stack additions
- **audioplayers** (pub) — audio playback (Phase 3)
- New `lib/src/feedback/` — state machine, session models, recorder
- New `lib/src/views/` — feedback_list, feedback_session, feedback_history,
  session_dashboard
- Rust additions in `muse.rs` — pulse, movement, peak-alpha computation

## State machine (`FeedbackStateNotifier`)
```
Idle → Calibrating → Ready → Playing ⇄ Paused → Ended → Dashboard
```
- Independent Riverpod provider, watches `appStateProvider` for signal quality
  and event stream.
- `Idle`: protocol info + controls shown
- `Calibrating`: 60s calibration audio, monitoring signal
- `Ready`: calibration done, waiting for start or auto-start on 4s all-green
- `Playing`: feedback active, timer counting
- `Paused`: timer paused
- `Ended`: session complete, navigate to dashboard

## Data flow
```
Muse headset → BLE → muse-rs → Rust forwarder → MuseEventDto stream
                                                      ├─ Eeg → LiveCache
                                                      ├─ Bands → BandCache
                                                      ├─ Pulse → PulseBuffer
                                                      ├─ Movement → MovementBuffer
                                                      ├─ PeakAlpha → AlphaBuffer
                                                      └─ SessionRecorder (disk)
```

## Navigation
- Sidebar for main views: Feedback, Feedback History, Bands, Raw EEG, ...
- Feedback flow uses Navigator.push (modal), not sidebar state
- Dashboard shown after session ends, full-screen overlay

## Recording model
Two parallel tracks:
1. **Continuous .muse** — raw EEG/PPG/IMU/telemetry (unchanged, for replay)
2. **Session .muse** — 1Hz derived metrics + bands, aligned to feedback session
   lifecycle. Extended binary format with new type tags.

## Binary format (.muse) extensions
| Tag | Type | Rate | Fields |
|-----|------|------|--------|
| 1   | EEG | 256Hz | timestamp, electrode, count, samples[f64] |
| 2   | Telemetry | ~1Hz | timestamp, battery, fuel, temp |
| 3   | Accelerometer | ~52Hz | timestamp, seq_id, count, xyz[f64] |
| 4   | Gyroscope | ~52Hz | same |
| 5   | PPG | 64Hz | timestamp, channel, count, samples[f64] |
| 6   | BANDS | 1Hz | timestamp, electrode, delta, theta, alpha, beta, gamma |
| 7   | PULSE | 1Hz | timestamp, bpm, confidence |
| 8   | MOVEMENT | 1Hz | timestamp, score |
| 9   | PEAK_ALPHA | 1Hz | timestamp, frequency, power |
