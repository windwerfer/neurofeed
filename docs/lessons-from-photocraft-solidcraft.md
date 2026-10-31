# Lessons from PhotoCraft and SolidCraft

Status: research note, 2026-10-29. Input to `design-mcp-core.md`, and the
basis for `AGENTS.proposed.md`.

Sources:
- **PhotoCraft**: github.com/storytold/photocraft, a local shallow clone
  at `/workspace/photocraft` (HEAD `5f9b439`). Its git history came from
  the GitHub commit-search API, because the clone is shallow.
- **SolidCraft**: github.com/tangency-labs/solidcraft. Its `AGENTS.md`,
  `skills/*/SKILL.md` and `docs/mcp.md` were read from
  raw.githubusercontent.com. Its git history was **not** mined, because
  cloning, `gh` and `curl` from the box were blocked.

Both projects are large, Rust-only, egui apps built mostly by agents, with
a headless engine, a control channel and an MCP server. They are the
closest public models of what we are building. SolidCraft started from
PhotoCraft's template and is about a generation later, so where the two
differ, SolidCraft usually shows what they learned.

Each section marks what it is based on:
- **[E]** is evidence: what the repos say or do, with a file or commit
  reference.
- **[I]** is our inference or recommendation.

---

## 1. Crate layout and layering

**[E]**
- PhotoCraft has 25 crates in L0–L6 plus apps (`AGENTS.md` §2). For
  example: geom/cms/raster L0, doc L1, ops/paint L2, compose/gpu/format
  L3, io L4, **engine L5 (Session + command registry)**, ui-egui and
  automation (MCP) L6, then the apps photocraft, photocraft-cli and
  photocraft-web.
- `cargo xtask layers` (`xtask/src/layers.rs`) fails the build when a
  lower layer depends on a higher one.
  - Each crate is registered in a TABLE as `Layer(n)`, `Standalone`,
    `Testkit` or `Exempt`.
  - A new crate must be added to it.
  - "Nothing below ui-egui may use egui, eframe, winit or rfd."
- SolidCraft uses the same scheme: L0 `geom` → L1 `sketch/kernel/render`
  → L2 `doc` → L3 `io` → L4 `engine` → L5 `ui-egui`/`mcp` → apps
  (`skills/solidcraft-commands/SKILL.md`). It adds two rules:
  - Only `crates/kernel` may use `truck` (third-party code is quarantined
    to one crate).
  - New `mod` lines go into the existing sorted group (`cargo xtask lists`
    checks sorted lists).
- **Drift between plan and code:**
  - PhotoCraft's `docs/architecture.md` opens with a dated "Current state"
    section that overrides the plan below it.
  - Line 158 says the `viewport`, `tools`, `platform` and `ml` crates were
    planned but never split out. "`viewport` and `tools` live inside
    `ui-egui` and `engine`; `platform` services are function hooks
    injected by each app (`ui_egui::Services`)."
  - The result: ui-egui is about 252k LOC, larger than the engine at
    about 144k.
- PhotoCraft's `docs/architecture.md:83-97` is a "rules we adopt from day
  one" table. It is based on GIMP's history: "fundamental properties were
  baked into the core as assumptions instead of being data", so every
  later feature needed a rewrite. Bit depth, colour model, channel count
  and tiling are therefore runtime data from v1.

**[I] For us:**
- Our layering (`nf-types` L0 → `nf-dsp/nf-sim/nf-format` L1 → `nf-core`
  L2 → `nf-device/nf-store` L3 → `nf-mcp` L4 → apps) matches theirs. Add
  `xtask layers` now, while there are 4 crates. Retrofitting it later is
  harder.
- Our "data, not assumptions" list:
  - channel count and names;
  - sample rate per stream;
  - which streams exist (EEG, PPG, IMU, AUX, optics);
  - electrode montage;
  - units.

  `DeviceInfo` and stream descriptors must carry these. Never assume "4
  EEG channels at 256 Hz". The Flutter app already paid for this: the
  Muse-4 vs Crown-8 split, the Athena AUX/optics special cases, and
  "Athena optical ≠ Classic PPG" in the neurofeed `AGENTS.md`.
- `DeviceKind` as a closed enum (Muse | Neurosity) is fine for
  connection logic. Signal-processing code must work from the stream
  descriptor, not from the kind.
- Keep a dated "Current state" header in `docs/architecture.md`, and
  update it whenever reality diverges from the plan.
- Keep the UI from becoming the place where logic lives. PhotoCraft's
  interactive tools stayed in ui-egui, and that crate ballooned.
  - Our equivalents are the viewport, Follow/Inspect, recording, and the
    calibration state machine.
  - They belong in `nf-core` as commands and state, with egui only
    drawing them.

## 2. "Everything is a command"

**[E]**
- PhotoCraft:
  - The `CommandSpec` in `crates/engine/src/cmd.rs` has `id`, `label`,
    `menu`, `shortcut`, `params: &'static str` (a doc string, not a
    schema), `enabled: fn(&Session) -> Result<(), String>` (the error is
    the disabled reason / tooltip), `run: fn(&mut Session, &Value) ->
    Result<Value>` and journalling.
  - There are about 700 commands.
  - The UI, CLI, control channel and MCP all dispatch by id (`AGENTS.md`
    rule 1).
  - Only pure view/window state (zoom, panels) stays in the shell
    (`UI_COMMANDS`).
- SolidCraft (`skills/solidcraft-commands/SKILL.md`):
  - Ids are dotted and lower-case: `area.verb[.variant]`.
  - **Programmatic calls never open dialogs.** "A dialog is a front-end
    form that builds the parameters."
  - A command that changes the document is **undoable by default**, and a
    failing command leaves the document unchanged.
  - Validate inputs first and return `BadParams`.
  - Every new command needs **input and output schemas** (`checked!`,
    `.contract`, `.output`). `schema/unconverted.txt` "only shrinks". In
    other words, they are retrofitting schemas because the early
    free-text `params` docs were not enough.
- Plan vs reality: PhotoCraft's architecture plan specified `params:
  schemars::Schema` with UI hints. The code shipped a free-text string,
  and SolidCraft is now paying to convert.
- **One rule across all entry points.** PhotoCraft commit `81925d77` fixed
  a preference that only File › Open honoured. Revert, Batch, MCP
  `doc.open` and the CLI all ignored it. The fix moved the rule into the
  shared path.

**[I] For us:**
- Keep the `Command` enum (serde, tagged by `cmd`). That gives typed input
  for free. Derive `schemars::JsonSchema` on every command payload and
  every reply type from day one, so we never need an `unconverted.txt`.
- Add `enabled(&Session) -> Result<(), DisabledReason>` to the command
  metadata. Example: "Record is disabled: a feedback session is running"
  replaces today's HTTP `409 recording_active`.
- **Keep transport out of command names.** Use dotted ids such as
  `device.connect`, `view.set`, `session.start`, `clock.advance` and
  `recording.start`. MCP tool names use underscores (see §3).
- A failing command must leave state unchanged. Settings and
  session-protocol changes should be undoable where it makes sense.
- Every rule that holds "no matter how you got here" goes in `nf-core`,
  never in the egui handler. Examples:
  - disconnect pauses, never ends;
  - Record and Start Session exclude each other;
  - an unsaved session blocks reset.

## 3. MCP tool design

**[E] PhotoCraft (`crates/automation/src/server.rs`,
`server/conventions.rs`, `docs/mcp.md`):**
- Uses rmcp, schemars 1 and tokio.
- **Generic** tools: `command_list`, `command_run` and `command_batch`.
- A **small typed set** for the session and documents: `session_list`,
  `doc_open/new/save/export/inspect/select/close`, `render_preview` and
  `jobs_list/jobs_cancel`.
- Bridge-only UI tools: `ui_inspect`, `ui_screenshot`, `ui_pointer`,
  `ui_menu_invoke`, `ui_set` and `control_call`.
- Tool names use underscores; dotted names belong to commands and the
  control protocol.
- Every tool has a `title` and all four annotation hints (read-only,
  destructive, idempotent, open-world), via the `annotated()` helper.
- Schemas set `additionalProperties: false`, and unknown arguments are
  rejected with JSON-RPC `-32602`.
- Execution failures return a tool result with `isError: true`, so the
  model can read the error and correct itself. A panic in a worker becomes
  a tool error and the session survives.
- Other features:
  - resources `photocraft://document` and `photocraft://commands`;
  - progress via `_meta.progressToken`, throttled to at most 10/s, with
    cancellation;
  - reply-size budgets, and screenshots downscaled before returning.
- Two modes:
  - **headless**: an in-process Session;
  - **bridge**: loopback TCP JSON lines to the running app, with a
    per-launch token.
- File access goes through an `AuthorizedWorkspace` with separate read
  and write roots.

**[E] SolidCraft (`docs/mcp.md`, `skills/solidcraft-agent-tools/SKILL.md`):**
- An explicit rule: **"Anything the user can do is a command; add a
  command, not a new tool, unless the tool is about the session itself
  (open, save, screenshot, batch)."**
- Tools:
  - `list_commands`;
  - `describe_command` (returns the JSON Schema 2020-12 input and output);
  - `execute`, `batch` and `inspect_design`;
  - `measure` and `set_parameter`;
  - `screenshot`, `export`, `undo/redo` and `new_design/open/save`;
  - `pending` and `running` (long requests);
  - `crash_reports`;
  - `skill_reference` (returns bundled agent skills).
- About 20 tools in total, not one per command.
- `batch` **rolls back by default** to an engine checkpoint.
  - The reply names `failed.index`, `applied`, `not_run` and
    `rolled_back`.
  - Steps are pre-validated: an unknown id or a strict schema violation
    fails the batch before anything runs (#5853).
  - Note: PhotoCraft's batch is *not* atomic. SolidCraft improved on this.
- Parameter checking is `--param-check off|warn|strict`.
  - `warn` adds `param_warnings`, such as "unknown key `operaton`; did you
    mean `operation`?".
- Small replies: `verbose: false` gives compact results, and "no
  unfiltered command catalogue or topology dumps". `document.revision`
  lets an agent check "did anything change?" without re-reading
  everything.
- Long work:
  - the app answers "still running" after 60 s;
  - `pending` fetches the result later;
  - a timeout tells "not sent, safe to resend" apart from "may have run:
    inspect first".
- The screenshot reply names its renderer (`gpu`, `gpu-software`, `cpu`
  plus a warning). If a minimised window cannot present a frame, it falls
  back to a model render and says so.
- The bridged server starts even when the app is not running yet. Every
  call then returns an actionable error ("no SolidCraft app is listening
  at HOST:PORT … start it with …").
- Bundled skills are tested: `skills_name_only_real_tools_and_commands`
  fails if a skill mentions a tool or command that no longer exists.
- Files are confined to allowed folders. Paths are resolved before
  comparison, so `..` and symlinks cannot escape, and dotfiles are out of
  reach by default.
- Annotations must be "honest". `execute` and `batch` are marked
  destructive and open-world because some commands write files.

**[I] For us. This is the biggest change to `design-mcp-core.md`:**
- The design and the current `nf-mcp` generate **one MCP tool per
  command** (about 40 tools: `view_set`, `bands_get`, `clock_advance`, …).
  Both reference projects converged on the opposite. Switch to:
  - `command_list`, `command_describe` (input and output schema), and
    `command_run`;
  - `command_batch`, with rollback by default and pre-validated steps;
  - a few typed session tools: `status` (cheap, includes `revision`),
    `bands_get` (high-frequency read), `screenshot`, `clock_advance`
    (sim/manual-clock only), `recording_list/export`, and
    `skill_reference` later.
- Why:
  - The tool list stays small and stable, so client context stays small
    and approval UIs stay sane.
  - Adding a command needs no MCP change, which is the goal we already
    stated.
  - Schemas live in one place (the command), not duplicated in tool
    descriptors.
- Keep the test "every `Command` variant is reachable". Change it to
  "every variant appears in `command_list` with a schema".
- Adopt these conventions verbatim:
  - underscore tool names, dotted command ids;
  - `title` plus all four annotations, honestly set (`command_run` is not
    read-only);
  - `additionalProperties: false`, and `-32602` with the list of valid
    arguments;
  - `isError: true` with an actionable message for domain errors;
  - panic → tool error, and the session stays alive;
  - resources `neurofeed://status` and `neurofeed://commands`;
  - compact replies by default;
  - progress plus cancellation for long jobs (recording export, model
    download, calibration).
- Two modes, as in both references:
  - **headless** (in-process `Session` + simulator, the default for tests
    and agents);
  - **bridge** to the running desktop app over loopback TCP JSON lines
    with a per-launch token file.
- Web: a browser cannot listen on TCP. MCP is native-only, and the web
  build is driven through Chrome DevTools in tests (PhotoCraft
  `docs/development.md`).
- EEG data is privacy-sensitive. Default file access to the app folder
  and scratch, plus explicit `--allow-path`. Raw-data export via MCP
  should be `destructiveHint`/`openWorldHint` honest.

## 4. UI automation and screenshots

**[E]**
- PhotoCraft:
  - UI state is serde data in `ui-egui/src/state.rs` (`AGENTS.md` rule 5),
    so `ui.inspect` and `ui.set` can read and drive it.
  - Control methods include `ui.pointer` (document coordinates),
    `ui.click`, `ui.key`, `ui.type` and `ui.screenshot`, all with strictly
    validated params (`docs/control-protocol.md`).
  - Offscreen rendering:
    `cargo run -p photocraft-ui-egui --example snapshot --script
    calls.json` renders with no window and doesn't steal focus.
  - Rule 6: "Verify UI changes visually … Look at the PNG."
  - Synthetic input to a hidden window needs `RequestPaintWhileHidden`.
- SolidCraft:
  - `ui.start {command}` opens the interactive tool or dialog, while
    `engine.execute` runs headlessly.
  - UI scenarios are JSON files in `crates/ui-egui/tests/scenarios/*.json`
    and are picked up automatically. `{"pending": "why"}` marks a scenario
    that records a not-yet-fixed bug.
  - The token is read from a per-port file. "Never paste the token into a
    PR."

**[I]** Our prototype already keeps `View`/sidebar state outside egui.
Next steps:
- Make all of it serde.
- Expose it through `ui_inspect`/`ui_set` (bridge mode) and a
  `screenshot` tool. Headless mode renders the egui frame offscreen with
  egui_kittest + wgpu.
- Make "attach a screenshot for every visual change" a rule.
- Replace the Flutter debug HTTP agent (`NEUROFEED_AGENT`) with the
  control channel.

## 5. Testing, determinism and simulators

**[E]**
- **panic_hunt** (`crates/engine/tests/panic_hunt.rs`) fuzzes *every*
  registered command with adversarial params (wrong types, huge numbers,
  NaN, empty values), with a per-command deadline of about 4 s. It must
  stay green (PhotoCraft `AGENTS.md` rule 9 and §5).
- Every crash fix includes a regression test that panicked before the fix.
  SolidCraft additionally starts it from the crash report's
  `design.sc` + `replay.json`.
- Snapshot and golden testing:
  - `egui_kittest` with `wgpu`/`snapshot`/`eframe`;
  - goldens via `testkit`;
  - the **CPU compositor is the oracle** for the GPU path;
  - the format crate deliberately **fails to compile** when a doc struct
    gains a field (exhaustive destructuring), so nothing is silently
    dropped from saves (PhotoCraft `AGENTS.md` §8).
- nextest (`.config/nextest.toml`):
  - a `gpu` test group capped at 4 threads;
  - a `ci` profile with fail-fast and a 60 s slow timeout;
  - heavy tests skipped on PRs but run in the merge queue and nightly
    (SolidCraft).
- Corpus tests are opt-in behind a cargo feature, with data fetched at
  pinned SHAs and sha256-verified, and never committed. Sweeps rotate a
  quarter of their cases per day.
- Ratchets that only move one way:
  - parity `FLOOR` "never lower";
  - SolidCraft `unconverted.txt`, help `BACKLOG` and the action matrix
    `--bless`;
  - robustness goldens re-recorded in the same PR with a stated reason
    (`ROBUSTNESS_GOLDENS_BLESS="why"`).
- SolidCraft tests rules (`skills/solidcraft-tests/SKILL.md`):
  - a regression test goes in the area's existing test file, never a file
    named after the bug (#3226);
  - expected values are derived independently, never copied from the
    program's output;
  - a failing test cannot merge without its fix (otherwise
    `#[ignore = "fails until #N"]`);
  - every test runs in its own process: no shared state, **no wall-clock
    timing**;
  - SolidCraft's MCP tests check results **only through MCP**
    (`crates/mcp/src/tests.rs`).
- Mutation testing is used to find behaviour the suites miss (SolidCraft
  `docs/mutation-testing.md`).

**[I] For us:**
- Our simulator plan (seeded, deterministic, replayable, scenario-driven)
  is the EEG equivalent of their oracle and corpus. Concretely:
  - **Oracle tests for DSP.** Use synthetic signals with closed-form
    answers: a 10 Hz sine at amplitude A gives alpha power ≈ A²/2 in the
    right bin; line noise at 50 Hz gives `line_noise_ratio` ≈ x. Never
    "bless" the output of the code under test.
  - **Recorded-session corpus.** Store a few real `.neurofeed` (NFED6)
    files outside git, fetched by pinned hash, and run them through
    `nf-core` in replay mode. Golden JSON stores features and events per
    second, not pixels.
  - **panic_hunt over every `Command`**, including absurd values:
    `clock.advance` of 1e300 s, unknown device ids, empty protocols.
  - **MCP end-to-end tests** run connect sim → calibrate → session →
    record → export only through MCP, with `--manual-clock`.
  - **UI snapshot tests** with egui_kittest for each view in
    deterministic sim state (seed + manual clock), with a small number of
    PNG goldens.
  - Make "no wall clock in tests" mechanical: all time comes from the
    injected `Clock`.
  - A `nf-format` exhaustiveness guard: the encoder destructures every
    `SessionMeta` field, so adding a field without serialising it fails
    to compile.
  - A `ci` nextest profile, and opt-in heavy and corpus features.

## 6. egui patterns and immediate-mode pitfalls

**[E] PhotoCraft `docs/egui-037-migration-plan.md` §3.3 and §8:**
- The logic/ui closures can run **more than once per rendered frame**
  (multi-pass, popup sizing passes, `request_discard`, lines ~287 and
  677). Hidden windows get logic-only ticks with stale input.
- Therefore:
  - every side effect must be idempotent, or drain a queue exactly once,
    guarded by a revision or generation number or a monotonic deadline;
  - "no counters inside popup/window closures that change on a sizing
    pass";
  - use `ctx.cumulative_frame_nr()` for frame delays (line 310), not call
    counting;
  - never use `ctx.input().time` for logic: use a monotonic clock
    (`web_time::Instant` on wasm);
  - **one user action → one command → one history step**; "never a
    command in a sizing pass with no user event" (line 693), with tests
    for forced sizing passes (line 695).
- Performance (`AGENTS.md` rule 8 and `docs/*-performance.md`):
  - never scan full data per frame; cache per document revision (an
    uncached `content_bounds` cost about 77 ms per frame);
  - benchmark in release on realistic sizes, and record before/after in
    the devlog.
- Theming (`docs/ui-design.md`; SolidCraft `skills/solidcraft-ui/SKILL.md`):
  - colours, radii, spacing and typography only from `theme::Tokens`, and
    no literal colours in feature code;
  - SolidCraft also has **one outer container** (`ui_kit::Container` /
    `Panel` / `Window` / `Confirm` / `Menu`), sliders only via
    `ui_kit::slider`, and **one camera/navigation path**
    (`navigation::handle`), with a test that rejects hand-rolled input.
    These are enforced by `cargo xtask ui-containers` with no allowances.
- PhotoCraft pins **forks of egui and winit** (storytold forks by rev)
  for fixes upstream lacks. That buys capability at the cost of
  migrations: a whole doc exists for the 0.37 migration.
- SolidCraft (`skills/solidcraft-performance/SKILL.md`):
  - never block the window: long work runs beside it and is applied when
    done;
  - agent commands longer than ~150 ms are evaluated ahead on a copy;
  - "a person's edit made meanwhile goes first".

**[I] For us:**
- Graphs are our hot path:
  - per-frame work must read prepared buffers (`SweepBuffer`, `BandCache`,
    STFT ring) keyed by a revision;
  - downsample min/max per pixel;
  - never FFT in `ui()`.

  The Flutter app learnt this ("Draw-path perf PRs 1–7"). Port the
  lesson, not the code.
- Slider and drag edits:
  - commit one command on release, not on every tick (we already had the
    `onChangeEnd` rule);
  - previews during the drag are UI-local state.
- One graph/viewport interaction path (Follow/Inspect, zoom, pan) shared
  by all panes. This is the counterpart of `navigation::handle`.
- Theme tokens only. A `ui_kit` for panels, rows and sliders. Add a cheap
  `xtask` grep check (no `Color32::from_rgb` outside `theme.rs`) before
  the UI grows.
- Avoid patching egui unless forced. If we must, pin by rev and write
  down why in `decisions.md`.

## 7. WASM, mobile and CI

**[E]**
- Wasm checks:
  - PhotoCraft: every crate through L6 must `cargo check --target
    wasm32-unknown-unknown` (`cargo xtask wasm`), and filesystem code is
    `cfg(not(wasm))` or goes through `Services`;
  - SolidCraft: "Do not add a dependency that cannot" build for wasm. The
    only JS allowed is the service worker and inline bootstrap
    (`cargo xtask web-offline-test`).
- Web delivery:
  - trunk + wasm-bindgen;
  - a `wasm-release` profile with opt-level z/s per crate;
  - the wasm is split into parts because Cloudflare caps files at 25 MiB
    (`photocraft-web-boot`);
  - file dialogs on web are rfd async plus a Blob download, injected via
    `Services`.
- `cargo xtask ci` is the single local gate. SolidCraft's runs fmt,
  assets, icons, licences, lists, layers, ui-containers, clippy
  `-D warnings`, tests and wasm.
- PhotoCraft CI workflows: ci, docs, freebsd, nix, packaging-lint,
  perf-nightly, release, sonarcloud and windows-arm64.

**[I] For us:**
- `nf-types/nf-dsp/nf-sim/nf-format/nf-core` must be wasm-clean.
  `nf-device` (btleplug, OSC) and `nf-mcp` (tokio) are native-only.
- Web devices come later through a WebBluetooth `DeviceSource` injected
  by the app.
- Android:
  - the thin native wrapper should call `nf-core` through the same
    command/JSON surface (`execute(json) -> json`), not a second FFI API;
  - JNI/btleplug init lives only in the wrapper or app crate;
  - this replaces flutter_rust_bridge codegen.
- Add `cargo xtask ci` now (fmt, clippy `-D warnings`, layers, wasm, test).
  Our prototype `AGENTS.md` lists these checks by hand.

## 8. Process: agent guidelines and docs

**[E]**
- PhotoCraft `AGENTS.md`:
  - 160 lines: an orientation table, workspace map, golden rules (never
    crash outranks features), how to pick work, a "before you finish"
    command list, and parallel-agent rules;
  - "Then append a terse entry to `log/devlog.md` … Sessions can end
    abruptly, so the dev log plus a green tree is how the next agent picks
    up";
  - parallel agents each use their own `CARGO_TARGET_DIR`, put new
    commands in a **new module** rather than growing shared files, and
    write `Cargo.toml` atomically ("one broken manifest breaks everyone's
    build").
- SolidCraft:
  - `AGENTS.md` is a short **router** to `skills/*/SKILL.md`, one per area
    (commands, ui, tests, performance, agent-tools, crash-safety,
    file-formats, preferences, ui-text, ground-rules);
  - each hard rule names the check that enforces it;
  - `cargo xtask skills` verifies that every path, command and skill cited
    in the docs exists;
  - generated docs (`docs/features.md`) are regenerated by `main` after
    merge, not committed by contributors, to avoid merge conflicts.
- Decision log: PhotoCraft `docs/decisions.md` has dated, ADR-style
  entries (only two so far; most rationale lives in architecture.md and
  the devlog).
- **Preferences:**
  - SolidCraft: a changed default keeps the old behaviour behind a
    preference;
  - PhotoCraft's scorecard counts "settings that do nothing" (dead
    preferences) as a regression.

**[I]** See `AGENTS.proposed.md`. Short version:
- a short AGENTS.md router with a few golden rules, each tied to a check;
- skill files per area;
- `log/devlog.md` handoff;
- `docs/decisions.md` for frozen decisions (our `.ai/contracts/` already
  plays this role and is worth keeping);
- `cargo xtask ci` as the gate.

## 9. Things they tried and abandoned (pitfalls)

All are **[E]** commit refs on github.com/storytold/photocraft unless
noted.

| What | Evidence | Lesson [I] |
|---|---|---|
| Optional local ML models for subject matting / object selection, merged then reverted with its Preferences follow-up | `6ab5c077`, `bb39b4a8` (2026-10-25, revert of PR #1199) | Heavy ML features need an opt-in feature gate and their own crate before merging into main. This matches our "AI is optional / gated weights in `.local/`". |
| Raw "develop_half" fused preview and band-by-band raw develop (perf rewrites) reverted | `92f59268` (#9454), `0134d2dc` (#9455). Other branches then needed messy merges: `1e52abfb`, `3e144a38`, `0dcc1777` | Perf rewrites without a benchmark and an equivalence oracle get reverted, and reverts are expensive for parallel branches. Measure first (SolidCraft: "Measure before you claim a speed-up … proof that nothing changed"). |
| GPU "batch resident overlap copies" reverted | `459a25bd` (2026-10-18). Follow-up `40b3bf9b` fixed a doc comment still describing the reverted design | When reverting, sweep comments and docs too. Stale docs mislead the next agent. |
| CMS `.cube` 1D shaper + 3D LUT reverted | `02074c9a` (#9183) | Format/colour features merged before their oracle tests existed. Test against independent references first. |
| "Animation Effects follows the system setting" reverted | `c01dc04b` (#4573) | Changing a default silently breaks users. SolidCraft's rule: a changed default keeps the old behaviour behind a preference. |
| A preference honoured only by File › Open | `81925d77` | Put rules in the shared core path. Every entry point (UI, CLI, MCP, batch, revert) must go through it. |
| Planned `params: schemars::Schema` became a free-text string | PhotoCraft `docs/architecture.md` vs `crates/engine/src/cmd.rs`. SolidCraft `schema/unconverted.txt` ratchet | Typed schemas are cheap on day one and expensive at 700 commands. |
| Planned `tools`/`viewport` crates never split out; interaction logic accumulated in ui-egui (~252k LOC) | `docs/architecture.md:158` | Enforce "thin UI" mechanically, or it erodes. |
| SolidCraft: old `Prompt` dialog element removed for `ui_kit::Confirm`. Hand-rolled camera input now rejected by a test. Kernel (truck) "is being replaced", so kernel perf work is paused | `skills/solidcraft-ui/SKILL.md`, `skills/solidcraft-performance/SKILL.md` | Consolidate duplicate UI primitives early. Quarantine third-party engines to one crate so they can be replaced. For us, that is btleplug/muse-rs in `nf-device` and Candle/REVE in an optional crate. |
| Free-text batch with no rollback (PhotoCraft) became checkpoint rollback with pre-validated steps (SolidCraft, #5853) | PhotoCraft `docs/mcp.md`, SolidCraft `docs/mcp.md` | Make batches atomic from the start. |

Many reverts landed together on 2026-10-25. **[I]** That suggests
high-volume agent PR merging followed by a maintainer clean-up. Ratchets,
benchmarks and an "optional feature" gate are cheaper than reverts.

## 10. Recommended changes to `design-mcp-core.md`

**[I]**, in priority order:

1. **MCP surface.** Replace about 40 generated per-command tools with
   these, plus the conventions in §3:
   - `command_list`, `command_describe`, `command_run` and
     `command_batch` (rollback, pre-validated);
   - about 8 typed tools: `status` with `revision`, `bands_get`,
     `screenshot`, `clock_advance`, `device_list`, `recording_export`,
     `crash_reports`, and later `skill_reference`;
   - in bridge mode, `ui_inspect` and `ui_set`.
2. **Typed command contracts on day one.** Use `schemars` on every
   `Command` payload and reply. `command_describe` returns both schemas.
   `--param-check` is strict by default for new code.
3. **`CommandSpec` metadata**: id (dotted), label, group, shortcut,
   `enabled → DisabledReason`, `undoable`, `read_only`. The UI builds menus
   and tooltips from it.
4. **State changes are atomic.** A failing command changes nothing. Keep a
   `revision` counter on `Session`, and bump it on every state change.
5. **Data, not assumptions.** Stream descriptors (channels, rates, units,
   montage) are runtime data. Nothing below the device layer depends on
   `DeviceKind`.
6. **Thin UI, enforced.** Viewport/Follow/Inspect, recording and the
   calibration state machines live in `nf-core`. Add `xtask` checks:
   layers, no egui below the app, no literal colours outside the theme,
   one viewport-input path.
7. **Never-crash, enforced.**
   - Workspace lints `deny` (not `warn`, as today) for `unwrap_used`,
     `expect_used`, `panic`, `todo`, `unimplemented`, `unreachable` in
     non-test code.
   - `forbid(unsafe_code)`, with the Android/JNI wrapper as the only
     isolated exception.
   - `panic_hunt` over all commands.
   - `catch_unwind` around dispatch in the app and MCP.
8. **Determinism.**
   - `Clock` injected everywhere, and no `Instant::now()` in core.
   - Seeded simulators.
   - Replay of NFED6 recordings as a `DeviceSource`.
   - DSP oracle tests with closed-form answers.
9. **Two MCP modes.** Headless in-process (default) and bridge to the
   running app over loopback TCP with a token file. On web, no MCP, and
   tests use CDP.
10. **Gate and handoff.** `cargo xtask ci`; nextest `ci` profile; opt-in
    heavy/corpus tests; `log/devlog.md`; `docs/decisions.md` (absorb
    `.ai/contracts/`); one `AGENTS.md` router plus skills.
11. **Optional heavy features.** ML (CBraMod/REVE/Candle) lives in its own
    optional crate and cargo feature, and the app works without it.
12. **Open question answered by both repos.** Go all-egui (desktop + web)
    with one Rust codebase. Both projects ship egui on desktop and web and
    have no Flutter/webview layer. PhotoCraft's `AGENTS.md` bans
    Tauri/webview shells outright. For Android, keep a thin native wrapper
    only for what egui/winit cannot do (BLE permissions, foreground
    service, SAF).

## 11. What we could not verify

- SolidCraft git history and reverts. Its `docs/book` long-form pages
  (`dev/commands.md`, `dev/schemas.md`, `dev/testing.md`) were not read.
  The skills summarise them.
- PhotoCraft issue and PR discussions. Only revert commit titles were
  mined.
- The `../craftrules` shared standards (private repo), such as
  `standards/never-crash.md`.
