---
name: neurofeed-run-linux
description: >
  Retired Flutter debug-agent notes. Use the neurofeed-mcp skill to drive
  NeuroFeed through the neurofeed-mcp server.
---

The debug HTTP agent and `flutter run -d linux` are gone. The app is the Rust
egui binary. Call the `neurofeed-mcp` tools. See the `neurofeed-mcp` skill
and `docs/automation.md`.

Do not kill Pulse, Wayland, or adb. Do not invent a virtual display.
