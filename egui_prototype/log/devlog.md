# Dev log (append-only, newest last)

## 2026-10-29: Phase 1 core + MCP
- Workspace: nf-types (L0), nf-sim (L1), nf-core (L2), nf-mcp (L4), apps neurofeed-egui, neurofeed-mcp.
- nf-core: Session tick/execute/query/run/batch/commands/enabled/drain_events; dotted command ids; schemars
  input schemas; enabled -> disabled reason; revision counter; atomic batch with rollback; failing commands change nothing.
- nf-mcp: command_list/describe/run/batch + status, bands_get, device_list, clock_advance. Panics caught per call.
- Gate (manual until xtask): cargo fmt --check; cargo clippy --all-targets -D warnings; cargo test (19); cargo check -p neurofeed-egui --target wasm32-unknown-unknown; trunk build.
- Open: xtask (layers/wasm/ci), output schemas, bridge mode, control channel, raw-sample simulator port, nf-dsp/nf-format moves.
