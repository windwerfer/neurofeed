# NeuroFeed

****
*
*  the app is porting from Flutter + Rust to pure Rust at the moment, the whole UI is just preliminary at the moment.
*  it will take me a while to bring it back to how it behaved, so no new releases for a while.
*  
*  the reason is, that i saw the software design of PhotoCraft and see now that mixing Flutter and Rust is possible but makes 
*  the development process for AI agents unnesseccarily complicated. Its an experiment so far, but it seems very potent.
*
****

EEG brainwave viewer and feedback. At the moment we support Muse 2, Muse S, Muse Athena
and the Neurosity Crown as input devices. 

- Bands Monitor
- Raw EEG
- Historgram
- Spectogram
- Feedback System is beeing worked on (using freely available, labeled EEG data, we try to find
  feedback presets that helps train you mind)
- Record your Brainwaves and export them to EDF+ or CSV
- Import from EDF data or MindMonitors CVS

This is a pure Rust implementation, making it natively on Windows, Linux, Mac and Android, or on every system with
chrome support through WEB Assembly.

The Project is structurally heavily inspired by PhotoCraft's approach to make AI agents able to use the programm through 
a headless core (`nf-core`), an MCP server and exposing every command (`nf-mcp`) through cli. Signal processing (`nf-dsp`), recording
formats NFED6/EDF+ (`nf-format`), deterministic raw-sample device simulators
(`nf-sim`), and an egui/eframe UI for desktop and web (Android later).


# how to run

Check out the release page if you just want to use it. If you want to help with improving or want to compile it yourself, i recommend using
the development container. you only need rust installed for the desktop version, for android builds you need the whole android toolchain (scripts for
easy setup are in the .devcontainer subfolder). I use Zed as my editing IDE and podman, so expect small glitches with VS Code and docker. 


```sh
# prerequisites: rustup target add wasm32-unknown-unknown; cargo install trunk
# Linux: apt install pkg-config libasound2-dev libdbus-1-dev
#   (Fedora: alsa-lib-devel dbus-devel); ALSA = feedback audio (skip with
#   --no-default-features), D-Bus = Bluetooth (BlueZ) for the Muse
cargo run --release -p neurofeed-egui                       # desktop (repo root)
cd apps/neurofeed-egui && trunk serve --release             # web, http://127.0.0.1:8080
cargo run --release -p neurofeed-cli --bin neurofeed-cli -- run status  # one command, headless
NF_BRIDGE=1 cargo run --release -p neurofeed-egui           # desktop + agent bridge, then:
target/release/neurofeed-cli --bridge mcp                   # MCP driving the live app
cargo test && cargo clippy --all-targets -- -D warnings
```

Real devices (desktop): the Device dialog scans for a Muse over Bluetooth and
a Crown streaming OSC to UDP 9000 for as long as it is open (Neurosity app /
SDK OSC output), then Connect. MCP: `device.dialog`, `device.list`,
`device.connect`. `device.scan {seconds}` is a timed scan. The web build has
simulators only.

Agent bridge: with `NF_BRIDGE=1` or Settings > About > Agents, the app listens on
127.0.0.1 (random port) and writes the port + a random token to
`~/.local/share/neurofeed/bridge.json` (0600; macOS `~/Library/Application
Support/NeuroFeed`, Windows `%APPDATA%\NeuroFeed`, or `NF_BRIDGE_FILE`).
`neurofeed-cli --bridge` then drives the running app with the same tools plus
`screenshot` and `ui_inspect` (widget tree). CLI, JSON lines, MCP and client setup: [docs/automation.md](docs/automation.md).

Read [AGENTS.md](AGENTS.md), then [docs/](docs/).

### Importing recordings

History → **Import…** (or drop a file on the window) accepts EDF/EDF+, Mind Monitor CSV (constant or interval mode), `.neurofeed` and raw NFEDBIN. A preview lists what is kept and what is lost before anything is saved. MCP: `history.import_preview` / `history.import` with `{file_name, data_base64}`.

### Protocol Builder

Feedback → "New protocol…" (starts from the selected protocol) or "Edit …" on a custom one. Set the title, reward feature, eyes, length, up to two band ceilings (beta, delta) and whether the drowsiness guard is offered (still off until switched on). The card preview and problems update as you type. Custom protocols are saved with history (SQLite on desktop, localStorage in the browser). MCP: `protocol.validate`, `protocol.draft`, `protocol.save`, `protocol.delete`.

### Streaming (OSC)

Streaming → enable, set IP/port/prefix. Messages `<prefix>/eeg|ppg|imu|bands` with `[t, values…]` float32. MCP: `streaming.set`, `streaming.status`. Desktop only (browsers cannot send UDP). LSL is not available yet.
