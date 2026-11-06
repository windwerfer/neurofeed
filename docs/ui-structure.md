# UI structure

```text
┌──────────────────────────────────────────────┐
│ topbar: ☰  NeuroFeed | ● device  N ch   Pause │
├───────────┬──────────────────────────────────┤
│ sidebar   │ central panel: views::show()     │
│ Feedback  │   Bands  → views/bands.rs        │
│ History   │   others → views/placeholder.rs  │
│ Bands  ◀  │                                  │
│ ...       │                                  │
│ ───────── │                                  │
│ Settings  │                                  │
└───────────┴──────────────────────────────────┘
```

- `apps/neurofeed-egui/src/ui/topbar.rs`: `TopBottomPanel`; ☰ toggles the sidebar, Pause freezes data.
- `apps/neurofeed-egui/src/ui/sidebar.rs`: `SidePanel` listing `View::ALL` (same order as the Flutter app).
- `apps/neurofeed-egui/src/ui/views/bands.rs`: Bands monitor (legacy layout). One full-bleed
  time series of band power averaged over the chosen electrodes, a floating band legend
  (tap hides a band), and the monitor toolbar: Follow | Inspect, window, dB | %, electrode
  chips, and `…` → per-electrode bars. Colors live in `apps/neurofeed-egui/src/ui/theme.rs`.
- `apps/neurofeed-egui/src/ui/monitor.rs`: shared monitor chrome and plot input for every
  live graph: the single toolbar row, gestures → `monitor.*` commands (drag pan, pinch /
  Ctrl+wheel zoom at the pointer, wheel pan, double-click Follow), and `m:ss` time grid.
  The viewport state machine is `nf_core::monitor`.
- Layouts (`ui/layout.rs`): Regular (sidebar), Compact (☰ drawer, `sidebar::drawer`), and
  Immersive (phone landscape, monitor screens show the graph only). See
  `.ai/contracts/ui-layout.md`.

The UI never mutates state: it returns `nf_core::Command`s that the app runs
through `Session::execute` (same path as MCP).

## Adding a view

1. Add a variant to `View` (+ `ALL`, `label`) in `crates/nf-core/src/state.rs`.
2. Create `apps/neurofeed-egui/src/ui/views/<name>.rs` with `pub fn show(ui, state, actions)`.
3. Route it in `apps/neurofeed-egui/src/ui/views/mod.rs`.
4. New behaviour = new `nf-core` command (see `design-mcp-core.md` §3); it is then reachable via MCP automatically.
