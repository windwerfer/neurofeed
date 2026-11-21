# HANDOFF: Feedback layer stack (stage 1)

**Branch:** `feedback-stack` (from origin/main). **Commit:** see `git log -1` (SHA in the final message).

## Goal
Feedback start screen as a responsive protocol tile grid with a Recent row; one generic setup screen showing the session as a layer stack (Background → Feedback → Guardrail, auto-sorted, only present layers, "+" to add, removable, several feedback / guardrail layers, per-layer settings). A protocol only seeds the stack. Everything reachable over MCP / CLI.

## Done
- `crates/nf-core/src/layers.rs` (data model, seeding, push/pull mapping, recents, unit tests), `session/layers_glue.rs` (commands, queries).
- Commands: `layers.list`, `layers.add {kind, settings?}`, `layers.remove {id}`, `layers.set {id, settings}`, `layers.reset`, `protocol.recent`, `feedback.setup {open}`.
- Recents persisted in the settings doc; touched when a session starts.
- UI: `ui/views/feedback_setup.rs` (tiles, Recent, setup screen), wired in `feedback.rs`; en/de strings.
- Tests: nf-core unit, nf-mcp `tests/protocols.rs`, app layout tests in `feedback.rs`.

## Decisions
See `docs/decisions.md` "2026-11-21 Feedback layer stack" (incl. rejected alternatives).

## Open questions
- Is a protocol *started* the right meaning of "used" for Recent (we chose start, not open)?
- Should layer edits be remembered per protocol? (now: no, session only, not persisted)

## Not done / next step (stage 2)
- The engine plays only the first layer of each kind; render extra layers in `nf_audio::Mixer`.
- Per-layer threshold / hold ("8 s in zone"), per-layer binaural preset for Background, music folder per layer.
- Flutter sub-tile dialogs (choose sound, guardrail scorer settings); screenshots of the new screens are NOT taken (no display on the box): do it with the bridge `screenshot` and attach.
- `docs/automation.md` has no per-command list; nothing to update there yet.

## Verify
```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets --exclude neurofeed-egui -- -D warnings
cargo clippy -p neurofeed-egui --no-default-features --all-targets -- -D warnings -A dead_code   # box lacks libasound; the allow is for a pre-existing native-audio-only fn
cargo test --workspace --exclude neurofeed-egui
RUSTFLAGS="-A dead_code" cargo test -p neurofeed-egui --no-default-features
cargo xtask layers && cargo xtask wasm
```
