# Decisions (dated, append-only)

- 2026-10-29: Flutter dropped; Rust-only, egui on desktop/web/Android. Dart stays as reference until the feedback engine is ported, then is deleted in one commit.
- 2026-10-29: Android = thin native wrapper (permissions, BLE scan/transport via JNI if needed) hosting the same Rust core; it supplies a `DeviceProvider`, and talks to the core through the same command JSON surface.
- 2026-10-29: MCP surface = generic command_list/describe/run/batch + a few typed session tools. Add a command, not a tool.
- 2026-10-29: Command ids are dotted (`area.verb`); MCP tool names use underscores.
