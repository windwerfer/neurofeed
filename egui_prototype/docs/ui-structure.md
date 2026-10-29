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

- `ui/topbar.rs`: `TopBottomPanel`; ☰ toggles the sidebar, Pause freezes data.
- `ui/sidebar.rs`: `SidePanel` listing `View::ALL` (same order as the Flutter app).
- `ui/views/bands.rs`: grid of one card per channel (TP9, AF7, AF8, TP10);
  each card has five colored bars with the value on top. Toggle between
  absolute (log10) and relative (%) scaling. Colors live in `ui/theme.rs`.

## Adding a view

1. Add a variant to `View` (+ `ALL`, `label`) in `state.rs`.
2. Create `ui/views/<name>.rs` with `pub fn show(ui, state, actions)`.
3. Route it in `ui/views/mod.rs`.
4. If it needs new state, add fields + `Action` variants in `state.rs`.
