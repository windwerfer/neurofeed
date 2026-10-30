# NeuroFeed (Rust)

Rust-only rewrite of NeuroFeed: a headless core (`nf-core`), an MCP server
exposing every command (`nf-mcp`), signal processing (`nf-dsp`), recording
formats NFED6/EDF+ (`nf-format`), deterministic raw-sample device simulators
(`nf-sim`), and an egui/eframe UI for desktop and web (Android later).

Status: Phase 3 + PPG. Functional views: **Bands, Raw EEG, PSD, Spectrogram,
Histogram, HR+SpO2** (simulators `sim:muse_s`, `sim:muse2`, `sim:athena` (no PPG), `sim:crown`;
`sim:muse` is an alias of `sim:muse_s`), plus record/stop and an auto/50/60/off
notch with per-pad quality in the top bar. Everything is also reachable via
MCP (`raw.get`, `psd.get`, `spectrogram.get`, `histogram.get`,
`signal.status`, `features.get`, `hr.get`, `spo2.get`, `ppg.get`, `mains.set`, `recording.*`).
Desktop start view: `NF_VIEW=psd cargo run -p neurofeed-egui`.

```sh
# prerequisites: rustup target add wasm32-unknown-unknown; cargo install trunk
# Linux: apt install pkg-config libasound2-dev libdbus-1-dev
#   (Fedora: alsa-lib-devel dbus-devel); ALSA = chime sound (skip with
#   --no-default-features), D-Bus = Bluetooth (BlueZ) for the Muse
cargo run --release -p neurofeed-egui                       # desktop (repo root)
cd apps/neurofeed-egui && trunk serve --release             # web, http://127.0.0.1:8080
cargo run --release -p neurofeed-mcp -- --device sim:muse_s # MCP over stdio (headless)
NF_BRIDGE=1 cargo run --release -p neurofeed-egui           # desktop + agent bridge, then:
cargo run --release -p neurofeed-mcp -- --bridge            # MCP driving the live app
cargo test && cargo clippy --all-targets -- -D warnings
```

Real devices (desktop): Settings > Devices > Scan finds a Muse over Bluetooth
and a Crown streaming OSC to UDP 9000 on this machine (Neurosity app / SDK
OSC output), then Connect. MCP: `device.scan`, `device.list`, `device.connect`.
The web build has simulators only.

Agent bridge: with `NF_BRIDGE=1` or Settings > Agents, the app listens on
127.0.0.1 (random port) and writes the port + a random token to
`~/.local/share/neurofeed/bridge.json` (0600; macOS `~/Library/Application
Support/NeuroFeed`, Windows `%APPDATA%\NeuroFeed`, or `NF_BRIDGE_FILE`).
`neurofeed-mcp --bridge` then drives the running app with the same tools plus
`screenshot` and `ui_inspect` (widget tree). MCP client config:
`{"command": "neurofeed-mcp", "args": ["--bridge"]}`.

Read [AGENTS.md](AGENTS.md), then [docs/](docs/).
