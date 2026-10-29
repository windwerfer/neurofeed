# Architecture

## Current state (2026-10-29)

Cargo workspace at the repo root: `crates/nf-types` (L0), `crates/nf-dsp`,
`crates/nf-format`, `crates/nf-sim` (L1), `crates/nf-core` (L2),
`crates/nf-mcp` (L4), `apps/neurofeed-egui`, `apps/neurofeed-mcp`. Only the
Bands view is functional, fed by raw-sample simulators through nf-dsp.
Plan and phases: `design-mcp-core.md`. This section overrides anything below.

```text
 DeviceProvider ─open─▶ DeviceSource ─poll(t)─▶ EegPacket (µV, 256 Hz)
   sim:muse / sim:crown / (ble, android)              │
                                                      ▼
 Session (nf-core): Recorder (nf-format body) ◀─┬─ Signal: EegFilter → 10 s buffers → band_powers every 0.1 s (nf-dsp)
   state, revision, events ◀─ Command/Query ─┬─ egui app (reads &AppState)
                                             └─ nf-mcp (command_run ...)
```

Each egui frame: `session.tick(ctx time)`, draw from `session.state()`,
apply returned `Command`s via `session.execute`. The MCP server does the same
per tool call (wall clock) or only on `clock_advance` (`--manual-clock`).
Layering is checked by `crates/nf-core/tests/layers.rs` until `xtask` exists.
