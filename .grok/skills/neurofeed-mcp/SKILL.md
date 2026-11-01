---
name: neurofeed-mcp
description: >
  Drive NeuroFeed by calling the neurofeed-mcp server's tools. Use when
  testing the running Linux app, a headless session, a BLE or Crown scan,
  connect, feedback, or any command.
---

`neurofeed-mcp` is a stdio MCP server. Call its tools. The shared client
snippet is `.ai/mcp.json`; how each host loads it is `docs/mcp.md`. Grok
reads `.grok/config.toml`.

- **`--bridge`** (the registered server) drives the running desktop app.
  Start the app with `NF_BRIDGE=1` when `~/.local/share/neurofeed/bridge.json`
  is missing. Same tools plus `screenshot` and `ui_inspect`.
- **Without `--bridge`** it is a headless session, for example
  `--device sim:muse_s`.

`WAYLAND_DISPLAY` is enough to start the egui app. Do not start Xvfb. Do not
kill Pulse, Wayland, or adb. Never print the bridge token.

```sh
mkdir -p /tmp/neurofeed-agent
NF_BRIDGE=1 setsid ./target/debug/neurofeed-egui \
  > /tmp/neurofeed-agent/egui.log 2>&1 < /dev/null &
echo $! > /tmp/neurofeed-agent/egui.pid
```

Use `target/release/neurofeed-egui` when the debug binary is absent. The app
connects `sim:muse_s` on launch. Stop only that pid.

`command_list` and `command_describe` are the catalog. Do not invent command
ids. `device.dialog {open:true}` watches Muse BLE and Crown OSC until
`{open:false}`. `device.scan {seconds}` is a timed scan. A real Muse id is
`muse:<ble id>`. Simulators are `simulated: true`. Failures are
`provider_errors`.

End a `feedback.start` you started with `feedback.stop`.

Android has no bridge. Use `adb logcat` (btleplug, droidplug). If the same
headset connects on the desktop, the phone failure is permissions or
droidplug.
