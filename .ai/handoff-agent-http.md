# Handoff — debug agent HTTP

| Field | Value |
|---|---|
| Date | 2026-09-05 |
| Branch | `main` (HTTP in `160affe`; dart-define `true`/`1` fix in the follow-up commit) |
| Do not mix | Crown Start unlock, OSC connect, pipeline-contract, session format, widget/`integration_test` pyramid |
| Status | HTTP **implemented**. First live drive **not finished**. Server is up on this machine. |

Maps: [ui-map.md](ui-map.md), [test-matrix.md](test-matrix.md), [testing-guide.md](testing-guide.md) Linux agent. Skill: `.grok/skills/muse-run-linux/SKILL.md`.

---

## What this is

Debug-only loopback HTTP so an agent can `curl` the **same Riverpod notifiers** the UI uses (connect, view, session). Not widget tests. Not OS clicks. Session smoke is **notifier-only** — it does **not** push `FeedbackSessionView`.

Gate: `kDebugMode && MUSE_AGENT`. Profile/release compile it out. Bind `127.0.0.1` only.

---

## Do this first (unfinished user request)

Human asked: `flutter run -d linux`, **Muse S classic** simulator, Raw EEG, wait 10s, Bands.

That run **did not complete**. First launch used `--dart-define=MUSE_AGENT=1`; Dart `bool.fromEnvironment` is true only for the string `true`, so **no HTTP server**. App still streamed EEG (something was already connected). Restarted with `MUSE_AGENT=true` — HTTP came up. **Did not curl connect/view yet.**

If this process is still alive:

```
[muse] agent-listen 127.0.0.1:17890
[muse] agent-ready
```

Log: `/tmp/muse-agent/flutter_run.log`. Binary pid ~36674. `ss` should show `127.0.0.1:17890` on `muse_ml`.

```bash
BASE=http://127.0.0.1:17890
curl -sS $BASE/health
curl -sS -X POST $BASE/connect -H 'Content-Type: application/json' \
  -d '{"id":"sim:muse-s"}'
curl -sS $BASE/state   # expect connected, deviceName Muse S (Simulated)
curl -sS -X POST $BASE/view -H 'Content-Type: application/json' \
  -d '{"view":"rawEeg"}'   # Spoken: Raw EEG
sleep 10
curl -sS -X POST $BASE/view -H 'Content-Type: application/json' \
  -d '{"view":"bands"}'
curl -sS $BASE/state   # expect view=bands
```

`sim:muse-s` = Muse S (Classic). Not `sim:muse-s-athena`. Never Crown (`sim:crown-osc`).

If 17890 is dead, relaunch per the skill with **`true`**, wait for **both** listen + ready, parse the port (fallback 17891–99 then 0).

---

## Dart-define fix (landed with this handoff)

`parseDartDefineFlag` accepts `true` / `1` / `yes`. Skills and testing-guide
use `--dart-define=MUSE_AGENT=true`. `flutter test test/agent/agent_config_test.dart`
green.

---

## API (loopback JSON)

`AgentCommands` in `lib/src/agent/agent_commands.dart`. Errors: `{ok:false, error, message?}`.

| Verb | Body | Notes |
|---|---|---|
| `GET /health` | — | `{ok, version}` |
| `GET /state` | — | view, connected, device*, phase, protocol, duration, `audioInitFailed` |
| `POST /view` | `{view}` | `AppView` **name**: `feedback`, `feedbackHistory`, `bands`, `rawEeg`, `spectrogram`, `psd`, `streaming`, `settings` |
| `POST /sidebar` | `{open:bool}` | |
| `POST /connect-window` | `{open, source?}` | `source`: `muse`/`neurosity`/`simulator`. New `setConnectWindow` (not toggle). |
| `POST /connect` | `{id}` | `simulatorCatalogRow` then scanned list. `persist: false`. 409 `connect_failed` / `busy`. |
| `POST /disconnect` | `{}` | `persist: false` (does not wipe human `lastDeviceId`). |
| `POST /session/select` | `{protocol}` | await catalog. 412 `unknown_protocol`. |
| `POST /session/duration` | `{minutes}` | `persist: false`. Smoke uses `1`. |
| `POST /session/start` | `{skipCalibration}` | 412 not connected; 409 `crown_refused`. |
| `POST /session/pause\|resume\|end\|reset` | `{}` | end/reset are 200 no-ops if idle / not connected. **Always end+reset** after a smoke. |

Agent path **never writes SharedPreferences**.

---

## Files

| Path | Role |
|---|---|
| `lib/src/agent/agent_flags.dart` | `MUSE_AGENT` / `MUSE_DEBUG` |
| `lib/src/agent/agent_server_config.dart` | enabled + port range |
| `lib/src/agent/agent_protocol.dart` | parse view/source, resolve id, errors |
| `lib/src/agent/agent_commands.dart` | HTTP → notifiers |
| `lib/src/agent/agent_server_io.dart` | `HttpServer.bind(loopback)` |
| `lib/src/agent/agent_server_stub.dart` | non-io |
| `lib/src/agent/agent_server.dart` | conditional export |
| `lib/src/app.dart` | `ProviderContainer` + `UncontrolledProviderScope`; `agent-ready` after first frame **and** `_init` |
| `lib/src/connection_provider.dart` | `persist:`, `setConnectWindow`, `initDone`; `MUSE_AGENT` skips BLE scan, starts Simulator catalog |
| `lib/src/settings.dart` | `MUSE_DEBUG` ORs into `enableSimulatedDevices` (no pref write) |
| `lib/src/feedback/feedback_state.dart` | `_setPhase` logs, `audioInitFailed`, `selectDuration(persist:)` |
| `test/agent/` | protocol + config + bind `/health` on port 0 |

---

## How to run

Defines are **`--dart-define` only**. Process `export MUSE_AGENT=…` does nothing.

```bash
# DISPLAY often unset here; Wayland works:
GDK_BACKEND=wayland flutter run -d linux \
  --dart-define=MUSE_AGENT=true \
  --dart-define=MUSE_DEBUG=true
```

Wait for `[muse] agent-listen 127.0.0.1:<port>` **and** `[muse] agent-ready`. Abort on `Content hash` (stale `rust/target/release/`). Do not kill Pulse/X/Wayland.

`debugPrint` **does** reach the `flutter run` log (proven this session once the flag was `true`).

---

## Known issues / gotchas

1. **`MUSE_AGENT=1` is a no-op for `bool.fromEnvironment`.** First live test failed for this. Fix is uncommitted (`parseDartDefineFlag`).
2. HTTP does **not** prove a button’s `onPressed`. Dead Start button can still start via `/session/start`.
3. Session UI is not mounted. Dashboard `pushReplacement` on `ended` will not run.
4. Default duration is 15 min if you skip `/session/duration`.
5. SoLoud init throw is caught → `audioInitFailed` + log; phase can still be `playing`. Silence ≠ fail.
6. GTK at-spi / cursor-theme warnings on Linux are noise.
7. Widget tests / `integration_test` / Patrol / goldens are **out of this thread**.
8. Frozen: Crown Start refused; `DeviceKind` Muse\|Neurosity; connect-simulator-ux names.

---

## Suggested order for the next thread

1. Finish the Muse S → `rawEeg` → 10s → `bands` smoke (above). Confirm `/state` and on-screen view.
2. Then: `sim:muse-s` + `recordOnly` + skip-cal + 1 min + `phase=playing` + end/reset (optional).
3. Only then: extra HTTP bugs the human reports.

---

## Out of scope

Crown run, OSC discovery/connect, session byte layout, CI `flutter test` workflow, `navigatorKey` / `POST /session/open`.
