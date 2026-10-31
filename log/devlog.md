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

## 2026-10-29: Phase 3 monitor state
- nf-dsp: MainsDetector (votes 8 / switch 16, sticky 50/60), pad_quality + sample_std, band features (atr/tar/btr,
  relative alpha/theta/beta/delta), line-noise fraction, histogram, PSD dB. PSD now Hamming and band power =
  summed µV² (legacy compute_fft_bands), so log10 band values shift up vs Phase 2.
- nf-core: Signal runs the detector on raw input and rebuilds (warm-started) notch filters on change; a recording
  locks the notch in effect at its start until it stops; mains.set overrides (auto/50/60/off). Per-pad quality every
  0.1 s (usable >= 80), spectrogram columns every 0.25 s (30 s). New: signal.status, features.get, histogram.get,
  spectrogram.get, mains.set, channel.set; event mains_changed. Session::live_signal() is the typed view accessor.
- nf-sim: background sines detuned + Schroeder phases (the harmonic comb summed to a 1.5 Hz pulse train).
- egui: Raw EEG / PSD / Spectrogram / Histogram views (painter only), record button, notch + pads in top bar.
- Skipped: HR/SpO2 (no PPG in nf-types/sim yet). Features use relative powers of the 1 s window, not the legacy 1 Hz
  aggregation.

## 2026-10-29: PPG, heart rate, SpO2
- nf-types: DeviceInfo.ppg_channels + ppg_rate_hz (runtime data), PpgPacket, DeviceSource::poll_ppg (default none).
- nf-sim: sim:muse_s and sim:muse2 (sim:athena: no PPG, corrected) with 3-channel PPG (ambient/infrared/red, 64 Hz, legacy DC levels); pulse =
  systolic peak + dicrotic shoulder, beat intervals from hr_bpm with respiratory HRV (hrv_ms) and seeded jitter;
  red AC set so ratio-of-ratios yields spo2_pct. sim:muse aliases sim:muse_s. Athena optics/AUX: later patch set.
- nf-dsp: heart_rate / spo2 / pulse_ac ported from rust/src/api/muse.rs (rate parameterised).
- nf-core: Optics (30 s buffers, estimates every 1 s, 120-entry history); hr.get, spo2.get, ppg.get; sim.configure
  hr_bpm/spo2_pct/hrv_ms. egui HR+SpO2 view (values, IR wave, trend).
