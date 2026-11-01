# MCP

`neurofeed-mcp` is a stdio MCP server. An agent host spawns it and calls its
tools. There is no separate client binary.

```sh
cargo run -q --release -p neurofeed-mcp -- --bridge
```

## Modes

- **`--bridge`** drives the running desktop app. The app must be started with
  `NF_BRIDGE=1` (or Settings → Agents). It writes `bridge.json` (address and
  token, mode 0600) under the user data dir, or `NF_BRIDGE_FILE`. Same tools
  as headless, plus `screenshot` and `ui_inspect`. Use this to see how a real
  headset behaves in the window.
- **Without `--bridge`** the process owns a headless session (simulators, and
  on desktop Muse BLE and Crown OSC). Example: `--device sim:muse_s`.
  `--manual-clock` moves time only through `clock_advance`.

The generic tools are `command_list`, `command_describe`, `command_run`, and
`command_batch`. Command ids are dotted (`device.connect`); tool names use
underscores. A few session tools (`status`, `device_list`, `bands_get`, …)
are shortcuts. Do not invent ids: `command_list` is the catalog.

`device.dialog {open:true}` watches for a Muse and a Crown until
`{open:false}`. `device.scan {seconds}` is a separate timed scan.

## Client config

The shared snippet is [`.ai/mcp.json`](../.ai/mcp.json). Each host loads its
own file. Cursor reads `.cursor/mcp.json`; symlink or copy `.ai/mcp.json`
there. This repo does not commit a client-specific folder.

Claude Code:

```sh
claude mcp add neurofeed -- cargo run -q --release -p neurofeed-mcp -- --bridge
```

Grok, `.grok/config.toml` (a release build can take longer than the default
startup timeout):

```toml
[mcp_servers.neurofeed]
command = "cargo"
args = ["run", "-q", "--release", "-p", "neurofeed-mcp", "--", "--bridge"]
startup_timeout_sec = 180
```

The first session compiles the release binary. Later sessions reuse it.
`--bridge` fails until the desktop app is running with the bridge on.

## Android

The phone build has no control channel, so `--bridge` does not reach it.
For a BLE failure on the device, read `adb logcat` and look for btleplug and
droidplug. A useful first check is whether the same headset connects in the
desktop app. If it does, the failure is on the phone (permission, droidplug),
not in the Muse decode.
