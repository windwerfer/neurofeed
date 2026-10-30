//! The Session: single owner of state; the only way to change it.

mod ai_glue;

use crate::command::{find, Command, CommandSpec, Query, Request, SPECS};
use crate::feedback::{Change, Observation, Phase};
use crate::recording::{base64, export, Finished, Recorder};
use crate::signal::{mains_name, Signal, SPEC_HOP_S};
use crate::state::{AppState, BandScale, View};
use crate::{CoreError, Reply};
use nf_sim::SimProvider;
use nf_types::{AccelPacket, Band, DeviceInfo, DeviceProvider, DeviceSource, EegPacket, PpgPacket};

/// One poll of the device: EEG, optical, accelerometer.
type Polled = (Vec<EegPacket>, Vec<PpgPacket>, Vec<AccelPacket>);
use serde::Serialize;
use serde_json::json;

/// Pipeline step used by `clock_advance`.
const STEP_S: f64 = 0.1;
const MAX_ADVANCE_S: f64 = 3600.0;
const MAX_EVENTS: usize = 1000;

/// Things that happened; drained by UI/MCP.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum Event {
    ViewChanged {
        view: View,
    },
    Connected {
        id: String,
    },
    /// Transport state of the connected device changed.
    LinkChanged {
        link: nf_types::LinkState,
    },
    Disconnected {
        id: String,
    },
    Paused {
        paused: bool,
    },
    ScaleChanged {
        scale: BandScale,
    },
    RecordingStarted {
        device: String,
    },
    RecordingStopped {
        duration: f64,
        eeg_samples: u64,
        reason: String,
    },
    MainsChanged {
        applied: String,
        detected: String,
    },
    /// Feedback phase changed.
    Feedback {
        phase: Phase,
    },
    /// Play the reward chime.
    Chime,
    /// Play the guard warning sound.
    GuardChime,
    /// A finished recording was saved to history.
    SessionSaved {
        id: u64,
    },
    StoreError {
        message: String,
    },
}

/// Simulator faults (`sim.fault`).
#[derive(Clone, Default)]
struct Fault {
    bad: Vec<usize>,
    dropout: bool,
    motion: bool,
    blink: bool,
    clench: bool,
    drowsy: bool,
}

/// Data older than this counts as no data (disconnect grace starts).
const STALE_S: f64 = 1.5;
/// Pad pairs the reward uses (legacy target electrodes); else all pads.
const TARGET_PADS: [[&str; 2]; 2] = [["AF7", "AF8"], ["PO3", "PO4"]];
/// Fault artifact: 200 µV at 3 Hz (pad quality 0).
const FAULT_UV: f64 = 200.0;

/// Data-path state that is not plain `AppState` (cloned for batch rollback).
#[derive(Clone, Default)]
struct Live {
    signal: Option<Signal>,
    optics: Option<crate::optics::Optics>,
    recorder: Option<Recorder>,
    finished: Option<Finished>,
    fault: Fault,
    artifacts: Option<crate::artifacts::Artifacts>,
    last_data: Option<f64>,
    /// Session time of the next feedback second.
    fb_next: f64,
    /// The recording was started by `feedback.start` (stops with it).
    auto_recording: bool,
    streamer: crate::streaming::Streamer,
    /// Session time of the next AI window.
    ai_next: f64,
    anchors: nf_feedback::anchors::Anchors,
    /// Eyes-closed scores seen after V_clear: capture V_sleep at play.
    ai_sleep_pending: bool,
}

/// Longest accepted session notes.
pub const MAX_NOTES: usize = 4000;

pub struct Session {
    state: AppState,
    sim: SimProvider,
    providers: Vec<Box<dyn DeviceProvider>>,
    source: Option<Box<dyn DeviceSource>>,
    sink: Option<Box<dyn crate::streaming::DatagramSink>>,
    outlets: Option<Box<dyn nf_types::StreamOutlets>>,
    ai: Option<Box<dyn nf_types::AiRuntime>>,
    /// Models auto-loaded once (cleared on install / remove).
    ai_autoloaded: Vec<nf_types::AiModel>,
    /// (device id, separate groups) the LSL outlets are open for.
    lsl_open: Option<(String, bool)>,
    live: Live,
    store: Box<dyn nf_store::Store>,
    events: Vec<Event>,
    /// Last absolute time passed to `tick` (tick works on deltas).
    last_tick: Option<f64>,
    /// Last settings doc written (or loaded).
    settings_doc: String,
}

impl Default for Session {
    fn default() -> Self {
        Self::new()
    }
}

impl Session {
    /// A session with the simulators registered and nothing connected.
    pub fn new() -> Self {
        Self {
            state: AppState::default(),
            sim: SimProvider::default(),
            providers: Vec::new(),
            source: None,
            sink: None,
            outlets: None,
            ai: None,
            ai_autoloaded: Vec::new(),
            lsl_open: None,
            live: Live::default(),
            store: Box::new(nf_store::MemoryStore::default()),
            events: Vec::new(),
            last_tick: None,
            settings_doc: String::new(),
        }
    }

    /// Use `store` for history (default: in memory).
    pub fn with_store(mut self, store: Box<dyn nf_store::Store>) -> Self {
        self.store = store;
        self.refresh_history();
        self.load_protocols();
        self.load_settings();
        self
    }

    fn load_settings(&mut self) {
        match self.store.get_doc(crate::settings::DOC_KEY) {
            Ok(Some(doc)) => match serde_json::from_str::<crate::settings::Persisted>(&doc) {
                Ok(p) => {
                    p.restore(&mut self.state);
                    self.settings_doc = doc;
                }
                Err(e) => self.emit(Event::StoreError { message: format!("settings ignored: {e}") }),
            },
            Ok(None) => {}
            Err(e) => self.emit(Event::StoreError { message: e.to_string() }),
        }
    }

    /// Write the settings doc if it changed since the last write.
    fn persist_settings(&mut self) {
        let doc = serde_json::to_string(&crate::settings::Persisted::of(&self.state)).unwrap_or_default();
        if doc == self.settings_doc {
            return;
        }
        match self.store.put_doc(crate::settings::DOC_KEY, Some(&doc)) {
            Ok(()) => self.settings_doc = doc,
            Err(e) => self.emit(Event::StoreError { message: format!("settings not saved: {e}") }),
        }
    }

    fn load_protocols(&mut self) {
        let (custom, errors) = crate::protocols::load(self.store.as_ref());
        self.state.custom_protocols = custom;
        for message in errors {
            self.emit(Event::StoreError { message });
        }
    }

    fn persist_protocols(&mut self) -> Result<(), CoreError> {
        crate::protocols::save(self.store.as_mut(), &self.state.custom_protocols).map_err(CoreError::BadRequest)
    }

    fn protocol_save(&mut self, draft: &crate::protocols::ProtocolDraft, replace: bool) -> Result<serde_json::Value, CoreError> {
        let problems = crate::protocols::validate(draft, &self.state.custom_protocols, replace);
        if let Some(p) = problems.first() {
            return Err(CoreError::InvalidArgs(format!("{}: {}", p.field, p.message)));
        }
        let p = crate::protocols::to_protocol(draft);
        let list = &mut self.state.custom_protocols;
        match list.iter_mut().find(|x| x.id == p.id) {
            Some(x) => *x = p.clone(),
            None => list.push(p.clone()),
        }
        if self.state.feedback.protocol.id == p.id {
            self.state.feedback.protocol = p.clone();
        }
        self.persist_protocols()?;
        Ok(json!(p))
    }

    fn protocol_delete(&mut self, id: &str, confirm: bool) -> Result<(), CoreError> {
        if !confirm {
            return Err(CoreError::InvalidArgs("deleting is permanent; pass confirm=true".into()));
        }
        let n = self.state.custom_protocols.len();
        self.state.custom_protocols.retain(|p| p.id != id);
        if self.state.custom_protocols.len() == n {
            return Err(CoreError::InvalidArgs(format!("no custom protocol `{id}`")));
        }
        if self.state.feedback.protocol.id == id {
            let d = crate::feedback::Trainer::default();
            self.state.feedback.minutes = d.minutes;
            self.state.feedback.protocol = d.protocol;
        }
        self.persist_protocols()
    }

    fn refresh_history(&mut self) {
        self.state.history_location = self.store.location();
        match self.store.list() {
            Ok(l) => self.state.history = l,
            Err(e) => self.emit(Event::StoreError { message: e.to_string() }),
        }
    }

    /// Export a saved session (typed; `history.export` wraps it).
    pub fn history_export(&self, id: u64, format: crate::ExportFormat) -> Result<Vec<u8>, CoreError> {
        if format == crate::ExportFormat::Pdf {
            let trust = self.history_trust(id)?;
            return Ok(crate::report::pdf(&self.stored(id)?.meta, &trust));
        }
        let s = self.stored(id)?;
        let device: DeviceInfo = serde_json::from_str(&s.device_json).map_err(|e| CoreError::BadRequest(format!("stored device: {e}")))?;
        let info = crate::recording::RecordingInfo {
            active: false,
            device: device.id.clone(),
            started: 0.0,
            duration: s.meta.duration_s,
            eeg_samples: s.meta.eeg_samples,
            ppg_samples: s.meta.ppg_samples,
            feedback_seconds: s.meta.feedback_seconds,
            bytes: s.body.len(),
            wall_clock_unix_ms: s.meta.started_unix_ms,
        };
        let f = Finished { device, info, body: s.body };
        let start = f.info.wall_clock_unix_ms.map_or((1985, 1, 1, 0, 0, 0), crate::recording::civil_utc);
        export(&f, format, start).map_err(CoreError::BadRequest)
    }

    fn import_prepare(&self, req: &crate::import::ImportRequest) -> Result<crate::import::Prepared, CoreError> {
        let bytes = crate::import::base64_decode(&req.data_base64)?;
        self.import_bytes(&bytes, &req.file_name, req.utc_offset_minutes.unwrap_or(0))
    }

    /// Parse (and band) an import without saving (typed; the UI uses it so
    /// the dialog does not round-trip megabytes through base64).
    pub fn import_bytes(&self, bytes: &[u8], file_name: &str, utc_offset_minutes: i32) -> Result<crate::import::Prepared, CoreError> {
        crate::import::prepare(bytes, file_name, utc_offset_minutes, self.state.mains_mode)
    }

    fn history_import(&mut self, req: &crate::import::ImportRequest) -> Result<Reply, CoreError> {
        let p = self.import_prepare(req)?;
        let summary = p.preview().summary;
        let id = self.import_save(p.into_stored())?;
        Ok(json!({ "id": id, "summary": summary }))
    }

    /// Store a prepared import; emits `SessionSaved`.
    pub fn import_save(&mut self, s: nf_store::StoredSession) -> Result<u64, CoreError> {
        let id = self.store.insert(s).map_err(|e| CoreError::BadRequest(e.to_string()))?;
        self.emit(Event::SessionSaved { id });
        self.refresh_history();
        Ok(id)
    }

    fn stored(&self, id: u64) -> Result<nf_store::StoredSession, CoreError> {
        self.store
            .get(id)
            .map_err(|e| CoreError::BadRequest(e.to_string()))?
            .ok_or_else(|| CoreError::InvalidArgs(format!("no session {id}")))
    }

    fn set_notes(&mut self, id: u64, notes: &str) -> Result<(), CoreError> {
        if notes.chars().count() > MAX_NOTES {
            return Err(CoreError::InvalidArgs(format!("notes are limited to {MAX_NOTES} characters")));
        }
        if !self.store.set_notes(id, notes).map_err(|e| CoreError::BadRequest(e.to_string()))? {
            return Err(CoreError::InvalidArgs(format!("no session {id}")));
        }
        self.refresh_history();
        Ok(())
    }

    /// What was in effect while recording (kept with the session).
    fn context(&self, trained: bool) -> serde_json::Value {
        let s = &self.state;
        json!({
            "app_version": env!("CARGO_PKG_VERSION"),
            "protocol": trained.then_some(&s.feedback.protocol),
            "minutes": s.feedback.minutes,
            "percentile": s.feedback.percentile,
            "guard": s.feedback.guard,
            "mains": s.mains_mode,
            "audio": s.audio,
            "settings": s.settings,
        })
    }

    /// Persist a finished recording (with its feedback summary).
    fn save(&mut self, f: &Finished) {
        let fb = &self.state.feedback;
        let trained = f.info.feedback_seconds > 0;
        let meta = nf_store::SessionMeta {
            id: 0,
            started_unix_ms: f.info.wall_clock_unix_ms,
            duration_s: f.info.duration,
            device_id: f.device.id.clone(),
            device_name: f.device.name.clone(),
            protocol: trained.then(|| fb.protocol.id.to_owned()),
            summary: if trained { fb.summary.as_ref().and_then(|s| serde_json::to_value(s).ok()) } else { None },
            eeg_samples: f.info.eeg_samples,
            ppg_samples: f.info.ppg_samples,
            feedback_seconds: f.info.feedback_seconds,
            bytes: f.body.len() as u64,
            import: None,
            notes: String::new(),
            context: Some(self.context(trained)),
        };
        let s = nf_store::StoredSession { meta, device_json: serde_json::to_string(&f.device).unwrap_or_default(), body: f.body.clone() };
        match self.store.insert(s) {
            Ok(id) => {
                if trained {
                    self.state.feedback.saved_id = Some(id);
                }
                self.emit(Event::SessionSaved { id });
            }
            Err(e) => self.emit(Event::StoreError { message: e.to_string() }),
        }
        self.refresh_history();
    }

    /// Add a real device provider (desktop BLE, Android JNI transport, ...).
    pub fn register_provider(&mut self, provider: Box<dyn DeviceProvider>) {
        if provider.can_scan() {
            self.state.scanners.push(provider.scheme().to_owned());
        }
        self.providers.push(provider);
    }

    /// Simulators plus everything the providers currently see.
    pub fn device_list(&self) -> Vec<DeviceInfo> {
        // Simulators only in debug mode (on by default).
        let mut all = if self.state.settings.debug { self.sim.list() } else { Vec::new() };
        for p in &self.providers {
            all.extend(p.list());
        }
        all
    }

    /// Schemes of providers with a scan running.
    pub fn scanning(&self) -> Vec<&'static str> {
        self.providers.iter().filter(|p| p.scanning()).map(|p| p.scheme()).collect()
    }

    /// `scheme: error` of providers that reported one.
    pub fn provider_errors(&self) -> Vec<String> {
        self.providers.iter().filter_map(|p| p.last_error().map(|e| format!("{}: {e}", p.scheme()))).collect()
    }

    /// The history / document store (read-only).
    pub fn store(&self) -> &dyn nf_store::Store {
        self.store.as_ref()
    }

    pub fn state(&self) -> &AppState {
        &self.state
    }

    /// The command/query catalog.
    pub fn commands() -> &'static [CommandSpec] {
        SPECS
    }

    /// `Ok` if the command can run now, else the disabled reason.
    pub fn enabled(&self, id: &str) -> Result<(), String> {
        let spec = find(id).ok_or_else(|| format!("unknown command `{id}`"))?;
        (spec.enabled)(&self.state)
    }

    /// Run several commands atomically. All steps are parsed first (an
    /// unknown id or bad params fails before anything runs); if any step
    /// fails, state is rolled back to before the batch.
    pub fn batch(&mut self, steps: &[(String, serde_json::Value)]) -> Result<Reply, CoreError> {
        let parsed = steps
            .iter()
            .enumerate()
            .map(|(i, (id, p))| Request::parse(id, p.clone()).map_err(|e| CoreError::BadRequest(format!("step {i}: {e}"))))
            .collect::<Result<Vec<_>, _>>()?;
        let checkpoint = (self.state.clone(), self.sim.config, self.events.len(), self.live.clone());
        let mut results = Vec::with_capacity(parsed.len());
        for (i, req) in parsed.into_iter().enumerate() {
            match self.run(req) {
                Ok(v) => results.push(v),
                Err(e) => {
                    self.rollback(checkpoint);
                    return Err(CoreError::BadRequest(format!(
                        "step {i} failed: {e}; applied {i}, not run {}, rolled back",
                        steps.len() - i - 1
                    )));
                }
            }
        }
        Ok(json!({ "results": results, "revision": self.state.revision }))
    }

    fn rollback(&mut self, (state, sim, events, live): (AppState, nf_sim::SimConfig, usize, Live)) {
        self.live = live;
        let reopen = state.device.as_ref().map(|d| d.id.clone());
        let changed = self.state.device.as_ref().map(|d| &d.id) != state.device.as_ref().map(|d| &d.id) || self.state.time != state.time;
        self.sim.config = sim;
        self.events.truncate(events);
        if changed {
            // Sources are not cloneable: reopen the previous device fresh.
            self.source = match &reopen {
                Some(id) => self.open(id).ok(),
                None => None,
            };
        }
        let protocols_changed = self.state.custom_protocols != state.custom_protocols;
        self.restore_notes(&state.history);
        self.state = state;
        if protocols_changed && self.persist_protocols().is_err() {
            self.emit(Event::StoreError { message: "custom protocols could not be restored after a rolled-back batch".into() });
        }
        self.persist_settings();
    }

    /// Undo note edits of a rolled-back batch.
    fn restore_notes(&mut self, before: &[nf_store::SessionMeta]) {
        for m in before {
            let now = self.state.history.iter().find(|h| h.id == m.id);
            if now.is_some_and(|h| h.notes != m.notes) && self.store.set_notes(m.id, &m.notes).is_err() {
                self.emit(Event::StoreError { message: format!("notes of session {} could not be restored", m.id) });
            }
        }
    }

    pub fn drain_events(&mut self) -> Vec<crate::Event> {
        std::mem::take(&mut self.events)
    }

    /// Feed wall-clock time (seconds, any origin). Advances session time by
    /// the delta since the previous call. Call once per UI frame.
    pub fn tick(&mut self, now: f64) {
        if self.store.take_changed() {
            self.refresh_history();
        }
        let dt = match self.last_tick {
            Some(last) if now > last => now - last,
            _ => 0.0,
        };
        self.last_tick = Some(now);
        self.advance(dt.min(1.0)); // cap a stalled frame / suspended tab
    }

    fn advance(&mut self, dt: f64) {
        if !(dt.is_finite() && dt > 0.0) {
            return;
        }
        self.state.time += dt;
        let now = self.state.time;
        self.sync_lsl();
        if let Some((mut packets, optical, accel)) = self.poll_device(now) {
            self.route_side_streams(&packets, &optical, &accel);
            let full = self.process_eeg(&mut packets);
            self.flush_stream();
            if let Some(r) = self.live.recorder.as_mut() {
                r.tick(now);
                self.state.recording = Some(r.info.clone());
            }
            if full {
                self.stop_recording("size limit reached");
            }
        }
        self.ai_tick();
        self.feedback_tick(now);
    }

    /// Drain the device (always, so resume has no backlog burst; pause only
    /// freezes the views), track the link and apply simulated faults.
    fn poll_device(&mut self, now: f64) -> Option<Polled> {
        let src = self.source.as_mut()?;
        let mut packets = src.poll(now);
        let mut optical = src.poll_ppg(now);
        let mut accel = src.poll_accel(now);
        let link = src.link();
        if self.state.link.as_ref() != Some(&link) {
            self.state.link = Some(link.clone());
            self.state.revision += 1;
            self.emit(Event::LinkChanged { link });
        }
        if self.live.fault.dropout {
            packets.clear();
            optical.clear();
            accel.clear();
        }
        if let Some(dev) = &self.state.device {
            inject_artifacts(&self.live.fault, dev, &mut packets, &mut accel);
        }
        if !packets.is_empty() {
            self.live.last_data = Some(now);
        }
        for p in packets.iter_mut().filter(|p| self.live.fault.bad.contains(&usize::from(p.electrode))) {
            let n = p.samples.len();
            for (k, x) in p.samples.iter_mut().enumerate() {
                let t = p.time - (n - 1 - k) as f64 / 256.0;
                *x += (FAULT_UV * (std::f64::consts::TAU * 3.0 * t).sin()) as f32;
            }
        }
        Some((packets, optical, accel))
    }

    /// Artifact detector, recorder (recording continues while paused), optics.
    fn route_side_streams(&mut self, packets: &[EegPacket], optical: &[PpgPacket], accel: &[AccelPacket]) {
        if let Some(a) = self.live.artifacts.as_mut() {
            accel.iter().for_each(|p| a.accel(p));
            packets.iter().for_each(|p| a.eeg(p));
        }
        if let Some(r) = self.live.recorder.as_mut() {
            optical.iter().for_each(|p| r.ppg(p));
            accel.iter().for_each(|p| r.accel(p));
        }
        if self.streaming() {
            optical.iter().for_each(|p| self.live.streamer.ppg(p));
            accel.iter().for_each(|p| self.live.streamer.accel(p));
        }
        if !self.state.paused {
            if let Some(o) = self.live.optics.as_mut() {
                optical.iter().for_each(|p| o.push(p));
            }
        }
    }

    /// Record and condition EEG into band snapshots. Returns true when the
    /// recorder hit its size limit.
    fn process_eeg(&mut self, packets: &mut [EegPacket]) -> bool {
        let mut full = false;
        for p in packets.iter() {
            if let Some(r) = self.live.recorder.as_mut() {
                full |= !r.eeg(p);
            }
            if self.state.paused {
                continue;
            }
            let Some(sig) = self.live.signal.as_mut() else { continue };
            let before = sig.applied();
            let snap = sig.push(p);
            if self.state.streaming.settings.enabled {
                let ch = usize::from(p.electrode);
                self.live.streamer.eeg(ch, p.time, &sig.last(ch, p.samples.len(), true));
            }
            let (after, detected) = (sig.applied(), sig.detected());
            if after != before {
                self.emit(Event::MainsChanged { applied: mains_name(after).into(), detected: mains_name(detected).into() });
            }
            let Some(snap) = snap else { continue };
            if self.state.streaming.settings.enabled {
                self.live.streamer.bands(&snap);
            }
            if let Some(r) = self.live.recorder.as_mut() {
                r.bands(&snap);
            }
            if let Some(a) = self.live.artifacts.as_mut() {
                a.gamma(&snap.powers);
            }
            self.state.bands.push(snap);
        }
        full
    }

    /// Streaming is on and a device is connected (syncs the streamer).
    fn streaming(&mut self) -> bool {
        let s = &self.state.streaming.settings;
        let transport = match s.protocol {
            crate::streaming::StreamProtocol::Osc => self.sink.is_some(),
            crate::streaming::StreamProtocol::Lsl => self.outlets.is_some(),
        };
        match (&self.state.device, s.enabled && transport) {
            (Some(d), true) => {
                self.live.streamer.sync(d, s);
                true
            }
            _ => false,
        }
    }

    /// Open, reopen or close the LSL outlets to match settings and device.
    fn sync_lsl(&mut self) {
        let st = &mut self.state.streaming;
        let Some(outlets) = self.outlets.as_mut() else { return };
        let s = &st.settings;
        let want = match &self.state.device {
            Some(d) if s.enabled && s.protocol == crate::streaming::StreamProtocol::Lsl => Some((d.id.clone(), s.separate_groups)),
            _ => None,
        };
        if want != self.lsl_open {
            outlets.close();
            if want.is_some() {
                let specs = crate::streaming::outlet_specs(self.state.device.as_ref(), s.separate_groups);
                if let Err(e) = outlets.open(&specs) {
                    st.stats.last_error = Some(e);
                }
            }
            self.lsl_open = want;
        }
        st.stats.lsl_consumers = if self.lsl_open.is_some() { outlets.consumers() } else { 0 };
    }

    /// Push complete chunks to the LSL outlets.
    fn flush_lsl(&mut self) {
        let (rows, dropped) = self.live.streamer.take_rows();
        let st = &mut self.state.streaming;
        st.stats.dropped_samples += dropped;
        let Some(o) = self.outlets.as_mut().filter(|_| self.lsl_open.is_some()) else { return };
        for (i, v) in rows {
            match o.push(i, &v) {
                Ok(()) => {
                    st.stats.packets_sent += 1;
                    st.stats.bytes_sent += 4 * v.len() as u64;
                }
                Err(e) => st.stats.last_error = Some(e),
            }
        }
    }

    /// Hand encoded OSC datagrams to the shell's sink (or rows to LSL).
    fn flush_stream(&mut self) {
        if self.state.streaming.settings.protocol == crate::streaming::StreamProtocol::Lsl {
            self.sync_lsl();
            return self.flush_lsl();
        }
        let (out, dropped) = self.live.streamer.take();
        let st = &mut self.state.streaming;
        st.stats.dropped_samples += dropped;
        let Some(sink) = self.sink.as_mut().filter(|_| st.settings.enabled) else { return };
        for d in out {
            match sink.send(&st.settings.ip, st.settings.port, &d) {
                Ok(()) => {
                    st.stats.packets_sent += 1;
                    st.stats.bytes_sent += d.len() as u64;
                }
                Err(e) => st.stats.last_error = Some(e),
            }
        }
    }

    /// Trust trace of a saved session.
    pub fn history_trust(&self, id: u64) -> Result<crate::trust::Trust, CoreError> {
        let s = self.stored(id)?;
        let records = nf_format::parse_body(&s.body).map_err(|e| CoreError::BadRequest(e.0))?;
        let marks = crate::trust::marks(s.meta.import.as_ref());
        Ok(crate::trust::build(crate::trust::rows_from_records(&records), marks))
    }

    /// Register the LSL outlet transport (desktop shells).
    pub fn set_stream_outlets(&mut self, outlets: Box<dyn nf_types::StreamOutlets>) {
        self.outlets = Some(outlets);
        self.state.streaming.lsl_transport = true;
    }

    /// Register the network transport for streaming out (desktop shells).
    pub fn set_stream_sink(&mut self, sink: Box<dyn crate::streaming::DatagramSink>) {
        self.sink = Some(sink);
        self.state.streaming.transport = true;
    }

    /// Run the feedback state machine for every whole second up to `now`.
    fn feedback_tick(&mut self, now: f64) {
        while self.state.feedback.phase.active() && now + 1e-9 >= self.live.fb_next {
            let t = self.live.fb_next;
            self.live.fb_next += 1.0;
            let mut obs = self.observation(t);
            obs.ai = self.state.ai.value_at(self.state.time);
            if let Some(a) = self.live.artifacts.as_mut() {
                obs.artifact = a.second(t);
                if let (Some(r), Some(s)) = (self.live.recorder.as_mut(), a.status.movement_score) {
                    r.movement(t, s);
                }
            }
            let mut out = Vec::new();
            let n = self.state.feedback.results.len();
            self.state.feedback.second(t, &obs, &mut out);
            if let Some(r) = self.live.recorder.as_mut() {
                self.state.feedback.results[n..].iter().for_each(|x| r.feedback(x));
            }
            self.changes(out);
        }
    }

    fn changes(&mut self, out: Vec<Change>) {
        if self.live.auto_recording && out.contains(&Change::Phase(Phase::Ended)) {
            self.stop_recording("feedback ended");
        }
        for c in out {
            self.emit(match c {
                Change::Phase(phase) => Event::Feedback { phase },
                Change::Chime => Event::Chime,
                Change::GuardChime => Event::GuardChime,
            });
        }
    }

    fn observation(&self, now: f64) -> Observation {
        let (Some(dev), Some(sig)) = (&self.state.device, &self.live.signal) else { return Observation::default() };
        let fresh = self.live.last_data.is_some_and(|t| now - t <= STALE_S) && sig.bands_linear.len() == dev.channels.len();
        let idx: Vec<usize> = TARGET_PADS
            .iter()
            .find_map(|pair| pair.iter().map(|n| dev.channels.iter().position(|c| c == n)).collect::<Option<Vec<_>>>())
            .unwrap_or_else(|| (0..dev.channels.len()).collect());
        Observation {
            connected: fresh,
            names: idx.iter().map(|&i| dev.channels[i].clone()).collect(),
            pads: idx.iter().map(|&i| sig.bands_linear.get(i).copied().unwrap_or_default()).collect(),
            quality: idx.iter().map(|&i| if fresh { f64::from(sig.quality.get(i).copied().unwrap_or(0.0)) } else { 0.0 }).collect(),
            artifact: None,
            ai: None,
        }
    }

    /// Apply a feedback transition; emits its events.
    fn feedback<T>(&mut self, f: impl FnOnce(&mut crate::feedback::Trainer, &mut Vec<Change>) -> T) -> T {
        let mut out = Vec::new();
        let r = f(&mut self.state.feedback, &mut out);
        self.changes(out);
        r
    }

    /// Typed access for views.
    pub fn trainer(&self) -> &crate::feedback::Trainer {
        &self.state.feedback
    }

    fn start_recording(&mut self, wall_clock_unix_ms: Option<f64>) -> Result<(), CoreError> {
        if wall_clock_unix_ms.is_some_and(|t| !t.is_finite() || t < 0.0) {
            return Err(CoreError::InvalidArgs("wall_clock_unix_ms must be a finite, non-negative Unix time".into()));
        }
        let dev = self.state.device.clone().ok_or_else(|| CoreError::Device("no device connected".into()))?;
        let r = Recorder::start(dev, self.state.time, wall_clock_unix_ms);
        self.emit(Event::RecordingStarted { device: r.info.device.clone() });
        self.state.recording = Some(r.info.clone());
        self.live.recorder = Some(r);
        if let Some(sig) = self.live.signal.as_mut() {
            sig.lock(true);
        }
        Ok(())
    }

    fn stop_recording(&mut self, reason: &str) {
        if let Some(r) = self.live.recorder.take() {
            if let Some(sig) = self.live.signal.as_mut() {
                if sig.lock(false) {
                    let (a, d) = (mains_name(sig.applied()).into(), mains_name(sig.detected()).into());
                    self.emit(Event::MainsChanged { applied: a, detected: d });
                }
            }
            let f = r.finish();
            self.emit(Event::RecordingStopped { duration: f.info.duration, eeg_samples: f.info.eeg_samples, reason: reason.into() });
            self.state.recording = Some(f.info.clone());
            self.live.auto_recording = false;
            self.save(&f);
            self.live.finished = Some(f);
        }
    }

    fn emit(&mut self, e: Event) {
        if self.events.len() >= MAX_EVENTS {
            self.events.remove(0);
        }
        self.events.push(e);
    }

    /// Parse and run a tool call by name.
    pub fn call(&mut self, id: &str, params: serde_json::Value) -> Result<Reply, CoreError> {
        let req = Request::parse(id, params)?;
        self.run(req)
    }

    pub fn run(&mut self, req: Request) -> Result<Reply, CoreError> {
        match req {
            Request::Command(c) => self.execute(c),
            Request::Query(q) => {
                let id = Request::Query(q.clone()).id();
                if let Err(reason) = self.enabled(&id) {
                    return Err(CoreError::Disabled { id, reason });
                }
                self.query(&q)
            }
        }
    }

    /// Run a command. Checks `enabled` first; a failing command leaves
    /// state unchanged. Bumps `revision` on success (except clock/events).
    pub fn execute(&mut self, cmd: Command) -> Result<Reply, CoreError> {
        let id = Request::Command(cmd.clone()).id();
        if let Err(reason) = self.enabled(&id) {
            return Err(CoreError::Disabled { id, reason });
        }
        let bumps = !matches!(cmd, Command::ClockAdvance { .. } | Command::EventsDrain);
        let reply = self.apply(cmd)?;
        if bumps {
            self.persist_settings();
            self.state.revision += 1;
        }
        Ok(reply)
    }

    // Flat dispatch match: one short arm per command (AGENTS.md, complexity exception).
    #[allow(clippy::too_many_lines)]
    fn apply(&mut self, cmd: Command) -> Result<Reply, CoreError> {
        match cmd {
            Command::ViewSet { view } => {
                if self.state.view != view {
                    self.state.view = view;
                    self.emit(Event::ViewChanged { view });
                }
            }
            Command::SidebarSet { open } => self.state.sidebar_open = open,
            Command::StreamPause | Command::StreamResume => {
                let paused = matches!(cmd, Command::StreamPause);
                if self.state.paused != paused {
                    self.state.paused = paused;
                    self.emit(Event::Paused { paused });
                }
            }
            Command::ScaleSet { scale } => {
                self.state.band_scale = scale;
                self.emit(Event::ScaleChanged { scale });
            }
            Command::DeviceConnect { id } => self.connect(&id)?,
            Command::DeviceDisconnect => self.disconnect(),
            Command::DeviceScan { seconds } => {
                let secs = seconds.unwrap_or(8.0);
                if !(1.0..=60.0).contains(&secs) {
                    return Err(CoreError::InvalidArgs("seconds must be in [1, 60]".into()));
                }
                let mut started = Vec::new();
                let mut errors = Vec::new();
                for p in self.providers.iter_mut().filter(|p| p.can_scan()) {
                    match p.scan(secs) {
                        Ok(()) => started.push(p.scheme()),
                        Err(e) => errors.push(format!("{}: {e}", p.scheme())),
                    }
                }
                if started.is_empty() {
                    return Err(CoreError::Device(errors.join("; ")));
                }
                return Ok(json!({ "scanning": started, "seconds": secs, "errors": errors }));
            }
            Command::SimConfigure { seed, alpha_uv, noise_uv, mains_uv, mains_hz, dc_uv, hr_bpm, spo2_pct, hrv_ms } => {
                let check = |name: &str, v: Option<f64>, lo: f64, hi: f64| match v {
                    Some(x) if !(x.is_finite() && (lo..=hi).contains(&x)) => {
                        Err(CoreError::InvalidArgs(format!("{name} must be in [{lo}, {hi}]")))
                    }
                    _ => Ok(()),
                };
                check("alpha_uv", alpha_uv, 0.0, 200.0)?;
                check("noise_uv", noise_uv, 0.0, 200.0)?;
                check("mains_uv", mains_uv, 0.0, 1000.0)?;
                check("dc_uv", dc_uv, -5000.0, 5000.0)?;
                check("hr_bpm", hr_bpm, 40.0, 180.0)?;
                check("spo2_pct", spo2_pct, 80.0, 100.0)?;
                check("hrv_ms", hrv_ms, 0.0, 150.0)?;
                if mains_hz.is_some_and(|h| h != 50.0 && h != 60.0) {
                    return Err(CoreError::InvalidArgs("mains_hz must be 50 or 60".into()));
                }
                let c = &mut self.sim.config;
                c.seed = seed.unwrap_or(c.seed);
                c.alpha_uv = alpha_uv.unwrap_or(c.alpha_uv);
                c.noise_uv = noise_uv.unwrap_or(c.noise_uv);
                c.mains_uv = mains_uv.unwrap_or(c.mains_uv);
                c.mains_hz = mains_hz.unwrap_or(c.mains_hz);
                c.dc_uv = dc_uv.unwrap_or(c.dc_uv);
                c.hr_bpm = hr_bpm.unwrap_or(c.hr_bpm);
                c.spo2_pct = spo2_pct.unwrap_or(c.spo2_pct);
                c.hrv_ms = hrv_ms.unwrap_or(c.hrv_ms);
                let reconnect = self.state.device.as_ref().filter(|d| d.simulated).map(|d| d.id.clone());
                if let Some(id) = reconnect {
                    self.connect(&id)?;
                }
                return Ok(serde_json::to_value(self.sim.config).unwrap_or_default());
            }
            Command::AudioSet(patch) => return crate::audio::set(&mut self.state, &patch),
            Command::StreamingSet(patch) => return crate::streaming::set(&mut self.state.streaming, &patch),
            cmd @ (Command::AiSet(_)
            | Command::AiInstall { .. }
            | Command::AiLoad { .. }
            | Command::AiUnload
            | Command::AiRemove { .. }) => return self.ai_apply(cmd),
            Command::HistoryImport(req) => return self.history_import(&req),
            Command::GuardSet { enabled } => {
                self.state.feedback.guard = enabled;
                return Ok(crate::audio::guard_status(&self.state));
            }
            Command::StabilitySet { window, difficulty, reset } => {
                use nf_feedback::StabilityConfig as S;
                if window.is_some_and(|w| !(S::MIN_WINDOW..=S::MAX_WINDOW).contains(&w)) {
                    return Err(CoreError::InvalidArgs(format!("window must be in [{}, {}]", S::MIN_WINDOW, S::MAX_WINDOW)));
                }
                if difficulty.is_some_and(|d| !(0.0..=S::MAX_DIFFICULTY).contains(&d)) {
                    return Err(CoreError::InvalidArgs(format!("difficulty must be in [0, {}]", S::MAX_DIFFICULTY)));
                }
                let st = &mut self.state.feedback.stability;
                if reset {
                    *st = S::default();
                }
                st.window = window.unwrap_or(st.window);
                st.difficulty = difficulty.unwrap_or(st.difficulty);
                let v = json!(*st);
                return Ok(v);
            }
            Command::ProtocolSet { id, minutes } => {
                let p = crate::protocols::find(&self.state.custom_protocols, &id)
                    .ok_or_else(|| CoreError::InvalidArgs(format!("unknown protocol `{id}`")))?;
                let (lo, hi) = crate::feedback::MINUTES;
                if minutes.is_some_and(|m| !(lo..=hi).contains(&m)) {
                    return Err(CoreError::InvalidArgs(format!("minutes must be in [{lo}, {hi}]")));
                }
                let fb = &mut self.state.feedback;
                if fb.protocol.id != p.id || minutes.is_some() {
                    fb.minutes = minutes.unwrap_or(p.default_minutes);
                }
                fb.protocol = p;
                fb.summary = None;
            }
            Command::FeedbackStart { minutes, wall_clock_unix_ms } => {
                let (lo, hi) = crate::feedback::MINUTES;
                if let Some(m) = minutes {
                    if !(lo..=hi).contains(&m) {
                        return Err(CoreError::InvalidArgs(format!("minutes must be in [{lo}, {hi}]")));
                    }
                    self.state.feedback.minutes = m;
                }
                let dev = self.state.device.as_ref().map(|d| d.id.clone()).unwrap_or_default();
                self.live.fb_next = self.state.time + 1.0;
                self.feedback(|t, o| t.start(&dev, o));
                // Every training is recorded (legacy behaviour); a manual
                // recording already running is kept as is.
                if self.live.recorder.is_none() && self.state.feedback.phase.active() {
                    self.start_recording(wall_clock_unix_ms)?;
                    self.live.auto_recording = true;
                }
            }
            Command::FeedbackStop => self.feedback(|t, o| t.stop("stopped", o)),
            Command::FeedbackPause => self.feedback(|t, o| t.pause(o)),
            Command::FeedbackResume => self.feedback(|t, o| t.resume(o)),
            Command::CalibrationStart { anyway } => {
                if !anyway && !self.state.feedback.fit_ready() {
                    let bad: Vec<String> = self.state.feedback.pads.iter().filter(|p| !p.good).map(|p| p.name.clone()).collect();
                    return Err(CoreError::InvalidArgs(format!(
                        "fit check not passed (needs {} s of good signal{}); pass anyway=true to start anyway",
                        crate::feedback::FIT_GREEN_S,
                        if bad.is_empty() { String::new() } else { format!("; check {}", bad.join(", ")) }
                    )));
                }
                self.feedback(|t, o| t.calibrate(o));
            }
            Command::CalibrationSkip => self.feedback(|t, o| t.finish_calibration(o)).map_err(CoreError::InvalidArgs)?,
            Command::CalibrationReuse => self.feedback(|t, o| t.reuse(o)).map_err(CoreError::InvalidArgs)?,
            Command::ThresholdSet { percentile } => {
                if !(1..=99).contains(&percentile) {
                    return Err(CoreError::InvalidArgs("percentile must be in [1, 99]".into()));
                }
                let thr = self.state.feedback.set_percentile(percentile);
                return Ok(json!({ "percentile": percentile, "threshold": thr }));
            }
            Command::SimFault { bad_pads, dropout, motion, blink, clench, drowsy } => {
                let chans = self.state.device.as_ref().map(|d| d.channels.clone()).unwrap_or_default();
                let bad = bad_pads
                    .iter()
                    .map(|n| chans.iter().position(|c| c == n).ok_or_else(|| CoreError::InvalidArgs(format!("unknown pad `{n}`"))))
                    .collect::<Result<Vec<_>, _>>()?;
                self.live.fault = Fault { bad, dropout, motion, blink, clench, drowsy };
            }
            Command::ClockAdvance { seconds } => {
                if !(seconds.is_finite() && seconds > 0.0 && seconds <= MAX_ADVANCE_S) {
                    return Err(CoreError::InvalidArgs(format!("seconds must be in (0, {MAX_ADVANCE_S}]")));
                }
                let steps = (seconds / STEP_S).round().max(1.0) as u64;
                let target = self.state.time + seconds;
                for _ in 0..steps {
                    self.advance(seconds / steps as f64);
                }
                self.state.time = target; // no float drift
                return Ok(json!({ "time": self.state.time }));
            }
            Command::EventsDrain => return Ok(serde_json::to_value(self.drain_events()).unwrap_or_default()),
            Command::RecordingStart { wall_clock_unix_ms } => self.start_recording(wall_clock_unix_ms)?,
            Command::ProtocolSave { draft, replace } => return self.protocol_save(&draft, replace),
            Command::ProtocolDelete { id, confirm } => self.protocol_delete(&id, confirm)?,
            Command::HistoryDelete { id, confirm } => {
                if !confirm {
                    return Err(CoreError::InvalidArgs("deleting is permanent; pass confirm=true".into()));
                }
                if !self.store.delete(id).map_err(|e| CoreError::BadRequest(e.to_string()))? {
                    return Err(CoreError::InvalidArgs(format!("no session {id}")));
                }
                self.refresh_history();
            }
            Command::SettingsSet(p) => crate::settings::apply(&mut self.state.settings, &p).map_err(CoreError::InvalidArgs)?,
            Command::HistoryNotes { id, notes } => self.set_notes(id, &notes)?,
            Command::MainsSet { mode } => {
                self.state.mains_mode = mode;
                if let Some(sig) = self.live.signal.as_mut() {
                    if sig.set_mode(mode) {
                        let (a, d) = (mains_name(sig.applied()).into(), mains_name(sig.detected()).into());
                        self.emit(Event::MainsChanged { applied: a, detected: d });
                    }
                }
                return Ok(self.signal_status());
            }
            Command::ChannelSet { channel } => {
                let names = self.state.device.as_ref().map(|d| d.channels.clone()).unwrap_or_default();
                let i = names
                    .iter()
                    .position(|n| *n == channel)
                    .ok_or_else(|| CoreError::InvalidArgs(format!("unknown channel `{channel}`; have {}", names.join(", "))))?;
                self.state.channel = i;
            }
            Command::RecordingStop => {
                self.stop_recording("stopped");
                return Ok(serde_json::to_value(&self.state.recording).unwrap_or_default());
            }
        }
        Ok(json!({ "ok": true }))
    }

    fn open(&mut self, id: &str) -> Result<Box<dyn DeviceSource>, CoreError> {
        let scheme = id.split(':').next().unwrap_or_default();
        if scheme == self.sim.scheme() {
            return self.sim.open(id).map_err(CoreError::Device);
        }
        match self.providers.iter_mut().find(|p| p.scheme() == scheme) {
            Some(p) => p.open(id).map_err(CoreError::Device),
            None => Err(CoreError::Device(format!("no provider for `{id}`"))),
        }
    }

    fn connect(&mut self, id: &str) -> Result<(), CoreError> {
        let src = self.open(id)?; // fails before touching state
        self.disconnect();
        let info = src.info();
        self.live.signal = Some(Signal::new(&info, self.state.mains_mode));
        self.live.optics = crate::optics::Optics::new(&info);
        self.live.artifacts = Some(crate::artifacts::Artifacts::new(&info));
        self.emit(Event::Connected { id: info.id.clone() });
        self.state.link = Some(src.link());
        self.state.device = Some(info);
        self.source = Some(src);
        Ok(())
    }

    fn disconnect(&mut self) {
        self.stop_recording("device disconnected");
        self.source = None;
        self.state.link = None;
        self.live.signal = None;
        self.live.optics = None;
        self.live.artifacts = None;
        self.state.bands.clear();
        if let Some(d) = self.state.device.take() {
            self.emit(Event::Disconnected { id: d.id });
        }
    }

    // Flat dispatch match: one short arm per query (AGENTS.md, complexity exception).
    #[allow(clippy::too_many_lines)]
    pub fn query(&self, q: &Query) -> Result<Reply, CoreError> {
        let s = &self.state;
        Ok(match q {
            Query::AppStatus => json!({
                "view": s.view,
                "sidebar_open": s.sidebar_open,
                "paused": s.paused,
                "scale": s.band_scale,
                "device": s.device.as_ref().map(|d| &d.id),
                "time": s.time,
                "revision": s.revision,
            }),
            Query::ProtocolList => json!(crate::protocols::all(&s.custom_protocols)
                .iter()
                .map(|p| json!({ "protocol": p, "selected": p.id == s.feedback.protocol.id }))
                .collect::<Vec<_>>()),
            Query::ProtocolGet { id } => {
                let p = match id {
                    Some(id) => crate::protocols::find(&s.custom_protocols, id)
                        .ok_or_else(|| CoreError::InvalidArgs(format!("unknown protocol `{id}`")))?,
                    None => s.feedback.protocol.clone(),
                };
                json!(p)
            }
            Query::ProtocolDraft { id } => {
                let p = match id {
                    Some(id) => crate::protocols::find(&s.custom_protocols, id)
                        .ok_or_else(|| CoreError::InvalidArgs(format!("unknown protocol `{id}`")))?,
                    None => s.feedback.protocol.clone(),
                };
                let (draft, notes) = crate::protocols::to_draft(&p);
                json!({ "draft": draft, "notes": notes })
            }
            Query::ProtocolValidate { draft, replace } => {
                let problems = crate::protocols::validate(draft, &s.custom_protocols, *replace);
                json!({ "ok": problems.is_empty(), "problems": problems })
            }
            Query::AudioStatus => crate::audio::status(s),
            Query::FeedbackTrust => json!(crate::trust::build(crate::trust::rows_from_results(&s.feedback.results), Vec::new())),
            Query::HistoryTrust { id } => json!(self.history_trust(*id)?),
            Query::AiStatus => crate::ai::status_json(&s.ai),
            Query::StreamingStatus => crate::streaming::status(&s.streaming, s.device.as_ref()),
            Query::HistoryImportPreview(req) => json!(self.import_prepare(req)?.preview()),
            Query::FeedbackStatus => {
                let f = &s.feedback;
                json!({
                    "protocol": f.protocol.id,
                    "minutes": f.minutes,
                    "percentile": f.percentile,
                    "stability": f.stability,
                    "phase": f.phase,
                    "fit": { "pads": f.pads, "green_s": f.green_for, "ready": f.fit_ready() },
                    "calibration": f.calibration,
                    "last_baseline": f.last_baseline().map(|b| json!({ "valid_s": b.valid_seconds, "wall_s": b.wall_seconds })),
                    "threshold": f.threshold(),
                    "played_s": f.played_s,
                    "total_s": f.total_s(),
                    "last": f.last(),
                    "summary": f.summary,
                    "message": f.message,
                })
            }
            Query::FeedbackResultGet { last } => {
                let r = &s.feedback.results;
                let n = last.unwrap_or(r.len()).min(r.len());
                json!(&r[r.len() - n..])
            }
            Query::ViewList => json!(View::ALL
                .iter()
                .map(|v| json!({ "id": v, "label": v.label(), "implemented": v.implemented(), "active": *v == s.view }))
                .collect::<Vec<_>>()),
            Query::FeedbackNerd => serde_json::to_value(crate::nerd::build(&s.feedback, s.time)).unwrap_or_default(),
            Query::SettingsGet => serde_json::to_value(crate::settings::Persisted::of(s)).unwrap_or_default(),
            Query::BandsGet { scale } => self.bands_json(scale.unwrap_or(s.band_scale)),
            Query::DeviceList => serde_json::to_value(self.device_list()).unwrap_or_default(),
            Query::DeviceStatus => json!({
                "connected": s.device.is_some(),
                "link": s.link,
                "scanning": self.scanning(),
                "provider_errors": self.provider_errors(),
                "device": s.device,
                "snapshots": s.bands.len(),
                "paused": s.paused,
            }),
            Query::RawGet { seconds, filtered } => self.raw_json(seconds.unwrap_or(1.0), filtered.unwrap_or(true))?,
            Query::PsdGet { channel, max_hz } => self.psd_json(channel.as_deref(), max_hz.unwrap_or(50.0))?,
            Query::HrGet => self.estimate_json(true)?,
            Query::Spo2Get => self.estimate_json(false)?,
            Query::PpgGet { seconds } => self.ppg_json(seconds.unwrap_or(5.0))?,
            Query::SignalStatus => self.signal_status(),
            Query::ArtifactStatus => {
                json!({ "connected": self.live.artifacts.is_some(), "status": self.live.artifacts.as_ref().map(|a| &a.status) })
            }
            Query::FeaturesGet => self.features_json()?,
            Query::HistogramGet { seconds, bins, half_range_uv } => {
                self.histogram_json(seconds.unwrap_or(2.0), bins.unwrap_or(64), half_range_uv.unwrap_or(100.0))?
            }
            Query::SpectrogramGet { channel, max_hz } => self.spectrogram_json(channel.as_deref(), max_hz.unwrap_or(50.0))?,
            Query::RecordingStatus => json!({ "recording": s.recording }),
            Query::HistoryList => json!({ "location": self.state.history_location, "sessions": self.state.history }),
            Query::HistoryGet { id } => {
                let s = self.stored(*id)?;
                let records = nf_format::parse_body(&s.body).map_err(|e| CoreError::BadRequest(e.0))?;
                let feedback: Vec<_> = records
                    .iter()
                    .filter_map(|r| match r {
                        nf_format::Record::Feedback { ts, value, threshold, flags } => {
                            Some(json!({ "t": ts, "value": finite(*value), "threshold": finite(*threshold), "flags": flags }))
                        }
                        _ => None,
                    })
                    .collect();
                json!({ "meta": s.meta, "device": serde_json::from_str::<serde_json::Value>(&s.device_json).unwrap_or_default(), "records": records.len(), "feedback": feedback })
            }
            Query::HistoryExport { id, format } => {
                let bytes = self.history_export(*id, *format)?;
                json!({ "id": id, "format": format, "extension": format.extension(), "bytes": bytes.len(), "base64": base64(&bytes) })
            }
            Query::RecordingExport { format, start } => {
                let f = self.live.finished.as_ref().ok_or_else(|| CoreError::BadRequest("nothing recorded yet".into()))?;
                let start = match (start, f.info.wall_clock_unix_ms) {
                    (Some([y, mo, d, h, mi, se]), _) => (*y, *mo, *d, *h, *mi, *se),
                    (None, Some(ms)) => crate::recording::civil_utc(ms),
                    (None, None) => (1985, 1, 1, 0, 0, 0),
                };
                let bytes = export(f, *format, start).map_err(CoreError::BadRequest)?;
                json!({
                    "format": format,
                    "extension": format.extension(),
                    "bytes": bytes.len(),
                    "base64": base64(&bytes),
                })
            }
        })
    }

    /// Typed read access for views: connected device and its signal path.
    pub fn live_signal(&self) -> Option<(&nf_types::DeviceInfo, &Signal)> {
        self.signal().ok()
    }

    /// Typed read access for the HR+SpO2 view.
    pub fn optics(&self) -> Option<&crate::optics::Optics> {
        self.live.optics.as_ref()
    }

    fn optics_or_err(&self) -> Result<&crate::optics::Optics, CoreError> {
        self.live.optics.as_ref().ok_or_else(|| CoreError::Device("connected device has no PPG (HR/SpO2: Muse 2 and Muse S only)".into()))
    }

    fn estimate_json(&self, hr: bool) -> Result<Reply, CoreError> {
        let o = self.optics_or_err()?;
        let h = if hr { &o.hr } else { &o.spo2 };
        let cur = crate::optics::Optics::current(h, o.time);
        Ok(json!({
            "time": o.time,
            "unit": if hr { "bpm" } else { "%" },
            "value": cur.map(|e| e.value),
            "confidence": cur.map(|e| e.confidence),
            "history": h.iter().map(|e| [e.time, e.value]).collect::<Vec<_>>(),
        }))
    }

    fn ppg_json(&self, seconds: f64) -> Result<Reply, CoreError> {
        if !(seconds.is_finite() && seconds > 0.0 && seconds <= crate::optics::PPG_BUFFER_S) {
            return Err(CoreError::InvalidArgs(format!("seconds must be in (0, {}]", crate::optics::PPG_BUFFER_S)));
        }
        let o = self.optics_or_err()?;
        let names = self.state.device.as_ref().map(|d| d.ppg_channels.clone()).unwrap_or_default();
        let n = (seconds * o.rate).round() as usize;
        let channels: Vec<_> = names.iter().enumerate().map(|(i, c)| json!({ "channel": c, "samples": o.last(i, n) })).collect();
        Ok(json!({ "time": o.time, "rate_hz": o.rate, "unit": "counts", "channels": channels }))
    }

    fn channel_index(dev: &nf_types::DeviceInfo, channel: Option<&str>) -> Result<Option<usize>, CoreError> {
        channel
            .map(|c| {
                dev.channels
                    .iter()
                    .position(|n| n == c)
                    .ok_or_else(|| CoreError::InvalidArgs(format!("unknown channel `{c}`; have {}", dev.channels.join(", "))))
            })
            .transpose()
    }

    fn signal_status(&self) -> Reply {
        let Ok((dev, sig)) = self.signal() else {
            return json!({ "connected": false, "mains_mode": self.state.mains_mode });
        };
        let pads: Vec<_> = dev
            .channels
            .iter()
            .enumerate()
            .map(|(i, n)| json!({ "channel": n, "quality": sig.quality[i], "usable": sig.usable(i), "line_noise": sig.line_noise[i] }))
            .collect();
        json!({
            "connected": true,
            "time": sig.time,
            "mains_mode": sig.mode(),
            "mains_detected": mains_name(sig.detected()),
            "mains_applied": mains_name(sig.applied()),
            "notch_locked": sig.locked(),
            "usable_threshold": nf_dsp::USABLE_QUALITY,
            "pads": pads,
        })
    }

    fn features_json(&self) -> Result<Reply, CoreError> {
        let (dev, sig) = self.signal()?;
        let usable: Vec<usize> = (0..dev.channels.len()).filter(|&i| sig.usable(i)).collect();
        let mut out = serde_json::Map::new();
        for id in nf_dsp::FEATURE_IDS {
            let vals: Vec<f64> = usable.iter().filter_map(|&i| nf_dsp::band_feature(id, &sig.bands_linear[i])).collect();
            let mean = (!vals.is_empty()).then(|| vals.iter().sum::<f64>() / vals.len() as f64);
            out.insert(id.into(), json!(mean));
        }
        let names: Vec<_> = usable.iter().map(|&i| &dev.channels[i]).collect();
        Ok(json!({ "time": sig.time, "usable_pads": names, "features": out }))
    }

    fn histogram_json(&self, seconds: f64, bins: usize, half_range: f64) -> Result<Reply, CoreError> {
        if !(seconds.is_finite() && seconds > 0.0 && seconds <= crate::signal::BUFFER_S) {
            return Err(CoreError::InvalidArgs(format!("seconds must be in (0, {}]", crate::signal::BUFFER_S)));
        }
        if !(2..=512).contains(&bins) || !(half_range.is_finite() && (1.0..=10_000.0).contains(&half_range)) {
            return Err(CoreError::InvalidArgs("bins must be in [2, 512], half_range_uv in [1, 10000]".into()));
        }
        let (dev, sig) = self.signal()?;
        let n = (seconds * sig.rate).round() as usize;
        let channels: Vec<_> = dev
            .channels
            .iter()
            .enumerate()
            .map(|(i, name)| json!({ "channel": name, "counts": nf_dsp::histogram(&sig.last(i, n, true), bins, half_range) }))
            .collect();
        Ok(json!({ "time": sig.time, "bins": bins, "half_range_uv": half_range, "unit": "uV", "channels": channels }))
    }

    fn spectrogram_json(&self, channel: Option<&str>, max_hz: f64) -> Result<Reply, CoreError> {
        if !(max_hz.is_finite() && (1.0..=nf_dsp::MAX_PSD_HZ).contains(&max_hz)) {
            return Err(CoreError::InvalidArgs(format!("max_hz must be in [1, {}]", nf_dsp::MAX_PSD_HZ)));
        }
        let (dev, sig) = self.signal()?;
        let i = Self::channel_index(dev, channel)?.unwrap_or(self.state.channel);
        let df = 1.0 / crate::signal::WINDOW_S;
        let keep = (max_hz / df).floor() as usize + 1;
        let cols: Vec<_> = sig.spectrogram[i].iter().map(|c| &c[..keep.min(c.len())]).collect();
        Ok(
            json!({ "time": sig.time, "channel": dev.channels[i], "hop_s": SPEC_HOP_S, "df_hz": df, "unit": "dB re uV^2/Hz", "columns": cols }),
        )
    }

    fn signal(&self) -> Result<(&nf_types::DeviceInfo, &Signal), CoreError> {
        match (&self.state.device, &self.live.signal) {
            (Some(d), Some(s)) => Ok((d, s)),
            _ => Err(CoreError::Device("no device connected".into())),
        }
    }

    fn raw_json(&self, seconds: f64, filtered: bool) -> Result<Reply, CoreError> {
        if !(seconds.is_finite() && seconds > 0.0 && seconds <= crate::signal::BUFFER_S) {
            return Err(CoreError::InvalidArgs(format!("seconds must be in (0, {}]", crate::signal::BUFFER_S)));
        }
        let (dev, sig) = self.signal()?;
        let n = (seconds * sig.rate).round() as usize;
        let channels: Vec<_> =
            dev.channels.iter().enumerate().map(|(i, name)| json!({ "channel": name, "samples": sig.last(i, n, filtered) })).collect();
        Ok(json!({ "time": sig.time, "rate_hz": sig.rate, "filtered": filtered, "unit": "uV", "channels": channels }))
    }

    fn psd_json(&self, channel: Option<&str>, max_hz: f64) -> Result<Reply, CoreError> {
        if !(max_hz.is_finite() && (1.0..=nf_dsp::MAX_PSD_HZ).contains(&max_hz)) {
            return Err(CoreError::InvalidArgs(format!("max_hz must be in [1, {}]", nf_dsp::MAX_PSD_HZ)));
        }
        let (dev, sig) = self.signal()?;
        Self::channel_index(dev, channel)?;
        let w = sig.window_len();
        let mut df = None;
        let mut out = Vec::new();
        for (i, name) in dev.channels.iter().enumerate().filter(|(_, n)| channel.is_none_or(|c| c == n.as_str())) {
            let Some(p) = nf_dsp::psd(&sig.last(i, w, true), sig.rate) else { continue };
            let keep = ((max_hz / p.df).floor() as usize + 1).min(p.power.len());
            df = Some(p.df);
            out.push(json!({
                "channel": name,
                "alpha_peak_hz": nf_dsp::peak_frequency(&p, 8.0, 13.0),
                "power": &p.power[..keep],
            }));
        }
        Ok(json!({ "time": sig.time, "df_hz": df, "unit": "uV^2/Hz", "channels": out }))
    }

    fn bands_json(&self, scale: BandScale) -> Reply {
        let (Some(dev), Some(snap)) = (&self.state.device, self.state.bands.latest()) else {
            return json!({ "time": null, "scale": scale, "channels": [] });
        };
        let channels: Vec<_> = dev
            .channels
            .iter()
            .enumerate()
            .map(|(i, name)| {
                let mut m = serde_json::Map::new();
                m.insert("channel".into(), json!(name));
                for b in Band::ALL {
                    let v = match scale {
                        BandScale::Absolute => snap.power(i, b),
                        BandScale::Relative => snap.relative(i, b),
                    };
                    m.insert(b.name().to_lowercase(), json!(v));
                }
                serde_json::Value::Object(m)
            })
            .collect();
        json!({ "time": snap.time, "scale": scale, "channels": channels })
    }
}

/// Blink bump amplitude (µV) and width (samples) injected by `sim.fault blink`.
const BLINK_UV: f64 = 300.0;
const BLINK_SAMPLES: f64 = 28.0;
/// Jaw-clench EMG (µV at 37 Hz) on temporal pads.
const CLENCH_UV: f64 = 20.0;
/// Drowsy delta (µV at 2 Hz) on every pad.
const DROWSY_UV: f64 = 10.0;
/// Head nod amplitude (g at 2 Hz) on the accelerometer.
const MOTION_G: f64 = 0.3;

/// Simulated artifacts (`sim.fault motion/blink/clench`).
fn inject_artifacts(f: &Fault, dev: &DeviceInfo, eeg: &mut [EegPacket], accel: &mut [nf_types::AccelPacket]) {
    let rate = dev.sample_rate_hz;
    let is = |e: u16, names: &[&str]| dev.channels.get(usize::from(e)).is_some_and(|c| names.contains(&c.as_str()));
    for p in eeg.iter_mut() {
        let (blink, clench) =
            (f.blink && is(p.electrode, &["AF7", "AF8", "F5", "F6"]), f.clench && is(p.electrode, &["TP9", "TP10", "CP3", "CP4"]));
        let n = p.samples.len();
        for (k, x) in p.samples.iter_mut().enumerate() {
            let t = p.time - (n - 1 - k) as f64 / rate;
            if blink {
                // One ~110 ms half-sine bump every 2 s (inside one 125 ms detector bin).
                let i = ((t.rem_euclid(2.0) - 0.38) * rate).round();
                if (0.0..BLINK_SAMPLES).contains(&i) {
                    *x += (BLINK_UV * (std::f64::consts::PI * i / BLINK_SAMPLES).sin()) as f32;
                }
            }
            if clench {
                *x += (CLENCH_UV * (std::f64::consts::TAU * 37.0 * t).sin()) as f32;
            }
        }
    }
    if f.drowsy {
        inject_drowsy(rate, eeg);
    }
    if f.motion {
        let rate = dev.accel_rate_hz.unwrap_or(52.0);
        for p in accel.iter_mut() {
            let n = p.samples.len();
            for (k, s) in p.samples.iter_mut().enumerate() {
                let t = p.time - (n - 1 - k) as f64 / rate;
                s[2] += (MOTION_G * (std::f64::consts::TAU * 2.0 * t).sin()) as f32;
            }
        }
    }
}

fn inject_drowsy(rate: f64, eeg: &mut [EegPacket]) {
    for p in eeg.iter_mut() {
        let n = p.samples.len();
        for (k, x) in p.samples.iter_mut().enumerate() {
            let t = p.time - (n - 1 - k) as f64 / rate;
            *x += (DROWSY_UV * (std::f64::consts::TAU * 2.0 * t).sin()) as f32;
        }
    }
}

fn finite(v: f32) -> Option<f32> {
    v.is_finite().then_some(v)
}
