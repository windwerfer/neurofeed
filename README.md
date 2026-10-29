# NeuroFeed (Rust)

Rust-only rewrite of NeuroFeed: a headless core (`nf-core`), an MCP server
exposing every command (`nf-mcp`), deterministic device simulators
(`nf-sim`), and an egui/eframe UI for desktop and web (Android later).

Status: Phase 1. Only the **Bands** view is functional (simulated Muse/Crown).

```sh
cargo run --release -p neurofeed-egui                 # desktop
cd apps/neurofeed-egui && trunk serve --release       # web, http://127.0.0.1:8080
cargo run -p neurofeed-mcp -- --manual-clock          # MCP over stdio
cargo test && cargo clippy --all-targets -- -D warnings
```

Read [AGENTS.md](AGENTS.md), then [docs/](docs/).
