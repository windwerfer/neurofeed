//! Application state. Plain data; changed only by `Session`.

use nf_types::{BandSnapshot, DeviceInfo};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

/// Top-level views, in sidebar order.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum View {
    Feedback,
    History,
    Bands,
    RawEeg,
    Histogram,
    Spectrogram,
    Psd,
    HeartRate,
    Optics,
    Movement,
    Streaming,
    Settings,
}

impl View {
    pub const ALL: [View; 12] = [
        View::Feedback,
        View::History,
        View::Bands,
        View::RawEeg,
        View::Histogram,
        View::Spectrogram,
        View::Psd,
        View::HeartRate,
        View::Optics,
        View::Movement,
        View::Streaming,
        View::Settings,
    ];

    pub fn label(self) -> &'static str {
        match self {
            View::Feedback => "Feedback",
            View::History => "History",
            View::Bands => "Bands",
            View::RawEeg => "Raw EEG",
            View::Histogram => "Histogram",
            View::Spectrogram => "Spectrogram",
            View::Psd => "PSD",
            View::HeartRate => "HR+SpO2",
            View::Optics => "Optics",
            View::Movement => "Movement",
            View::Streaming => "Streaming",
            View::Settings => "Settings",
        }
    }

    pub fn implemented(self) -> bool {
        matches!(
            self,
            View::Feedback
                | View::Bands
                | View::HeartRate
                | View::Movement
                | View::RawEeg
                | View::Histogram
                | View::Spectrogram
                | View::Psd
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum BandScale {
    /// log10 absolute power.
    Absolute,
    /// Share of the channel total.
    Relative,
}

/// Bounded ring buffer of recent snapshots.
#[derive(Debug, Clone, Default)]
pub struct BandHistory {
    snapshots: VecDeque<BandSnapshot>,
}

impl BandHistory {
    /// Seconds the history covers (live, in memory; the longest Bands zoom).
    pub const SECONDS: f64 = 3600.0;
    /// One snapshot every `BAND_INTERVAL_S` (4 Hz): 14 400 for the hour.
    pub const CAPACITY: usize = 14_400;

    /// Append; evicts by age (older than [`Self::SECONDS`] before the newest)
    /// and by count. The ring is allocated once at its full size.
    pub fn push(&mut self, s: BandSnapshot) {
        if self.snapshots.capacity() < Self::CAPACITY {
            self.snapshots.reserve_exact(Self::CAPACITY - self.snapshots.len());
        }
        while self.snapshots.len() >= Self::CAPACITY || self.snapshots.front().is_some_and(|f| f.time < s.time - Self::SECONDS) {
            self.snapshots.pop_front();
        }
        self.snapshots.push_back(s);
    }

    /// Heap bytes: the ring slots plus each snapshot's per-channel powers.
    pub fn heap_bytes(&self) -> usize {
        self.snapshots.capacity() * std::mem::size_of::<BandSnapshot>()
            + self.snapshots.iter().map(|s| s.powers.capacity() * std::mem::size_of::<[f32; 5]>()).sum::<usize>()
    }

    /// Oldest first.
    pub fn iter(&self) -> impl Iterator<Item = &BandSnapshot> {
        self.snapshots.iter()
    }

    /// Oldest snapshot.
    pub fn oldest(&self) -> Option<&BandSnapshot> {
        self.snapshots.front()
    }

    /// Snapshots with `start <= time <= end` (binary search; oldest first).
    pub fn range(&self, start: f64, end: f64) -> impl Iterator<Item = &BandSnapshot> {
        let a = self.snapshots.partition_point(|s| s.time < start);
        let b = self.snapshots.partition_point(|s| s.time <= end).max(a);
        self.snapshots.range(a..b)
    }

    pub fn latest(&self) -> Option<&BandSnapshot> {
        self.snapshots.back()
    }

    pub fn len(&self) -> usize {
        self.snapshots.len()
    }

    pub fn is_empty(&self) -> bool {
        self.snapshots.is_empty()
    }

    pub fn clear(&mut self) {
        self.snapshots.clear();
    }
}

#[derive(Debug, Clone)]
pub struct AppState {
    pub view: View,
    pub sidebar_open: bool,
    pub paused: bool,
    pub band_scale: BandScale,
    /// Connected device, if any.
    pub device: Option<DeviceInfo>,
    pub bands: BandHistory,
    /// Session time in seconds (advanced by `tick` / `clock_advance`).
    pub time: f64,
    /// Notch choice (auto = detected mains).
    pub mains_mode: crate::MainsMode,
    /// Channel shown by single-channel views (spectrogram).
    pub channel: usize,
    /// Active or last finished recording.
    pub recording: Option<crate::recording::RecordingInfo>,
    /// Feedback session (phases, results, stored baselines).
    pub feedback: crate::feedback::Trainer,
    pub audio: nf_audio::AudioSettings,
    /// Protocols made in the Protocol Builder (built-ins are not listed here).
    pub custom_protocols: Vec<nf_feedback::Protocol>,
    /// OSC streaming out.
    pub streaming: crate::streaming::StreamState,
    /// AI sleep guard: models, scorer, live scores.
    pub ai: crate::ai::AiState,
    /// Folder the desktop shell loads music from (`music` reward output).
    pub music_dir: Option<String>,
    /// Appearance, subject, onboarding, debug (persisted).
    pub settings: crate::settings::UserSettings,
    /// Saved sessions, newest first (cache of the store's list).
    pub history: Vec<nf_store::SessionMeta>,
    /// Where history is stored (`memory` or a file).
    pub history_location: String,
    /// A recording interrupted by a crash, waiting for Recover / Discard.
    pub recovery: Option<crate::recovery::Pending>,
    /// Active simulator faults (`sim.fault.add`).
    pub faults: Vec<crate::faults::ActiveFault>,
    /// Schemes of registered providers that can scan (`muse`, `crown`).
    pub scanners: Vec<String>,
    /// Transport state of the connected device.
    pub link: Option<nf_types::LinkState>,
    /// Battery of the connected device in percent, once it reported one.
    pub battery: Option<f32>,
    /// The Device dialog (current device + scan list) is open.
    pub device_dialog: bool,
    /// Background reconnect to the last device (`.ai/contracts/device-autoconnect.md`).
    pub auto: crate::autoconnect::AutoReconnect,
    /// Monitor viewports (Follow/Inspect, window) and Bands display choices.
    pub monitors: crate::monitor::Monitors,
    /// Analysis channel exclusions (global) and the contact-quality hint.
    pub analysis: crate::analysis::Analysis,
    /// Bumped on every state change (not on time/data ticks).
    pub revision: u64,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            view: View::Bands,
            sidebar_open: true,
            paused: false,
            band_scale: BandScale::Absolute,
            device: None,
            bands: BandHistory::default(),
            time: 0.0,
            mains_mode: crate::MainsMode::Auto,
            channel: 0,
            recording: None,
            feedback: crate::feedback::Trainer::default(),
            audio: nf_audio::AudioSettings::default(),
            streaming: crate::streaming::StreamState::default(),
            ai: crate::ai::AiState::default(),
            settings: crate::settings::UserSettings::default(),
            custom_protocols: Vec::new(),
            music_dir: None,
            history: Vec::new(),
            scanners: Vec::new(),
            link: None,
            battery: None,
            device_dialog: false,
            auto: crate::autoconnect::AutoReconnect::default(),
            history_location: "memory".into(),
            recovery: None,
            faults: Vec::new(),
            monitors: crate::monitor::Monitors::default(),
            analysis: crate::analysis::Analysis::default(),
            revision: 0,
        }
    }
}
