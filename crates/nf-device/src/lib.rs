//! Real device transports (native only; never in the wasm build).
//!
//! Every transport pushes raw blocks into a [`Feed`] from its own thread;
//! the matching [`LiveSource`] is the [`DeviceSource`] the session polls.
//! The source maps samples onto **session time** (it never reads a clock):
//! a block that arrives at poll time `now` continues its stream's sample
//! timeline, and the timeline re-anchors to `now` when it drifts more than
//! [`REANCHOR_S`] (dropout, clock skew).
//!
//! Providers: [`MuseProvider`] (`muse:<ble id>`, feature `ble`),
//! [`CrownProvider`] (`crown:<device id>`, feature `osc`) and
//! [`PushProvider`] (any scheme; for transports outside Rust such as the
//! Android BLE wrapper, and for tests).

use std::collections::VecDeque;
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};

pub use nf_types::{AccelPacket, DeviceInfo, DeviceKind, DeviceProvider, DeviceSource, EegPacket, LinkState, OpticsPacket, PpgPacket};

#[cfg(feature = "osc")]
mod crown;
#[cfg(feature = "lsl")]
mod lsl;
#[cfg(feature = "ble")]
mod muse;
mod push;
mod udp;
#[cfg(feature = "lsl")]
pub use lsl::LslOutlets;

#[cfg(feature = "osc")]
pub use crown::{CrownProvider, CROWN_OSC_PORT};
#[cfg(feature = "ble")]
pub use muse::{map_muse_event, MuseProvider};
pub use push::{PushHandle, PushProvider};
pub use udp::UdpSink;

/// Re-anchor a stream's timeline when it is this far from the poll time.
pub const REANCHOR_S: f64 = 0.5;

/// Muse/Crown EEG channel names.
pub const MUSE_CHANNELS: [&str; 4] = ["TP9", "AF7", "AF8", "TP10"];
/// Muse auxiliary inputs: AUX1 on Classic (electrode 4), AUX1..AUX4 on
/// Athena (electrodes 4..7: FPz, AUX_R, AUX_L, AUX in muse-rs order).
pub const MUSE_AUX: [&str; 4] = ["AUX1", "AUX2", "AUX3", "AUX4"];
pub const CROWN_CHANNELS: [&str; 8] = ["CP3", "C3", "F5", "PO3", "PO4", "F6", "C4", "CP4"];
pub const PPG_CHANNELS: [&str; 3] = ["ambient", "infrared", "red"];

/// `DeviceInfo` for a real Muse (Muse 2 / Muse S Classic: PPG + accel).
pub fn muse_info(id: &str, name: &str) -> DeviceInfo {
    DeviceInfo {
        id: id.to_owned(),
        name: name.to_owned(),
        kind: DeviceKind::Muse,
        channels: MUSE_CHANNELS.iter().map(|c| (*c).to_owned()).collect(),
        sample_rate_hz: 256.0,
        simulated: false,
        ppg_channels: PPG_CHANNELS.iter().map(|c| (*c).to_owned()).collect(),
        ppg_rate_hz: Some(64.0),
        optics_channels: Vec::new(),
        optics_rate_hz: None,
        optics_preset: None,
        accel_rate_hz: Some(52.0),
        aux_channels: MUSE_AUX.iter().map(|c| (*c).to_owned()).collect(),
        rssi: None,
    }
}

/// `DeviceInfo` for a Crown (8 ch EEG, no PPG/accel over OSC).
pub fn crown_info(id: &str, name: &str) -> DeviceInfo {
    DeviceInfo {
        id: id.to_owned(),
        name: name.to_owned(),
        kind: DeviceKind::Crown,
        channels: CROWN_CHANNELS.iter().map(|c| (*c).to_owned()).collect(),
        sample_rate_hz: 256.0,
        simulated: false,
        ppg_channels: Vec::new(),
        ppg_rate_hz: None,
        optics_channels: Vec::new(),
        optics_rate_hz: None,
        optics_preset: None,
        accel_rate_hz: None,
        aux_channels: Vec::new(),
        rssi: None,
    }
}

/// What a transport sends.
#[derive(Debug, Clone, PartialEq)]
pub enum Block {
    /// EEG electrode index, µV.
    Eeg(u16, Vec<f32>),
    /// PPG channel index, sensor counts.
    Ppg(u16, Vec<f32>),
    /// Athena optical lane index, raw ADC counts.
    Optics(u16, Vec<f32>),
    /// Firmware/layout known after connect (Classic vs Athena).
    Info(Box<DeviceInfo>),
    /// Accelerometer x/y/z in g.
    Accel(Vec<[f32; 3]>),
    /// Link state change.
    Link(LinkState),
    /// Device-reported pad quality, one value 0..=1 per EEG channel (Crown).
    Quality(Vec<f32>),
    /// Battery charge in percent (0..=100).
    Battery(f32),
}

/// Transport side of a [`LiveSource`]. Cheap to clone; `send` fails once
/// the source was dropped (the transport should then disconnect).
#[derive(Debug, Clone)]
pub struct Feed(Sender<Block>);

impl Feed {
    pub fn send(&self, b: Block) -> bool {
        self.0.send(b).is_ok()
    }
    pub fn eeg(&self, electrode: u16, samples: Vec<f32>) -> bool {
        self.send(Block::Eeg(electrode, samples))
    }
    pub fn ppg(&self, channel: u16, samples: Vec<f32>) -> bool {
        self.send(Block::Ppg(channel, samples))
    }
    pub fn optics(&self, lane: u16, samples: Vec<f32>) -> bool {
        self.send(Block::Optics(lane, samples))
    }
    pub fn info(&self, info: DeviceInfo) -> bool {
        self.send(Block::Info(Box::new(info)))
    }
    pub fn accel(&self, samples: Vec<[f32; 3]>) -> bool {
        self.send(Block::Accel(samples))
    }
    pub fn link(&self, state: LinkState) -> bool {
        self.send(Block::Link(state))
    }
    pub fn quality(&self, per_pad: Vec<f32>) -> bool {
        self.send(Block::Quality(per_pad))
    }
    pub fn battery(&self, percent: f32) -> bool {
        self.send(Block::Battery(percent))
    }
}

/// One stream's sample timeline on session time.
#[derive(Debug, Clone, Default)]
struct Timeline {
    /// Session time of the next sample.
    next: Option<f64>,
}

impl Timeline {
    /// Session time of the last sample of an `n`-sample block arriving at `now`.
    fn place(&mut self, n: usize, rate: f64, now: f64) -> f64 {
        let dur = n as f64 / rate;
        let start = match self.next {
            Some(t) if (t + dur - now).abs() <= REANCHOR_S => t,
            _ => now - dur,
        };
        self.next = Some(start + dur);
        start + dur - 1.0 / rate
    }
}

/// Session side: a [`DeviceSource`] fed by a transport thread.
pub struct LiveSource {
    info: DeviceInfo,
    rx: Receiver<Block>,
    link: LinkState,
    eeg_t: Vec<Timeline>,
    ppg_t: Vec<Timeline>,
    optics_t: Vec<Timeline>,
    accel_t: Timeline,
    eeg: VecDeque<EegPacket>,
    ppg: VecDeque<PpgPacket>,
    optics: VecDeque<OpticsPacket>,
    accel: VecDeque<AccelPacket>,
    quality: Vec<Vec<f32>>,
    battery: Option<f32>,
    /// Called on drop (transport teardown, e.g. BLE disconnect).
    on_drop: Option<Box<dyn FnOnce() + Send>>,
    pending_preset: Arc<Mutex<Option<String>>>,
}

impl LiveSource {
    /// A source plus the feed its transport writes to.
    pub fn new(info: DeviceInfo) -> (Self, Feed) {
        let (tx, rx) = mpsc::channel();
        let n_eeg = info.channels.len() + info.aux_channels.len();
        let n_ppg = info.ppg_channels.len();
        let n_opt = info.optics_channels.len();
        let s = Self {
            info,
            rx,
            link: LinkState::Connecting,
            eeg_t: vec![Timeline::default(); n_eeg],
            ppg_t: vec![Timeline::default(); n_ppg],
            optics_t: vec![Timeline::default(); n_opt.max(16)],
            accel_t: Timeline::default(),
            eeg: VecDeque::new(),
            ppg: VecDeque::new(),
            optics: VecDeque::new(),
            accel: VecDeque::new(),
            quality: Vec::new(),
            battery: None,
            on_drop: None,
            pending_preset: Arc::new(Mutex::new(None)),
        };
        (s, Feed(tx))
    }

    pub fn preset_slot(&self) -> Arc<Mutex<Option<String>>> {
        self.pending_preset.clone()
    }

    pub fn on_drop(mut self, f: impl FnOnce() + Send + 'static) -> Self {
        self.on_drop = Some(Box::new(f));
        self
    }

    fn apply_info(&mut self, info: DeviceInfo) {
        let n_opt = info.optics_channels.len().max(16);
        if self.optics_t.len() < n_opt {
            self.optics_t.resize(n_opt, Timeline::default());
        }
        let n_ppg = info.ppg_channels.len();
        if self.ppg_t.len() < n_ppg {
            self.ppg_t.resize(n_ppg, Timeline::default());
        }
        self.info = info;
    }

    /// Move everything that arrived into the timed queues.
    fn drain(&mut self, now: f64) {
        while let Ok(b) = self.rx.try_recv() {
            match b {
                Block::Eeg(e, samples) => {
                    let Some(t) = self.eeg_t.get_mut(usize::from(e)) else { continue };
                    if samples.is_empty() {
                        continue;
                    }
                    let time = t.place(samples.len(), self.info.sample_rate_hz, now);
                    self.eeg.push_back(EegPacket { time, electrode: e, samples });
                    self.link = LinkState::Streaming;
                }
                Block::Ppg(c, samples) => {
                    let (Some(t), Some(rate)) = (self.ppg_t.get_mut(usize::from(c)), self.info.ppg_rate_hz) else { continue };
                    if samples.is_empty() {
                        continue;
                    }
                    let time = t.place(samples.len(), rate, now);
                    self.ppg.push_back(PpgPacket { time, channel: c, samples });
                }
                Block::Optics(c, samples) => {
                    let (Some(t), Some(rate)) = (self.optics_t.get_mut(usize::from(c)), self.info.optics_rate_hz) else { continue };
                    if samples.is_empty() {
                        continue;
                    }
                    let time = t.place(samples.len(), rate, now);
                    self.optics.push_back(OpticsPacket { time, lane: c, samples });
                }
                Block::Info(info) => {
                    self.apply_info(*info);
                }
                Block::Accel(samples) => {
                    let Some(rate) = self.info.accel_rate_hz else { continue };
                    if samples.is_empty() {
                        continue;
                    }
                    let time = self.accel_t.place(samples.len(), rate, now);
                    self.accel.push_back(AccelPacket { time, samples });
                }
                Block::Link(l) => self.link = l,
                Block::Quality(q) => self.quality.push(q),
                Block::Battery(b) if b.is_finite() => self.battery = Some(b.clamp(0.0, 100.0)),
                Block::Battery(_) => {}
            }
        }
    }
}

fn due<T>(q: &mut VecDeque<T>, now: f64, time: impl Fn(&T) -> f64) -> Vec<T> {
    let mut out = Vec::new();
    while q.front().is_some_and(|p| time(p) <= now + 1e-9) {
        if let Some(p) = q.pop_front() {
            out.push(p);
        }
    }
    out
}

impl DeviceSource for LiveSource {
    fn info(&self) -> DeviceInfo {
        self.info.clone()
    }
    fn poll(&mut self, now: f64) -> Vec<EegPacket> {
        self.drain(now);
        due(&mut self.eeg, now, |p| p.time)
    }
    fn poll_ppg(&mut self, now: f64) -> Vec<PpgPacket> {
        self.drain(now);
        due(&mut self.ppg, now, |p| p.time)
    }
    fn poll_optics(&mut self, now: f64) -> Vec<OpticsPacket> {
        self.drain(now);
        due(&mut self.optics, now, |p| p.time)
    }
    fn set_optics_preset(&mut self, preset: &str) -> Result<(), String> {
        if !is_athena_preset(preset) {
            return Err(format!("unknown Athena preset `{preset}`"));
        }
        *self.pending_preset.lock().unwrap_or_else(|e| e.into_inner()) = Some(preset.to_owned());
        Ok(())
    }
    fn poll_accel(&mut self, now: f64) -> Vec<AccelPacket> {
        self.drain(now);
        due(&mut self.accel, now, |p| p.time)
    }
    fn poll_quality(&mut self, now: f64) -> Vec<Vec<f32>> {
        self.drain(now);
        std::mem::take(&mut self.quality)
    }
    fn battery(&self) -> Option<f32> {
        self.battery
    }
    fn link(&self) -> LinkState {
        self.link.clone()
    }
}

impl Drop for LiveSource {
    fn drop(&mut self) {
        if let Some(f) = self.on_drop.take() {
            f();
        }
    }
}

/// Counts live transport tasks (one per opened device) so that
/// [`DeviceProvider::shutdown`] can wait for their disconnect.
#[derive(Clone, Default)]
pub struct Tasks(Arc<(Mutex<usize>, std::sync::Condvar)>);

/// Held by a transport task until its device is disconnected.
pub struct TaskGuard(Tasks);

impl Tasks {
    pub fn enter(&self) -> TaskGuard {
        *lock(&self.0 .0) += 1;
        TaskGuard(self.clone())
    }

    pub fn live(&self) -> usize {
        *lock(&self.0 .0)
    }

    /// Block until no task is live, at most `timeout`. `true` if idle.
    pub fn wait_idle(&self, timeout: std::time::Duration) -> bool {
        let (m, cv) = &*self.0;
        let g = lock(m);
        let (g, _) = cv.wait_timeout_while(g, timeout, |n| *n > 0).unwrap_or_else(std::sync::PoisonError::into_inner);
        *g == 0
    }
}

impl Drop for TaskGuard {
    fn drop(&mut self) {
        let (m, cv) = &*self.0 .0;
        let mut n = lock(m);
        *n = n.saturating_sub(1);
        cv.notify_all();
    }
}

#[cfg(test)]
mod task_tests {
    use super::Tasks;
    use std::time::{Duration, Instant};

    #[test]
    fn wait_idle_returns_when_the_last_task_ends() {
        let t = Tasks::default();
        assert!(t.wait_idle(Duration::ZERO));
        let g = t.enter();
        let h = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(50));
            drop(g);
        });
        let start = Instant::now();
        assert!(t.wait_idle(Duration::from_secs(5)));
        assert!(start.elapsed() < Duration::from_secs(2));
        h.join().ok();
    }

    #[test]
    fn wait_idle_gives_up_at_the_timeout() {
        let t = Tasks::default();
        let _g = t.enter();
        let start = Instant::now();
        assert!(!t.wait_idle(Duration::from_millis(120)));
        assert!(start.elapsed() >= Duration::from_millis(120));
        assert_eq!(t.live(), 1);
    }
}

pub(crate) fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// All native providers with default settings (Muse BLE, Crown OSC).
pub fn native_providers() -> Vec<Box<dyn DeviceProvider>> {
    vec![
        #[cfg(feature = "ble")]
        Box::new(MuseProvider::default()),
        #[cfg(feature = "osc")]
        Box::new(CrownProvider::default()),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timeline_continues_then_reanchors() {
        let mut t = Timeline::default();
        // 12 samples at 256 Hz arriving at 1.0 s: last sample at 1.0 - 1/256.
        let a = t.place(12, 256.0, 1.0);
        assert!((a - (1.0 - 1.0 / 256.0)).abs() < 1e-12);
        // Next block continues the timeline even if it arrives a bit late.
        let b = t.place(12, 256.0, 1.2);
        assert!((b - (a + 12.0 / 256.0)).abs() < 1e-12);
        // After a 3 s gap it re-anchors.
        let c = t.place(12, 256.0, 4.2);
        assert!((c - (4.2 - 1.0 / 256.0)).abs() < 1e-12);
    }

    #[test]
    fn live_source_releases_packets_by_session_time() {
        let (mut s, feed) = LiveSource::new(muse_info("x:1", "X"));
        assert_eq!(s.link(), LinkState::Connecting);
        assert!(feed.eeg(1, vec![1.0; 12]));
        assert!(feed.eeg(9, vec![1.0; 12]), "unknown electrode is dropped, not an error");
        let p = s.poll(2.0);
        assert_eq!(p.len(), 1);
        assert_eq!(p[0].electrode, 1);
        assert!(p[0].time <= 2.0);
        assert_eq!(s.link(), LinkState::Streaming);
        feed.link(LinkState::Lost { reason: "gone".into() });
        assert!(s.poll(2.1).is_empty());
        assert!(matches!(s.link(), LinkState::Lost { .. }));
        drop(s);
        assert!(!feed.eeg(0, vec![0.0]), "feed reports a dropped source");
    }
}

fn is_athena_preset(preset: &str) -> bool {
    matches!(
        preset,
        "p1025"
            | "p1026"
            | "p1027"
            | "p1028"
            | "p1029"
            | "p102A"
            | "p1031"
            | "p1032"
            | "p1033"
            | "p1034"
            | "p1035"
            | "p1036"
            | "p1041"
            | "p1042"
            | "p1043"
            | "p1044"
            | "p1045"
            | "p1046"
    )
}
