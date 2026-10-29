# Design: NeuroFeed Rust core + MCP + simulators

Status: Phase 1 implemented (2026-10-29), see `log/devlog.md`. Revised after
`lessons-from-photocraft-solidcraft.md`. Modeled on PhotoCraft (`crates/engine` =
Session + command registry, `crates/automation` = rmcp MCP server with a
headless mode and a bridge mode to the running app, `apps/*` thin shells).

## 1. Assessment of today's repo

| Area | Where it lives | Size |
|---|---|---|
| BLE: Muse (muse-rs fork + btleplug), Crown (OSC/UDP `rosc`) | Rust `rust/src/api/muse.rs`, `neurosity_osc.rs` | ~3.7k LOC |
| Device simulator | Rust `api/simulator.rs` (emits same events as real device) | ~0.5k |
| DSP / features / filters / band math | Rust `api/features.rs`, `eeg_conditioning.rs`, `analysis/*` | several k |
| Session file format, EDF export, capture spine | Rust `session_format.rs`, `edf_export`, `spine/` | ~3k |
| AI (REVE, CBraMod) | Rust `analysis/` | |
| Feedback engine, protocols, calibration, reward/guard lanes | **Dart** `lib/src/feedback` | ~19.6k |
| Monitor state (bands, raw, PSD buffers) | **Dart** `lib/src/monitor` | ~13.1k |
| History/SQLite store, PDF/import/export | **Dart** `feedback/session_*`, `history` | ~3k |
| Views/UI | Dart `views`, `charts` | ~9k |
| Agent control | Dart `lib/src/agent` (JSON TCP server, ~30 fields: view, sidebar, connect, protocol, threshold, override, phase…) | ~0.5k |

Rust total ~20.7k LOC; Dart ~56.7k. Rust is wired to Flutter via
flutter_rust_bridge 2.11 (`frb_generated.rs`).

**Verdict: feasible, medium-hard.** The hard, platform-bound parts (BLE, DSP,
file format, simulator) are already Rust. What is missing is the *application
logic* layer: feedback engine, monitor state, history store are Dart and must
be ported (~35k Dart LOC, likely ~12–15k Rust). The existing Dart agent server
gives a ready-made inventory of the commands MCP must cover.

Risks:
- **Behavioural drift** while porting the feedback engine (thresholds,
  calibration, guard lanes). Mitigate: golden tests from recorded sessions run
  against both Dart and Rust before switching.
- **Flutter is dropped** (decision 2026-10-29). No flutter_rust_bridge
  adapter: new crates copy only the useful Rust (device, DSP, sim, format)
  out of `rust/`. Dart stays as a reference until the feedback engine is
  ported, then is deleted in one commit.
- **BLE on mobile**: btleplug on Android needs JNI glue (already present);
  iOS untested. Keep BLE in its own crate behind `DeviceSource`, never in core.
- **WASM**: core must stay `no tokio/threads/fs` (time injected, I/O via
  traits) to run in the egui web build. MCP server, BLE, SQLite: native only.
  Web BLE (WebBluetooth) would be a separate later `DeviceSource`.
- AI models (rlx/reve) are heavy; keep them feature-gated out of core.

## 2. Crate layout

```text
crates/
  nf-types     L0  ids, units, stream descriptors, DTOs (serde + schemars)       [done: bands, DeviceInfo, traits]
  nf-dsp       L1  filters, PSD, band powers, quality (copied from rust/)          [phase 2]
  nf-sim       L1  deterministic seeded simulators (Muse 4ch, Crown 8ch)           [done: band level; raw port phase 2]
  nf-format    L1  NFED6 container, EDF export (copied)                            [phase 2]
  nf-core      L2  Session + command registry + event log; no egui/tokio; wasm     [done]
  nf-device    L3  btleplug Muse, Crown OSC (native); DeviceProvider impls          [phase 6]
  nf-store     L3  history behind HistoryStore trait (SQLite native)               [phase 5]
  nf-mcp       L4  rmcp server, headless now, bridge later; native only            [done]
apps/
  neurofeed-egui   desktop + web (trunk); later also the Android library          [done]
  neurofeed-mcp    stdio MCP binary (--manual-clock, --device)                    [done]
  android/         thin native wrapper (later, see section 7)
xtask/             ci | layers | wasm (to add; layers is a test in nf-core today)
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

Current commands: `app.status`, `view.list`, `view.set`, `sidebar.set`,
`stream.pause`, `stream.resume`, `scale.set`, `bands.get`, `device.list`,
`device.connect`, `device.disconnect`, `device.status`, `sim.configure`,
`clock.advance`, `events.drain`.

## 4. MCP surface (implemented: generic + typed, not one tool per command)

"Add a command, not a tool, unless the tool is about the session itself."

| Tool | Purpose |
|---|---|
| `command_list {group?}` | id, label, group, read_only, enabled, disabled_reason |
| `command_describe {id}` | metadata + params JSON Schema |
| `command_run {id, params?}` | run any command; failure = `isError` result, state unchanged |
| `command_batch {steps:[{id,params}]}` | pre-validated, atomic, rollback; error names failing step, applied / not run |
| `status` | `app.status` incl. `revision` |
| `bands_get {scale?}` | latest band powers |
| `device_list` | connectable devices |
| `clock_advance {seconds}` | deterministic time (headless) |

Conventions: titles + all four annotation hints; `additionalProperties:false`,
unknown args -> JSON-RPC -32602; execution errors -> `isError: true`; panics
caught per call, session survives. Clock: `--manual-clock` (tests) or wall
clock since start.
Later: `screenshot`, `ui_inspect`/`ui_set` (bridge mode to the running app
over loopback TCP + token file), `recording_export`, `crash_reports`,
`skill_reference`, resources (`neurofeed://status`, `neurofeed://commands`),
progress for long runs.

## 5. Simulator design (nf-sim)

- Implements `BandSource`, opened through a `DeviceProvider` (`sim:muse`,
  `sim:crown`), exactly like real devices.
- Today: band-power level, 1/f baseline, slow alpha swell, seeded xorshift
  noise; `sim.configure {seed, alpha_gain, noise}`.
- Phase 2: port `rust/src/api/simulator.rs` to emit **raw** samples (+PPG/IMU
  descriptors) so nf-dsp runs unchanged; scripted scenarios (eyes closed,
  focus, blinks, jaw, electrode pop, contact loss, battery, dropouts);
  `Replay` source for NFED6 recordings (golden tests vs the Dart engine).
- Data, not assumptions: channels, rates, streams, montage, units come from
  the descriptor; nothing below the device layer branches on `DeviceKind`.

## 6. Migration phases

| # | Phase | Output | Effort |
|---|---|---|---|
| 0 | Prototype | egui shell, mock bands | done |
| 1 | Core + MCP + sim skeleton | this commit: Session, 15 commands, 8 MCP tools, 19 tests, egui on core | done |
| 1b | Gate | `cargo xtask ci` (fmt, clippy -D, layers, wasm, test), output schemas | 0.5 d |
| 2 | Copy DSP/format/raw simulator from `rust/` into nf-dsp/nf-format/nf-sim | Bands from real DSP on simulated raw | 3-5 d |
| 3 | Monitor state in core | Raw EEG, PSD, Spectrogram, Histogram views | 1-2 wk |
| 4 | Feedback engine + protocols + calibration (golden tests vs Dart replay) | Feedback view + tools; **then delete Dart in one commit** | 2-4 wk |
| 5 | History store + export | History view | 1 wk |
| 6 | nf-device (btleplug Muse, Crown OSC), bridge-mode MCP, screenshot | real hardware on desktop | 1 wk |
| 7 | Android wrapper | APK hosting the egui app | 1-2 wk |

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
