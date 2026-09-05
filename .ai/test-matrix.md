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
  test/feedback_pipeline_test.dart \
  test/user_protocol_builder_test.dart \
  test/output_ids_test.dart \
  test/soloud_engine_test.dart \
  test/calibration_assets_test.dart \
  test/settings_guardrail_migrate_test.dart \
  test/session_metadata_roundtrip_test.dart \
  test/streaming_osc_test.dart \
  test/streaming_mixer_test.dart \
  test/streaming_brainflow_test.dart \
  test/streaming_indicator_test.dart \
  test/agent/agent_protocol_test.dart \
  test/agent/agent_config_test.dart \
  test/agent/agent_server_test.dart \
  test/app_ui_state_test.dart
```

## FFI (host lib first)

```bash
cargo build --manifest-path rust/Cargo.toml
flutter test test/session_store_test.dart test/session_export_test.dart \
  test/session_computed_charts_test.dart
```

`test/streaming_lsl_test.dart` needs liblsl — skip if missing.

## Rust

```bash
cargo test --lib session_format   # format edits
cargo test --lib                  # features / simulator / device_config
```

## Surfaces

| Surface | Layer | Existing | Command | Agent can assert | Gap |
|---|---|---|---|---|---|
| Connect catalog | Dart unit | `test/connect_source_test.dart` | `flutter test test/connect_source_test.dart` | Frozen ids/labels; debug off hides Simulator | No widget of dropdown |
| Connect live (sim) | agent-linux | HTTP | `POST /connect` `sim:muse-2` or `sim:muse-s` | `connected=true`; `scanMessage` **null** | Real BLE **cannot** |
| View switch | agent-linux | HTTP | `POST /view` `bands` / `rawEeg` / `settings` | `GET /state` → `view=` that name | Button wiring untested |
| Sidebar / connect window | agent-linux | HTTP | `POST /sidebar`, `POST /connect-window` | `sidebarOpen` / `connectWindowOpen` | Overlay chrome untested |
| Session start Crown | Dart + HTTP | notifier refuse | `POST /session/start` after `sim:crown-osc` | HTTP 409 `crown_refused` | Dialog UI untested |
| Session start Muse sim | agent-linux | HTTP | `recordOnly` + skip-cal | `[feedback] phase=playing` | 50 s cal too slow — always skip |
| Lanes / features | Dart unit | `test/feedback_pipeline_test.dart` | that file | Guard does not change reward | Orchestrator as a whole |
| Protocol JSON | Dart unit | `user_protocol_builder_test.dart`, `calibration_assets_test.dart` | those files | Catalog copy, clip files | Builder UI |
| Guard pref migrate | Dart unit | `settings_guardrail_migrate_test.dart` | that file | Old enum → feature ids | Debug switch widget |
| History / store | Dart+FFI | `session_store_test.dart` | FFI command above | `publishSession` lists id | History UI |
| Session format v5 | Rust + Dart+FFI | `session_format` + export/charts tests | rust + FFI | Roundtrip | Don't edit layout from Dart |
| Simulator identity | Rust unit | `simulator.rs` | `cargo test --lib simulator` | name/firmware table | Live spawn needs tokio |
| Streaming OSC/BF | Dart unit | `test/streaming_*.dart` | `flutter test test/streaming_*.dart` | Datagram shape | View untested |
| Audio playback | — | ids only | — | — | Silence ≠ fail in this container |
| Live charts | — | none | — | — | Visual **cannot** without goldens |
| REVE/LUNA | Rust `#[ignore]` | analysis tests | `cargo test --lib -- --ignored` | If `.local/` weights | Never CI |
| Real BLE Muse | **cannot** | — | phone + testing-guide logcat | Human | |
| Real Crown OSC | **cannot** | — | — | Start refused | |
| Android AAudio | **cannot** | — | — | — | |
| Pad fit | **cannot** | — | — | Sim pads are synthetic ≥ 80 | |

## Agent Linux smoke (HTTP)

Needs a GTK window. This sandbox: `DISPLAY` unset — use `GDK_BACKEND=wayland`.
How to launch and the API table: [testing-guide.md](testing-guide.md) Linux agent.
Skill: `.grok/skills/muse-run-linux/SKILL.md`.

Pure Dart first (`flutter analyze lib/src` + `test/agent/*` +
`test/app_ui_state_test.dart` + `test/connect_source_test.dart`). Then live:

1. `GDK_BACKEND=wayland flutter run -d linux --dart-define=MUSE_AGENT=true --dart-define=MUSE_DEBUG=true`
2. Wait `[muse] agent-listen` **and** `[muse] agent-ready`. Abort on `Content hash`. Parse the port.
3. `GET /health` → `{ok:true}`. `POST /view {"view":"nope"}` → `unknown_view`.
4. `POST /connect {"id":"sim:muse-2"}` or `sim:muse-s` (not Crown). `connected=true`, `scanMessage` null.
5. `POST /view` `bands`, then `rawEeg` (optional `settings`). `GET /state` matches.
6. `POST /session/select {"protocol":"recordOnly"}`
7. `POST /session/duration {"minutes":1}`
8. `POST /session/start {"skipCalibration":true}` → `phase=playing`.
9. `POST /session/end` then `/session/reset` → `ended` then `idle`.
10. Optional: disconnect, `POST /connect {"id":"sim:crown-osc"}`, `POST /session/start` → HTTP **409** `crown_refused`. Then disconnect.
11. Never `publishSession`. Audio silence is N/A; `audioInitFailed` is a real fail to note, not a reason to skip end+reset.

Always end+reset, even on failure.
