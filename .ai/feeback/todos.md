# Feedback Dev Todos

## Current branch: feat/feedback-backbone

- [x] Create branch
- [x] .ai/feeback/ directory
- [x] Phase 0a: AppView enum + settings.dart
- [x] Phase 0b: Feedback state machine + session models
- [x] Phase 0c: Stub views (feedback_list, feedback_session, feedback_history)
- [x] Phase 0d: Wire up navigation + sidebar in app.dart
- [x] Phase 1a: Enable PPG + add new DTOs in Rust
- [x] Phase 1b: Implement pulse/movement/peak-alpha algorithms in Rust
- [x] Phase 1c: Emit new events from forwarder
- [x] Phase 2a: Extend .muse recording for new data types (Bands)
- [x] Phase 2b: Feedback-aware recorder wrapper

## Pending (require FRB codegen on dev machine)

- [ ] Run `flutter_rust_bridge_codegen generate` to generate Dart types for PulseDto, MovementDto, PeakAlphaDto, and new MuseEventDto variants
- [ ] Wire Pulse/Movement/PeakAlpha into SessionRecorder after codegen
- [ ] Wire Pulse/Movement/PeakAlpha into connection_provider event handler (for UI display)

## Future phases
- Phase 3: Audio playback (audioplayers + AudioService)
- Phase 4: Feedback protocol selection UI (big buttons — DONE in Phase 0c)
- Phase 5: Full session flow (calibration → feedback → end)
- Phase 6: Session dashboard (graphs, stats, notes, save)
- Phase 7: Feedback history (list, thumbnails, stats)
