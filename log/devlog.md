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

## 2026-11-07 — 4 Hz bands, 1 h low-rate history
- BAND_INTERVAL_S 0.25; `Signal::with_band_interval` (1 Hz tested). BandHistory 3600 s/14,400; HR/SpO2 3600 s.
- audio guard test made phase-independent (chime times + ≥20 s cooldown).

## 2026-11-07 — Analysis exclusion + PSD milestone
- nf_core::analysis (exclude/include/remember/hint), nf_core::spectrum (Welch average), commands analysis.* / monitor.psd / psd.average.
- Device dialog "Use in analysis" switches + confirm; top bar exclusion count + hint; notch removed; Pause/Record reorder.
- PSD view: spectrum widget (ui/spectrum.rs) + Bands strip.

## 2026-11-07 – Exclusion review corrections
- Record button: red painted dot + normal-colour "Record" label, tooltip.
- Pause tooltip states the meaning: freezes live graphs only; recording and acquisition continue (open user decision).
- Histogram/Spectrogram honor analysis exclusion; artifact detectors skip excluded pads; tests for blink contamination and no target-pair substitution.
- Time axis: no ticks before t=0 (duplicate "0:00" in early PSD strip fixed).

## 2026-11-07 – Overview + Histogram + Spectrogram
- Shared overview widget (PSD strip refactored into it); toggles per view, defaults PSD+Spectrogram on.
- Histogram: pooled eligible pads, 2/4/8 s epoch Follow/Inspect, ±50/100/200 µV, readout.
- Spectrogram: 300 s linear per-channel history, averaged eligible pads, plasma + colour bar, dB auto/lock, readout.
- Tests: tests/overview.rs (core), ui overview gestures, histogram/spectrogram UI.

## 2026-11-07 – Overview refinements
- Bookmarks (long press / desktop icon + ×), in-graph span menu, no "(custom)", Follow resets overview.

## 2026-11-08 — Histogram minimap default-on; Follow smooth entry; Discard safety
- Overview default now ON for PSD, Spectrogram and Histogram (`MonitorId::overview_default`). Only explicit toggles are persisted (`overview` map), so a saved "off" survives restarts and older files without a histogram entry get the new default — no migration needed. Tests: `histogram_overview_default_on_and_explicit_off_survives_restart`, `defaults_draw_on_psd_spectrogram_and_histogram`. Screenshot: `ui-shots/monitors/rust-histogram-overview.png`.
- Follow pop-in diagnosis: Follow's right edge trails the newest data by `FOLLOW_LEAD_S` (1 s), but Bands queried snapshots only up to the visible end and Spectrogram built its texture only up to the end slot, so each new point/column appeared when it reached the edge. Fix: Bands reads real snapshots `OFFSCREEN_S` = 1.5 s past the edge, Spectrogram includes `OFFSCREEN_SLOTS` = 6 columns past the edge (block-aligned texture range, rebuilt on new data or every 2 s of panning; the quad moves every repaint). Painters clip at the plot. No delay added, no interpolated values. Tests: `follow_edge_tests` (60 Hz frames, 4 Hz data, 1.5 s burst; fail with the old ranges).
- Discard: placed left of Record, 0.8 s guard after Stop, confirm modal (Cancel default, unchecked "Don't ask again"; `confirm_discard` setting re-enables).

## 2026-11-08 — HR+SpO2 monitor
- Audit: Muse 2/S: 3 optical channels (ambient, infrared, red) @ 64 Hz, 6 samples/packet/channel, timestamped by `LiveSource` (`Timeline::place`, contiguous unless >0.5 s off). Crown: no optics. Athena: optics not decoded by muse-rs → no data (view says so). Simulators `sim:muse*` generate synthetic optics (labelled "simulated optics").
- Before: 30 s raw ring (no timestamps, estimator read across gaps), a 1 h estimate list without reliability, 2 min trend UI.
- Now: `optics::Wave` (5 min native, segments with real times; 230 400 B on Muse), 1 Hz estimates 1 h (86 400 B per series), reliability gates, incremental hour mean + per-recording running mean, cursor `at()` ±1 s, `view_time` (Pause). UI: `views/heart.rs` dual-axis timeline via the shared `overview::show_in` (refactored from `show`) + pulse waveform with min/max decimation of only the visible window; Follow leads 2 s (timeline) / 1 s (waveform) and draws real data past the edge.
- Sim check: HR conf ≈ 0.97, SpO2 perfusion conf ≈ 0.12–0.13 (ratio fixed at 96.96 %).
- Not in this pass: disk paging, Movement.
- 2026-11-08 later: HR/SpO2 mean lines grid-fine (grid width + 0.2, 45 % colour). Pulse waveform now sweeps via `nf_core::rawtrace` (new `trace_samples` over time-stamped PPG segments, shared `build` with Raw EEG's `trace`; Raw's `mapping`/`time_grid` reused); `heart_detail` span gets Raw's one-window `ahead_s` so Inspect freezes on the pass.
- 2026-11-11: Feedback compact fixes (plan step 1): single-column protocol cards + full-width Start, stacked fit check, wrapping button rows, live header split, 3-column trust totals on phones, short trust caption on narrow plots; vertical scroll for non-live phases. Regular layout unchanged.

## 2026-11-11: Athena optics (separate stream + monitor page)

- `.local/` is now gitignored. The stale `.gitmodules` entry for `.local/muse-rs`
  (URL `eugenehp/muse-rs`) was removed: that path is a local checkout of the
  `windwerfer/muse-rs` fork, not a submodule, and must not be committed. Other
  `.local/*` submodule entries were left as-is but are also covered by `.local/`.
- muse-rs (fork, branch `athena-optics`): `MuseEvent::Optics` with per-lane
  samples and labels `ambient`/`infrared`/`red`/`opt3`…`opt15` (names, not
  wavelengths). Athena emits Optics only; Classic PPG is unchanged. Default
  startup preset `p1041` (16 lanes); `p1044`/`p1045` and other measured presets
  are selectable. `AthenaDecoder` is wired in the notify loop so Gap events emit.
- nf-types/nf-device/nf-sim/nf-core: `OpticsPacket`, `DeviceInfo` optics fields,
  `Block::Optics` + `Block::Info`, `DeviceSource::poll_optics` / `set_optics_preset`.
  `sim:athena` emits plausible 16-lane pulsatile + ambient data (no PPG).
- Recording: NFEDBIN tag 14 (`Optics`), only while Record/training is on. Disk-backed
  waveform loading stays on hold. History meta has no new SQLite column yet.
- Commands: `optics.get`, `optics.preset.get`, `optics.preset.set`, `monitor.optics`.
  Settings `athena_preset` (default p1041). Heart view: pulse/SpO2 is Classic-only
  on Athena; use the Optics page.
- Optics monitor: stacked lanes like Raw (sweep/Follow/Inspect, lane selector,
  overview off by default, compact + regular, safe area, graph-only phone landscape,
  EN/DE, 5 min ring, per-lane auto scale).
- `cargo update -p rmcp` (3.8.0 → 3.9.0) for RUSTSEC-2026-0462 so `cargo deny` stays green.

## 2026-11-11: Pin muse-rs to published athena-optics

- `athena-optics` is on `windwerfer/muse-rs` at `fe7cfd6`. nf-device now uses
  the git rev (default-features = false) instead of the `.local/` path dep, so
  CI can fetch it.

## 2026-11-11: Release workflow macos-15 + upload on cancelled jobs

- GitHub retired `macos-14` on 2026-11-02. The 0.64.0 (and 0.63.0) release runs cancelled
  the macOS job at queue time (`macos-14-arm64-us-default is not supported`). `upload`
  `needs` every platform job, so it was skipped and the GitHub releases got no assets
  even though Linux, Windows, Flatpak, web and Android had built.
- Switch the Apple Silicon job to `macos-15`. Run `upload` with `if: always()` after
  meta succeeds so surviving artifacts still attach; fail the workflow if a platform
  dropped. `workflow_dispatch` with a tag checks out that tag from a main workflow run.
