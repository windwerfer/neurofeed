# NeuroFeed (Rust)

Rust-only rewrite of NeuroFeed: a headless core (`nf-core`), an MCP server
exposing every command (`nf-mcp`), signal processing (`nf-dsp`), recording
formats NFED6/EDF+ (`nf-format`), deterministic raw-sample device simulators
(`nf-sim`), and an egui/eframe UI for desktop and web (Android later).

Status: Phase 3 + PPG. Functional views: **Bands, Raw EEG, PSD, Spectrogram,
Histogram, HR+SpO2** (simulators `sim:muse_s`, `sim:muse2`, `sim:athena` (no PPG), `sim:crown`;
`sim:muse` is an alias of `sim:muse_s`), plus record/stop and an auto/50/60/off
notch with per-pad quality in the top bar. Everything is also reachable via
MCP (`raw.get`, `psd.get`, `spectrogram.get`, `histogram.get`,
`signal.status`, `features.get`, `hr.get`, `spo2.get`, `ppg.get`, `mains.set`, `recording.*`).
Desktop start view: `NF_VIEW=psd cargo run -p neurofeed-egui`.

```sh
cargo run --release -p neurofeed-egui                 # desktop
cd apps/neurofeed-egui && trunk serve --release       # web, http://127.0.0.1:8080
cargo run -p neurofeed-mcp -- --manual-clock          # MCP over stdio
cargo test && cargo clippy --all-targets -- -D warnings
```

Read [AGENTS.md](AGENTS.md), then [docs/](docs/).
