# Feedback Dev Todos

## Current branch: feat/feedback-backbone

- [x] Phase 0: Navigation backbone + state machine + stub views
- [x] Phase 1: Rust derived metrics (pulse, movement, peak alpha)
- [x] Phase 2: Recording extension + zstd compression
- [x] Phase 3: Audio playback (just_audio + AudioService)

## Phase 3.5: Dual-layer reward audio
- [x] Target-state predicate: relative band power (alpha_rel > theta_rel), AF7/AF8 average
- [x] Dual-layer engine: background (drone/rain at 0.35) + bowl reward chime (4-player pool, soft attack, tails preserved)
- [x] Movement gating: accel score > 0.05 resets hold timer and gates chimes (1s buffer)
- [x] Sound selector updated (Ambient Drone / Rain)
- [ ] v1.1: personalized baseline threshold (alpha_rel > baseline_alpha_rel * 1.2) via BaselineProfile
- [ ] v1.1: EEG artifact flag for jaw-clench/blink EMG (accel gating only catches head motion)

## Phase 4: Full session flow
- [x] Signal quality auto-start: 4s all-green (all channels ≥ 80) in ready phase → auto startPlaying
- [x] Connection check on start — opens connect window if Muse disconnected (calibration + playing)
- [x] Wire FeedbackRecorder into session lifecycle (start on playing, save on end, discard on reset)
- [x] End-of-session → session dashboard navigation (auto pushReplacement to stub dashboard)
- [x] Calibration completed event sound (bowl_high confirmation chime)
- [x] Disconnect during playing/paused → interrupted phase: pause session, 10s grace countdown, auto-resume on reconnect, end only if unrecovered (connect window auto-opens via connection_provider reconnect)
- [x] Persistent bad signal (any channel < 40 for 10s) → interrupted phase; recovers when signal returns to green

## Phase 5: Session dashboard
- [x] Session reader (`.muse` v3 parsing: tags 1–9, zstd frames via new `decompressBlock` FFI)
- [x] Bands/motion/pulse graphs from recorded data (alpha_rel vs theta_rel, movement score, bpm)
- [x] Stats: peak alpha (freq@max power), target time % (alpha_rel > theta_rel), stillness %, avg BPM, avg alpha_rel
- [x] Notes text field (persisted in Phase 6 metadata)
- [x] Save (green, renames temp → session_<ts>.muse) / Discard (gray, deletes temp) buttons
- [x] Thumbnail generation (RepaintBoundary → PNG next to .muse)

## Phase 6: Feedback history
- [ ] Session metadata persistence (JSON alongside .muse)
- [ ] History list view with thumbnails, dates, stats
- [ ] Tap to re-open dashboard
