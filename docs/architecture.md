# Architecture

## Current state (2026-10-29)

Cargo workspace at the repo root: `crates/nf-types` (L0), `crates/nf-sim`
(L1), `crates/nf-core` (L2), `crates/nf-mcp` (L4), `apps/neurofeed-egui`,
`apps/neurofeed-mcp`. Only the Bands view is functional, fed by simulators.
Plan and phases: `design-mcp-core.md`. This section overrides anything below.

```text
 DeviceProvider ─open─▶ BandSource ─poll(t)─▶ Session (nf-core) ◀─ Command/Query ─┬─ egui app (reads &AppState)
   sim:muse / sim:crown / (ble, android)        state, revision, events            └─ nf-mcp (command_run ...)
```

Each egui frame: `session.tick(ctx time)`, draw from `session.state()`,
apply returned `Command`s via `session.execute`. The MCP server does the same
per tool call (wall clock) or only on `clock_advance` (`--manual-clock`).
Layering is checked by `crates/nf-core/tests/layers.rs` until `xtask` exists.
