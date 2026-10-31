# Decisions (dated, append-only)

- 2026-10-29: Flutter dropped; Rust-only, egui on desktop/web/Android. Dart stays as reference until the feedback engine is ported, then is deleted in one commit.
- 2026-10-29: Android = thin native wrapper (permissions, BLE scan/transport via JNI if needed) hosting the same Rust core; it supplies a `DeviceProvider`, and talks to the core through the same command JSON surface.
- 2026-10-29: MCP surface = generic command_list/describe/run/batch + a few typed session tools. Add a command, not a tool.
- 2026-10-29: Command ids are dotted (`area.verb`); MCP tool names use underscores.
- 2026-10-29: Rust workspace moved to repo root; Flutter docs renamed AGENTS.flutter.md / README.flutter.md.
- 2026-10-29: No Dart NFED6 import compatibility work (Flutter is dropped). nf-format keeps the legacy byte layout, but the computed JSONL/thumbnail sections stay empty and band records hold our log10 values; Rust is the only reader.
- 2026-10-29: Wall clock is injected by shells: `recording.start {wall_clock_unix_ms}` is filled by the egui app (web-time) and by neurofeed-mcp in wall-clock mode; manual-clock MCP injects nothing (deterministic). Core never reads a clock.
- 2026-10-29: File output is a shell concern: MCP tool `recording_export {format, start?, path?}` writes natively when `path` is given; core `recording.export` only returns base64.
- 2026-10-29: Mains detection votes per channel window into one shared counter (as legacy); the notch is rebuilt warm (replaying 2 s of raw) on change; recordings freeze the notch in effect at start. Views may call pure `nf_core::dsp` functions on core buffers; all state stays in the Session.
- 2026-10-29: Simulator ids `sim:muse_s`, `sim:athena`, `sim:crown`; `sim:muse` opens `sim:muse_s` (reported id is the canonical one). Athena exposes the legacy 3-channel PPG view (ambient/infrared/red, 64 Hz); its AUX and fNIRS optics are not modelled. HR/SpO2 use the legacy algorithms unchanged (SpO2 = 110 - 25 R, uncalibrated).
- 2026-10-29 (supersedes the Athena part above): PPG/HR/SpO2 only on Muse 2 (`sim:muse2`) and Muse S (`sim:muse_s`). `sim:athena` has no PPG; hr/spo2/ppg queries are disabled there with a reason. Athena optics come in a separate patch set.

## 2026-10-29: nf-feedback, a faithful port of the engine math plus four deliberate fixes

The hybrid plan from `docs/review-feedback-engine.md` is approved, with the current defaults:
- 40th-percentile threshold;
- 75 s success window;
- adaptation every 30 s;
- ceiling at mean + 1.5 SD;
- guard at P75 with a 20 s chime cooldown;
- 45 valid / 60 max calibration seconds.

`nf-feedback` (L1, no clock, WASM-safe) reproduces the legacy Dart engine. Golden fixtures pin it (`tools/golden-dart`, `crates/nf-feedback/tests/golden`). It differs from the legacy engine only in these four ways; each has its own `div_*` fixture and test:

1. **Sample time, not wall clock.**
   - The success window, recalibration window, guard cooldown and calibration max-time all use `Input::t`, which is active session time with pauses excluded.
   - In the legacy engine, a pause or jank aged or dropped epochs.
2. **No 1.0 fallback.**
   - Without a baseline threshold, nothing is rewarded and `held_back = [no_threshold]`.
   - The legacy engine rewarded `value > 1.0`, which is wrong for TAR, BTR and single bands.
3. **Same pads for every lane.**
   - The reward feature, inhibit limits, guard delta and calibration all come from the pads with quality ≥ 80 in the same `Input`.
   - In the legacy engine, the feature came from the Rust-side autodrop and the limits from Dart's own pad set.
4. **Muffle in both modes.**
   - A guard warning with `muffle = true` withholds reward (`held_back = [guard]`) in both uptrain and stability. With `muffle = false` it never blocks.
   - The legacy engine blocked only in stability mode, ignoring the flag; in uptrain it only muted the audio while still counting the reward.

**Small behaviour change.** Legacy `clamp(initial, max)` throws when initial > max; we let max win.

## 2026-10-29: feedback session state machine (nf-core::feedback)

- Phases idle → fit_check → calibrating → playing ⇄ paused{user|bad_signal|disconnected} → ended. Driven once per session second by `Session` (injected clock; `clock.advance` in tests).
- Reward uses the legacy target pads (AF7/AF8, Crown PO3/PO4, else all); the fit check passes after 3 s of all target pads ≥ 80.
- Calibration: 45 good seconds or 60 s of sample time, whichever first (bad signal extends it to 60 s). Sample time stops while no data arrives, so a dropout does not use up the window. Fewer than 10 good seconds goes back to the fit check. "Start now" (`calibration.skip`) needs ≥ 10. The last baseline is stored per device+protocol for `calibration.reuse`.
- Timing: no usable target pad for 10 s → auto-pause; it auto-resumes after 2 good s. No data for 1.5 s counts as disconnected: paused, and the session ends after a 10 s grace (before training, it is cancelled to idle).
- Protocol and length are locked while a session runs. `threshold.set` (percentile) is the one live control; it is disabled for stability and during calibration.
- One `SecondResult` per second (`feedback.result.get`, UI). The reward chime fires on the rising edge into target (`Event::Chime`).
- The AI sleep guard (`ai.a_vig`) is not ported: Sleep Guard is listed as unavailable, and the other protocols run without a guard.
- `sim.fault` (bad pads / dropout) is a test hook; it does not reconnect.

## 2026-10-30 Artifact detection (movement, blink, jaw)

- Ported legacy `compute_movement` (std of |accel| over 2 s, gate 0.05 g) and `GestureDetector` blink/clench (5x / 100 µV bin energy, 3x gamma) into `nf-dsp::artifact`; eye up/down not ported (experimental, not used for gating).
- Deviation: the blink baseline learns only from quiet bins (legacy learned from every bin, so blinks every ~2 s stopped being counted). Clench already did this.
- Legacy `_sampleIsClean` uses a 1 s buffer after the last event, which at 1 Hz ticks means only the current second is dirty; we do the same. Priority movement > blink > jaw.
- Recordings now carry accelerometer (tag 3) and 1 Hz movement score (tag 8). `sim.fault` gains `motion`, `blink` (one ~110 ms 300 µV bump every 2 s), `clench` (20 µV 37 Hz). New query `artifact.status`.

## 2026-10-30 Band Stability defaults

Window 10 s, difficulty 0.10 (legacy Dart `StabilityConfig`; bounds window 1..30, difficulty 0..0.5). Replaces the earlier guess of 0.2.

## 2026-10-30 Desktop chime (cpal)

`native-audio` feature (default) plays the same 660 Hz / 0.85 s envelope as Web Audio through cpal 0.16; one stream opened lazily on the first chime, triggered via an atomic counter (no locks in the callback). No device: logs once and stays silent. Linux builds need `libasound2-dev` + `pkg-config` (or `--no-default-features`).

## 2026-10-30 History (nf-store)

- `nf-store` (L1, UI-free): `Store` trait; `MemoryStore` (wasm, tests) and `SqliteStore` (feature `sqlite`, rusqlite bundled, native only). One `sessions` table, body as BLOB (`PRAGMA user_version = 1`).
- Every `feedback.start` auto-starts a recording unless one is running; it stops when the session ends. Every finished recording is saved (protocol + summary when it has feedback seconds).
- Commands: `history.list`, `history.get` (meta + per-second feedback), `history.export` (nfed6/raw_body/edf), `history.delete {id, confirm}` (needs confirm=true; disabled with "no saved sessions").
- Desktop: `NF_DB` or the user data dir (`~/.local/share/neurofeed/history.sqlite`, macOS Application Support, Windows %APPDATA%). `neurofeed-mcp`: memory unless `--db`/`NF_DB`. Web: memory only for now.

## Leftovers after History (2026-10-30)
- **Web history = IndexedDB** (`nf-store` feature `indexeddb`, wasm only): the sync `Store` is a cache over IDB; rows load async on start and `Store::take_changed` makes the session re-list on the next tick. Sessions saved before the load finished are renumbered above the persisted ids. Verified in headless Chrome: 3 demo sessions survive a reload (`/workspace/web-history-idb.png`).
- **Local time**: the core stores UTC Unix ms; only the shell formats in the viewer's zone (chrono `Local`, `wasmbind` on web).
- **Band Stability settings**: `stability.set {window?, difficulty?, reset?}` (locked while a session runs), value in `feedback.status.stability`; applies only to stability protocols. Settings view has sliders (one command per drag release).
- **Start params on web**: `?view=…&demo=…` mirror `NF_VIEW`/`NF_DEMO`.
- **CI**: workflow staged at `ci/rust-ci.yml` (the bot token lacks the `workflow` scope, so it cannot push into `.github/workflows/`); `git mv ci/rust-ci.yml .github/workflows/` to enable. Runs every gate; installs `libasound2-dev libdbus-1-dev`.

## Phase 6: real devices + agent bridge (2026-10-30)

- **`nf-device`** (native only; features `ble`, `osc`): `MuseProvider` (muse-rs fork + btleplug, lazy tokio runtime, 18 s connect timeout, ids `muse:<ble id>`), `CrownProvider` (std UDP hub on 9000, layout detection, ids `crown:<device id>`, 5 s seen TTL), `PushProvider` (any platform wrapper — e.g. the future Android app — pushes blocks/announces devices via a handle). `nf-core` does not depend on it (layers test).
- **Provider trait** gains `can_scan/scan/scanning/last_error`; `DeviceSource::link()` → `connecting|streaming|lost{reason}` in `device.status.link` + `Event::LinkChanged`. No auto-reconnect yet (Lost stays until the user reconnects).
- **`device.scan {seconds 1..=60, default 8}`**: disabled with reason when only simulators are registered (web, `--no-hardware`). Provider errors (no BLE adapter, port busy) are in `device.status.provider_errors` and shown in Settings.
- **Bridge**: 127.0.0.1 TCP + 256-bit token in a 0600 discovery file (portable incl. Windows; Unix sockets would not be). Newline JSON; requests run on the UI thread via `nf_mcp::run_tool` (same dispatcher as the stdio server, `ClockMode::Host`). Opt-in (`NF_BRIDGE=1` / Settings toggle) because it grants full control. `nf-mcp` feature `server` (rmcp/tokio) is off in the app.
- **`ui_inspect`** re-runs the UI once off-screen with AccessKit on and returns the tree (role, label, value, disabled, toggled, rect). Side effect: eframe `accesskit` is on, so the desktop app is now screen-reader visible.
- **`screenshot`** uses `ViewportCommand::Screenshot` (real window pixels, PNG); 5 s timeout if the window is minimized.

## 2026-10-30 Feedback audio + drowsiness guard

- **`nf-audio` (L1, wasm-clean)**: `Cue` = what should sound (computed in `nf_core::audio::cue` from phase + last record: background in calibrating/playing, reward in playing, pct, muffle, warning). `Mixer` renders it (no device I/O); hosts pull frames: cpal on desktop, a ScriptProcessorNode on web (AudioWorklet would need a separate JS/wasm worker; later if glitches show).
- **Outputs ported 1:1 from Dart**: rain 5 stages (volumes 1/.7/.45/.2/.04, cutoffs 9000…900 Hz, bounds 20/40/60/80, hysteresis 3, start stage 3, 0.5 s slew, muffle 900 Hz/0.04); binaural swell (L carrier, R carrier+beat, gain × pct/100, ×0.05 muffled, 5 presets); music low-pass min..max by pct (invertible, 1.2 s slew, muffle = min). Guard one-shots rate-limited by the engine (20 s); alarm loops and ramps 0.12→1 over 60 s; cough rotates 3 clips.
- **Assets**: Opus has no pure-Rust decoder, so clips are re-encoded to Ogg Vorbis (`assets/audio/ogg`, same licenses) and decoded with symphonia (also MP3/FLAC/WAV for the music folder). Clips decode lazily (desktop: worker thread; web: on first need). Calibration voice clips are not ported.
- **Guard**: legacy default scorer is the AI model `ai.a_vig` (not ported). Protocols with a guard lane get an **opt-in** band-math guard (`guard.set`, `band.delta` > p75 of calibration, legacy muffleReward per protocol). Off by default because it is not the legacy scorer. **Sleep Guard stays unavailable**: its legacy spec says "no band.delta fallback".
- **Fix**: `feedback.start` reset the Band Stability setting to defaults; the trainer now keeps stability + guard across starts.
- Audio settings are not persisted yet (in-memory like the other settings); `music_dir` lives in `AppState` so MCP can set it, only the desktop shell reads the folder.

## Import (EDF/EDF+, Mind Monitor CSV, .neurofeed / raw)

- New L1 crate `nf-import` (wasm-clean): format sniffing, montage matching (Muse 4 + AUX or Crown 8; anything else is refused with the labels found), resampling (`nf_dsp::resample`, windowed sinc) to the device rate, provenance (dropped channels, resampled, reference, prefiltering, interval coverage, warnings, annotations).
- **Bands**: files with raw EEG get bands by replaying it through the live `Signal` pipeline (same cadence as a live recording, 0.1 s); files that only carry bands (Mind Monitor interval CSV, band-labelled EDF) keep them (`bands_from_file`).
- **Time**: EDF and Mind Monitor stamp local time; the shell injects `utc_offset_minutes`. NeuroFeed's own EDF export stamps UTC (recording field ends in `neurofeed`) and is read as UTC. Legacy `.neurofeed` (ms timestamps, ISO startedAt) is rebased to session seconds.
- Annotations (EDF+ TALs, Mind Monitor Elements, EDF+D gaps → disconnect) and provenance live in `SessionMeta.import` (sqlite schema v2, v1 migrated with `ALTER TABLE`).
- Commands: `history.import_preview` (query, nothing saved) and `history.import` (saves). The UI dialog shows kept / not imported / warnings before saving; desktop: path field or drop, web: file picker or drop. Max 96 MB.

## Streaming out (OSC)

- Core (`nf_core::streaming`, wasm-clean) chooses the groups, aligns channels (legacy `GroupMixer`, 128-sample queues) and encodes OSC 1.0 (big-endian float32). The shell registers a `nf_types::DatagramSink` (desktop: `nf_device::UdpSink`); the web build has none, so `streaming.set {enabled:true}` is refused with that reason.
- Legacy wire format kept: `<prefix>/<group>`, `[t_first, row-major values]`, chunks EEG 12 / PPG 6 / IMU 3 / Bands 1, EEG = conditioned signal, defaults `192.168.1.100:9000`, `/muse`.
- Differences: time is session seconds (not device epoch); IMU is accelerometer only (3 ch, no gyro in our sources); bands are 10 Hz snapshots (log10 µV²). Streaming follows Pause (the signal pipeline is paused too). Settings are in-memory like audio.
- LSL / BrainFlow: not ported yet (LSL needs the C liblsl; decision pending).

## Trust model (per-second trust records)

Each feedback second now writes a `Record::Trust` (tag 12) right after its
`Feedback` record, with the same timestamp: native value, percent, threshold
percent and a bit field (dirty reason in the low 3 bits — movement, blink, jaw,
pads, no_signal — then held-back reasons, guard warn/chime/muted, produced).
We chose a new binary record over JSON in the meta so live and saved sessions
go through one encoder (`feedback.trust` and `history.trust` build rows the same
way). Older sessions have no trust records; their non-clean seconds report
`dirty: "unknown"`. Trade-off: readers older than this tag reject the new
record, so files written now do not open in builds from before this change.
Seconds with no feature at all (no verdict, not an artifact) are `no_signal`.

## Protocol Builder (custom protocols)

`Protocol` is now owned data (`String` fields, `builtin()` instead of a
`'static` table) so custom protocols and built-ins share one type. Custom
protocols are stored as `ProtocolDraft`s (schemars-checked, the same shape the
`protocol.save` command takes) in a named store document `custom_protocols`:
a `docs` table in SQLite (schema v3) and `localStorage` in the browser (read
synchronously at startup; IndexedDB stays for sessions). Drafts that no longer
validate on load are skipped with a store error event rather than failing the
start-up.

The builder offers only what the engine runs today: percentile uptrain on one
of the six band features, eyes, length, beta/delta ceilings and the band-math
guard lane (offered, still off by default). The stability policy, sounds,
calibration variants and colours of the legacy builder are not editable; a
copy of Band Stability or Sleep Guard says so in `notes`. Ids are slugs and
cannot shadow a built-in; saving an existing id needs `replace`. A batch that
fails after `protocol.save` rolls the document back as well.

## Trust pane and feedback dashboard
One `views::trust::pane` renders live training, the end-of-session summary and History detail: percentile/value plot with calibration shading, per-second state strip (in zone / below / held / dirty / idle), hover explanations, totals and dirty breakdown. The live pane is cached on result count and last timestamp. The training header shows progress and a Trust toggle; the indicator adds a percentile meter with the threshold tick.

## Session metadata and persisted settings
`SessionMeta` gains `notes` (user text, ≤ 4000 chars, edited via `history.notes`) and `context` (snapshot at save: protocol, minutes, percentile, guard, mains, audio, user settings, app version). SQLite schema v4 adds the two columns (migrated from v1–v3). A rolled-back batch restores edited notes in the store.
All user settings live in one store doc `settings` (`nf_core::settings::Persisted`: user settings, audio, mains, band scale, music folder, Band Stability, guard flag). It is rewritten after any successful state-changing command when its JSON changed, loaded in `with_store`, and re-written after a rollback. New `settings.set` / `settings.get`. Debug mode (default on) controls whether simulators are listed.

## Settings sections, About and onboarding
Settings is a section rail (General, Devices, Training, AI, Recording, About) with cards from one `CARDS` table; the search box matches section + title + terms across all sections. The AI card is a placeholder until the REVE / CBraMod decision. About embeds THIRD_PARTY_NOTICES.md. The first-run tour (five pages, Skip / Back / Next / Start) shows while `settings.onboarded` is false; runs started with NF_DEMO / NF_VIEW skip it without persisting anything.

## Nerd sheet and PDF export
- Nerd sheet (`feedback.nerd`): reward pile histogram (24 bins, threshold/live markers kept inside), live value, threshold percentile, mean, spread, n, success rate; guard pile when a guard runs. Anchored bottom-right so the header toggles and trust pane stay usable.
- PDF report: own minimal PDF 1.4 writer in nf-format (`pdf.rs`, Helvetica/WinAnsi, text/rect/polyline, ~150 lines) instead of a crate — wasm-clean, no font embedding. Non-Latin-1 characters become `?` (accepted for now; embedding a TTF would be the upgrade). `history.export` format `pdf`; `recording.export` rejects it (needs the stored session). One page: title, info, totals, percentile/threshold plot + trust strip, notes, recording context.

## LSL: own pure-Rust crate `pure-lsl`, sending only (2026-10-30)
- Existing pure-Rust crates exist (rlsl 0.0.6, labstream 0.1.2, lsl-core 0.0.1; `lsl`/`lsl-sys` are liblsl bindings). We still wrote our own, designed from the protocol (liblsl studied, not translated); publishing is the owner's call (`publish = false` for now).
- Outlet only: ~1.3k lines. An inlet (resolver, XML parse, TCP client, time correction) estimated +65% > 30% budget → not built.
- Protocol 1.10 only (1.00 → 505), little-endian, timestamps = local monotonic clock at send. Slow consumers drop chunks (bounded queue), counted.
- NeuroFeed: `StreamOutlets` trait in nf-types, `LslOutlets` in nf-device (feature `lsl`, native only); web build has no transport and `streaming.set {protocol:"lsl"}` errors there.
- Interop: tests/interop.rs (pylsl, gated on PURE_LSL_PYTHON), scripts/lsl_e2e.py for the whole app.

## AI models (nf-ai) — 2026-10-30

- Reused the existing Rust REVE (reve-rs, rlx pinned `=0.2.14`, vendored rlx-cpu patch) and CBraMod (Candle) inference as the `nf-ai` crate; no flutter_rust_bridge layer. Heads ship embedded (f32bin).
- Runtime boundary: `nf_types::AiRuntime` trait; `nf_ai::NativeAi` (one worker thread, one model loaded at a time, skip-if-busy, one window/s). Registered only on native builds.
- Web: models are desktop-only. `nf-ai` core compiles to wasm without features, but Candle pulls getrandom (no wasm_js), weights are 20–280 MB, and REVE takes ~530 ms/window natively single-threaded. The web build reports "AI models run in the desktop app only" and gates every `ai.*` command plus Sleep Guard via `has_ai`.
- Sleep Guard is AI-only (`guard_only`): staged calibration (artifacts → eyes open → eyes closed), no reward lane, no band-math fallback; start is blocked with the model's not-ready reason.
- AI guard is the default for guard-lane protocols when the selected model is Ready; band math stays opt-in (`guard.set`, off by default).
- Threshold: fixed 0.50 by default (0.05–0.95), or p75 of the eyes-closed calibration AI samples; switchable mid-session.
- REVE scores 2 s windows (512 samples @ 256 Hz) as its head packs' manifests say; the legacy app fed 4 s (changed 2026-10-31, owner OK).
- AI baseline samples wait for V_clear, as in legacy: V_clear comes from the staged eyes-open step, or from the whole baseline of an eyes-open protocol. Eyes-closed unstaged protocols (Rest Awake) therefore collect no AI baseline; percentile mode has no threshold there and the fixed threshold applies.
- Batches: `ai.set` rolls back with the rest of the state; `ai.load`/`ai.unload` are undone by reloading or unloading the model that was loaded before the batch. `ai.install`/`ai.remove` are refused inside a batch before any step runs: they write or delete model files (a download keeps going on its own thread), so they cannot be rolled back.
- REVE is gated on Hugging Face: import only; CBraMod downloads (sha256-verified, .part + rename).
- Verified: CBraMod vs Python reference max_abs 1.6e-7; REVE runs on the real weights (dim 512).

## UI pass vs legacy Flutter (2026-10-31)

- Sleep Guard calibration shows a red "No awake reference" banner when the
  eyes-open step produced no AI score; those seconds do not count.
- Recordings auto-save; the top bar offers "Discard last recording" instead of
  the legacy Save/Discard modal.
- Bands defaults to the legacy "Over time" chart (60 s, chosen electrodes,
  toggleable bands); egui's bar view stays as an option.
- Settings > Training > Calibration "Always staged" ported (off by default).
- F11 toggles fullscreen (legacy cinema mode). UI strings use ">" (font lacks the arrow).
- Not ported yet: crash recovery of interrupted sessions; history multi-select,
  bulk export and thumbnails; opening a recording in the graph views; Movement
  (IMU) and optical overview panes; Muse AUX channels / AUX recording;
  Follow/Inspect scrolling; moving the save folder; debug feature override;
  "Reduce audio stutter"; Crown quality source; eye up/down markers.
  Android-only items (multicast lock, foreground capture) are N/A.
