//! # nf-types (L0)
//!
//! Shared EEG domain types and the device traits that every data source
//! (simulator, Muse/Crown BLE, Android-supplied transport, replay) implements.
#![forbid(unsafe_code)]

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Classic EEG frequency bands.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum Band {
    Delta,
    Theta,
    Alpha,
    Beta,
    Gamma,
}

impl Band {
    pub const ALL: [Band; 5] = [Band::Delta, Band::Theta, Band::Alpha, Band::Beta, Band::Gamma];

    pub fn name(self) -> &'static str {
        match self {
            Band::Delta => "Delta",
            Band::Theta => "Theta",
            Band::Alpha => "Alpha",
            Band::Beta => "Beta",
            Band::Gamma => "Gamma",
        }
    }

    /// Frequency range in Hz (low inclusive, high exclusive).
    pub fn range_hz(self) -> (f32, f32) {
        match self {
            Band::Delta => (1.0, 4.0),
            Band::Theta => (4.0, 8.0),
            Band::Alpha => (8.0, 13.0),
            Band::Beta => (13.0, 30.0),
            Band::Gamma => (30.0, 44.0),
        }
    }

    pub fn index(self) -> usize {
        self as usize
    }
}

/// Absolute band power per channel at one point in time.
///
/// `powers[channel][band.index()]` is log10(µV²/Hz) (Muse convention,
/// roughly -1.0 ..= 2.0).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct BandSnapshot {
    /// Session time in seconds.
    pub time: f64,
    pub powers: Vec<[f32; 5]>,
}

impl BandSnapshot {
    pub fn power(&self, channel: usize, band: Band) -> Option<f32> {
        self.powers.get(channel).map(|p| p[band.index()])
    }

    /// Share of the channel total in linear units (0..=1).
    pub fn relative(&self, channel: usize, band: Band) -> Option<f32> {
        let p = self.powers.get(channel)?;
        let total: f32 = p.iter().map(|v| 10f32.powf(*v)).sum();
        if total <= 0.0 || !total.is_finite() {
            return None;
        }
        Some(10f32.powf(p[band.index()]) / total)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum DeviceKind {
    Muse,
    Crown,
}

/// Static description of a device (available or connected).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct DeviceInfo {
    /// Stable id, e.g. `sim:muse` or a BLE address.
    pub id: String,
    pub name: String,
    pub kind: DeviceKind,
    pub channels: Vec<String>,
    /// EEG sample rate (data, not an assumption: Muse and Crown are 256 Hz today).
    pub sample_rate_hz: f64,
    pub simulated: bool,
    /// Optical (PPG) channels, e.g. `["ambient", "infrared", "red"]` on Muse
    /// S / Athena; empty when the device has no PPG.
    #[serde(default)]
    pub ppg_channels: Vec<String>,
    /// PPG sample rate (runtime data; Muse streams 64 Hz).
    #[serde(default)]
    pub ppg_rate_hz: Option<f64>,
    /// Accelerometer rate (Muse 52 Hz), `None` without one.
    #[serde(default)]
    pub accel_rate_hz: Option<f64>,
    /// Auxiliary inputs (Muse AUX1..), sent as `EegPacket`s with electrode
    /// `channels.len() + k`. Not EEG: they never feed bands or feedback.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub aux_channels: Vec<String>,
    /// Advertised signal strength (dBm) from the last scan; `None` when
    /// the transport has none (Crown OSC, replays).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rssi: Option<i16>,
}

impl DeviceInfo {
    pub fn has_ppg(&self) -> bool {
        self.ppg_rate_hz.is_some() && !self.ppg_channels.is_empty()
    }

    /// Index of a PPG channel by name.
    pub fn ppg_index(&self, name: &str) -> Option<usize> {
        self.ppg_channels.iter().position(|c| c == name)
    }
}

/// A block of raw optical samples for one PPG channel (sensor counts).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct PpgPacket {
    /// Session time (s) of the **last** sample in the block.
    pub time: f64,
    /// Index into `DeviceInfo::ppg_channels`.
    pub channel: u16,
    pub samples: Vec<f32>,
}

/// A block of accelerometer samples (g), x/y/z.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct AccelPacket {
    /// Session time (s) of the **last** sample in the block.
    pub time: f64,
    pub samples: Vec<[f32; 3]>,
}

/// A block of raw EEG samples for one electrode, in µV.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct EegPacket {
    /// Session time (s) of the **last** sample in the block.
    pub time: f64,
    /// Index into `DeviceInfo::channels`.
    pub electrode: u16,
    pub samples: Vec<f32>,
}

/// A connected device. `poll` is called from `Session::tick` with the session
/// time and returns all raw packets due up to `now`. It must never block
/// (WASM, UI thread) and never read a clock itself.
pub trait DeviceSource: Send {
    fn info(&self) -> DeviceInfo;
    fn poll(&mut self, now: f64) -> Vec<EegPacket>;
    /// PPG packets due up to `now` (same rules as `poll`). Default: none.
    fn poll_ppg(&mut self, _now: f64) -> Vec<PpgPacket> {
        Vec::new()
    }
    /// Accelerometer packets due up to `now`. Default: none.
    fn poll_accel(&mut self, _now: f64) -> Vec<AccelPacket> {
        Vec::new()
    }
    /// Device-reported pad quality frames since the last call, one value
    /// 0..=1 per EEG channel (Neurosity Crown `signalQuality`). Default: none.
    fn poll_quality(&mut self, _now: f64) -> Vec<Vec<f32>> {
        Vec::new()
    }
    /// Battery charge in percent (0..=100) as last reported. Default: unknown.
    fn battery(&self) -> Option<f32> {
        None
    }
    /// Transport state (real devices connect asynchronously). Default: streaming.
    fn link(&self) -> LinkState {
        LinkState::Streaming
    }
}

/// Transport state of a [`DeviceSource`].
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum LinkState {
    /// Opening the link (BLE connect, service discovery, waiting for data).
    Connecting,
    Streaming,
    /// The link failed or dropped; the source stays open but delivers nothing.
    Lost {
        reason: String,
    },
}

/// Something that can list and open devices: the simulator registry, a
/// btleplug scanner on desktop, or an Android wrapper that does the BLE scan
/// and transport via JNI and hands samples to Rust.
pub trait DeviceProvider: Send {
    /// Id prefix this provider owns, e.g. `sim` or `ble`.
    fn scheme(&self) -> &'static str;
    fn list(&self) -> Vec<DeviceInfo>;
    fn open(&mut self, id: &str) -> Result<Box<dyn DeviceSource>, String>;
    /// Whether `scan` does anything (BLE, LAN discovery).
    fn can_scan(&self) -> bool {
        false
    }
    /// Start discovery for `seconds` in the background (never blocks); found
    /// devices show up in `list` as they arrive.
    fn scan(&mut self, _seconds: f64) -> Result<(), String> {
        Ok(())
    }
    /// Keep discovering until [`stop_scan`](Self::stop_scan). The Device
    /// dialog uses this for as long as it is open. Default: one timed scan.
    fn watch(&mut self) -> Result<(), String> {
        self.scan(8.0)
    }
    /// Stop discovery started by [`scan`](Self::scan) or [`watch`](Self::watch).
    /// Devices already found stay listed. A connected source keeps its link.
    fn stop_scan(&mut self) {}
    /// A scan is running.
    fn scanning(&self) -> bool {
        false
    }
    /// Last background error (no BLE adapter, UDP port busy, ...).
    fn last_error(&self) -> Option<String> {
        None
    }
}

/// Sends one UDP datagram (streaming out). Shells provide it; the web build
/// has none.
pub trait DatagramSink: Send {
    fn send(&mut self, ip: &str, port: u16, bytes: &[u8]) -> Result<(), String>;
}

/// One stream a [`StreamOutlets`] transport should announce.
#[derive(Debug, Clone, PartialEq)]
pub struct OutletSpec {
    pub name: String,
    /// Content type (`EEG`, `PPG`, `Accelerometer`, ...).
    pub kind: String,
    pub channels: Vec<String>,
    pub unit: String,
    pub rate_hz: f64,
    pub source_id: String,
}

/// Lab Streaming Layer style outlets (streaming out). Desktop shells
/// provide one; the web build has none.
pub trait StreamOutlets: Send {
    /// Replace any open outlets with these.
    fn open(&mut self, specs: &[OutletSpec]) -> Result<(), String>;
    /// Push row-major float32 rows to outlet `index`, the last row stamped now.
    fn push(&mut self, index: usize, rows: &[f32]) -> Result<(), String>;
    fn close(&mut self);
    /// Connected consumers over all outlets.
    fn consumers(&self) -> usize;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn relative_sums_to_one() {
        let s = BandSnapshot { time: 0.0, powers: vec![[1.0, 0.8, 0.7, 0.3, -0.2]] };
        let sum: f32 = Band::ALL.iter().filter_map(|b| s.relative(0, *b)).sum();
        assert!((sum - 1.0).abs() < 1e-4);
        assert!(s.relative(3, Band::Alpha).is_none());
    }
}

// ── AI sleep scorers (implemented natively by `nf-ai`) ─────────────────────

/// An EEG foundation model behind the AI sleep guard.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum AiModel {
    /// Frozen CBraMod encoder (Apache-2.0) + A-vig / wake-light heads, 2 s windows.
    CbramodAVig,
    /// REVE base (gated on Hugging Face), 2 s windows, experimental heads.
    ReveBase,
}

impl AiModel {
    pub const ALL: [Self; 2] = [Self::CbramodAVig, Self::ReveBase];

    /// Stable id (folder name, legacy `ffId`).
    pub fn id(self) -> &'static str {
        match self {
            Self::CbramodAVig => "cbramod_a_vig",
            Self::ReveBase => "reve_base",
        }
    }
    pub fn label(self) -> &'static str {
        match self {
            Self::CbramodAVig => "CBraMod A-vig",
            Self::ReveBase => "REVE Base",
        }
    }
    /// Approximate weights download size.
    pub fn size_mb(self) -> u32 {
        match self {
            Self::CbramodAVig => 20,
            Self::ReveBase => 280,
        }
    }
    /// Samples per scored window at 256 Hz.
    pub fn window_samples(self) -> usize {
        match self {
            Self::CbramodAVig => 512,
            Self::ReveBase => 512,
        }
    }
    /// Weights file the user downloads or imports.
    pub fn weights_file(self) -> &'static str {
        match self {
            Self::CbramodAVig => "pretrained_weights.pth",
            Self::ReveBase => "model.safetensors",
        }
    }
    /// SHA-256 of the weights file.
    pub fn sha256(self) -> &'static str {
        match self {
            Self::CbramodAVig => "0792cb808c14e6b7a2bb2ce1dff379bc47bc54c49a779825bdfeb33bf8157178",
            Self::ReveBase => "8ecc650619598748286c2457f81f5c6bd12e8bb59db44f7b02af1955c44de8fe",
        }
    }
    pub fn page_url(self) -> &'static str {
        match self {
            Self::CbramodAVig => "https://huggingface.co/weighting666/CBraMod",
            Self::ReveBase => "https://huggingface.co/brain-bzh/reve-base/tree/main",
        }
    }
    /// Direct download, `None` when gated (import only).
    pub fn download_url(self) -> Option<&'static str> {
        match self {
            Self::CbramodAVig => Some("https://huggingface.co/weighting666/CBraMod/resolve/main/pretrained_weights.pth"),
            Self::ReveBase => None,
        }
    }
    pub fn description(self) -> &'static str {
        match self {
            Self::CbramodAVig => "Open vigilance head on the frozen CBraMod encoder (Apache-2.0). Scores 2 s windows; the guard value is P(hypnagogic). The heads ship with the app; the ~20 MB encoder weights are downloaded once.",
            Self::ReveBase => "REVE base (67M parameters), gated on Hugging Face. Scores 2 s windows; its heads are experimental (subsample-trained).",
        }
    }
    pub fn guide(self) -> &'static str {
        match self {
            Self::CbramodAVig => "Download the encoder weights (pretrained_weights.pth, Apache-2.0, no login), or import a copy you already have.",
            Self::ReveBase => "REVE is gated: open Hugging Face, log in, accept the responsible-use agreement, download model.safetensors (~280 MB), then import it here.",
        }
    }
    /// Scorer ids (feature ids) this model's heads produce.
    pub fn scorers(self) -> &'static [&'static str] {
        match self {
            Self::CbramodAVig => &["ai.a_vig", "ai.wake_light"],
            Self::ReveBase => &["ai.a_vig_reve", "ai.wake_light_reve"],
        }
    }
    /// The model behind a scorer id (`ai.drowsiness` = legacy alias of `ai.a_vig`).
    pub fn for_scorer(id: &str) -> Option<Self> {
        match id {
            "ai.a_vig" | "ai.wake_light" | "ai.drowsiness" => Some(Self::CbramodAVig),
            "ai.a_vig_reve" | "ai.wake_light_reve" => Some(Self::ReveBase),
            _ => None,
        }
    }
}

/// Install / load state of one model.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum AiModelState {
    /// Weights not on disk.
    Missing,
    /// Download or import running; `progress` 0..1 when the size is known.
    Installing {
        progress: Option<f64>,
    },
    /// Verified on disk, not loaded.
    Installed,
    Loading,
    /// Loaded and scoring.
    Ready {
        description: String,
    },
    Failed {
        message: String,
    },
}

/// Where `install` gets the weights from.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum AiSource {
    /// The model's public download URL.
    Download,
    /// A local weights file (checked against the pinned SHA-256).
    Import { path: String },
}

/// One window to score: 4 rows (frontal L/R, temporal L/R) × `n_times`
/// conditioned µV samples at 256 Hz, row-major.
#[derive(Debug, Clone, PartialEq)]
pub struct AiWindow {
    pub model: AiModel,
    /// Session time of the window's last sample.
    pub t: f64,
    pub n_times: usize,
    pub signal: Vec<f32>,
}

/// Result of one scored window.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct AiScore {
    pub model: AiModel,
    pub t: f64,
    /// Pooled encoder embedding (anchors / clarity).
    pub embedding: Vec<f32>,
    /// `(scorer id, P(class 1))` for every loaded head of this model.
    pub heads: Vec<(String, f32)>,
    /// Inference time.
    pub ms: f64,
}

/// Native AI runtime: install, load and run the models off the UI thread.
/// All calls return immediately; long work runs in the background and shows
/// up in `state` / `poll`.
pub trait AiRuntime: Send {
    fn state(&self, model: AiModel) -> AiModelState;
    /// Folder holding the model files (for the model card).
    fn folder(&self, model: AiModel) -> Option<String>;
    fn install(&mut self, model: AiModel, source: AiSource) -> Result<(), String>;
    /// Delete the downloaded / imported weights.
    fn remove(&mut self, model: AiModel) -> Result<(), String>;
    /// Load `model` (unloads any other: one model at a time).
    fn load(&mut self, model: AiModel) -> Result<(), String>;
    fn unload(&mut self);
    /// Queue a window. `false` while the previous one is still running
    /// (the caller skips that second instead of stacking work).
    fn submit(&mut self, window: AiWindow) -> bool;
    /// Finished scores since the last poll.
    fn poll(&mut self) -> Vec<AiScore>;
}
