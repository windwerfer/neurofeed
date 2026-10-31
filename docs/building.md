# Building

Requirements: stable Rust (`rustup default stable`), and for web
`rustup target add wasm32-unknown-unknown` plus `cargo install trunk --locked`.
Linux desktop needs the usual X11/Wayland + OpenGL libraries.

| Task | Command |
|---|---|
| Desktop run | `cargo run --release -p neurofeed-egui` |
| MCP server (stdio) | `cargo run -p neurofeed-mcp -- [--manual-clock] [--device sim:crown]` |
| Web dev server | `cd apps/neurofeed-egui && trunk serve --release` → http://127.0.0.1:8080 |
| Web static build | `cd apps/neurofeed-egui && trunk build --release` → `dist/` |
| Tests | `cargo test` |
| Lints | `cargo clippy --all-targets -- -D warnings` and `cargo fmt --all --check` |
| WASM type check | `cargo check -p neurofeed-egui --target wasm32-unknown-unknown` (nf-mcp is native only) |

Rendering uses eframe's `glow` (OpenGL / WebGL) backend to keep the dependency
tree small. Switch to `wgpu` in `Cargo.toml` if needed.

Headless screenshot on Linux: `xvfb-run -s "-screen 0 1100x700x24" cargo run`
then capture with `import -window root out.png` (ImageMagick).
