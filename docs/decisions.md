# Decisions (dated, append-only)

- 2026-10-29: Flutter dropped; Rust-only, egui on desktop/web/Android. Dart stays as reference until the feedback engine is ported, then is deleted in one commit.
- 2026-10-29: Android = thin native wrapper (permissions, BLE scan/transport via JNI if needed) hosting the same Rust core; it supplies a `DeviceProvider`, and talks to the core through the same command JSON surface.
- 2026-10-29: MCP surface = generic command_list/describe/run/batch + a few typed session tools. Add a command, not a tool.
- 2026-10-29: Command ids are dotted (`area.verb`); MCP tool names use underscores.
- 2026-10-29: Rust workspace moved to repo root; Flutter docs renamed AGENTS.flutter.md / README.flutter.md.
- 2026-10-29: No Dart NFED6 import compatibility work (Flutter is dropped). nf-format keeps the legacy byte layout, but the computed JSONL/thumbnail sections stay empty and band records hold our log10 values; Rust is the only reader.
- 2026-10-29: Wall clock is injected by shells: `recording.start {wall_clock_unix_ms}` is filled by the egui app (web-time) and by neurofeed-mcp in wall-clock mode; manual-clock MCP injects nothing (deterministic). Core never reads a clock.
- 2026-10-29: File output is a shell concern: MCP tool `recording_export {format, start?, path?}` writes natively when `path` is given; core `recording.export` only returns base64.
- 2026-10-29: Mains detection votes per channel window into one shared counter (as legacy); the notch is rebuilt warm (replaying 2 s of raw) on change; recordings freeze the notch in effect at start. Views may call pure `nf_core::dsp` functions on core buffers; all state stays in the Session.
- 2026-10-29: Simulator ids `sim:muse_s`, `sim:athena`, `sim:crown`; `sim:muse` opens `sim:muse_s` (reported id is the canonical one). Athena exposes the legacy 3-channel PPG view (ambient/infrared/red, 64 Hz); its AUX and fNIRS optics are not modelled. HR/SpO2 use the legacy algorithms unchanged (SpO2 = 110 - 25 R, uncalibrated).
- 2026-10-29 (supersedes the Athena part above): PPG/HR/SpO2 only on Muse 2 (`sim:muse2`) and Muse S (`sim:muse_s`). `sim:athena` has no PPG; hr/spo2/ppg queries are disabled there with a reason. Athena optics come in a separate patch set.

## 2026-10-29: nf-feedback, a faithful port of the engine math plus four deliberate fixes

The hybrid plan from `docs/review-feedback-engine.md` is approved, with the current defaults:
- 40th-percentile threshold;
- 75 s success window;
- adaptation every 30 s;
- ceiling at mean + 1.5 SD;
- guard at P75 with a 20 s chime cooldown;
- 45 valid / 60 max calibration seconds.

`nf-feedback` (L1, no clock, WASM-safe) reproduces the legacy Dart engine. Golden fixtures pin it (`tools/golden-dart`, `crates/nf-feedback/tests/golden`). It differs from the legacy engine only in these four ways; each has its own `div_*` fixture and test:

1. **Sample time, not wall clock.**
   - The success window, recalibration window, guard cooldown and calibration max-time all use `Input::t`, which is active session time with pauses excluded.
   - In the legacy engine, a pause or jank aged or dropped epochs.
2. **No 1.0 fallback.**
   - Without a baseline threshold, nothing is rewarded and `held_back = [no_threshold]`.
   - The legacy engine rewarded `value > 1.0`, which is wrong for TAR, BTR and single bands.
3. **Same pads for every lane.**
   - The reward feature, inhibit limits, guard delta and calibration all come from the pads with quality ≥ 80 in the same `Input`.
   - In the legacy engine, the feature came from the Rust-side autodrop and the limits from Dart's own pad set.
4. **Muffle in both modes.**
   - A guard warning with `muffle = true` withholds reward (`held_back = [guard]`) in both uptrain and stability. With `muffle = false` it never blocks.
   - The legacy engine blocked only in stability mode, ignoring the flag; in uptrain it only muted the audio while still counting the reward.

**Small behaviour change.** Legacy `clamp(initial, max)` throws when initial > max; we let max win.
