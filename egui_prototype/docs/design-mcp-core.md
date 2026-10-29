# Design: NeuroFeed Rust core + MCP + simulators

Status: proposal (not implemented). Modeled on PhotoCraft (`crates/engine` =
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
- **flutter_rust_bridge**: fine to keep during migration (Flutter calls the new
  core through frb), but the API surface changes; regenerate per phase.
- **BLE on mobile**: btleplug on Android needs JNI glue (already present);
  iOS untested. Keep BLE in its own crate behind `DeviceSource`, never in core.
- **WASM**: core must stay `no tokio/threads/fs` (time injected, I/O via
  traits) to run in the egui web build. MCP server, BLE, SQLite: native only.
  Web BLE (WebBluetooth) would be a separate later `DeviceSource`.
- AI models (rlx/reve) are heavy; keep them feature-gated out of core.

## 2. Crate layout

```text
crates/
  nf-types     L0  Band, Channel, DeviceKind, Sample, BandSnapshot (serde, no deps)
  nf-dsp       L1  filters, PSD, band powers, features (moved from rust/src/api)
  nf-sim       L1  simulators: Muse, Crown, scripted/replay; deterministic seed
  nf-format    L1  session file format, EDF export (moved)
  nf-core      L2  Session: state + Command registry + event log (no egui, no tokio, WASM-safe)
  nf-device    L3  real sources: Muse BLE (btleplug/muse-rs), Crown OSC (native only)
  nf-store     L3  history store (SQLite) behind `HistoryStore` trait (native); in-memory impl in core for tests/web
  nf-mcp       L4  rmcp server: headless (in-process Session) + bridge (to running app)
apps/
  neurofeed-egui   egui shell (desktop + web) over nf-core
  neurofeed-mcp    binary: `neurofeed-mcp --sim muse` (stdio) / `--bridge 127.0.0.1:PORT`
  (Flutter app keeps working via frb against nf-core during migration)
```
Layering enforced by a small `xtask layers` check (as PhotoCraft).

## 3. Core API (nf-core)

```rust
pub struct Session { /* AppState, sources, feedback engine, history */ }

impl Session {
    pub fn new(cfg: SessionConfig) -> Self;
    pub fn tick(&mut self, now: f64);                       // pull sources, run DSP/feedback
    pub fn execute(&mut self, cmd: Command) -> Result<Reply, CoreError>;
    pub fn query(&self, q: Query) -> Result<Reply, CoreError>;
    pub fn commands() -> &'static [CommandSpec];            // name, json schema, doc
    pub fn drain_events(&mut self) -> Vec<Event>;           // for UI + MCP notifications
}

pub trait DeviceSource { fn info(&self) -> DeviceInfo; fn poll(&mut self, now: f64) -> Vec<Sample>; fn connect(&mut self) -> Result<()>; fn disconnect(&mut self); }
pub trait HistoryStore  { fn list(&self) -> Vec<SessionMeta>; fn load(&self, id: &str) -> Result<SessionData>; fn save(&mut self, s: &SessionData) -> Result<()>; }
pub trait Clock { fn now(&self) -> f64; }                   // injected; enables fast-forward in tests
```
Every user action is a serde `Command` (`#[serde(tag = "cmd")]`). The egui UI,
the MCP server and Flutter all go through `execute`, so "reachable via MCP" is
guaranteed by construction: MCP tools are generated from `Session::commands()`
(plus a few hand-written ones for screenshots in bridge mode). A unit test
asserts every `Command` variant has an MCP tool.

## 4. MCP tool list (v1)

App/UI: `app_status`, `view_list`, `view_set`, `sidebar_set`, `screenshot` (bridge only), `ui_click` (bridge only).
Device: `device_list` (real + simulators), `device_connect {id|sim:muse|sim:crown}`, `device_disconnect`, `device_status` (battery, contact quality, sample rate), `sim_configure {seed, alpha_gain, artifacts, noise, dropout}`.
Stream: `stream_pause`, `stream_resume`, `bands_get {channels?, scale: abs|rel, window_s}`, `raw_get {seconds}`, `psd_get`, `quality_get`.
Feedback: `protocol_list`, `protocol_get`, `protocol_set`, `feedback_start`, `feedback_stop`, `feedback_status` (phase, in_target, reward, threshold), `threshold_set`, `override_set`, `calibration_run`.
Recording/history: `recording_start/stop`, `history_list`, `history_get`, `history_export {edf|json}`, `history_delete` (confirm flag).
Time (headless/sim only): `clock_advance {seconds}`. This makes a 20-min feedback session testable in milliseconds.
Settings: `settings_get`, `settings_set`.

## 5. Simulator design (nf-sim)

- Implements `DeviceSource`; same `Sample` stream as real devices (raw µV at
  256 Hz Muse / 256 Hz Crown, 4/8 channels, plus PPG/accel where relevant), so
  DSP, feedback and recording run unchanged. Real devices differ only in transport.
- Signal model: sum of band oscillators with 1/f background, per-channel
  gains, scripted state changes (eyes closed → alpha up, focus → beta up),
  artifacts (blink, jaw, electrode pop), contact loss, battery drain, dropouts.
- Deterministic: seeded RNG + injected clock → reproducible tests.
- `Replay` source: plays a recorded session file (golden tests vs. Dart).
- Scenario files (TOML/JSON) selectable via `sim_configure`.
- Port existing `rust/src/api/simulator.rs` rather than rewrite.

## 6. Migration phases

| # | Phase | Output | Rough effort |
|---|---|---|---|
| 0 | Prototype (done) | egui shell, mock bands | — |
| 1 | Workspace + `nf-types`, `nf-core` skeleton, `nf-mcp` headless, egui on core | tools: views, bands, pause, scale, sim select; MCP-driven tests | 2–3 d |
| 2 | Move DSP/format/simulator out of `rust/` into crates; frb crate becomes a thin adapter | Flutter unchanged, now calls crates | 3–5 d |
| 3 | Port monitor state (bands/raw/PSD buffers) to core | Bands/Raw/PSD/Spectrogram views in egui | 1–2 wk |
| 4 | Port feedback engine + protocols + calibration, golden tests vs Dart | feedback tools | 2–4 wk |
| 5 | History store (SQLite) + export | history tools | 1 wk |
| 6 | Bridge mode (MCP ↔ running app, screenshot) ; real BLE `nf-device` | parity with Dart agent server | 1 wk |
| 7 | Decide: egui replaces Flutter, or Flutter stays as UI over core | | |

Open questions: keep Flutter as the mobile UI (frb over core) or go all-egui?
WebBluetooth for the web build? MCP transport: stdio only or also loopback TCP/HTTP?
