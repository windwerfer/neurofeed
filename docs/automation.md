# Automation: `neurofeed-cli` and MCP

Everything NeuroFeed can do is a **command** in the nf-core registry (dotted
ids such as `device.connect`, `feedback.start`). `neurofeed-cli` runs those
commands from a shell, a script, or an agent. Every subcommand uses the same
dispatcher (`nf_mcp::NfMcp::call`), so the CLI, the JSON-lines server and the
MCP server behave the same way.

It can drive one of two targets:

- **headless** (default): the process owns its own Session. That means
  simulators, plus Muse BLE and Crown OSC on desktop. Use it for tests and CI.
- **`--bridge`**: drives the *running* desktop app over loopback, and adds
  the `screenshot` and `ui_inspect` tools. Use it to see what the user sees,
  or to test a real headset in the window.

The web and Android builds have no control channel (see [Android](#android)).
Design rationale: [design-mcp-core.md](design-mcp-core.md).

## Build and run

```sh
cargo build --release -p neurofeed-cli     # -> target/release/neurofeed-cli (+ neurofeed-mcp alias)
target/release/neurofeed-cli --help
```

```text
neurofeed-cli [GLOBAL FLAGS] <SUBCOMMAND>
  list [GROUP]            commands (id, label, group, read_only, enabled, disabled_reason)
  describe <ID>           one command with its params JSON Schema
  run <ID|TOOL> [JSON]    a command (dotted id) or a tool (status, bands_get, screenshot, ...)
  batch <FILE|->          steps atomically, rolled back on failure
  serve                   JSON lines on stdin/stdout
  mcp                     MCP server over stdio

  --device ID     connect at start: sim:muse_s (default), sim:muse2, sim:athena, sim:crown,
                  muse:<ble-id>, crown:<id> (real devices are scanned for first, up to 8 s), or none
  --no-hardware   simulators only (no Bluetooth, no UDP 9000)
  --manual-clock  time moves only via clock_advance (deterministic)
  --db PATH       SQLite history (default: in memory; or NF_DB)
  --bridge [FILE] drive the running app (FILE defaults to NF_BRIDGE_FILE or the data dir's
                  bridge.json); --device/--db/--manual-clock are then ignored
```

Results are JSON on stdout. Errors are JSON on stderr as
`{"error": "...", "invalid": bool}`. The exit code is 1 when a command failed
(state unchanged) and 2 for invalid input (an unknown command, bad params,
usage). The `neurofeed-mcp` binary is the same program with `mcp` as its
default subcommand. It is kept so that existing client configs still work.

A headless one-shot `run` starts from a fresh session each time. To get a
sequence with data in between, use `batch`, `serve`, or `mcp`, and advance
time with `clock_advance` (or let the wall clock run).

## Examples (verified)

```sh
$ neurofeed-cli --no-hardware run status
{ "device": "sim:muse_s", "faults": [], "paused": false, "revision": 2,
  "scale": "absolute", "sidebar_open": true, "time": 0.00047, "view": "bands" }

$ neurofeed-cli --no-hardware --device none run device.connect '{"id":"sim:athena"}'
{ "ok": true }

$ neurofeed-cli --no-hardware describe sim.fault.add   # params_schema; kind: disconnect|movement|blink|...

$ echo '[{"id":"view.set","params":{"view":"psd"}},{"id":"device.connect","params":{"id":"sim:nope"}}]' \
    | neurofeed-cli --no-hardware batch -
{"error":"step 1 failed: device: unknown simulator `sim:nope`; have sim:muse_s, sim:muse2, sim:athena, sim:crown; applied 1, not run 0, rolled back","invalid":false}
# exit 1; view.set was rolled back
```

`batch` takes `[{"id","params"}, ...]` or `{"steps": [...]}`. Which commands
can be rolled back, and the limits on that: [batch-limits.md](batch-limits.md).

### `serve`: JSON lines

The request is `{"id", "method", "params"}`. The method is a command id or a
tool name. The reply is `{"id", "ok": true, "result"}` or
`{"id", "ok": false, "error", "invalid"}`, one line per request, in order.
A full simulated session (fit check → calibration → training → EDF export),
input on stdin:

```text
{"id":1,"method":"feedback.start","params":{"minutes":1}}
{"id":2,"method":"clock_advance","params":{"seconds":5}}
{"id":3,"method":"calibration.start","params":{"anyway":true}}
{"id":4,"method":"clock_advance","params":{"seconds":130}}
{"id":5,"method":"feedback.status"}
{"id":6,"method":"recording_export","params":{"format":"edf","path":"/tmp/nf-demo.edf"}}
{"id":7,"method":"nope.cmd"}
```

`neurofeed-cli --no-hardware --manual-clock serve` answers:

```text
{"id":1,"ok":true,"result":{"ok":true}}
{"id":2,"ok":true,"result":{"time":5.0}}
{"id":3,"ok":true,"result":{"ok":true}}
{"id":4,"ok":true,"result":{"time":135.0}}
{"id":5,"ok":true,"result":{"phase":{"phase":"ended"},"played_s":60,"minutes":1,"fit":{...},...}}
{"id":6,"ok":true,"result":{"bytes":227696,"extension":"edf","format":"edf","path":"/tmp/nf-demo.edf"}}
{"error":"unknown command `nope.cmd`","id":7,"invalid":true,"ok":false}
```

`feedback.status` reports `phase`: `idle`, `fit_check`, `calibrating`,
`playing` (or `paused`), then `ended`. End a `feedback.start` you began with `feedback.stop`.

Simulator faults (headless only): `sim.fault.add {"kind":"disconnect","duration_s":3}`
returns `{"ends":3.0,"id":1}`. After that, `device.status` shows
`"link":{"state":"lost","reason":"simulated disconnect"}`. `sim.fault.clear`
removes all faults, and `sim.fault` lists them. The kinds are `disconnect`,
`movement`, `blink`, `clench`, `noise`, `spikes`, `glitch` and `out_of_range`.

## The live app (`--bridge`)

1. Start the app with the bridge on: `NF_BRIDGE=1 target/release/neurofeed-egui`,
   or toggle Settings → About → **Agents**. The app listens on
   `127.0.0.1:<random port>`. It writes `{"addr", "token", "pid"}` (mode 0600)
   to `NF_BRIDGE_FILE` if set, or otherwise to:
   - Linux: `$XDG_DATA_HOME/neurofeed/bridge.json` (`~/.local/share/neurofeed/bridge.json`)
   - macOS: `~/Library/Application Support/NeuroFeed/bridge.json`
   - Windows: `%APPDATA%\NeuroFeed\bridge.json`
2. Use `neurofeed-cli --bridge [FILE] <subcommand>`. The client reads that
   file, connects, and sends the token first. Never print or paste the token.

```text
$ neurofeed-cli --bridge run device.connect '{"id":"sim:muse_s"}'
{ "ok": true }
$ neurofeed-cli --bridge run screenshot '{"path":"/tmp/nf-shot.png"}'
{ "height": 700, "mime": "image/png", "path": "/tmp/nf-shot.png", "width": 1100 }
$ neurofeed-cli --bridge run ui_inspect      # widget tree: role, label, value, rect (points)
```

With a real Muse: run `device.dialog {"open":true}` (it watches Muse BLE and
Crown OSC until `{"open":false}`), or `device.scan {"seconds":8}`. Then use
`device_list`; real ids are `muse:<ble id>` and `"simulated": false`. Then
call `device.connect {"id":"muse:..."}`. Scan failures appear in
`device.status` under `provider_errors`.

The last real device that streamed is remembered (`settings.get` →
`last_device`). While nothing is connected, the app scans in short bursts
(6 s every 30 s, every 2 min after 5 min) and reconnects that device only.
Other devices always need `device.connect`. `device.disconnect` turns this
off until the next connect or app start. `device.status` shows `scan_mode`
(`dialog`, `background`, `timed`, `idle`) and `auto_reconnect`
(`target`, `suspended`, `searching`, `attempts`, `next_scan_in_s`). Contract:
[.ai/contracts/device-autoconnect.md](../.ai/contracts/device-autoconnect.md).

A `screenshot` `path` is written by the CLI process, not by the app. The
screenshot times out after 5 s, and any other bridge reply after 30 s.

### UI layout

`settings.set {"layout":"compact"}` forces the phone layout on any window: in
portrait a compact top bar, a `☰` navigation drawer and a full-screen Device
sheet; in landscape monitor screens are immersive (graph only). `"regular"`
forces sidebar + top bar. `"auto"` (default) switches below 600 px width on
desktop, and by orientation on phones. Start the desktop app with
`NF_WINDOW=400x850` (or `850x400`) to get a phone-sized window, then combine with
`screenshot` to capture each mode.

### Monitors (time viewport)

Every live graph has a viewport in the core. In Follow the right edge is the
newest data. In Inspect the right edge is frozen at `end_s` (session seconds).

```sh
neurofeed-cli run monitor.get                                    # window, mode, start_s/end_s, presets, min/max per monitor
neurofeed-cli run monitor.viewport '{"monitor":"bands","window_s":60}'   # saved per monitor
neurofeed-cli run monitor.zoom '{"monitor":"bands","factor":2,"focal":0.5}'  # pinch / Ctrl+wheel
neurofeed-cli run monitor.pan '{"monitor":"bands","seconds":-10}'        # drag; enters Inspect
neurofeed-cli run monitor.viewport '{"monitor":"bands","mode":"follow"}'
neurofeed-cli run monitor.display '{"electrodes":["AF7","AF8"],"hidden_bands":["gamma"]}'
neurofeed-cli run scale.set '{"scale":"relative"}'                       # dB | % (saved)
neurofeed-cli run monitor.raw '{"mode":"scroll","scale":"100"}'           # Raw EEG: sweep|scroll, auto|50|100|200 µV (saved)
neurofeed-cli run monitor.raw '{"electrodes":["TP9","TP10"]}'             # shown panes (empty = all; session only)
```

Monitor ids are `bands`, `raw_eeg`, `spectrogram`, `heart_overview`, `heart_detail`
and `movement`. Bands and Raw EEG draw from this viewport (Raw EEG: the 5 min signal ring; sweep while following, a time-ordered hold in Inspect) (the other screens follow
in later milestones). Zoom keeps the time under `focal` (0 = left edge, 1 = right
edge) in place. Zooming at the right edge keeps Follow, while any other focal point
enters Inspect. The window is clamped to the monitor's range (Bands 5 s to 30 min)
and the right edge to the available data. In the app, a drag pans, a pinch or
Ctrl/Cmd+wheel zooms at the pointer, the wheel pans (vertical only while inspecting)
and a double-click returns to Follow.
`settings.set {"language":"de"}` switches the UI to German (`"en"`, or
`"auto"` = system locale, the default); tool and CLI output stay English.
Contract: [.ai/contracts/i18n.md](../.ai/contracts/i18n.md). Contract:
[.ai/contracts/ui-layout.md](../.ai/contracts/ui-layout.md).

## MCP clients

`neurofeed-cli mcp` speaks MCP over stdio (server name `neurofeed`). Point the
client at the **built binary**. The first `cargo run --release` compile takes
minutes and usually exceeds a client's startup timeout. Use `cargo run` only
when you are changing the server itself.

Cursor reads `.cursor/mcp.json` (not committed; create it locally):

```json
{ "mcpServers": { "neurofeed": {
    "command": "${workspaceFolder}/target/release/neurofeed-cli", "args": ["--bridge", "mcp"] } } }
```

Claude Code:

```sh
claude mcp add neurofeed -- "$PWD/target/release/neurofeed-cli" --bridge mcp
claude mcp add neurofeed-headless -- "$PWD/target/release/neurofeed-cli" --no-hardware --manual-clock mcp
```

Any stdio host uses the generic `mcpServers` shape. [`.ai/mcp.json`](../.ai/mcp.json)
is the `cargo run` variant:

```json
{ "mcpServers": { "neurofeed": {
    "command": "cargo",
    "args": ["run", "-q", "--release", "-p", "neurofeed-cli", "--bin", "neurofeed-cli", "--", "--bridge", "mcp"] } } }
```

Grok reads `.grok/config.toml` (the same `cargo run`, with `startup_timeout_sec = 180`).

### Tools

| Tool | Args | Notes |
|---|---|---|
| `command_list` | `{group?}` | the catalog; do not invent ids |
| `command_describe` | `{id}` | metadata plus `params_schema` (JSON Schema); no output schema yet |
| `command_run` | `{id, params?}` | any command |
| `command_batch` | `{steps:[{id,params?}]}` | atomic, rolled back on failure |
| `status` | `{}` | `app.status`, including `revision` (bumped on every change) |
| `bands_get` | `{scale?: absolute\|relative}` | latest band powers per channel |
| `device_list` | `{}` | simulators and real devices found |
| `clock_advance` | `{seconds}` | 0 < s ≤ 3600; runs the pipeline |
| `recording_export` | `{format: nfed6\|raw_body\|edf\|pdf, start?, path?}` | with `path` it writes the file and returns `{path, bytes}`; otherwise base64 |
| `screenshot` | `{path?}` | bridge only: a PNG image, or written to `path` |
| `ui_inspect` | `{}` | bridge only: the accessibility widget tree |

Verified exchange (`neurofeed-mcp --no-hardware --manual-clock`):

```text
>> {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"command_run","arguments":{"id":"device.connect","params":{"id":"sim:crown"}}}}
<< {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"{\"ok\":true}"}],"isError":false}}
>> {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"clock_advance","arguments":{"seconds":2}}}
<< {"jsonrpc":"2.0","id":4,"result":{"content":[{"type":"text","text":"{\"time\":2.0}"}],"isError":false}}
>> {"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"nope","arguments":{}}}
<< {"jsonrpc":"2.0","id":7,"error":{"code":-32602,"message":"unknown tool `nope`"}}
>> {"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"status","arguments":{"x":1}}}
<< {"jsonrpc":"2.0","id":8,"error":{"code":-32602,"message":"unknown argument `x` for status"}}
```

Errors: an unknown tool, an unknown argument, or a missing required string
argument gets JSON-RPC **-32602**. A command that fails, including an unknown
command id or bad `params`, returns a result with `isError: true` and a
message, and leaves the state unchanged. Panics are caught per call and the
session survives.

## Android

The phone build has no bridge or control channel. To debug BLE there, run
`adb logcat` and filter for `btleplug`, `droidplug` and `neurofeed`. Check
first whether the same headset connects in the desktop app. If it does, the
fault is on the phone (permissions, droidplug), not in the Muse decode.

## Troubleshooting

- `--bridge`: "No such file" or "connection refused": the app is not running
  with the bridge on, or it was restarted and the file is stale. Restart it
  with `NF_BRIDGE=1`, or pass the right `FILE` (or `NF_BRIDGE_FILE`).
- The client times out at startup: use the built binary, not `cargo run`.
- A headless start hangs for about 8 s: `--device muse:...` scans first. Use
  `--no-hardware` for simulator-only runs, so there is no Bluetooth and no
  UDP 9000.
- No Muse found on Linux: check that BlueZ is running, that `rfkill` does not
  block it, and that `bluetoothctl scan on` sees the headset. Then try
  `device.scan` followed by `device_list`. The scan runs on every adapter.
  It lists a device when its name starts with "Muse" (any case) or when it
  advertises the Muse service 0xFE8D (shown as "Muse" until the name
  arrives). RSSI is optional. A device BlueZ had cached before the scan
  started, and that reports no RSSI, is treated as not nearby. A headset
  drops off the list 10 s after its last advertisement. A Muse that is
  connected (to the phone, say) does not advertise.
- See every advertisement: start the desktop app with `RUST_LOG=nf_device=debug`. Each poll
  logs `BLE adv id=... name=... rssi=... muse_service=... -> listed|ignored`.
  Adapter, scan and connect failures appear in `device.status` under
  `provider_errors`.
- Connect fails with "not seen in a 4 s rescan": muse-rs cannot reuse the
  scan's peripheral, so connecting rescans for 4 s and picks the selected
  BLE id. Keep the headset on and close by, and make sure nothing else is
  connected to it.
- The Muse is not found after the app was killed or crashed: the headset can
  still believe it is connected, so it does not advertise. The next scan
  disconnects a Muse that BlueZ still holds without a NeuroFeed link. If that
  does not help, run `bluetoothctl disconnect <addr>`, or power-cycle the
  headset (hold the button until the lights go off, then turn it on). A normal
  window close or Ctrl-C disconnects first, waiting at most 10 s.
- A simulator connected at start: only with `NF_DEVICE=sim:...`, `NF_DEMO`,
  `NF_VIEW`, the web build, or the CLI's default `--device sim:muse_s`. The
  desktop app reconnects only the remembered real device.
- Port 9000 already in use (Crown OSC): another NeuroFeed instance is
  running. Use `--no-hardware`.
