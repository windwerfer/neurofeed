# Dev log (append-only, newest last)

## 2026-10-29: Phase 1 core + MCP
- Workspace: nf-types (L0), nf-sim (L1), nf-core (L2), nf-mcp (L4), apps neurofeed-egui, neurofeed-mcp.
- nf-core: Session tick/execute/query/run/batch/commands/enabled/drain_events; dotted command ids; schemars
  input schemas; enabled -> disabled reason; revision counter; atomic batch with rollback; failing commands change nothing.
- nf-mcp: command_list/describe/run/batch + status, bands_get, device_list, clock_advance. Panics caught per call.
- Gate (manual until xtask): cargo fmt --check; cargo clippy --all-targets -D warnings; cargo test (19); cargo check -p neurofeed-egui --target wasm32-unknown-unknown; trunk build.
- Open: xtask (layers/wasm/ci), output schemas, bridge mode, control channel, raw-sample simulator port, nf-dsp/nf-format moves.

## 2026-10-29: Phase 2 DSP, formats, raw simulator
- nf-dsp (new, no deps): Biquad/EegFilter ported from rust/src/analysis/eeg_filter.rs (sample rate now a parameter),
  radix-2 FFT, Hann PSD, log10 band powers, dominant band, peak frequency, line-noise ratio. Known-answer tests.
- nf-format (new): record codec (tags 1-10), NFEDBIN body writer/reader, NFED6 container (crc32), EDF+ via
  third_party/edf_export (path dep). zstd via pure-Rust ruzstd so it builds for wasm. Roundtrip tests.
- nf-types: BandSource -> DeviceSource (raw EegPacket); DeviceInfo.sample_rate_hz.
- nf-sim: raw 256 Hz packets (ported eeg_sample + 1/f background, hum, DC); sim.configure in µV.
- nf-core: Signal (filter, 10 s buffers, bands every 0.1 s over 1 s), Recorder (in memory, 64 MiB cap);
  queries now also run the enabled check. New: raw.get, psd.get, recording.start/stop/status/export.
- third_party/edf_export/rustfmt.toml disables formatting (cargo fmt --all visits path deps).
- Open: mains detector + recording notch lock, pad quality, features; computed 1 Hz JSONL section is empty;
  timestamps are session seconds (no wall clock in core); export returns base64 (no fs in core).
