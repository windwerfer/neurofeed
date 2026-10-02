# Test matrix

What can be tested, the command, what an agent can assert without a human.
CWD = repo root. Layers: Rust unit · Dart unit · Dart+FFI · agent-linux · **cannot**.

Widget / integration_test layers are **deferred**. Drive a live app with debug
HTTP ([testing-guide.md](testing-guide.md) Linux agent).

## Pure Dart (no `.so`) — after almost every Dart edit

```bash
flutter analyze lib/src
flutter test \
  test/connect_source_test.dart \
  test/device_type_switch_test.dart \
  test/feedback_pipeline_test.dart \
  test/user_protocol_builder_test.dart \
  test/output_ids_test.dart \
  test/soloud_engine_test.dart \
  test/audio_hardening_test.dart \
  test/calibration_assets_test.dart \
  test/settings_guardrail_migrate_test.dart \
  test/last_calibration_baseline_test.dart \
  test/session_metadata_roundtrip_test.dart \
  test/session_leave_test.dart \
  test/streaming_osc_test.dart \
  test/streaming_mixer_test.dart \
  test/streaming_brainflow_test.dart \
  test/streaming_indicator_test.dart \
  test/agent/agent_protocol_test.dart \
  test/agent/agent_config_test.dart \
  test/agent/agent_server_test.dart \
  test/app_ui_state_test.dart \
  test/connection_reconnect_test.dart \
  test/feature_override_test.dart \
  test/trust_graphs_test.dart \
  test/trust_dirty_test.dart \
  test/nerd_sheet_test.dart \
  test/monitor/band_cache_test.dart \
  test/monitor/sweep_buffer_test.dart \
  test/monitor/capture_lease_test.dart \
  test/monitor/monitor_sampler_test.dart \
  test/monitor/viewport_controller_test.dart \
  test/monitor/graph_shell_test.dart \
  test/monitor/graph_cinema_test.dart \
  test/monitor/dsp_test.dart \
  test/monitor/stft_ring_test.dart \
  test/monitor/sliding_spectrum_test.dart \
  test/monitor/spectrogram_pane_test.dart \
  test/monitor/histogram_pane_test.dart \
  test/monitor/split_pane_tick_test.dart \
  test/monitor/electrode_toggles_test.dart \
  test/monitor/band_toggles_test.dart \
  test/monitor/time_series_pane_test.dart \
  test/monitor/recording_bands_computed_test.dart \
  test/smooth_path_test.dart \
  test/monitor/bands_context_strip_test.dart \
  test/monitor/plot_isolation_test.dart \
  test/monitor/sweep_pane_test.dart \
  test/monitor/overshoot_hold_test.dart \
  test/monitor/recording_metadata_test.dart \
  test/history_filter_test.dart \
  test/history/session_trust_test.dart \
  test/history/history_dashboard_summary_test.dart \
  test/settings_sections_test.dart \
  test/agent/agent_commands_test.dart \
  test/capture_foreground_test.dart \
  test/freeform_insets_test.dart
```

## FFI (host lib first)

```bash
cargo build --manifest-path rust/Cargo.toml
# Capture is a process-global Rust writer; do not parallelize these files.
flutter test --concurrency=1 \
  test/session_store_test.dart test/session_export_test.dart \
  test/session_computed_charts_test.dart \
  test/monitor/file_backed_source_test.dart \
  test/monitor/recording_assemble_test.dart \
  test/monitor/crash_recovery_test.dart \
  test/monitor/recording_store_test.dart
```

`test/streaming_lsl_test.dart` needs liblsl — skip if missing.

## Rust

```bash
cargo test --lib session_format   # format edits
cargo test --lib                  # features / simulator / device_config
```

Spine soak (capture writer + streaming assemble — copy `.raw`, no outer zstd):

```bash
# Max-rate Classic Muse filler → capture writer try_send + capture_assemble.
# Default 60 s equivalent. Prints GB, RSS if /proc is available, drop counters.
# Extra assemble RSS must not scale with filled volume. Drops must be 0.
cargo test --manifest-path rust/Cargo.toml --lib spine::soak -- --nocapture

# 12 h-equivalent volume (not wall-clock).
NEUROFEED_SOAK_EQUIV_SECS=43200 cargo test --manifest-path rust/Cargo.toml \
  --lib spine::soak -- --ignored --nocapture
```

## Surfaces

| Surface | Layer | Existing | Command | Agent can assert | Gap |
|---|---|---|---|---|---|
| Connect catalog | Dart unit | `test/connect_source_test.dart`, `test/device_type_switch_test.dart` | `flutter test test/connect_source_test.dart test/device_type_switch_test.dart` | Frozen ids/labels; debug off hides Simulator; device-type change disconnects then scans; recording/session asks Disconnect / Cancel | Real BLE / OSC **cannot** |
| Connect live (sim) | agent-linux | HTTP | `POST /connect` `sim:muse-2` or `sim:muse-s` | `connected=true`; `scanMessage` **null** | Real BLE **cannot** |
| View switch | agent-linux | HTTP | `POST /view` `bands` / `rawEeg` / `histogram` / `spectrogram` / `psd` / `settings` | `GET /state` → `view=` that name | Button wiring untested |
| Sidebar / connect window | agent-linux | HTTP | `POST /sidebar`, `POST /connect-window` | `sidebarOpen` / `connectWindowOpen` | Overlay chrome untested |
| Session start Crown | Dart + FFI + HTTP | `test/agent/agent_commands_test.dart`, `test/session_computed_charts_test.dart` | `POST /session/start {"skipCalibration":true}` after `sim:crown-osc` | Start passes to the recording check; gate pads from Rust `session_gate_electrodes` (Muse 1/2, Crown 3/4, reward override, `band.delta` guard default = frontal pair Muse 1/2 / Crown F5/F6 2/5 and its override, AI guard → needed pads; also `features.rs` unit tests); band-math guard delta pads = Rust `frontalElectrodes` (Muse AF7/AF8, Crown F5/F6); 8-ch charts average PO3/PO4 and caption `PO3/PO4` | Full Crown session on device untested |
| Record / Stop | Dart + FFI | `test/monitor/capture_lease_test.dart`, `recording_assemble_test.dart`, `test/agent/agent_commands_test.dart` | `POST /record/start` after `sim:muse-2`; `GET /state` `captureKind=recording`; `POST /record/stop` scratch `.neurofeed` | 412 `disconnected`; 409 `feedback_active`; 409 `recording_active` on `/session/start` | Save/Discard widget untested |
| Recording crash recovery | Dart + FFI | `test/monitor/crash_recovery_test.dart`, `recording_store_test.dart` | `flutter test test/monitor/crash_recovery_test.dart test/monitor/recording_store_test.dart` | Leftover `recording_*` assemble; `tmp_`/`session_*` untouched; publish `kind=recording`; existing rows `feedback`; discard no sqlite row | Dialog widget untested |
| Feedback leftover / unsaved summary | Dart + FFI | `test/session_computed_charts_test.dart`, `test/agent/agent_commands_test.dart` | those files | Leftover `session_*` assemble; attach scratch id/path; 409 `unsaved_session` on `/session/start` and `/session/reset`; computed pulse/SpO₂ + raw fallback | Summary Back/`PopScope` widget untested |
| Leave feedback session | Dart unit | `test/session_leave_test.dart` | `flutter test test/session_leave_test.dart` | AppBar back and system back while calibrating, playing, paused, or interrupted ask `End session?`. `Cancel`, barrier, and a second back stay. `End session` calls `end()` once and does not pop. Idle pops with no dialog. Ended does not pop. In-flight `end()` and a phase that leaves in progress before confirm do not end again. A failed `end()` can be retried. A sheet above the session closes first. | Summary Back/`PopScope` still untested |
| Session start Muse sim | agent-linux | HTTP | `recordOnly` + skip-cal | `[feedback] phase=playing` | 50 s cal too slow — always skip |
| Lanes / features | Dart unit | `test/feedback_pipeline_test.dart` | that file | Guard does not change reward | Orchestrator as a whole |
| Trust graphs | Dart unit | `test/trust_graphs_test.dart`, `test/trust_dirty_test.dart`, `test/nerd_sheet_test.dart` | those files | Chip defaults/persist; dirty skip epoch/audio/guard; inhibit wash (even below the line); inhibit pane under Reward (one pane, two series); overshoot colors stay distinct; verdict priority; More glued; viewport 75 s Follow 15–300; Blink/Jaw live ring; calibrating hides graphs; nerd sheet piles / band stack / (i) rows; guard block omitted if lane did not run | Visual Follow slide **cannot** |
| Protocol JSON | Dart unit | `user_protocol_builder_test.dart`, `calibration_assets_test.dart` | those files | Catalog copy, clip files | Builder UI |
| Guard pref migrate | Dart unit | `settings_guardrail_migrate_test.dart` | that file | Old enum → feature ids | Debug switch widget |
| History / store | Dart+FFI | `session_store_test.dart`, `test/history_filter_test.dart` | FFI command above + `flutter test test/history_filter_test.dart` | List includes `kind=recording`; no orphan-file backfill; `moveAllTo` both prefixes; delete uses sqlite `path`; filter All/Feedback/Recordings | History widget |
| History trust reader | Dart unit | `test/history/session_trust_test.dart` | `flutter test test/history/session_trust_test.dart` | Dirty second holds last clean percentile (first dirty uses its own); in-zone ignores calibration and noise and caps a 60 s gap at the median gap; dirty `heldBack` adds no inhibited time; null percents when all noisy or a recording; chimes only `reward_chime` / `guard_chime`; marks only `double_blink` and `double_jaw_clench` | Session Dashboard is PR 3; Feedback chip is PR 4 |
| History Dashboard chip | Dart unit | `test/history/history_dashboard_summary_test.dart` | `flutter test test/history/history_dashboard_summary_test.dart` | Recording summary: empty stats do not throw; absent cells omitted (not `0`); no in-zone or chime cells without feedback totals; More defaults closed, toggle writes `history_dashboard_more_expanded`, a second pump opens when the pref is true | Session summary hosts the same widget in PR 3 |
| Session format v6 (NFED6) | Rust + Dart+FFI | `session_format` + export/charts tests | rust + FFI | Roundtrip | Don't edit layout from Dart |
| Spine soak (capture writer) | Rust | `rust/src/spine/soak.rs` | `cargo test --manifest-path rust/Cargo.toml --lib spine::soak -- --nocapture` | Max-rate fill through writer `try_send`; volume printed; assemble is `capture_assemble` copy of `.raw` (no outer zstd; extra RSS must not scale with filled volume). Drops = 0. Env `NEUROFEED_SOAK_EQUIV_SECS` (default 60). 12 h-equivalent: same command with `--ignored` (or env `43200`) | Phone overnight **cannot** |
| Simulator identity | Rust unit | `simulator.rs` | `cargo test --lib simulator` | name/firmware table | Live spawn needs tokio |
| Streaming OSC/BF | Dart unit | `test/streaming_*.dart` | `flutter test test/streaming_*.dart` | Datagram shape | View untested |
| Feature probe | Dart unit | `test/feature_override_test.dart` | that file | Latch replace; synthetic TAR/delta baseline | Ear-test is human |
| Audio playback | — | ids only | — | — | Silence ≠ fail in this container |
| Live charts | Dart unit | `test/monitor/*` | dsp / panes / graph_shell / strip / plot_isolation / sweep_pane / sliding_spectrum | FFT 256-pt, strip highlight, window presets, plot `RepaintBoundary`, GraphShell isolated from plot ticks, Raw EEG min/max downsample, Follow sliding Welch / histogram | Visual **cannot** without goldens |
| REVE/LUNA | Rust `#[ignore]` | analysis tests | `cargo test --lib -- --ignored` | If `.local/` weights | Never CI |
| Real BLE Muse | **cannot** | — | phone + testing-guide logcat | Human | |
| Crown OSC decode / match | Rust unit | `neurosity_osc.rs` | `cargo test --manifest-path rust/Cargo.toml --lib neurosity_osc` | Node-`osc` byte layout (`/raw` `[ffffffff]sis`, `/info`), exact id segment, `/crown{prefix}`, array flatten, 16-sample batching, signalQuality 8/1 floats | |
| Band definitions | Rust unit + Dart unit | `muse.rs` `fft_bands_match_direct_dft`, `known_alpha_sine_band_power`; `test/monitor/dsp_test.dart` | `cargo test --manifest-path rust/Cargo.toml --lib fft_bands known_alpha`; `flutter test test/monitor/dsp_test.dart` | Hamming one-sided PSD matches a direct DFT; 10 µV alpha sine (on/off bin) ≈ 50 µV², rel alpha > 0.97; every 1–44 Hz bin in exactly one band `[lo, hi)`, 45–50 Hz in none; Dart PSD matches | Real EEG spectra **cannot** |
| EEG conditioning | Rust unit + Dart+FFI | `analysis/eeg_filter.rs`, `muse.rs` `conditioning_tests`, `test/eeg_conditioning_test.dart`, `test/session_import_test.dart`, `test/session_computed_charts_test.dart`, `test/monitor/crash_recovery_test.dart` | `cargo test --manifest-path rust/Cargo.toml --lib eeg_filter conditioning_tests`; `flutter test test/eeg_conditioning_test.dart` | DC removed, 50/60 (+harmonic) attenuated, alpha within 1 dB; settles from −2e5 µV and after a gap; mains none/50/60/none→50, sticky; notch locked per recording (detected / saved / undecided = both), reconnect keeps the lock, live filter seeded from the saved per-device value (`capture.rs` lock test, settings round-trip); crash-recovered session + recording keep `device.conditioning`; Muse offset+hum → usable quality and clean bands; captured packet unchanged; `condition_eeg` shape; `device.rawFiltering`/`conditioning` round-trip for Classic/Athena/Crown; EDF Prefiltering export → `import.prefiltering`; imported RAW stored unfiltered; lost samples (1/3/12) filled live and dropped offline, sub-sample jitter not filled (`short_timeline_gaps…`); Crown sample clock counter/wrap/re-anchor, a lost `/raw` sample is a RAW timestamp gap (`neurosity_osc.rs`) | Real mains / real headsets **cannot** |
| Crown OSC loopback sim | Rust `#[ignore]` + Python | `tools/crown_osc_sim.py` | `cargo test --manifest-path rust/Cargo.toml --lib crown_osc_sim -- --ignored --nocapture --test-threads=1` | Binds UDP 9000. Discovery id/nickname, 256 samples/s × 8 ch, µV range, bad pad, decoy device not routed, dropout keeps listing, per-pad `--quality` → Crown 1 Hz source, `--quality-overall` → app fallback, `--epoch 16` sample- and `--channel-major` epochs decode at 256 samples/s without bad-pad leakage, `--realistic-raw --line-noise 50/60` after conditioning: mains detected, good pads usable, bad pad not, bands match the clean run | Real Wi-Fi / Android broadcast **cannot** |
| Real Crown OSC | **cannot** | — | — | Unfiltered raw vs app pad quality unverified | |
| Android AAudio | **cannot** | — | — | — | |
| Android FGS (keepable capture) | Dart unit | `test/capture_foreground_test.dart` | `flutter test test/capture_foreground_test.dart` | Policy: FGS for `recording` / `feedback` / unsaved Save-Discard, not `tmp_` | Phone overnight **cannot** (no adb device in CI). Manual: Record or Start Session, background, screen off, 10+ min still appending |
| Pad fit | **cannot** | — | — | Sim pads are synthetic ≥ 80 | |

## Agent Linux smoke (HTTP)

Needs a GTK window. This sandbox: `DISPLAY` unset — use `GDK_BACKEND=wayland`.
How to launch and the API table: [testing-guide.md](testing-guide.md) Linux agent.
Skill: `.grok/skills/neurofeed-run-linux/SKILL.md`.

Pure Dart first (`flutter analyze lib/src` + `test/agent/*` +
`test/app_ui_state_test.dart` + `test/connect_source_test.dart`). Then live:

1. `GDK_BACKEND=wayland flutter run -d linux --dart-define=NEUROFEED_AGENT=true --dart-define=NEUROFEED_DEBUG=true`
2. Wait `[muse] agent-listen` **and** `[muse] agent-ready`. Abort on `Content hash`. Parse the port.
3. `GET /health` → `{ok:true}`. `POST /view {"view":"nope"}` → `unknown_view`.
4. `POST /connect {"id":"sim:muse-2"}` or `sim:muse-s` (not Crown). `connected=true`, `scanMessage` null.
5. `POST /view` `bands`, then `rawEeg` / `histogram` / `spectrogram` / `psd` (optional `settings`). `GET /state` matches. Keep `spectrogram` (no `waterfall`).
6. `POST /session/select {"protocol":"recordOnly"}`
7. `POST /session/duration {"minutes":1}`
8. `POST /session/start {"skipCalibration":true}` → `phase=playing`.
9. `POST /session/end` then `/session/reset` → `ended` then `idle`.
10. Optional: disconnect, `POST /connect {"id":"sim:crown-osc"}`, repeat steps 6–9 on the Crown simulator. Then disconnect.
11. Never `publishSession`. Audio silence is N/A; `audioInitFailed` is a real fail to note, not a reason to skip end+reset.

Always end+reset, even on failure.
