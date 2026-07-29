# Feedback Dev Todos

## Current branch: feat/feedback-backbone

- [x] Create branch
- [x] .ai/feeback/ directory
- [x] Phase 0a-d: AppView, state machine, stub views, navigation
- [x] Phase 1a-c: Rust PPG, DTOs, derived metrics, forwarder
- [x] Phase 2a-b: Recording extension + FeedbackRecorder
- [x] Phase 2c: zstd compression via Rust compress_block FFI

## REQUIRED: FRB codegen (run on dev machine)

After pulling this branch, run:
```
flutter_rust_bridge_codegen generate
```

This resolves:
- `PulseDto`, `MovementDto`, `PeakAlphaDto` Dart classes
- New `MuseEventDto.pulse`, `.movement`, `.peakAlpha` variants
- `compressBlock()` top-level function in `muse.dart`
- `flutter analyze lib/src/` should then pass

## Phase 3 backlog: Audio (next)
- Add `audioplayers` to pubspec.yaml
- Create `AudioService` (play calibration, feedback, end chime)
- Place audio files in `assets/`
- Wire into FeedbackSessionView controls

## Phase 4: Full session flow
- Calibration → feedback → end state machine wiring
- Signal quality auto-start (4s all-green)
- Timer display + elapsed countdown
- Session end → dashboard navigation

## Phase 5: Session dashboard
- Bands/motion/pulse graphs from recorded data
- Stats (peak alpha, avg concentration, stillness)
- Notes + Save/Discard
- Thumbnail generation

## Phase 6: Feedback history
- List view with thumbnails, dates, stats
- Session metadata persistence
