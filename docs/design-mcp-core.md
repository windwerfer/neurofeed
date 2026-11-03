# Design: NeuroFeed Rust core + MCP + simulators

Status: implemented; progress is in `log/devlog.md`. Revised after
`lessons-from-photocraft-solidcraft.md`. Modeled on PhotoCraft (`crates/engine` =
Session + command registry, `crates/automation` = rmcp MCP server with a
headless mode and a bridge mode to the running app, `apps/*` thin shells).

## 1. Why a Rust core

The Flutter app had its platform parts (BLE, DSP, file format, simulator) in
Rust but its application logic (feedback engine, monitor state, history) in
Dart, with a small JSON TCP agent server on the side. Flutter was dropped
(decision 2026-10-29). The logic now lives in `nf-core`, which has no tokio, threads or
fs, so the same Session runs in the egui desktop app, the web build, the
Android library and the headless automation binary. That is what makes one
command registry, and one set of tests, cover every shell.

## 2. Crate layout

The main crates (full map: `docs/architecture.md`).

```text
crates/
  nf-types     L0  ids, units, stream descriptors, DTOs (serde + schemars)       [done: bands, DeviceInfo, traits]
  nf-dsp       L1  biquads/EegFilter, FFT, PSD, band powers, line-noise ratio     [done]
  nf-sim       L1  deterministic seeded raw 256 Hz simulators (Muse 4ch, Crown 8ch) [done]
  nf-format    L1  NFEDBIN records/body, NFED6 container, EDF+ (ruzstd, wasm-ok)  [done phase 2]
  nf-core      L2  Session + command registry + event log; no egui/tokio; wasm     [done]
  nf-device    L3  btleplug Muse, Crown OSC (native); DeviceProvider impls          [done]
  nf-store     L3  history behind HistoryStore trait (SQLite native)               [done]
  nf-mcp       L4  NfMcp dispatcher + rmcp server, headless and bridge; native only  [done]
apps/
  neurofeed-egui   desktop + web (trunk)                                          [done]
  neurofeed-cli    run/batch/serve/mcp over a headless Session or the app bridge  [done]
  neurofeed-android  Android cdylib + Gradle shell (section 7)                     [done]
(CI gate: scripts and .github/workflows; layers is a test in nf-core)
```
Lints: `unsafe_code = forbid`; `unwrap/expect/panic/todo/unimplemented/unreachable = deny`
(tests allowed via `clippy.toml`). Only the Android JNI glue may use `unsafe`.

## 3. Core API (nf-core, implemented)

```rust
impl Session {
    pub fn new() -> Self;                                     // simulators registered, nothing connected
    pub fn register_provider(&mut self, p: Box<dyn DeviceProvider>); // BLE, Android transport, replay
    pub fn tick(&mut self, now: f64);                          // injected time; core never reads a clock
    pub fn execute(&mut self, cmd: Command) -> Result<Reply, CoreError>; // enabled check, atomic, bumps revision
    pub fn query(&self, q: &Query) -> Result<Reply, CoreError>;
    pub fn call(&mut self, id: &str, params: Value) -> Result<Reply, CoreError>; // parse + run (strict params)
    pub fn batch(&mut self, steps: &[(String, Value)]) -> Result<Reply, CoreError>; // pre-validated, rollback
    pub fn enabled(&self, id: &str) -> Result<(), String>;     // Err = disabled reason
    pub fn commands() -> &'static [CommandSpec];               // id, label, group, read_only, description, enabled
    pub fn drain_events(&mut self) -> Vec<Event>;
    pub fn state(&self) -> &AppState;                          // includes `revision`
}
pub fn input_schema(id: &str) -> Option<Value>;               // schemars, JSON Schema 2020-12, additionalProperties:false
```
- `Command`/`Query` are serde enums tagged by `cmd`, with dotted ids
  (`view.set`, `device.connect`, `clock.advance`, ...). Typed payloads; the
  schema is derived, never hand-written.
- Failing commands leave state unchanged (validate/open first, mutate last).
- `revision` bumps on every successful state-changing command (not on
  `clock.advance` / data ticks), so agents can ask "did anything change?".
- Batch rollback restores state; a device whose source moved on is reopened
  fresh (sources are not cloneable). Documented limitation.
- Next: output schemas (`schemars` on reply types), `undoable` flag, label/
  shortcut for UI menus, `catch_unwind` in the app shell too.

The live catalog is `command_list` (or `neurofeed-cli list`); it is not
repeated here.

## 4. Automation surface (generic + typed, not one tool per command)

Usage, tool table, client configs and verified examples: [automation.md](automation.md).
This section is only the why.

- "Add a command, not a tool, unless the tool is about the session itself."
  Tools are the four generic ones (`command_list`, `command_describe`,
  `command_run`, `command_batch`), a few session shortcuts, and bridge-only
  `screenshot` / `ui_inspect`. A new feature is a command and automatically
  reaches the UI, the CLI, JSON lines and MCP.
- One dispatcher (`NfMcp::call`) serves MCP, `neurofeed-cli run|batch|serve`
  and the bridge. The bridge forwards tool calls to the app, which runs the
  same dispatch on its UI thread, so headless and live behave the same.
- Errors split by who is wrong: a malformed *tool call* (unknown tool or
  argument) is a protocol error (-32602); a *command* that fails is an
  `isError` result the model can read and act on, with state unchanged.
- Time is injected (`--manual-clock` + `clock_advance`, or the wall clock),
  so agent tests are deterministic.
- Bridge: loopback TCP, a per-launch random token in a 0600 file, off by
  default. No MCP on web or Android.
- Not done yet: output schemas in `command_describe`, a file allow-list for
  `path` arguments (today `recording_export` / `screenshot` write wherever
  the caller points), a widget-setting tool (ui_set), resources, progress/cancel for long jobs.

## 5. Simulator design (nf-sim)

- Implements `DeviceSource` (raw `EegPacket`s, 12 samples at 256 Hz, µV),
  opened through a `DeviceProvider` (`sim:muse_s`, `sim:muse2`, `sim:athena`, `sim:crown`), exactly like
  real devices. Core conditions (nf-dsp `EegFilter`: 0.5 Hz HP + 50/60 Hz
  notches) and computes bands every 0.1 s over a 1 s window.
- Done (phase 2): 10 Hz alpha with slow swell (edge pads full, inner 55 %),
  1/f background (sines every 1.5 Hz, `6/sqrt(f)` µV), seeded noise,
  optional mains hum and DC offset;
  `sim.configure {seed, alpha_uv, noise_uv, mains_uv, mains_hz, dc_uv}`.
- Faults are timed and scripted through commands, not simulator flags:
  `sim.fault.add {kind: disconnect|movement|blink|clench|noise|spikes|glitch|out_of_range}`,
  so tests drive artifacts the same way an agent would. Open: a `Replay`
  source for NFED6 recordings.
- Data, not assumptions: channels, rates, streams, montage, units come from
  the descriptor; nothing below the device layer branches on `DeviceKind`.

## 6. Migration

Phases 0-6 (core, DSP/format/sim, monitor state, feedback engine, history,
devices + bridge) have landed; the Dart code is gone. Progress and open items
are in `log/devlog.md`, not here.

## 7. Android wrapper

- The egui app builds as a `cdylib` for Android (eframe/winit
  `android-activity`, `NativeActivity` or `GameActivity`). Same Rust core,
  same views.
- A minimal Kotlin/Java shell does only what Rust cannot do comfortably:
  runtime permissions (BLE, location, notifications), optionally the BLE
  scan/GATT transport, a foreground service for long sessions, and the
  Storage Access Framework for exports.
- Seam: the wrapper implements `DeviceProvider`/`BandSource` (later a raw
  `DeviceSource`) through a small JNI bridge that pushes packets into a
  queue that `poll` drains. Alternatively btleplug's Android backend inside
  nf-device; the trait lets us pick per platform without touching core.
- Control from the wrapper uses the same command JSON (`Session::call`),
  no second FFI API, no codegen.
- `unsafe` is allowed only in the JNI glue crate, every block with `SAFETY:`.

## 8. Open questions

- Web BLE (WebBluetooth `DeviceProvider`)? Not needed for phase 1-6.
- MCP over loopback HTTP in addition to stdio? (bridge mode uses TCP anyway)
