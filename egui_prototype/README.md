# NeuroFeed egui prototype

A clean-room [egui](https://github.com/emilk/egui)/eframe prototype of the
NeuroFeed UI: left sidebar, top bar, and a main view area. One codebase runs
as a native desktop app and in the browser (WebAssembly via trunk).

Status: **prototype**. Only the **Bands** view is functional and it shows
simulated EEG band powers. Every other sidebar item shows "Not implemented yet".

## Run

```sh
# desktop
cargo run --release

# web (needs: rustup target add wasm32-unknown-unknown; cargo install trunk --locked)
trunk serve --release      # open http://127.0.0.1:8080
trunk build --release      # static files in dist/
```

## Check

```sh
cargo build
cargo test
cargo clippy --all-targets
cargo check --target wasm32-unknown-unknown
```

See [AGENTS.md](AGENTS.md) and [docs/](docs/) for structure and conventions.
