# NeuroFeed 0.10.0-experimental — Rust/egui rewrite

> **EXPERIMENTAL.** The Flutter app has been replaced by a Rust/egui rewrite.
> It is not yet verified on real hardware. This is most likely the way forward,
> but expect rough edges.

## What's in it
- One Rust codebase for desktop, web (WASM) and Android (APK built in CI).
- MCP agent interface, so AI agents can drive and inspect the app.
- Device simulators with fault injection for testing without hardware.
- Feedback engine and AI models.
- Session import/export.
- LSL and OSC streaming.

## Not yet verified
- Real Muse and Neurosity Crown hardware.
- Android: BLE connection and background streaming.
- Android safe-area insets (notch and navigation bar).

## Known limits
- The AI models run on desktop only.
- On Android, sessions only advance while the app is in the foreground.
- PDF export prints characters outside Latin-1 as "?".

## Going back
The last Flutter version is tagged `pre-rust-port`:
`git checkout pre-rust-port`.
