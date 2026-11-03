# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased] — EXPERIMENTAL: Rust/egui rewrite

> **Experimental.** The Flutter app is replaced by a Rust/egui rewrite.
> It is not yet verified on real hardware. This is most likely the direction
> going forward, but expect rough edges.

### Added
- One Rust/egui codebase for desktop, web (WASM) and Android (APK built in CI).
- MCP agent interface, so AI agents can drive and inspect the app.
- `neurofeed-cli` (formerly `neurofeed-mcp`): `run`, `batch`, `serve` (JSON lines) and `mcp`
  over a headless session or the running app; see docs/automation.md.
- Device simulators with fault injection for testing without hardware.
- Feedback engine and AI models.
- Session import/export.
- LSL and OSC streaming.
- Release packaging (`release.yml`, `docs/release.md`): signed Android APKs per ABI
  (arm64-v8a, armeabi-v7a), Linux tarball + AppImage, Flatpak, Windows x64 zip,
  macOS arm64 DMG. Reproducible-APK check (`repro-android.yml`) and local build
  scripts under `scripts/`.
- Build version from the git tag (`scripts/version.sh`; override with
  `NEUROFEED_VERSION` or `--version`), shown in About, sessions and MCP.
- Auto-reconnect: the last real device that streamed is remembered across
  restarts. While nothing is connected, the app scans in bursts and reconnects
  only that device; new devices still need Connect. Disconnect pauses this until
  the next connect. `device.status` shows `scan_mode` and `auto_reconnect`.

### Fixed
- Muse battery now comes from the headset status JSON (`bp`), refreshed with an `s` request every 60 s; implausible telemetry battery (Muse S classic showed 1 %) is ignored.
- `device.connect muse:<id>` works right after `device.scan` without a `device.list` in between.
- Closing the app (window, Ctrl-C, SIGTERM; CLI exit) now halts streaming and
  disconnects the Muse, waiting up to 10 s. Before, the headset stayed
  "connected" and could not be found on the next start.
- The desktop/Android app no longer connects the simulator at start. It
  reconnects only the last real device. Set `NF_DEVICE=sim:muse_s` to start
  with the simulator.
- A Muse that BlueZ still holds connected from a previous run is
  disconnected before scanning, so it advertises again.

### Changed
- License metadata is Apache-2.0 everywhere (Cargo workspace said MIT by mistake).
  `crates/pure-lsl` is dual `MIT OR Apache-2.0`.

### Removed
- The Flutter app. Its last version is tagged `pre-rust-port`
  (`git checkout pre-rust-port` to go back).

### Not yet verified
- Real Muse and Neurosity Crown hardware.
- Android: BLE connection and background streaming.
- Android safe-area insets (notch and navigation bar).

### Known limits
- The AI models run on desktop only.
- On Android, sessions only advance while the app is in the foreground.
- PDF export prints characters outside Latin-1 as "?".
