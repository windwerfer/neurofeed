# AGENTS.md: guide for AI agents and contributors

This crate is an egui/eframe prototype of the NeuroFeed Flutter UI. It is a
standalone Cargo package (it declares its own empty `[workspace]`) and does not
depend on the Flutter app or on `../rust`. Read this file, then `docs/`.

## Orientation

| Read | Why |
|---|---|
| `docs/architecture.md` | Module map, layering, data-source seam |
| `docs/building.md` | Toolchain, desktop and web builds, checks |
| `docs/ui-structure.md` | Panels, views, how to add a view |

## Module map

```text
src/
  main.rs            entry points (the ONLY place with #[cfg(target_arch)])
  lib.rs             module declarations
  app.rs             eframe::App: owns AppState + Box<dyn BandSource>, ticks per frame
  state.rs           AppState, View, Action (no egui)
  data/              EEG types + sources (no egui)
    bands.rs         Band, BandSnapshot
    source.rs        trait BandSource, DeviceInfo  <- real devices plug in here
    mock.rs          MockBandSource (deterministic simulated Muse)
  ui/                egui only; reads &AppState, emits Actions
    theme.rs topbar.rs sidebar.rs
    views/{bands.rs, placeholder.rs}
```

## Rules

1. **Layering:** `data` and `state` never import `egui`/`eframe`. `ui` never
   mutates `AppState`; it pushes `Action`s that `app.rs` applies after drawing.
2. **One codebase:** platform-specific code stays in `main.rs`. Do not add
   `#[cfg(target_arch = "wasm32")]` elsewhere without a strong reason; no
   threads, filesystem or blocking calls in shared code (they break WASM).
3. **Never panic** in non-test code: no `unwrap`/`expect`/indexing on
   untrusted values. No `unsafe` (forbidden in `Cargo.toml`).
4. **Don't translate Dart 1:1.** Use the Flutter app for behaviour and naming
   (view list, channel names), not structure.
5. Before committing: `cargo build`, `cargo test`, `cargo clippy --all-targets`,
   `cargo check --target wasm32-unknown-unknown` all clean.
