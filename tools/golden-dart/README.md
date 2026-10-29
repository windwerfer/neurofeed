# golden-dart: legacy feedback-engine fixtures

Headless Dart program, no Flutter. It writes `crates/nf-feedback/tests/golden/*.json`.
This is a dev tool: delete it together with `lib/` once the port is accepted.

```bash
tools/golden-dart/gen.sh   # needs the Dart SDK at ~/dart-sdk (3.x)
```

## Verbatim and transcribed code

- **Copied verbatim into `.vendor/`.** These files are used as they are:
  - `target_state.dart` (`RatioEngine`, stability math, `RelativeBandAggregator`);
  - `baseline_window.dart` (`BaselineWindow`, `BaselineFrameClock`);
  - `feedback_engine.dart`;
  - `feedback_phase.dart` (constants);
  - `stabilityOutputPercentile` from `reward_lane.dart`.

  Only three things change:
  - import paths;
  - `debugPrint` / `@immutable` / `BandsDto`, which come from `shim.dart`;
  - `DateTime.now()`, which becomes `shimNow()` so the harness can set the clock for each input (`w`, the wall time).
- **Transcribed in `bin/golden.dart`.** This is the glue that cannot run without Riverpod, FRB or audio:
  - `RewardLane.onFeature`;
  - the band-math path of `GuardLane` (percentile warn, 20 s chime cooldown);
  - the calibration accept rule (clean and all pads ≥ 80; staged = 15 s + 30 s timed stages, then the baseline window);
  - the 1 Hz ticker (adapt every 30 s);
  - the legacy band-feature aggregation from `rust/src/api/features.rs`.

## Not covered

- The AI guard (`ai.a_vig`, which needs the REVE model).
- EMA adaptation (off by default).
- Audio outputs.

`div_*` fixtures record the legacy behaviour where Rust differs on purpose. See `docs/decisions.md`, 2026-10-29.
