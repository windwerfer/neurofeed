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
- [ ] Signal quality auto-start (4s all-green detection in FeedbackStateNotifier)
- [ ] Connection check on start — show connect overlay if Muse disconnected
- [ ] Wire FeedbackRecorder into session lifecycle
- [ ] End-of-session → session dashboard navigation
- [ ] Calibration completed event sound

## Phase 5: Session dashboard
- [ ] Bands/motion/pulse graphs from recorded data
- [ ] Stats (peak alpha, avg concentration, stillness)
- [ ] Notes text field
- [ ] Save (green) / Discard (gray) buttons
- [ ] Thumbnail generation

## Phase 6: Feedback history
- [ ] Session metadata persistence (JSON alongside .muse)
- [ ] History list view with thumbnails, dates, stats
- [ ] Tap to re-open dashboard
