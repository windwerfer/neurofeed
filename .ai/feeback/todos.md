# Feedback Dev Todos

## Current branch: feat/feedback-backbone

- [x] Phase 0: Navigation backbone + state machine + stub views
- [x] Phase 1: Rust derived metrics (pulse, movement, peak alpha)
- [x] Phase 2: Recording extension + zstd compression
- [x] Phase 3: Audio playback (just_audio + AudioService)

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
