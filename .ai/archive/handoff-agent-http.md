# Handoff — debug agent HTTP (archived)

| Field | Value |
|---|---|
| Date | 2026-09-05 |
| Branch | `main` (`160affe` HTTP; `fa53f7b` dart-define `true`/`1`/`yes`) |
| Status | **Landed.** Live smoke done. Do not treat this file as current how-to. |

Current how-to: [../testing-guide.md](../testing-guide.md) Linux agent.
What to assert: [../test-matrix.md](../test-matrix.md).
Skill: `.grok/skills/muse-run-linux/SKILL.md`.
Spoken names: [../ui-map.md](../ui-map.md).

---

## What this was

Debug-only loopback HTTP so an agent can `curl` the same Riverpod notifiers
the UI uses (connect, view, session). Not widget tests. Gate:
`kDebugMode && MUSE_AGENT`. Bind `127.0.0.1` only.

## Proven live (2026-09-05)

- `agent-listen` + `agent-ready` with `--dart-define=MUSE_AGENT=true`.
- `sim:muse-s` connect; `scanMessage` null after the connect fix.
- `POST /view` `bands` / `rawEeg` / `settings`; sidebar; connect-window.
- `recordOnly` + skip-cal → `phase=playing` → end/reset.
- `sim:crown-osc` start → HTTP 409 `crown_refused`.

## Lessons (do not re-learn)

- `--dart-define=MUSE_AGENT=1` is a no-op for raw
  `bool.fromEnvironment`. Use `parseDartDefineFlag` (`true`/`1`/`yes`).
  Prefer `--dart-define=MUSE_AGENT=true`. Process `export` does nothing.
- First live drive used `1` and never bound; `true` bound.
- `DISPLAY` unset here; `GDK_BACKEND=wayland` works. Do not invent Xvfb.
- Agent `persist: false` does not wipe a human `lastDeviceId` — next
  launch can autoconnect to a saved Crown.
- Successful `connectTo` must clear `scanMessage` (was leftover
  `Connecting… (attempt 1)`).

## Out of scope (still)

Crown run, OSC discovery/connect, session byte layout, widget /
`integration_test` pyramid, `navigatorKey` / `POST /session/open`.
