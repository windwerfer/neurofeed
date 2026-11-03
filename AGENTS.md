# AGENTS.md: guide for AI agents and contributors

NeuroFeed is an EEG neurofeedback app written in **Rust only**:
- `nf-core` is the headless engine. It has no UI and builds for wasm.
- Every feature is reachable through MCP (rmcp).
- The egui/eframe UI is one codebase for desktop and web, with Android
  later.
- Devices are simulated deterministically for tests and agents.
- A thin native Android wrapper comes later.

Repo layout: the Rust workspace is the repo root (`Cargo.toml`, `crates/`,
`apps/`). The Flutter app (`lib/`, `rust/`, `android/`, `pubspec.yaml`, ...)
was removed on 2026-10-31; tag `pre-rust-port` and git history keep it for
reference (`git show pre-rust-port:lib/...`).

Do not add Flutter, Tauri, Electron or a webview UI. Read this file, then
`docs/`.

## Git rules (owner, binding)

- Commit as `Thomas Grok Bot Barth <windwerfer@gmail.com>`.
- Never push to `main`. Push working branches only (HTTPS; SSH is blocked).
- Never open pull requests.
- Do not disturb other people's uncommitted work: use a `git worktree`
  under `/workspace` when the main checkout is dirty.

## 1. Orientation

| Read | Why |
|---|---|
| `docs/architecture.md` | Crate map, layers, the core/UI seam. Its dated "Current state" section overrides the plan below it. |
| `docs/automation.md` | `neurofeed-cli` (run, batch, serve, mcp), MCP client setup, the bridge, tools, workflows |
| `docs/design-mcp-core.md` | Why the command model and automation surface look as they do; simulators |
| `docs/decisions.md` | Dated decisions and frozen contracts. Do not reopen them without a new entry. |
| `docs/building.md` | Toolchain, desktop/web builds, the CI gate |
| `docs/ui-structure.md` | Views, panels, theme, how to add a view |
| `docs/contracts/` | Frozen product contracts carried over from the Flutter app (file format NFED6, pipeline, data plane, feedback disconnect, app folder) |
| `log/devlog.md` | What landed recently and what is still open |

## 2. Workspace map

```text
crates/
  nf-types            L0  ids, units, stream descriptors, DTOs (serde, schemars)
  nf-dsp nf-format nf-sim  L1  filters/FFT/bands; NFEDBIN/NFED6/EDF formats; seeded raw simulators
  nf-feedback         L1  feedback engine math (threshold, adaptation, stability, inhibit, guard); sample-time, no clock
  nf-format           L1  .neurofeed NFED6 container (the only owner of the byte layout)
  nf-core             L2  Session + command registry + event log + Clock (no egui, no tokio, wasm-clean)
  nf-device nf-store  L3  real devices (btleplug, OSC; native) ; history/storage behind traits
  nf-mcp              L4  MCP server over nf-core (native only)
apps/
  neurofeed-egui      desktop + web UI (eframe; trunk for web); control channel on desktop
  neurofeed-cli       automation binary: run, batch, serve (JSON lines), mcp; headless Session or bridge to the app (alias neurofeed-mcp = mcp)
xtask/                cargo xtask ci | layers | wasm   (to add)
```

**Layering is enforced** by `cargo xtask layers` (to add). A crate may
depend only on lower layers, and a new crate must be registered in the
layers table. Nothing below the apps may use egui, eframe, winit, rfd,
tokio or btleplug, except `nf-device` (btleplug) and `nf-mcp` (tokio).
Third-party engines are quarantined to one crate each:
- BLE and OSC live in `nf-device`;
- ML models (Candle, REVE) go in an optional crate behind a cargo
  feature;
- the app must work without them.

## 3. Golden rules

### Never crash (outranks feature work)

A session is someone's hour of recording. A malformed file, a bad command
or MCP param, a BLE disconnect, a corrupt settings file or a full disk
must produce an error the user or agent can act on, never a panic.

- **Non-test code never panics.** No `unwrap`, `expect`, `panic!`,
  `unreachable!`, `todo!` or `unimplemented!`. Return the crate's error
  type and use `?`. Workspace lints `deny` these, and tests are allowed
  them via `clippy.toml`. Every crate has `[lints] workspace = true`.
- **Keep functions small** (SonarCloud-style; PhotoCraft uses the same
  clippy lints). `clippy.toml`: `cognitive-complexity-threshold = 25`,
  `too-many-lines-threshold = 100`, `too-many-arguments-threshold = 7`;
  workspace lints `deny` `cognitive_complexity` and `too_many_arguments`
  and `warn` `too_many_lines` (fatal in CI via `-D warnings`). Split long
  functions into named phases, egui views into sub-panel functions, and
  long test scenarios into helper steps. The only exception is a **flat
  dispatch match** (one short arm per command/query/tool, e.g.
  `Session::apply`, `Session::query`): it may carry
  `#[allow(clippy::too_many_lines)]` with a one-line comment saying so.
  Never allow `cognitive_complexity`.
- **No `unsafe`** (`unsafe_code = "forbid"`). The future Android/JNI
  wrapper is the one isolated exception, and every `unsafe` block there
  needs a `SAFETY:` comment.
- **Input-derived numbers are hostile.** This covers device packets,
  files, command params and sample counts:
  - use `get()` instead of indexing;
  - use `checked_*`/`saturating_*` arithmetic;
  - guard against divide-by-zero and NaN/inf;
  - cap allocations sized by input;
  - never decode an empty buffer **(ours)**.
- **Don't cascade.** Handle lock poisoning
  (`unwrap_or_else(PoisonError::into_inner)`). Thread and task joins are
  `Result`s.
- **Last-resort guard.** The app and the MCP server catch a panic around
  command dispatch, report it, and keep the session.
- **Every write that matters is atomic** **(ours)**: write a temp file,
  then rename it. A recording is recoverable after a crash.
- **Prove it.** Every crash fix includes a regression test that failed
  before the fix. `panic_hunt` (to add) fuzzes every command with
  adversarial params and must stay green.

### Rules

1. **Everything is a command.** New user-visible behaviour is a
   `Command` in `nf-core` and needs:
   - a dotted id (`device.connect`, `session.start`, `view.set`);
   - a label;
   - typed params and a typed reply (serde + schemars);
   - `enabled(&Session) -> Result<(), DisabledReason>`;
   - tests.

   The UI, MCP, CLI, the control channel and the Android wrapper all
   dispatch commands. **Programmatic calls never open dialogs.** A dialog
   is a form that builds a command's params. Only pure view chrome that no
   one else needs (hover, scroll offset, an open combo box) stays in the
   UI.
2. **One rule, every entry point.** A behaviour that must hold however you
   got there belongs in `nf-core`, never in a UI handler. Examples:
   - disconnect pauses and never ends a session;
   - Record and Start Session exclude each other;
   - an unsaved session blocks reset.

   A command that fails leaves the state unchanged.
3. **Data, not assumptions.** Channel count, names and montage, sample
   rates, which streams exist (EEG/PPG/IMU/AUX/optics) and units are all
   runtime data in the stream descriptors. Nothing in DSP, core or UI
   assumes "4 channels at 256 Hz" or switches on the device model.
   **(ours)** Names carry units: `_ms`, `_s`, `_hz`, `_uv`. Timestamps say
   whether they are epoch ms or seconds from the start of the recording.
4. **The UI is thin and data-driven.** UI state is serde data in the app's
   state module, so `ui_inspect` can read it and commands can drive it. Views
   read `&Session` state and emit commands; they never mutate the core
   directly. State machines live in `nf-core`, including Follow/Inspect,
   recording, calibration and feedback phases.
5. **Theme tokens and the UI kit only.** Colours, spacing, radii and type
   come from `theme::Tokens`, with no literal colours outside `theme.rs`.
   Panels, rows, sliders and confirmations use the shared kit components.
   **(ours)** Don't fork a shared widget: one music-settings panel, one
   model selector, one connect overlay. Graphs share one viewport and
   input path.
6. **Verify UI changes visually.** Render offscreen (egui_kittest
   snapshot) or run the app with its control channel and take a
   screenshot. Look at the PNG and attach it to the PR. **(ours)** When
   you change on-screen names, update the UI name map
   (`docs/ui-map.md`) in the same change.
7. **Never break wasm.** Everything below the apps must pass
   `cargo check --target wasm32-unknown-unknown` (`cargo xtask wasm`).
   Filesystem, threads, BLE and tokio go through injected traits
   (`DeviceSource`, `HistoryStore`, `Clock`, platform services), never
   through `cfg` scattered in shared code. Do not add a dependency that
   cannot build for wasm below the apps.
8. **Time is injected.** Core logic reads time only from `Clock`:
   - no `Instant::now()`/`SystemTime::now()` in `nf-core`, `nf-dsp` or
     `nf-sim`;
   - never `ctx.input().time` for logic;
   - in egui, count frames with `ctx.cumulative_frame_nr()`;
   - tests use a manual clock and never depend on wall-clock timing.
9. **Performance is a feature.**
   - Never scan or FFT full buffers in `ui()`. Read prepared ring buffers
     and caches keyed by a revision, and downsample min/max per pixel.
   - Long work (export, model load, file load) runs beside the UI thread
     and is applied when done.
   - Measure before you claim a speed-up: release build, medians with
     range, before/after in the devlog, and proof that the output did not
     change.
   - No perf rewrite lands without a benchmark and an equivalence test.
10. **Frozen means frozen.** `docs/decisions.md` and `docs/contracts/` are
    law **(ours)**. The file format NFED6, the feedback pipeline Key
    Decisions, the data plane and feedback-disconnect are examples.
    - Change them only with a new dated decision entry that says why.
    - Use the vocabulary they define; do not invent synonyms.
    - A changed default keeps the old behaviour behind a preference.
    - A preference that does nothing is a bug.
11. **Clean dependencies and secrets.**
    - Check `Cargo.toml` before using a crate **(ours)**.
    - Pin git dependencies and forks by tag or rev.
    - Never commit secrets, tokens, gated model weights (`.local/`) or
      recorded EEG of real people **(ours)**.
    - Test corpora are fetched by pinned hash and never committed.
12. **Don't translate Dart 1:1** **(ours)**. Use the Flutter app (tag `pre-rust-port`) for
    behaviour and naming, not for structure.

### Adding a dependency

- Justify it: std or a crate already in the tree is not enough.
- Prefer the maintained, widely used option with minimal features (`default-features = false` plus what you need), at the latest compatible version.
- Check the license (Apache-2.0 compatible, see `deny.toml`) and RustSec advisories.
- Pin git deps to a `rev`, and add the repo to `[sources] allow-git` in `deny.toml`.
- Run `cargo deny check` before committing (it is part of the gates).

## 4. MCP, CLI and the control channel

Usage and client setup: `docs/automation.md`.

- **Add a command, not a tool.** Tools are:
  - the generic `command_list`, `command_describe` (metadata and the input
    JSON Schema), `command_run` and `command_batch`;
  - a few session tools: `status` (includes `revision`), `bands_get`,
    `clock_advance`, `device_list`, `recording_export`;
  - in bridge mode only, `screenshot` and `ui_inspect`.

  A new tool needs a reason that is about the session itself. Every path
  (`neurofeed-cli run|batch|serve|mcp`, the bridge) goes through
  `NfMcp::call`. Do not add a second dispatcher.
- Tool names use underscores; command ids are dotted.
- Every tool has a `title` and honest annotations (read-only,
  destructive, idempotent, open-world).
- Arguments are `additionalProperties: false`. An unknown tool or argument
  gets `-32602`. Domain failures (including a bad command id or bad params)
  are `isError: true` with an actionable message.
- `command_batch` pre-validates every step and rolls back on failure. The
  reply names the failing step and lists what was applied and what was
  not run.
- Keep replies small (no unfiltered dumps).
- Two modes:
  - **headless**: an in-process Session plus a simulator, the default for
    tests;
  - **bridge**: loopback TCP JSON lines to the running app, with a
    per-launch token read from a file.

  Never paste the token anywhere. There is no control channel on web or
  Android.
- Not implemented yet (do not document them as existing): output schemas,
  a widget-setting tool (ui_set), a path allow-list for `path` arguments, progress and cancel for
  long jobs.
- Keep `docs/automation.md` and any bundled agent skills in step with the
  commands. `apps/neurofeed-cli/tests/cli.rs` fails when one of those docs
  names a tool or command that does not exist.

## 5. egui pitfalls

- `ui()` and logic may run several times per rendered frame (multi-pass,
  sizing passes, `request_discard`). Hidden windows get ticks with stale
  input. Therefore:
  - every side effect is idempotent, or drains a queue once, guarded by a
    revision;
  - no counters in closures;
  - a sizing pass never emits a command.
- **One user action → one command → one history step.** Sliders and drags
  preview locally and commit on release **(ours)**. Never store a raw
  slider position; store the value it maps to.
- Hidden views do no work **(ours)**: they are not drawn and they compute
  nothing. Data buffers keep filling in the core regardless of which view
  is shown.

## 6. Tests

- Every change comes with tests. A failing test without its fix does not
  merge; otherwise mark it `#[ignore = "fails until #N"]`.
- Regression tests go into the area's existing test file, never a file
  named after the bug.
- DSP and feature tests use **oracles**: synthetic signals with
  closed-form answers. Never set an expected value by copying the code's
  output.
- Simulators are seeded and deterministic. NFED6 recordings replay as a
  `DeviceSource`. Golden outputs are per-second features and events
  (JSON); there are a few UI PNG goldens via egui_kittest.
- MCP end-to-end tests drive simulator → calibrate → session → record →
  export **only through MCP**, with a manual clock.
- **(ours)** The `nf-format` encoder destructures every field, so a new
  field that is not serialised fails to compile. Format changes ship with
  round-trip tests and the human spec update in the same change.
- Heavy or corpus tests are opt-in (cargo feature or nextest group) and
  run in CI.

## 7. Before you finish a task

```sh
cargo xtask ci        # (to add) = all of the below
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace            # or: cargo nextest run --profile ci
cargo xtask layers                # (to add)
cargo xtask wasm                  # (to add) = cargo check --target wasm32-unknown-unknown for L0–L2 and the web app
```

If you added or changed commands, also run `panic_hunt` (to add). If you
touched a hot path, add a benchmark and put the numbers in the devlog. If
you changed UI, add a screenshot.

Then append a terse entry to `log/devlog.md`: what landed, numbers, and
what is still open. Sessions end abruptly, so a green tree plus the devlog
is how the next agent picks up. Keep the tree building at every step.

## 8. Parallel agents

- Use your own `CARGO_TARGET_DIR=target/agent-<name>`, and edit only the
  files you own.
- Re-read shared files (the command registry, `lib.rs`, the UI state
  module) before making small, surgical edits.
- Put new commands in a new module (`nf-core/src/cmds/<area>.rs`) rather
  than growing a shared file.
- If someone else's in-progress edit breaks the build, wait and retry.
  Don't fix their files.
- Keep every `Cargo.toml` valid at all times, because one broken manifest
  breaks everyone's build. Write manifests atomically: write a temp file,
  then `mv` it.
- When you revert something, also remove the comments and docs that
  describe the reverted design.

## 9. Docs

- `docs/architecture.md` starts with a dated "Current state" section.
- Decisions go in `docs/decisions.md`, one dated entry each.
- Generated docs are produced by `xtask`, never hand-edited.
- When this file grows past one screen per topic, split topics into
  `skills/<area>/SKILL.md` and keep this file as a router. Every rule
  should name the check that enforces it.

---

## Appendix: our previous rules that were dropped, and why

Sources: `/workspace/neurofeed/AGENTS.md`, `.ai/README.md`,
`.grok/skills/neurofeed-*`, and the prototype's `AGENTS.md`. The rules we
kept are marked **(ours)** above.

| Dropped rule | Why |
|---|---|
| "NEVER add code comments unless explicitly asked" | Conflicts with both references, which keep crate/module doc comments and fix stale ones (PhotoCraft `40b3bf9b`). Replaced by: keep comments true, and remove stale ones with a revert. |
| Flutter / Dart / flutter_rust_bridge rules: version pins, FRB codegen and committed generated bindings, `flutter analyze`, `flutter test` loader traps, `cargo check --target aarch64-linux-android` is unreliable | No Flutter or FRB in the pure-Rust app. `clippy -D warnings` replaces `flutter analyze`. The Android wrapper calls the same command JSON surface instead of a generated FFI. |
| Flutter widget traps (no `LayoutBuilder` in dialogs, `DecoratedBox` around a `ListTile`, directory assets, `IndexedStack`) | Toolkit-specific. The egui equivalents are in §5. |
| Product UI freezes in AGENTS.md (no Spectrogram `FFT 1s ▾`, no Bands `SMOOTH`/`REAL TIME` chrome, 1 s Bands Follow lead, trust-graph wash rules, Settings card list, connect-dropdown details) | These are product specs, not agent guidelines. Their AGENTS.md files stay generic and route to docs. Move them to `docs/contracts/` or the per-view specs, which Rule 10 makes binding. |
| Audio engine rules (SoLoud init/deinit, `setMuffle` placement, Android latency profile) | The implementation is Flutter/SoLoud-specific. The product decision (don't duck unmodulated background) moves to the audio contract doc. |
| Android/macOS/Windows/Flatpak packaging notes, glibc/ALSA container notes, release-tag versioning | Packaging is not a code rule here yet. Move to `docs/release.md` when the Rust app ships. |
| btleplug `[patch]` version trap, `jni` version match, JNI init order, QueueStream race, Muse presets (`p50`), Athena optics mapping | Still true, but device-crate knowledge. Move to `crates/nf-device/README.md` (or a `skills/devices` file) when `nf-device` lands. The AGENTS.md golden rules stay generic, as in their files. |
| "Debug HTTP agent (`NEUROFEED_AGENT`) for Linux driving" | Replaced by the control channel + MCP bridge (§4), which both references use. |
| "Simulator only in Debug mode"; "`DeviceKind` is Muse \| Neurosity only; do not restore Simulated*" | The new design makes simulators first-class `DeviceSource`s for tests, agents and demos. Whether they are visible in release UI is a product setting, not an agent rule. |
| "Simulator must not emit derived Bands/Pulse/SpO₂" (as a separate rule) | Covered by Rule 2: simulators emit raw device events only, and derived data comes from the same pipeline as real devices. |
| Specific numbers (75 s epoch window, 45 clean frames, 30 s silence → Disconnected, 60 s recalibrate) | Product constants. They belong in typed config/constants in `nf-core` plus the pipeline contract, and are tested there. Wall-clock dependence is replaced by the injected `Clock` (Rule 8). |
| Long "Project layout / Where things live" file maps of the Dart tree | They describe the old app. The workspace map in §2 replaces them, and crate READMEs hold details, as in PhotoCraft. |
| Prototype: "platform-specific code only in `main.rs`; no threads/filesystem in shared code" | Refined, not dropped. Platform capabilities are injected traits and services (Rule 7), as PhotoCraft's `Services` does. `cfg(target_arch)` stays in apps. |
| `.ai/active-task.md` as the single "current work" file | Replaced by `log/devlog.md` (append-only, survives parallel agents), as in PhotoCraft. |
