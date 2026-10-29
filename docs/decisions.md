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
