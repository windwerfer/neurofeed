//! The Session: single owner of state; the only way to change it.

use crate::command::{find, Command, CommandSpec, Query, Request, SPECS};
use crate::state::{AppState, BandScale, View};
use crate::{CoreError, Reply};
use nf_sim::SimProvider;
use nf_types::{Band, BandSource, DeviceProvider};
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
}

pub struct Session {
    state: AppState,
    sim: SimProvider,
    providers: Vec<Box<dyn DeviceProvider>>,
    source: Option<Box<dyn BandSource>>,
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
        let checkpoint = (self.state.clone(), self.sim.config, self.events.len());
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

    fn rollback(&mut self, (state, sim, events): (AppState, nf_sim::SimConfig, usize)) {
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
        if self.state.paused {
            return;
        }
        if let Some(src) = self.source.as_mut() {
            if let Some(s) = src.poll(self.state.time) {
                self.state.bands.push(s);
            }
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
            Request::Query(q) => self.query(&q),
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
            Command::SimConfigure { seed, alpha_gain, noise } => {
                let finite = |v: Option<f32>| v.is_none_or(f32::is_finite);
                if !(finite(alpha_gain) && finite(noise)) {
                    return Err(CoreError::InvalidArgs("alpha_gain/noise must be finite".into()));
                }
                let c = &mut self.sim.config;
                if let Some(s) = seed {
                    c.seed = s;
                }
                if let Some(a) = alpha_gain {
                    c.alpha_gain = a.clamp(0.0, 3.0);
                }
                if let Some(n) = noise {
                    c.noise = n.clamp(0.0, 1.0);
                }
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
        }
        Ok(json!({ "ok": true }))
    }

    fn open(&mut self, id: &str) -> Result<Box<dyn BandSource>, CoreError> {
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
        self.emit(Event::Connected { id: info.id.clone() });
        self.state.device = Some(info);
        self.source = Some(src);
        Ok(())
    }

    fn disconnect(&mut self) {
        self.source = None;
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
        })
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
