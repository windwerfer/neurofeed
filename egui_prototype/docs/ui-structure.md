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
- `apps/neurofeed-egui/src/ui/views/bands.rs`: grid of one card per channel (TP9, AF7, AF8, TP10);
  each card has five colored bars with the value on top. Toggle between
  absolute (log10) and relative (%) scaling. Colors live in `apps/neurofeed-egui/src/ui/theme.rs`.

The UI never mutates state: it returns `nf_core::Command`s that the app runs
through `Session::execute` (same path as MCP).

## Adding a view

1. Add a variant to `View` (+ `ALL`, `label`) in `crates/nf-core/src/state.rs`.
2. Create `apps/neurofeed-egui/src/ui/views/<name>.rs` with `pub fn show(ui, state, actions)`.
3. Route it in `apps/neurofeed-egui/src/ui/views/mod.rs`.
4. New behaviour = new `nf-core` command (see `design-mcp-core.md` §3); it is then reachable via MCP automatically.
