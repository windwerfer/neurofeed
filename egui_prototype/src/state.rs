//! Application state and the actions that change it. No egui in here.

use crate::data::{BandSnapshot, DeviceInfo};

/// Top-level views, in sidebar order (mirrors the Flutter app).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
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
}

/// How the bands view scales its bars.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BandScale {
    /// log10 absolute power.
    Absolute,
    /// Share of the channel total (0..100 %).
    Relative,
}

/// Rolling buffer of recent snapshots.
#[derive(Debug, Default)]
pub struct BandHistory {
    snapshots: std::collections::VecDeque<BandSnapshot>,
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
}

/// Everything the UI renders from.
#[derive(Debug)]
pub struct AppState {
    pub view: View,
    pub sidebar_open: bool,
    pub paused: bool,
    pub band_scale: BandScale,
    pub device: DeviceInfo,
    pub bands: BandHistory,
}

/// User intents emitted by the UI; applied after the frame is drawn.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Action {
    SelectView(View),
    ToggleSidebar,
    TogglePause,
    SetBandScale(BandScale),
}

impl AppState {
    pub fn new(device: DeviceInfo) -> Self {
        Self {
            view: View::Bands,
            sidebar_open: true,
            paused: false,
            band_scale: BandScale::Absolute,
            device,
            bands: BandHistory::default(),
        }
    }

    pub fn apply(&mut self, action: Action) {
        match action {
            Action::SelectView(v) => self.view = v,
            Action::ToggleSidebar => self.sidebar_open = !self.sidebar_open,
            Action::TogglePause => self.paused = !self.paused,
            Action::SetBandScale(s) => self.band_scale = s,
        }
    }
}
