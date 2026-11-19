# Building

Requirements: stable Rust (`rustup default stable`), and for web
`rustup target add wasm32-unknown-unknown` plus `cargo install trunk --locked`.
Linux desktop needs the usual X11/Wayland + OpenGL libraries.

| Task | Command |
|---|---|
| Desktop run | `cargo run --release -p neurofeed-egui` |
| Automation (CLI, JSON lines, MCP stdio) | `cargo run -p neurofeed-cli --bin neurofeed-cli -- [--manual-clock] [--device sim:crown] run status` (or `serve`, `mcp`); see `docs/automation.md` |
| Web dev server | `cd apps/neurofeed-egui && trunk serve --release` → http://127.0.0.1:8080 |
| Web static build | `cd apps/neurofeed-egui && trunk build --release` → `dist/` |
| Tests | `cargo test` |
| Lints | `cargo clippy --all-targets -- -D warnings` and `cargo fmt --all --check` |
| Android APKs (per ABI) | `scripts/build-android.sh` (see [release.md](release.md)) |
| Android quick iteration (arm64 debug) | `scripts/build-android.sh --fast` (not reproducible; see apps/neurofeed-android/README.md) |
| Release packages | `scripts/package-{linux,flatpak,macos}.sh`, `scripts/package-windows.ps1` ([release.md](release.md)) |
| WASM type check | `cargo xtask wasm`: `cargo check --target wasm32-unknown-unknown` for every crate marked wasm in `xtask/src/layers.rs`, then wasm clippy for `neurofeed-egui` (nf-mcp is native only) |
| Layering | `cargo xtask layers`: every crate registered with a layer; no edge to a higher layer; egui/tokio/btleplug/rmcp/candle only in their quarantine crate |
| Everything | `cargo xtask ci` (fmt, clippy, test, layers, wasm, `cargo deny check` if installed) |

Rendering uses eframe's `glow` (OpenGL / WebGL) backend to keep the dependency
tree small. Switch to `wgpu` in `Cargo.toml` if needed.

Headless screenshot on Linux: `xvfb-run -s "-screen 0 1100x700x24" cargo run`
then capture with `import -window root out.png` (ImageMagick).
