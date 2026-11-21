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
- Linux apt on ubuntu-22.04 can fail with `Temporary failure resolving azure.archive.ubuntu.com`;
  the install step now falls back to archive.ubuntu.com and retries.
- Shared `scripts/ci-apt-install.sh` (retries + archive.ubuntu.com fallback, including
  `security.ubuntu.com`) is used by rust-ci native as well as the release Linux job.
- ubuntu-22.04 release Linux also failed resolving *archive.ubuntu.com* (broken
  runner stub resolver). `ci-apt-install.sh` now rewrites `/etc/resolv.conf` to
  1.1.1.1 / 8.8.8.8 when name lookup fails.
- A workflow_dispatch that checks out tag 0.64.0 cannot run `scripts/ci-apt-install.sh`
  from the tagged tree (exit 127). The release Linux job now also checks out the
  workflow SHA to get that script, then builds the tagged source.

## 2026-11-12: Universal macOS DMG

- The DMG was arm64 only, so Intel Macs could not run it. The `macos` job (macos-15) now adds
  `aarch64-apple-darwin` + `x86_64-apple-darwin`, `scripts/package-macos.sh` builds both with
  `MACOSX_DEPLOYMENT_TARGET=11.0` and `lipo -create`s one universal binary into the .app
  (`lipo -verify_arch arm64 x86_64`, `lipo -info` on the mounted DMG). Asset renamed to
  `neurofeed-X.Y.Z-macos-universal.dmg`. First shipped in 0.64.1.

## 2026-11-18 SignPath prep
- Alarm clip replaced: CC BY-NC "Alarm Clock Digital" (zanox) -> CC0 "Alarm Clock SFX" (haydenrem, freesound 557616),
  `assets/audio/guardrail-alarm-02.opus`; `ogg/guard-alarm.ogg` re-encoded and trimmed to 2.69 s (no edge silence).
  The mixer's alarm voice already loops while the warning is active (ramps over 60 s); added a seam test in `nf-audio` dsp.
- `apps/neurofeed-egui/build.rs` (winresource, Windows host+target only) embeds version info + icon (`assets/neurofeed.ico`).
- README code signing policy + privacy statement; release.yml windows job signs via SignPath when configured (docs/release.md).
- Open: `cargo deny check advisories` fails on main already (chrono unmaintained, zip advisories); not touched here.

## 2026-11-19: Never auto-stop a feedback session (new feedback-disconnect contract)
- Owner law (`.ai/contracts/feedback-disconnect.md`, decision 2026-11-19): the 10 s disconnect grace end is gone.
  A lost link pauses (`paused:disconnected`), silences all audio incl. calibration background, freezes training and
  calibration time, and auto-reconnect looks for the same device. After `RECONNECT_PROMPT_S` = 15 s
  `feedback.status.reconnect_prompt` + event `reconnect_prompt`; new command `feedback.keep_waiting` (or `feedback.stop`).
- `device.disconnect {end_session}`: refused during a session unless true; true ends the session ("device disconnected
  by the user", recording saved) then disconnects. `device.connect` during a session only accepts the session's
  device and reopens it in place.
- egui `ui/session_guard.rs`: Disconnect confirmation (Cancel default) and the Device-not-found prompt (no Escape
  close). EN/DE copy. Tests: nf-mcp `feedback.rs` (long dropout never ends, calibration waits silently), egui
  `session_guard` click tests. Screenshot of the prompt via bridge; the confirm dialog has no screenshot (no input tool).
- Open: no explicit `disconnect` annotation span in the recording; `sim.configure` reconnect still stops a session's recording.

## 2026-11-19: cargo xtask (ci | layers | wasm)
- New `xtask` crate + `.cargo/config.toml` alias. `layers` reads `cargo metadata` edges: every crate registered in
  `xtask/src/layers.rs` (L0..L4, App, wasm flag), no edge to a higher layer (same layer allowed), egui/eframe/winit/rfd
  apps only, tokio nf-device/nf-mcp, btleplug/muse-rs/rosc nf-device, rmcp nf-mcp, candle/reve nf-ai (dev-deps exempt
  from quarantine, not from layers). `wasm` = check of the wasm crates + wasm clippy of neurofeed-egui. `ci` = fmt,
  clippy, test, layers, wasm, `cargo deny check` if installed. Replaces `crates/nf-core/tests/layers.rs`; rust-ci uses it.
- AGENTS.md map corrected: nf-store is L1 (nf-core uses it), nf-ai L3. `cargo deny check` is green again on this tree.

## 2026-11-19: panic_hunt fuzzer
- `crates/nf-core/tests/panic_hunt.rs`: every catalog id (commands + queries) × params from its JSON Schema and catalog
  example (each property × 23 hostile values, every enum value, property removed, all-hostile, non-object/unknown keys)
  × 4 fixtures (fresh, connected, recording, training). Asserts no panic and "failed call ⇒ AppState unchanged"
  (Debug compare). ~30 k calls, deterministic, 17 s debug (one test per fixture, cheap fixture restore).
- First run: 0 panics, 1 finding: `feedback.start` with a bad `wall_clock_unix_ms` started the trainer (fit check +
  events) before the recording rejected it. Fixed (validate first); regression test in `tests/session.rs`.
- Perf: `Request::parse` regenerated the full schemars schema per call to list allowed keys. Now cached per id
  (`allowed_keys`, equivalence test vs. `schema_keys`). Release, `cargo run --release -p nf-core --example parse_bench`
  (11 × 2000 calls): before median 486.88 µs/call (463.95..589.66), after 0.45 µs (0.41..22.82, max = cache fill).
  Every MCP / CLI / bridge call goes through it.

## 2026-11-19: Disconnect annotations; sim.configure keeps the session
- `nf_types::Annotation {onset, duration, type}` (fileformat_v6 names). The recorder writes a `disconnect` span from the
  last data to the first data back, by the feedback pause rule (link down or no data for `STALE_S` 1.5 s); touching
  spans merge, non-finite times are dropped, an outage still open at stop / checkpoint closes at the recording end.
- Stored with the session: `SessionMeta.annotations`, SQLite schema v5 `annotations_json` (migration from v1..v4),
  IndexedDB via the meta JSON, crash-recovery doc. Exported in NFED6 metadata `annotations` and as EDF+ TAL.
- `sim.configure` reopens a running simulator in place (`reconnect`), so a recording / feedback session continues.
  Regression test `sim_configure_keeps_the_session_and_its_recording` failed before (recording `active: false`).
- Tests (nf-mcp `feedback.rs`): dropout → one span (onset 10 s, 12 s), stored in `history.get`; open span closed at stop.
- Open: EDF+ export is continuous, so a disconnect is an instant there (EDF+D starts would carry the gap); imports
  keep their markers in `import.annotations` (not moved to the root list); no `bad_quality` / `pause` rows yet.

## 2026-11-19: TODO cleanup
- Removed `.gitmodules` (only stale `.local/*` entries; no gitlinks are tracked) and `.ai/TODO/github actions appimage.md`
  (an Electron Q&A; the release job already builds a best-effort AppImage, see `.ai/release.md`).
- `.ai/TODO/README.md`: Athena optics and import/export marked landed. `.ai/feedback/todos.md`: disconnect auto-end bug
  is fixed (needs the real-device pass); dropped the done Athena and `edf_export` items.

## 2026-11-19: Blink / jaw-clench reward gate (TODO was stale)
- Already in Rust: `artifacts.rs` (`nf_dsp::GestureDetector`) feeds blink / jaw to the engine (`Dirty::Blink|Jaw`, not
  counted, no chime); only the movement case was tested. `nf-mcp/tests/artifacts.rs` now checks per second that a
  blink / clench second never counts or chimes. Finding: on the simulator the blink second usually trips the pad-quality
  gate first ("no good signal on AF7, AF8"), so `dirty` stays null and the reason is the quality gate; same outcome.
- Open: real-headset check that natural blinks / EMG are caught (sim artifacts are large).

## 2026-11-20: Long jobs: progress + cancel (`job.start` / `job.status` / `job.cancel`)
- Before: `recording.export` / `history.export` were sync queries (whole encode + base64 in one call; the History view
  calls `Session::history_export` on the UI thread), `history.import` sync in `Session::apply`, `ai.install` / `ai.load`
  already async in `nf-ai` (progress in `AiModelState::Installing`) but not cancellable.
- Cost, release, 60 min Muse S: export raw_body 121 ms / nfed6 149 ms / edf 373 ms (incl. base64 of ~24 MB), PDF 218 ms,
  EDF import 3.6 s (band replay dominates). One-off measurement, not a benchmark (no hot path changed).
- `nf_core::jobs`: stepped `Work` (import: parse → band 1024 records/step → body; export: encode → base64 786 KiB/step),
  `JobCtl` (cancel flag, progress, outcome), `JobRunner` seam. Session steps inline once per `advance` (manual clock,
  wasm, tests); `nf_mcp::ThreadRunner` (catch_unwind → failed job) in the desktop app and wall-clock CLI. AI jobs watch
  the runtime; new `AiRuntime::cancel_install` (default: refuse); `NativeAi` stops between 64 KiB chunks, deletes
  `.part`, keeps an earlier verified copy. `import::Bander` is now shared by the sync import and the job.
- Results = the wrapped command's reply; import stored only on completion (cancel ⇒ nothing saved). Jobs live outside
  `AppState`; no stepping inside `command_batch`, which refuses `job.*` writes. Limits 4 running / 1 AI / 8 kept.
- Tests: `nf-mcp/tests/jobs.rs` (7): job import == sync import (nfed6 bytes), monotonic progress + events; cancel
  mid-import saves nothing (revision +2 only); export jobs == sync replies (raw_body > one base64 step); refusals change
  nothing; 4-job limit; AI install progress/done/cancel + load with a fake runtime; ThreadRunner import + cancel.
  nf-ai store: stopped install removes `.part`. panic_hunt covers the three new ids (catalog examples added).
- Docs: decisions 2026-11-20, automation.md "Long jobs" (verified serve exchange), AGENTS.md §4, design-mcp-core.md.
- Open: the egui History export / Import dialog still call the sync paths on the UI thread (switch them to `job.start`
  with a progress row + Cancel; needs a screenshot); EDF/NFED6 encode and the PDF report are single steps; MCP-native
  progress notifications; job results are kept in memory (8 × up to ~130 MB base64 worst case).

## 2026-11-20: Movement monitor on the shared chrome
- `ui/views/movement.rs` rewritten: shared toolbar (Follow | Inspect, window 15 s–5 min), trace chips, Y range menu, overview
  toggle (off by default, saved per view), stacked panes with the shared decimation, dropout shading, Follow glide, Inspect
  without jump, immersive landscape = graphs only, theme tokens (`theme::movement_trace`, no literal colours). Removed the
  view-local viewport and card grid from `plot.rs`.
- Core: `MonitorId::MovementOverview`, `MoveTrace` / `MoveRange` / `MovementDisplay`, command `monitor.movement`
  (`traces`, `range_g`; range saved as `movement_range`), accelerometer ring 30 s → 5 min (`ACCEL_S`; ≈ 250 KB at 52 Hz),
  Movement monitor span from the ring (stale data keeps a trailing gap). `monitor.overview` accepts `movement`.
- Tests: nf-core `monitor.rs` (ring bounded at 5 min, command validation + persistence, trace-value oracles), `overview.rs`
  (default off, per-view); app `movement.rs` (gap oracle, line break at dropout, regular / compact / landscape render,
  overview toggle, no-device message). panic_hunt covers `monitor.movement` via the catalog example.
- Open: no Flutter-style spline smoothing; real-headset check of the accelerometer axes (sim only).

## 2026-11-21: Feedback layer stack, stage 1 (branch feedback-stack)
- Core: `nf_core::layers` (LayerKind Background < Feedback < Guardrail, LayerConfig, LayerStack with sorted insert, caps 4/kind and 8 total, LayerPatch validation), seeding from the protocol, first-layer ↔ `AudioSettings`/guard mapping (`push`/`pull`) so the single-slot engine is unchanged, recents (6 kept, 3 shown, saved in the settings doc, touched on `feedback.start`).
- Commands: `layers.list|add|remove|set|reset`, `protocol.recent`, `feedback.setup`. panic_hunt covers them through the catalog examples.
- UI: tile grid (1/2/3 columns by width) with a Recent row; one generic setup screen with the stack, expandable layer tiles, "+ Add layer", reset, Start. i18n en/de.
- Tests: layers unit tests (ordering, add/remove/limits, seeding, patches, push/pull round trip, recents), MCP e2e (seed/edit/engine sync, recents persist), egui layout tests (phones, recent row).
- Open: stage 2 audio for extra layers, per-layer thresholds/hold, Flutter sub-tile dialogs, screenshot of the new screens (not taken: no display here), `cargo clippy` of the app with default features needs libasound (checked with `--no-default-features`).
