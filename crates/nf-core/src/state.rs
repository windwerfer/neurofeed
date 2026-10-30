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
    Streaming,
    Settings,
}

impl View {
    pub const ALL: [View; 10] = [
        View::Feedback,
        View::History,
        View::Bands,
        View::RawEeg,
        View::Histogram,
        View::Spectrogram,
        View::Psd,
        View::HeartRate,
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
            View::Streaming => "Streaming",
            View::Settings => "Settings",
        }
    }

    pub fn implemented(self) -> bool {
        matches!(self, View::Feedback | View::Bands | View::HeartRate | View::RawEeg | View::Histogram | View::Spectrogram | View::Psd)
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
    pub const CAPACITY: usize = 600; // ~60 s at 10 Hz

    pub fn push(&mut self, s: BandSnapshot) {
        if self.snapshots.len() >= Self::CAPACITY {
            self.snapshots.pop_front();
        }
        self.snapshots.push_back(s);
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
    /// OSC streaming out.
    pub streaming: crate::streaming::StreamState,
    /// Folder the desktop shell loads music from (`music` reward output).
    pub music_dir: Option<String>,
    /// Saved sessions, newest first (cache of the store's list).
    pub history: Vec<nf_store::SessionMeta>,
    /// Where history is stored (`memory` or a file).
    pub history_location: String,
    /// Schemes of registered providers that can scan (`muse`, `crown`).
    pub scanners: Vec<String>,
    /// Transport state of the connected device.
    pub link: Option<nf_types::LinkState>,
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
            music_dir: None,
            history: Vec::new(),
            scanners: Vec::new(),
            link: None,
            history_location: "memory".into(),
            revision: 0,
        }
    }
}
