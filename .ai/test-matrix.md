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
  test/calibration_assets_test.dart \
  test/settings_guardrail_migrate_test.dart \
  test/session_metadata_roundtrip_test.dart \
  test/streaming_osc_test.dart \
  test/streaming_mixer_test.dart \
  test/streaming_brainflow_test.dart \
  test/streaming_indicator_test.dart \
  test/agent/agent_protocol_test.dart \
  test/agent/agent_config_test.dart
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
| Connect live (sim) | agent-linux | HTTP | `POST /connect {"id":"sim:muse-2"}` | `[muse] connect returned: connected=true` | Real BLE **cannot** |
| Sidebar / Settings | agent-linux | HTTP | `POST /view {"view":"settings"}` | `GET /state` → `view=settings` | Button wiring untested |
| Session start Crown | Dart + HTTP | notifier refuse | `POST /session/start` after Crown sim | HTTP 409 `crown_refused` | Dialog UI untested |
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

Needs a GTK window. This sandbox: `DISPLAY` unset — best-effort.

1. `flutter run -d linux --dart-define=MUSE_AGENT=1 --dart-define=MUSE_DEBUG=1`
2. Wait `[muse] agent-listen` **and** `[muse] agent-ready`. Abort on `Content hash`.
3. `POST /connect {"id":"sim:muse-2"}` (not Crown).
4. `POST /session/select {"protocol":"recordOnly"}`
5. `POST /session/duration {"minutes":1}`
6. `POST /session/start {"skipCalibration":true}`
7. Grep `phase=playing`. Then `POST /session/end` and `POST /session/reset`.
8. Never `publishSession`. Audio silence is N/A; `[feedback] audio-init-failed` is a real fail to note, not a reason to skip end+reset.

Skill: `.grok/skills/muse-run-linux/SKILL.md`.
