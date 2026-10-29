//! The Session: single owner of state; the only way to change it.

use crate::command::{find, Command, CommandSpec, Query, Request, SPECS};
use crate::recording::{base64, export, Finished, Recorder};
use crate::signal::{mains_name, Signal, SPEC_HOP_S};
use crate::state::{AppState, BandScale, View};
use crate::{CoreError, Reply};
use nf_sim::SimProvider;
use nf_types::{Band, DeviceProvider, DeviceSource};
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
    ViewChanged { view: View },
    Connected { id: String },
    Disconnected { id: String },
    Paused { paused: bool },
    ScaleChanged { scale: BandScale },
    RecordingStarted { device: String },
    RecordingStopped { duration: f64, eeg_samples: u64, reason: String },
    MainsChanged { applied: String, detected: String },
}

/// Data-path state that is not plain `AppState` (cloned for batch rollback).
#[derive(Clone, Default)]
struct Live {
    signal: Option<Signal>,
    optics: Option<crate::optics::Optics>,
    recorder: Option<Recorder>,
    finished: Option<Finished>,
}

pub struct Session {
    state: AppState,
    sim: SimProvider,
    providers: Vec<Box<dyn DeviceProvider>>,
    source: Option<Box<dyn DeviceSource>>,
    live: Live,
    events: Vec<Event>,
    /// Last absolute time passed to `tick` (tick works on deltas).
    last_tick: Option<f64>,
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
            live: Live::default(),
            events: Vec::new(),
            last_tick: None,
        }
    }

    /// Add a real device provider (desktop BLE, Android JNI transport, ...).
    pub fn register_provider(&mut self, provider: Box<dyn DeviceProvider>) {
        self.providers.push(provider);
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
        self.state = state;
    }

    pub fn drain_events(&mut self) -> Vec<crate::Event> {
        std::mem::take(&mut self.events)
    }

    /// Feed wall-clock time (seconds, any origin). Advances session time by
    /// the delta since the previous call. Call once per UI frame.
    pub fn tick(&mut self, now: f64) {
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
        let Some(src) = self.source.as_mut() else { return };
        // Always drain the device (no backlog burst on resume); pause only
        // freezes what the views show. Recording continues while paused.
        let packets = src.poll(now);
        let optical = src.poll_ppg(now);
        if !self.state.paused {
            if let Some(o) = self.live.optics.as_mut() {
                optical.iter().for_each(|p| o.push(p));
            }
        }
        let mut full = false;
        for p in &packets {
            if let Some(r) = self.live.recorder.as_mut() {
                full |= !r.eeg(p);
            }
            if self.state.paused {
                continue;
            }
            let Some(sig) = self.live.signal.as_mut() else { continue };
            let before = sig.applied();
            let snap = sig.push(p);
            let (after, detected) = (sig.applied(), sig.detected());
            if after != before {
                self.emit(Event::MainsChanged { applied: mains_name(after).into(), detected: mains_name(detected).into() });
            }
            if let Some(snap) = snap {
                if let Some(r) = self.live.recorder.as_mut() {
                    r.bands(&snap);
                }
                self.state.bands.push(snap);
            }
        }
        if let Some(r) = self.live.recorder.as_mut() {
            r.tick(now);
            self.state.recording = Some(r.info.clone());
        }
        if full {
            self.stop_recording("size limit reached");
        }
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
            self.state.revision += 1;
        }
        Ok(reply)
    }

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
            Command::RecordingStart { wall_clock_unix_ms } => {
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
            }
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
        self.emit(Event::Connected { id: info.id.clone() });
        self.state.device = Some(info);
        self.source = Some(src);
        Ok(())
    }

    fn disconnect(&mut self) {
        self.stop_recording("device disconnected");
        self.source = None;
        self.live.signal = None;
        self.live.optics = None;
        self.state.bands.clear();
        if let Some(d) = self.state.device.take() {
            self.emit(Event::Disconnected { id: d.id });
        }
    }

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
            Query::ViewList => json!(View::ALL
                .iter()
                .map(|v| json!({ "id": v, "label": v.label(), "implemented": v.implemented(), "active": *v == s.view }))
                .collect::<Vec<_>>()),
            Query::BandsGet { scale } => self.bands_json(scale.unwrap_or(s.band_scale)),
            Query::DeviceList => {
                let mut all = self.sim.list();
                for p in &self.providers {
                    all.extend(p.list());
                }
                serde_json::to_value(all).unwrap_or_default()
            }
            Query::DeviceStatus => json!({
                "connected": s.device.is_some(),
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
            Query::FeaturesGet => self.features_json()?,
            Query::HistogramGet { seconds, bins, half_range_uv } => {
                self.histogram_json(seconds.unwrap_or(2.0), bins.unwrap_or(64), half_range_uv.unwrap_or(100.0))?
            }
            Query::SpectrogramGet { channel, max_hz } => self.spectrogram_json(channel.as_deref(), max_hz.unwrap_or(50.0))?,
            Query::RecordingStatus => json!({ "recording": s.recording }),
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
        self.live.optics.as_ref().ok_or_else(|| CoreError::Device("connected device has no PPG".into()))
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
