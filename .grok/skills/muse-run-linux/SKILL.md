---
name: muse-run-linux
description: >
  Start Muse ML on Linux, wait for the debug agent HTTP server, curl connect /
  session / settings, read logs. Use when running the app, connecting the
  simulator, starting a feedback session, or reading Linux logs.
---

Linux only. Do **not** kill Pulse, X, Wayland, adb, or the Dart language-server.
Crown Start stays refused. Audio silence is N/A (not a failure). Needs a GTK
display — if `flutter run -d linux` never prints `agent-ready`, stop and
report; do not invent Xvfb.

Defines are **`--dart-define` only**. `export MUSE_AGENT=1` does nothing.
`parseDartDefineFlag` accepts `true` / `1` / `yes`. Prefer `true`.
API table and gotchas: `.ai/testing-guide.md` (Linux agent). What to assert:
`.ai/test-matrix.md`. Spoken names: `.ai/ui-map.md`.

This sandbox often has `DISPLAY` unset — set `GDK_BACKEND=wayland`.

```bash
# Previous Linux run only — do not pkill language-server / Pulse / X.
pkill -f 'flutter run -d linux' 2>/dev/null || true
pkill -f '/build/linux/.*/muse_ml' 2>/dev/null || true

# If rust/src/api/ or generated bindings changed:
cargo build --release --manifest-path rust/Cargo.toml

mkdir -p /tmp/muse-agent
: > /tmp/muse-agent/flutter_run.log
cd /workspaces/flutter_muse_ml
GDK_BACKEND=wayland setsid flutter run -d linux \
  --dart-define=MUSE_AGENT=true \
  --dart-define=MUSE_DEBUG=true \
  > /tmp/muse-agent/flutter_run.log 2>&1 < /dev/null &
echo $! > /tmp/muse-agent/flutter_run.pid
```

Wait (timeout ~180s cold, ~30s warm). Abort if the log contains `Content hash` or
`Init error`. Ready = both lines:

- `[muse] agent-listen 127.0.0.1:<port>`
- `[muse] agent-ready`

Parse the port from `agent-listen`. Do not assume 17890. Never `tail -f` as the wait.

```bash
PORT=$(grep -oE 'agent-listen 127.0.0.1:[0-9]+' /tmp/muse-agent/flutter_run.log | tail -1 | grep -oE '[0-9]+$')
BASE=http://127.0.0.1:$PORT

curl -sS $BASE/health
# Startable Muse: sim:muse-2 or sim:muse-s. Never sim:crown-osc / sim:notion-osc here.
curl -sS -X POST $BASE/connect -H 'Content-Type: application/json' -d '{"id":"sim:muse-2"}'
curl -sS $BASE/state   # connected=true, scanMessage null
curl -sS -X POST $BASE/session/select -H 'Content-Type: application/json' -d '{"protocol":"recordOnly"}'
curl -sS -X POST $BASE/session/duration -H 'Content-Type: application/json' -d '{"minutes":1}'
curl -sS -X POST $BASE/session/start -H 'Content-Type: application/json' -d '{"skipCalibration":true}'
curl -sS $BASE/state   # phase=playing
grep -nE '\[muse\]|\[feedback\]|Content hash' /tmp/muse-agent/flutter_run.log | tail -50

# always, even on failure:
curl -sS -X POST $BASE/session/end -H 'Content-Type: application/json' -d '{}'
curl -sS -X POST $BASE/session/reset -H 'Content-Type: application/json' -d '{}'
```

- Connect **Muse 2** (`sim:muse-2`) or **Muse S** (`sim:muse-s`). After connect,
  `scanMessage` must be null. Never Crown/Notion for a playing session.
- `POST /view {"view":"settings"}` (or `bands` / `rawEeg`) uses `AppView.name`.
  Session UI is **not** pushed; start/pause/end go through the notifier.
- HTTP 409 `crown_refused` is success for a Crown-start check.
- Omit the `pkill` / pid kill when keeping the app up for further curls.
- Do not leave `MUSE_AGENT=true` on an Android `flutter run`.
