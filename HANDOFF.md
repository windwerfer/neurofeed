# HANDOFF: Feedback layer stack (stage 1b: music settings + volumes)

**Branch:** `feedback-stack`. **Commit:** see `git log -1`.

## Goal
Per-layer music settings in the tile, a speaker Volume dialog on the setup screen, per-layer volume only when a group has several layers; all over MCP/CLI. UI + state only, engine not wired.

## Done
- `nf-core/layers.rs`: `MusicSettings`, patch fields `music_*`, `shows_volume`, push/pull map first feedback layer's music onto `AudioSettings`/`music_dir`; layer volume is relative in-group (default 1).
- `nf-core/audio.rs`: `volume.set` / `volume.get`; `AudioSettings` + `intro_volume`, `end_bell_volume` (serde default).
- `nf-audio`: `Background::Music` (mixer silent).
- UI: `views/layer_music.rs` (folder, track count, two-handle log cutoff slider, invert, shuffle), `views/volume_dialog.rs` (🔊 + dialog, 6 sliders, Reset, Done), wired in `feedback_setup.rs`; en/de strings.
- Tests: nf-core unit (music, rule, mapping), nf-mcp `protocols.rs` (music, slider rule, volume persistence), app layout tests.

## Decisions
`docs/decisions.md` 2026-11-23.

## Open questions
- Add `rfd` for a real folder dialog (new dependency)?
- Intro / End bell volumes are stored only: no intro/end sounds exist in the mixer yet.
- No `docs/ui-map.md` exists, so no name map was updated. No screenshots (no display).

## Verify
```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets --exclude neurofeed-egui -- -D warnings
cargo clippy -p neurofeed-egui --no-default-features --all-targets -- -D warnings -A dead_code
cargo test --workspace --exclude neurofeed-egui
RUSTFLAGS="-A dead_code" cargo test -p neurofeed-egui --no-default-features
cargo xtask layers   # ok; `cargo xtask wasm` needs `rustup target add wasm32-unknown-unknown` (not installed here, CI runs it)
```

## Next step (stage 2)
Render extra layers and per-layer volume / shuffle / background music in `nf_audio::Mixer`; intro and end-bell sounds; screenshots via the bridge.
