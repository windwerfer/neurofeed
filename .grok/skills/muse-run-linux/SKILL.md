---
name: muse-run-linux
description: >
  Start Muse ML on Linux, wait for the debug agent HTTP server, curl connect /
  session / settings, read logs. Use when running the app, connecting the
  simulator, starting a feedback session, or reading Linux logs.
---

Linux only. Do **not** kill Pulse, X, Wayland, or adb. Crown Start stays refused.
Audio silence is N/A (not a failure). Needs a GTK display — if `flutter run -d linux`
never prints `agent-ready`, stop and report; do not invent Xvfb.

Defines are **`--dart-define` only**. `export MUSE_AGENT=1` does nothing.

```bash
ps aux | grep -iE 'flutter|dart:flutter' | grep -v grep | grep -v defunct \
  | awk '{print $2}' | xargs -r kill -9

# If rust/src/api/ or generated bindings changed:
cargo build --release --manifest-path rust/Cargo.toml

mkdir -p /tmp/muse-agent
: > /tmp/muse-agent/flutter_run.log
cd /workspaces/flutter_muse_ml
setsid flutter run -d linux \
  --dart-define=MUSE_AGENT=1 \
  --dart-define=MUSE_DEBUG=1 \
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
curl -sS -X POST $BASE/connect -H 'Content-Type: application/json' -d '{"id":"sim:muse-2"}'
curl -sS -X POST $BASE/session/select -H 'Content-Type: application/json' -d '{"protocol":"recordOnly"}'
curl -sS -X POST $BASE/session/duration -H 'Content-Type: application/json' -d '{"minutes":1}'
curl -sS -X POST $BASE/session/start -H 'Content-Type: application/json' -d '{"skipCalibration":true}'
curl -sS $BASE/state
grep -nE '\[muse\]|\[feedback\]|Content hash' /tmp/muse-agent/flutter_run.log | tail -50

# always, even on failure:
curl -sS -X POST $BASE/session/end -H 'Content-Type: application/json' -d '{}'
curl -sS -X POST $BASE/session/reset -H 'Content-Type: application/json' -d '{}'

kill -- -$(cat /tmp/muse-agent/flutter_run.pid) 2>/dev/null || true
```

- Connect **Muse 2** (`sim:muse-2`), never `sim:crown-osc` / `sim:notion-osc`.
- `POST /view {"view":"settings"}` to open Settings. Session UI is **not** pushed;
  start/pause/end go through the notifier.
- HTTP 409 `crown_refused` is success for a Crown-start check.
- Do not leave `MUSE_AGENT=1` on an Android `flutter run`.
