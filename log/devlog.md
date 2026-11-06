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

## 2026-10-31: edf_export joins the workspace
- Moved our EDF+ codec from `third_party/edf_export` to `crates/edf_export` (workspace member, zero deps).
  `nf-format` takes it from `workspace.dependencies`. `third_party/` had no other tracked files and is gone.
- `decode_edf_plus` split so the crate passes workspace clippy. Golden layout tests unchanged
  (10 in edf_export, `edf_roundtrip` in nf-format, layers includes the crate). wasm `cargo check` ok.
- Open: `.gitmodules` still names `third_party/{btleplug,muse-rs,reve-rs,luna-rs,brainflow,neurofeed.wiki}`;
  those gitlinks are not in the index.

## 2026-10-31: Device dialog keeps scanning
- `device.dialog {open:true}` calls `DeviceProvider::watch` (Muse BLE + Crown OSC) and `{open:false}` calls `stop_scan`. `device.scan {seconds}` is unchanged and timed.
- Muse watch uses btleplug directly and records a headset only while its RSSI is present (BlueZ clears RSSI when discovery stops). Connect still goes through muse-rs, aimed at that advertised name.
- Open: Android has no control channel, so this dialog behavior is desktop-only.

## 2026-11-06: UI port milestone 1 (monitor foundation + Bands)
- `nf_core::monitor` holds the Follow/Inspect/zoom/pan viewport per monitor (`monitor.viewport|zoom|pan|display`, `monitor.get`). Windows and hidden bands are persisted. Bands history is 30 min.
- Bands is rebuilt in the legacy layout: shared toolbar row, full-bleed graph with an `m:ss` grid, floating legend, dB | % (linear averaging over electrodes, relative = share of the visible bands), and legacy palette.
- Compact navigation is a `☰` drawer (bottom bar removed). Phone landscape is immersive (graph only) on monitor screens. Layout selection uses phone identity + orientation.
- `NF_WINDOW=WxH` sets the desktop window size for screenshot runs.
- i18n tests that switch the global language are serialized (removes a flaky race).
- Plan and next steps: docs/ui-port/monitors.md.

## 2026-11-07 — M1b fixes (safe area, simulator reconnect, smooth Follow, perf overlay)
- Status bar overlap: egui 0.37 root ui = full viewport; the app now lays out inside `content_rect` (see decisions 2026-11-07). Desktop preview: `NF_SAFE_AREA=l,t,r,b`.
- Simulator chosen last reconnects after restart; Disconnect persists (`auto_suspended`).
- Bands Follow glides (`FollowClock`, 1 s lead, vsync repaint only while live + Follow). Measured sim cadence: 10 Hz snapshots, 94–141 ms apart; the old repaint was 100 ms, unsynced.
- Perf overlay setting `perf_overlay`.
