//! Commands (change state) and queries (read state), plus their catalog.
//!
//! Ids are dotted (`area.verb`); MCP reaches them via `command_run`.
//! Adding an action: add a variant (serde rename = id), a `spec()` entry and
//! an `examples()` entry, then handle it in `Session`. Tests fail on drift.
//! Input schemas are derived with schemars from the variant fields.

use crate::feedback::{PauseReason, Phase};
use crate::recording::ExportFormat;
use crate::signal::MainsMode;
use crate::state::{AppState, BandScale, View};
use crate::CoreError;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "cmd", deny_unknown_fields)]
pub enum Command {
    /// Switch the main view.
    #[serde(rename = "view.set")]
    ViewSet { view: View },
    /// Show or hide the sidebar.
    #[serde(rename = "sidebar.set")]
    SidebarSet { open: bool },
    #[serde(rename = "stream.pause")]
    StreamPause,
    #[serde(rename = "stream.resume")]
    StreamResume,
    /// Bands view scaling.
    #[serde(rename = "scale.set")]
    ScaleSet { scale: BandScale },
    /// Monitor viewport: window length and/or Follow / Inspect.
    #[serde(rename = "monitor.viewport")]
    MonitorViewport {
        monitor: crate::monitor::MonitorId,
        /// Window length in seconds (clamped to the monitor's zoom range).
        #[serde(default)]
        window_s: Option<f64>,
        #[serde(default)]
        mode: Option<crate::monitor::ViewportMode>,
        /// Inspect: session time of the right edge (default: newest data).
        #[serde(default)]
        end_s: Option<f64>,
    },
    /// Zoom the time axis around a point (pinch / Ctrl+wheel).
    #[serde(rename = "monitor.zoom")]
    MonitorZoom {
        monitor: crate::monitor::MonitorId,
        /// > 1 zooms in (shorter window), < 1 zooms out.
        factor: f64,
        /// Anchor, 0 = left edge .. 1 = right edge (default 1).
        #[serde(default)]
        focal: Option<f64>,
    },
    /// Pan the time axis (drag); enters Inspect.
    #[serde(rename = "monitor.pan")]
    MonitorPan {
        monitor: crate::monitor::MonitorId,
        /// Positive = later, negative = earlier.
        seconds: f64,
    },
    /// Bands display: electrodes in the average and hidden bands.
    #[serde(rename = "monitor.display")]
    MonitorDisplay {
        /// Electrode names in the average; empty = all.
        #[serde(default)]
        electrodes: Option<Vec<String>>,
        #[serde(default)]
        hidden_bands: Option<Vec<nf_types::Band>>,
    },
    /// Raw EEG display: trace mode (sweep | scroll, saved), Y scale
    /// (auto | 50 | 100 | 200 µV, saved) and the electrodes shown (empty = all).
    #[serde(rename = "monitor.raw")]
    MonitorRaw {
        #[serde(default)]
        mode: Option<crate::monitor::RawMode>,
        #[serde(default)]
        scale: Option<crate::monitor::RawScale>,
        #[serde(default)]
        electrodes: Option<Vec<String>>,
    },
    /// PSD display: frequency range (60 | 100 Hz) and electrodes in the
    /// average (empty = all). Display only: analysis exclusions still apply.
    #[serde(rename = "monitor.psd")]
    MonitorPsd {
        #[serde(default)]
        range: Option<crate::monitor::PsdRange>,
        #[serde(default)]
        electrodes: Option<Vec<String>>,
    },
    /// Show or hide a view's overview timeline (saved per view). Views:
    /// bands, raw_eeg, histogram, psd, spectrogram.
    #[serde(rename = "monitor.overview")]
    MonitorOverview { monitor: crate::monitor::MonitorId, on: bool },
    /// Histogram display: µV range (50 | 100 | 200) and electrodes pooled
    /// (empty = all). Display only: analysis exclusions still apply.
    #[serde(rename = "monitor.histogram")]
    MonitorHistogram {
        #[serde(default)]
        range: Option<crate::monitor::HistRange>,
        #[serde(default)]
        electrodes: Option<Vec<String>>,
    },
    /// Spectrogram display: electrodes averaged (empty = all) and colour
    /// range: `db_min` + `db_max` lock it, `auto: true` unlocks.
    #[serde(rename = "monitor.spectrogram")]
    MonitorSpectrogram {
        #[serde(default)]
        electrodes: Option<Vec<String>>,
        #[serde(default)]
        db_min: Option<f32>,
        #[serde(default)]
        db_max: Option<f32>,
        #[serde(default)]
        auto: Option<bool>,
    },
    /// Exclude one channel from **all** analysis (feedback, every derived
    /// graph, features, AI input) for this connection; raw data, recordings
    /// and Raw EEG keep it. `confirm` must be true (the UI asks first);
    /// `remember` also stores it for this device id + channel name.
    #[serde(rename = "analysis.exclude")]
    AnalysisExclude {
        channel: String,
        confirm: bool,
        #[serde(default)]
        remember: bool,
    },
    /// Include a channel in analysis again (immediate). Also forgets a
    /// remembered exclusion of it for this device.
    #[serde(rename = "analysis.include")]
    AnalysisInclude { channel: String },
    /// Dismiss the contact-quality hint (not shown again this connection).
    #[serde(rename = "analysis.hint_dismiss")]
    AnalysisHintDismiss,
    /// Acknowledge the "remembered exclusions restored" notice.
    #[serde(rename = "analysis.ack_restored")]
    AnalysisAckRestored,
    /// Connect a device by id (`sim:muse`, `sim:crown`, ...).
    #[serde(rename = "device.connect")]
    DeviceConnect { id: String },
    #[serde(rename = "device.disconnect")]
    DeviceDisconnect,
    /// Open or close the Device dialog. Opening watches Muse BLE and Crown
    /// OSC until the dialog closes (errors show in the dialog, not here).
    #[serde(rename = "device.dialog")]
    DeviceDialog { open: bool },
    /// Start a timed background discovery on every scanning provider (BLE
    /// Muse, Crown OSC). The Device dialog does not use this: it watches
    /// until it closes. Results appear in `device.list` as they arrive.
    #[serde(rename = "device.scan")]
    DeviceScan {
        /// 1..=60 s, default 8.
        #[serde(default)]
        seconds: Option<f64>,
    },
    /// Tune the simulator; reconnects a running simulator.
    #[serde(rename = "sim.configure")]
    SimConfigure {
        #[serde(default)]
        seed: Option<u64>,
        /// Alpha amplitude, 0..=200 µV.
        #[serde(default)]
        alpha_uv: Option<f64>,
        /// White noise, 0..=200 µV.
        #[serde(default)]
        noise_uv: Option<f64>,
        /// Mains hum amplitude, 0..=1000 µV.
        #[serde(default)]
        mains_uv: Option<f64>,
        /// Mains frequency: 50 or 60.
        #[serde(default)]
        mains_hz: Option<f64>,
        /// Electrode DC offset, -5000..=5000 µV.
        #[serde(default)]
        dc_uv: Option<f64>,
        /// Simulated heart rate (PPG devices), 40..=180 bpm.
        #[serde(default)]
        hr_bpm: Option<f64>,
        /// Simulated SpO2, 80..=100 %.
        #[serde(default)]
        spo2_pct: Option<f64>,
        /// Beat-interval variability, 0..=150 ms.
        #[serde(default)]
        hrv_ms: Option<f64>,
    },
    /// Advance session time (0 < seconds <= 3600) in 0.1 s steps.
    #[serde(rename = "clock.advance")]
    ClockAdvance { seconds: f64 },
    #[serde(rename = "events.drain")]
    EventsDrain,
    /// Start recording the connected device (raw EEG + bands) in memory.
    #[serde(rename = "recording.start")]
    RecordingStart {
        /// Wall-clock start (Unix ms, UTC), injected by the shell; the core
        /// never reads a clock. Used for EDF start and NFED6 metadata.
        #[serde(default)]
        wall_clock_unix_ms: Option<f64>,
    },
    #[serde(rename = "recording.stop")]
    RecordingStop,
    /// Notch: auto (detected 50/60 Hz, sticky), 50, 60 or off. A running
    /// recording keeps the notch it started with until it stops.
    #[serde(rename = "mains.set")]
    MainsSet { mode: MainsMode },
    /// Channel for single-channel views (spectrogram), by name.
    #[serde(rename = "channel.set")]
    ChannelSet { channel: String },
    /// Choose the training protocol (locked while a session runs).
    #[serde(rename = "protocol.set")]
    ProtocolSet {
        id: String,
        /// Session length, 1..=120 min; default the protocol's.
        #[serde(default)]
        minutes: Option<u32>,
    },
    /// Create or (with `replace`) update a custom protocol.
    #[serde(rename = "protocol.save")]
    ProtocolSave {
        draft: crate::protocols::ProtocolDraft,
        /// Overwrite the custom protocol with the same id.
        #[serde(default)]
        replace: bool,
    },
    /// Delete a custom protocol. `confirm` must be true.
    #[serde(rename = "protocol.delete")]
    ProtocolDelete {
        id: String,
        #[serde(default)]
        confirm: bool,
    },
    /// Band Stability settings (window in clean samples, difficulty 0..=0.5).
    #[serde(rename = "stability.set")]
    StabilitySet {
        #[serde(default)]
        window: Option<u32>,
        #[serde(default)]
        difficulty: Option<f64>,
        /// Reset both to the defaults (10, 0.10) first.
        #[serde(default)]
        reset: bool,
    },
    /// Feedback audio: reward output, background, guard sound, volumes.
    #[serde(rename = "streaming.set")]
    StreamingSet(crate::streaming::StreamPatch),
    #[serde(rename = "audio.set")]
    AudioSet(crate::audio::AudioPatch),
    /// AI guard choices: model / scorer, threshold mode, fixed cut, auto-load.
    #[serde(rename = "ai.set")]
    AiSet(crate::ai::AiPatch),
    /// Install a model: download it (public weights) or import a local file.
    #[serde(rename = "ai.install")]
    AiInstall {
        /// Default: the selected model.
        #[serde(default)]
        model: Option<nf_types::AiModel>,
        /// Absolute path of a weights file to import; omitted = download.
        #[serde(default)]
        path: Option<String>,
    },
    /// Load a model into memory (it then scores once per second).
    #[serde(rename = "ai.load")]
    AiLoad {
        #[serde(default)]
        model: Option<nf_types::AiModel>,
    },
    /// Unload the loaded model (frees memory; stays installed).
    #[serde(rename = "ai.unload")]
    AiUnload,
    /// Delete an installed model's files; requires confirm=true.
    #[serde(rename = "ai.remove")]
    AiRemove {
        model: nf_types::AiModel,
        #[serde(default)]
        confirm: bool,
    },
    /// Import an EDF/EDF+, Mind Monitor CSV, `.neurofeed` or raw body file
    /// into History. Returns the new session id and what was lost.
    #[serde(rename = "history.import")]
    HistoryImport(crate::import::ImportRequest),
    /// Band-math drowsiness guard on/off (protocols with a guard lane).
    #[serde(rename = "guard.set")]
    GuardSet { enabled: bool },
    /// Start a session: enters the fit check.
    #[serde(rename = "feedback.start")]
    FeedbackStart {
        /// Training length, 1..=120 min; default the protocol's.
        #[serde(default)]
        minutes: Option<u32>,
        /// Wall clock for the session recording (injected by the shell).
        #[serde(default)]
        wall_clock_unix_ms: Option<f64>,
    },
    /// Permanently delete a saved session. `confirm` must be true.
    /// Save the recording interrupted by a crash to History.
    #[serde(rename = "recovery.restore")]
    RecoveryRestore,
    /// Drop the recording interrupted by a crash.
    #[serde(rename = "recovery.discard")]
    RecoveryDiscard,
    /// Replay a saved session in the graph views (connects `replay:<id>`).
    #[serde(rename = "history.open")]
    HistoryOpen { id: u64 },
    #[serde(rename = "history.delete")]
    HistoryDelete {
        id: u64,
        #[serde(default)]
        confirm: bool,
    },
    /// Change user settings (appearance, subject, onboarding, debug).
    #[serde(rename = "settings.set")]
    SettingsSet(crate::settings::SettingsPatch),
    /// Replace a saved session's notes (≤ 4000 characters).
    #[serde(rename = "history.notes")]
    HistoryNotes { id: u64, notes: String },
    /// End the session now and build the summary.
    #[serde(rename = "feedback.stop")]
    FeedbackStop,
    #[serde(rename = "feedback.pause")]
    FeedbackPause,
    /// Debug: replace the protocol feature with `value` (`null` = off).
    #[serde(rename = "feedback.override")]
    FeedbackOverride {
        #[serde(default)]
        value: Option<f64>,
    },
    #[serde(rename = "feedback.resume")]
    FeedbackResume,
    /// Fit check → calibration (45 good seconds, at most 60 s).
    #[serde(rename = "calibration.start")]
    CalibrationStart {
        /// Start even though the fit check has not passed.
        #[serde(default)]
        anyway: bool,
    },
    /// Finish calibration now with the good seconds collected (>= 10).
    #[serde(rename = "calibration.skip")]
    CalibrationSkip,
    /// Skip calibration and reuse the last baseline of this device + protocol.
    #[serde(rename = "calibration.reuse")]
    CalibrationReuse,
    /// Reward percentile 1..=99 (difficulty); live while training.
    #[serde(rename = "threshold.set")]
    ThresholdSet { percentile: u8 },
    /// Simulator faults (tests): make pads bad and/or stop data (radio dropout).
    /// Add a timed simulator fault (see `nf_core::faults`). Returns its id.
    #[serde(rename = "sim.fault.add")]
    SimFaultAdd {
        kind: crate::faults::FaultTag,
        /// `disconnect` only: reconnect after this many seconds.
        #[serde(default)]
        reconnect_after_s: Option<f64>,
        /// `noise` only: probability each channel-second is clean (default 0.5).
        #[serde(default)]
        clean_fraction: Option<f64>,
        /// `out_of_range` only: nan (default), inf or rail.
        #[serde(default)]
        value: Option<crate::faults::BadValue>,
        /// Seconds until it clears itself (default: until `sim.fault.clear`).
        #[serde(default)]
        duration_s: Option<f64>,
        /// Channel names to affect (default: the kind's usual pads or all).
        #[serde(default)]
        channels: Vec<String>,
    },
    /// Clear one fault by id, or all (`id` omitted).
    #[serde(rename = "sim.fault.clear")]
    SimFaultClear {
        #[serde(default)]
        id: Option<u32>,
    },
    #[serde(rename = "sim.fault")]
    SimFault {
        /// Pad names to corrupt (huge artifact); empty = none.
        #[serde(default)]
        bad_pads: Vec<String>,
        /// Deliver no data (looks like a disconnect).
        #[serde(default)]
        dropout: bool,
        /// Nod the head (accelerometer movement artifact).
        #[serde(default)]
        motion: bool,
        /// One eye blink every 2 s on the frontal pads.
        #[serde(default)]
        blink: bool,
        /// Jaw-clench EMG on the temporal pads.
        #[serde(default)]
        clench: bool,
        /// Drowsiness: extra 2 Hz delta on every pad (trips the guard).
        #[serde(default)]
        drowsy: bool,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "cmd", deny_unknown_fields)]
pub enum Query {
    #[serde(rename = "app.status")]
    AppStatus,
    #[serde(rename = "view.list")]
    ViewList,
    #[serde(rename = "bands.get")]
    BandsGet {
        #[serde(default)]
        scale: Option<BandScale>,
    },
    /// Monitor viewports (window, Follow/Inspect, visible range) and Bands display.
    #[serde(rename = "monitor.get")]
    MonitorGet,
    #[serde(rename = "device.list")]
    DeviceList,
    #[serde(rename = "device.status")]
    DeviceStatus,
    /// Recent samples per channel.
    #[serde(rename = "raw.get")]
    RawGet {
        /// 0 < seconds <= 10; default 1.
        #[serde(default)]
        seconds: Option<f64>,
        /// Conditioned (high-pass + notch) instead of as received; default true.
        #[serde(default)]
        filtered: Option<bool>,
    },
    /// Analysis exclusions, eligible channels, remembered ones, the hint.
    #[serde(rename = "analysis.get")]
    AnalysisGet,
    /// One averaged spectrum (Welch, linear mean, then dB) of the eligible
    /// selected electrodes over a window of the raw ring.
    #[serde(rename = "psd.average")]
    PsdAverage {
        /// Window length, 2..=8 s; default: the PSD monitor's.
        #[serde(default)]
        window_s: Option<f64>,
        /// Window end (session seconds); default: the PSD viewport's end
        /// (Inspect) or the newest sample (Follow).
        #[serde(default)]
        end_s: Option<f64>,
        /// Electrodes (empty / missing = the PSD monitor's selection).
        #[serde(default)]
        electrodes: Option<Vec<String>>,
        /// Upper frequency, 1..=100 Hz; default: the PSD range.
        #[serde(default)]
        max_hz: Option<f64>,
    },
    /// Power spectral density of the last 1 s window per channel.
    #[serde(rename = "psd.get")]
    PsdGet {
        /// Only this channel (by name, e.g. "TP9").
        #[serde(default)]
        channel: Option<String>,
        /// Upper frequency, 1..=64 Hz; default 50.
        #[serde(default)]
        max_hz: Option<f64>,
    },
    /// Heart rate from PPG (latest, confidence, history), every 1 s.
    #[serde(rename = "hr.get")]
    HrGet,
    /// SpO2 from PPG (ratio of ratios), every 1 s.
    #[serde(rename = "spo2.get")]
    Spo2Get,
    /// Recent raw optical samples per PPG channel.
    #[serde(rename = "ppg.get")]
    PpgGet {
        /// 0 < seconds <= 30; default 5.
        #[serde(default)]
        seconds: Option<f64>,
    },
    /// Mains detection / notch and per-pad quality (usable >= 80).
    #[serde(rename = "signal.status")]
    SignalStatus,
    /// Last evaluated artifact second.
    #[serde(rename = "artifact.status")]
    ArtifactStatus,
    /// Band features (atr, tar, btr, relative alpha/theta/beta/delta), mean over usable pads.
    #[serde(rename = "features.get")]
    FeaturesGet,
    /// Amplitude histogram of the conditioned signal per channel.
    #[serde(rename = "histogram.get")]
    HistogramGet {
        /// 0 < seconds <= 10; default 2.
        #[serde(default)]
        seconds: Option<f64>,
        /// 2..=512; default 64.
        #[serde(default)]
        bins: Option<usize>,
        /// Range ±µV around the mean, 1..=10000; default 100.
        #[serde(default)]
        half_range_uv: Option<f64>,
        /// Window end (session s); default the newest sample.
        #[serde(default)]
        end_s: Option<f64>,
    },
    /// Spectrogram columns (oldest first, every 0.25 s, up to 300 s) in dB:
    /// one channel, or (no channel) the linear-power average of the
    /// Spectrogram display's eligible electrodes.
    #[serde(rename = "spectrogram.get")]
    SpectrogramGet {
        /// Channel name; default the averaged display selection.
        #[serde(default)]
        channel: Option<String>,
        /// Seconds back from the newest column, 0 < s <= 300; default 30.
        #[serde(default)]
        seconds: Option<f64>,
        /// Upper frequency, 1..=64 Hz; default 50.
        #[serde(default)]
        max_hz: Option<f64>,
    },
    /// Saved sessions, newest first.
    #[serde(rename = "history.list")]
    HistoryList,
    /// One saved session: metadata, summary and its feedback seconds.
    #[serde(rename = "history.get")]
    HistoryGet { id: u64 },
    /// Export a saved session (base64).
    #[serde(rename = "history.export")]
    HistoryExport { id: u64, format: ExportFormat },
    #[serde(rename = "recording.status")]
    RecordingStatus,
    /// Encode the last finished recording; returns base64 bytes.
    #[serde(rename = "recording.export")]
    RecordingExport {
        format: ExportFormat,
        /// EDF start (year, month, day, hour, minute, second, UTC). Default:
        /// the recording's injected wall clock, else 1985-01-01 00:00:00.
        #[serde(default)]
        start: Option<[u16; 6]>,
    },
    #[serde(rename = "protocol.list")]
    ProtocolList,
    /// One protocol; default the selected one.
    #[serde(rename = "protocol.get")]
    ProtocolGet {
        #[serde(default)]
        id: Option<String>,
    },
    /// Check a draft without saving: `{ok, problems: [{field, message}]}`.
    #[serde(rename = "protocol.validate")]
    ProtocolValidate {
        draft: crate::protocols::ProtocolDraft,
        #[serde(default)]
        replace: bool,
    },
    /// Builder draft from a protocol: a custom one as is, a built-in as a
    /// copy with a free id. Default the selected one.
    #[serde(rename = "protocol.draft")]
    ProtocolDraft {
        #[serde(default)]
        id: Option<String>,
    },
    /// Phase, fit, calibration progress, last second, summary.
    #[serde(rename = "feedback.status")]
    FeedbackStatus,
    /// Nerd sheet: the numbers behind the reward / guard decision.
    #[serde(rename = "feedback.nerd")]
    FeedbackNerd,
    /// All persisted settings.
    #[serde(rename = "settings.get")]
    SettingsGet,
    /// Audio settings, the live cue and the guard state.
    #[serde(rename = "feedback.trust")]
    FeedbackTrust,
    #[serde(rename = "history.trust")]
    HistoryTrust { id: u64 },
    #[serde(rename = "streaming.status")]
    StreamingStatus,
    /// AI models (install / load state), scorer, threshold and live scores.
    #[serde(rename = "ai.status")]
    AiStatus,
    #[serde(rename = "audio.status")]
    AudioStatus,
    /// Parse an import without saving: kept / lost summary for the dialog.
    #[serde(rename = "history.import_preview")]
    HistoryImportPreview(crate::import::ImportRequest),
    /// Per-second results of the current/last session.
    #[serde(rename = "feedback.result.get")]
    FeedbackResultGet {
        /// Only the last N; default all.
        #[serde(default)]
        last: Option<usize>,
    },
}

/// Either kind, as parsed from an id + JSON params.
#[derive(Debug, Clone, PartialEq)]
pub enum Request {
    Command(Command),
    Query(Query),
}

/// `Ok` = enabled; `Err(reason)` = disabled, reason shown as tooltip / error.
pub type EnabledFn = fn(&AppState) -> Result<(), String>;

#[derive(Debug, Clone, Copy)]
pub struct CommandSpec {
    pub id: &'static str,
    pub label: &'static str,
    pub group: &'static str,
    pub read_only: bool,
    pub description: &'static str,
    pub enabled: EnabledFn,
}

fn has_recovery(s: &AppState) -> Result<(), String> {
    if s.recovery.is_some() {
        Ok(())
    } else {
        Err("no interrupted recording".into())
    }
}
fn debug_on(s: &AppState) -> Result<(), String> {
    if s.settings.debug {
        Ok(())
    } else {
        Err("turn on debug mode first (Settings → Debug)".into())
    }
}
fn always(_: &AppState) -> Result<(), String> {
    Ok(())
}
fn can_scan(s: &AppState) -> Result<(), String> {
    if s.scanners.is_empty() {
        Err("no real-device providers (simulators only)".into())
    } else {
        Ok(())
    }
}
fn needs_device(s: &AppState) -> Result<(), String> {
    s.device.as_ref().map(|_| ()).ok_or_else(|| "no device connected".to_owned())
}
fn can_pause(s: &AppState) -> Result<(), String> {
    needs_device(s)?;
    if s.paused {
        Err("already paused".into())
    } else {
        Ok(())
    }
}
fn can_resume(s: &AppState) -> Result<(), String> {
    if s.paused {
        Ok(())
    } else {
        Err("not paused".into())
    }
}

fn has_ppg(s: &AppState) -> Result<(), String> {
    needs_device(s)?;
    if s.device.as_ref().is_some_and(|d| d.has_ppg()) {
        Ok(())
    } else {
        Err(format!("{} has no PPG (HR/SpO2: Muse 2 and Muse S only)", s.device.as_ref().map_or("device", |d| d.name.as_str())))
    }
}
fn has_signal(s: &AppState) -> Result<(), String> {
    needs_device(s)?;
    if s.bands.latest().is_some() {
        Ok(())
    } else {
        Err("no signal yet (needs 1 s of data)".into())
    }
}
fn can_record(s: &AppState) -> Result<(), String> {
    needs_device(s)?;
    if s.recording.as_ref().is_some_and(|r| r.active) {
        Err("already recording".into())
    } else {
        Ok(())
    }
}
fn is_recording(s: &AppState) -> Result<(), String> {
    if s.recording.as_ref().is_some_and(|r| r.active) {
        Ok(())
    } else {
        Err("not recording".into())
    }
}
fn has_recording(s: &AppState) -> Result<(), String> {
    match &s.recording {
        Some(r) if !r.active => Ok(()),
        Some(_) => Err("recording in progress; stop it first".into()),
        None => Err("nothing recorded yet".into()),
    }
}

fn fb_idle(s: &AppState) -> Result<(), String> {
    if s.feedback.phase.active() {
        Err("locked during a session; stop it first".into())
    } else {
        Ok(())
    }
}
fn fb_can_start(s: &AppState) -> Result<(), String> {
    needs_device(s)?;
    fb_idle(s)?;
    let p = &s.feedback.protocol;
    if let Some(r) = &p.unavailable {
        return Err(format!("{}: {r}", p.title));
    }
    if p.guard_only {
        s.ai.ready_reason().map_err(|r| format!("{} needs the AI model (no band-math fallback): {r}", p.title))?;
    }
    Ok(())
}
fn has_ai(s: &AppState) -> Result<(), String> {
    if s.ai.runtime {
        Ok(())
    } else {
        Err(crate::ai::NO_RUNTIME.into())
    }
}
fn ai_loaded(s: &AppState) -> Result<(), String> {
    has_ai(s)?;
    if s.ai.models.iter().any(|m| matches!(m.state, nf_types::AiModelState::Ready { .. } | nf_types::AiModelState::Loading)) {
        Ok(())
    } else {
        Err("no model loaded".into())
    }
}
fn ai_idle(s: &AppState) -> Result<(), String> {
    has_ai(s)?;
    if s.feedback.phase.active() && s.ai.ready() {
        Err("the AI guard is in use; stop the session first".into())
    } else {
        Ok(())
    }
}
fn fb_active(s: &AppState) -> Result<(), String> {
    if s.feedback.phase.active() {
        Ok(())
    } else {
        Err("no session running".into())
    }
}
fn fb_playing(s: &AppState) -> Result<(), String> {
    match s.feedback.phase {
        Phase::Playing => Ok(()),
        Phase::Paused { .. } => Err("already paused".into()),
        _ => Err("not training".into()),
    }
}
fn fb_paused(s: &AppState) -> Result<(), String> {
    match s.feedback.phase {
        Phase::Paused { reason: PauseReason::User } => Ok(()),
        Phase::Paused { reason: PauseReason::BadSignal } => Err("waiting for good signal; resumes by itself".into()),
        Phase::Paused { reason: PauseReason::Disconnected } => Err("waiting for the device to reconnect".into()),
        _ => Err("not paused".into()),
    }
}
fn fb_fit(s: &AppState) -> Result<(), String> {
    if s.feedback.phase == Phase::FitCheck {
        Ok(())
    } else {
        Err("only from the fit check".into())
    }
}
fn fb_calibrating(s: &AppState) -> Result<(), String> {
    if s.feedback.phase != Phase::Calibrating {
        return Err("not calibrating".into());
    }
    let v = s.feedback.calibration.as_ref().map_or(0, |c| c.valid_s);
    if v < crate::feedback::MIN_CALIBRATION_S {
        return Err(format!("only {v} good seconds so far; needs {}", crate::feedback::MIN_CALIBRATION_S));
    }
    Ok(())
}
fn fb_reuse(s: &AppState) -> Result<(), String> {
    if !matches!(s.feedback.phase, Phase::FitCheck | Phase::Calibrating) {
        return Err("only before training starts".into());
    }
    s.feedback.last_baseline().map(|_| ()).ok_or_else(|| "no stored baseline for this device and protocol".into())
}
fn fb_threshold(s: &AppState) -> Result<(), String> {
    if s.feedback.protocol.stability.is_some() {
        return Err("this protocol rewards steadiness; it has no percentile".into());
    }
    if s.feedback.phase == Phase::Calibrating {
        return Err("locked during calibration".into());
    }
    Ok(())
}
fn can_delete_protocol(s: &AppState) -> Result<(), String> {
    if s.custom_protocols.is_empty() {
        return Err("no custom protocols".into());
    }
    fb_idle(s)
}
fn has_history(s: &AppState) -> Result<(), String> {
    if s.history.is_empty() {
        return Err("no saved sessions".into());
    }
    Ok(())
}

fn sim_device(s: &AppState) -> Result<(), String> {
    match &s.device {
        Some(d) if d.simulated => Ok(()),
        Some(_) => Err("only for simulated devices".into()),
        None => Err("no device connected".into()),
    }
}

const fn spec(
    id: &'static str,
    label: &'static str,
    group: &'static str,
    read_only: bool,
    description: &'static str,
    enabled: EnabledFn,
) -> CommandSpec {
    CommandSpec { id, label, group, read_only, description, enabled }
}

/// The full catalog, in display order.
pub const SPECS: &[CommandSpec] = &[
    spec("app.status", "Status", "app", true, "Current view, sidebar, pause, scale, device, time and revision.", always),
    spec("view.list", "List views", "view", true, "All views in sidebar order, with labels and whether implemented.", always),
    spec("view.set", "Switch view", "view", false, "Switch the main view.", always),
    spec("sidebar.set", "Show/hide sidebar", "view", false, "Show or hide the sidebar.", always),
    spec("stream.pause", "Pause", "stream", false, "Freeze incoming band data.", can_pause),
    spec("stream.resume", "Resume", "stream", false, "Resume incoming band data.", can_resume),
    spec("scale.set", "Band scale", "bands", false, "Absolute (log10) or relative (share of total) scaling.", always),
    spec("bands.get", "Band powers", "bands", true, "Latest band powers per channel (delta..gamma).", always),
    spec("monitor.get", "Monitor viewports", "monitor", true, "Per monitor: window, Follow/Inspect, visible range; Bands electrodes and hidden bands.", always),
    spec("monitor.viewport", "Monitor window", "monitor", false, "Set a monitor's window length (saved) and/or Follow / Inspect.", always),
    spec("monitor.zoom", "Zoom monitor", "monitor", false, "Zoom a monitor's time axis by a factor around a focal point (0 left .. 1 right).", always),
    spec("monitor.pan", "Pan monitor", "monitor", false, "Move a monitor's time window by seconds; enters Inspect.", always),
    spec("monitor.display", "Bands display", "monitor", false, "Electrodes in the Bands average (empty = all) and hidden bands.", always),
    spec("monitor.raw", "Raw EEG display", "monitor", false, "Raw EEG: sweep or scroll traces, Y scale (auto, ±50/100/200 µV) and shown electrodes (empty = all).", always),
    spec("monitor.psd", "PSD display", "monitor", false, "PSD: frequency range (60 or 100 Hz) and electrodes in the average (empty = all).", always),
    spec("monitor.overview", "Overview timeline", "monitor", false, "Show/hide a view's overview timeline (saved per view; default on for psd and spectrogram).", always),
    spec("monitor.histogram", "Histogram display", "monitor", false, "Histogram: µV range (50/100/200) and electrodes pooled (empty = all).", always),
    spec("monitor.spectrogram", "Spectrogram display", "monitor", false, "Spectrogram: electrodes averaged (empty = all); lock the dB colour range (db_min, db_max) or auto.", always),
    spec("analysis.get", "Analysis channels", "analysis", true, "Per channel: excluded from analysis, remembered for this device, eligible; restored notice and quality hint.", always),
    spec("analysis.exclude", "Exclude channel", "analysis", false, "Exclude a channel from feedback and all derived graphs (raw/recording keep it). Needs confirm=true; remember=true stores it for this device.", needs_device),
    spec("analysis.include", "Include channel", "analysis", false, "Use a channel in analysis again; forgets a remembered exclusion.", needs_device),
    spec("analysis.hint_dismiss", "Dismiss quality hint", "analysis", false, "Hide the contact-quality hint for this connection.", always),
    spec("analysis.ack_restored", "Acknowledge restored", "analysis", false, "Hide the notice that remembered exclusions were restored.", always),
    spec("psd.average", "Averaged spectrum", "signal", true, "One Welch spectrum (linear mean over eligible selected electrodes, then dB) for a 2–8 s window of the last 5 min.", has_signal),
    spec("device.list", "List devices", "device", true, "Connectable devices (simulators and registered providers).", always),
    spec("device.connect", "Connect", "device", false, "Connect a device by id, e.g. sim:muse or sim:crown.", always),
    spec("device.scan", "Scan", "device", false, "Timed discovery (Muse BLE, Crown OSC). The Device dialog watches until it closes instead.", can_scan),
    spec("device.disconnect", "Disconnect", "device", false, "Disconnect the current device.", needs_device),
    spec(
        "device.dialog",
        "Device dialog",
        "device",
        false,
        "Open/close the Device dialog. While it is open, Muse BLE and Crown OSC stay in discovery.",
        always,
    ),
    spec("device.status", "Device status", "device", true, "Connected device, link, scan_mode, auto_reconnect target and buffered snapshot count.", always),
    spec(
        "sim.configure",
        "Configure simulator",
        "device",
        false,
        "Seed, alpha/noise/mains/DC in µV. Reconnects a running simulator.",
        always,
    ),
    spec("raw.get", "Raw EEG", "signal", true, "Last N seconds of samples per channel (filtered or as received), µV.", needs_device),
    spec("psd.get", "Spectrum", "signal", true, "PSD (µV²/Hz) of the last 1 s per channel, with alpha peak.", has_signal),
    spec("recording.start", "Start recording", "recording", false, "Record raw EEG + band snapshots in memory.", can_record),
    spec("recording.stop", "Stop recording", "recording", false, "Stop and keep the recording for export.", is_recording),
    spec("hr.get", "Heart rate", "optics", true, "Heart rate (bpm) from PPG with confidence and history.", has_ppg),
    spec("spo2.get", "SpO2", "optics", true, "Blood oxygen (%) from PPG IR/red with confidence and history.", has_ppg),
    spec("ppg.get", "PPG samples", "optics", true, "Last N seconds of raw optical samples per PPG channel.", has_ppg),
    spec(
        "artifact.status",
        "Artifact status",
        "signal",
        true,
        "Last second's movement score (g), blink count, jaw clench and the artifact fed to feedback.",
        always,
    ),
    spec("signal.status", "Signal status", "signal", true, "Mains detected/applied, notch lock, per-pad quality and usability.", always),
    spec("features.get", "Features", "signal", true, "Band ratio features averaged over usable pads.", has_signal),
    spec("histogram.get", "Histogram", "signal", true, "Amplitude histogram of the conditioned signal per channel, plus the pooled histogram of the display selection.", has_signal),
    spec("spectrogram.get", "Spectrogram", "signal", true, "PSD dB columns every 0.25 s (up to 300 s): one channel or the averaged display selection.", has_signal),
    spec("mains.set", "Set notch", "signal", false, "Notch mode: auto, 50, 60 or off.", always),
    spec("channel.set", "Select channel", "signal", false, "Channel for single-channel views.", needs_device),
    spec(
        "history.list",
        "List sessions",
        "history",
        true,
        "Saved sessions (newest first): date, device, protocol, duration, summary.",
        always,
    ),
    spec(
        "history.get",
        "Get session",
        "history",
        true,
        "One saved session with its summary and per-second feedback (value, threshold, flags).",
        always,
    ),
    spec("history.export", "Export session", "history", true, "Export a saved session as nfed6 | raw_body | edf | pdf (base64).", always),
    spec(
        "history.import",
        "Import recording",
        "history",
        false,
        "Import EDF/EDF+, Mind Monitor CSV, .neurofeed or raw body (base64) into History; one Muse or Crown montage is kept.",
        always,
    ),
    spec(
        "history.import_preview",
        "Preview import",
        "history",
        true,
        "Parse an import file without saving: channels, duration, and what the import loses.",
        always,
    ),
    spec("recovery.restore", "Recover recording", "history", false, "Save the recording interrupted by a crash.", has_recovery),
    spec("recovery.discard", "Discard recovery", "history", false, "Drop the recording interrupted by a crash.", has_recovery),
    spec("history.open", "Open in graphs", "history", false, "Replay a saved session as the live device (not recorded again).", has_history),
    spec("history.delete", "Delete session", "history", false, "Permanently delete a saved session; requires confirm=true.", has_history),
    spec(
        "settings.set",
        "Change settings",
        "settings",
        false,
        "Appearance, UI layout (auto/compact/regular), language (auto/en/de), subject id, onboarding done, debug mode, gesture markers.",
        always,
    ),
    spec(
        "settings.get",
        "Settings",
        "settings",
        true,
        "All persisted settings: user, audio, mains, band scale, music folder, stability, guard.",
        always,
    ),
    spec("history.notes", "Session notes", "history", false, "Replace the free-text notes of a saved session.", has_history),
    spec("recording.status", "Recording status", "recording", true, "Active or last recording: device, duration, samples, bytes.", always),
    spec(
        "recording.export",
        "Export recording",
        "recording",
        true,
        "Encode the last recording as nfed6, raw_body or edf (base64).",
        has_recording,
    ),
    spec("protocol.list", "Protocols", "feedback", true, "Built-in and custom protocols with availability.", always),
    spec(
        "protocol.validate",
        "Check protocol draft",
        "feedback",
        true,
        "Validate a Protocol Builder draft: problems per field (id, title, summary, minutes, inhibit, muffle_reward).",
        always,
    ),
    spec(
        "protocol.draft",
        "Protocol draft",
        "feedback",
        true,
        "Builder draft from a protocol (built-ins as a copy) and notes on what is lost.",
        always,
    ),
    spec(
        "protocol.save",
        "Save protocol",
        "feedback",
        false,
        "Create a custom protocol from a draft, or update one with replace=true.",
        fb_idle,
    ),
    spec("protocol.delete", "Delete protocol", "feedback", false, "Delete a custom protocol; requires confirm=true.", can_delete_protocol),
    spec("protocol.get", "Protocol", "feedback", true, "One protocol (default the selected one).", always),
    spec("protocol.set", "Choose protocol", "feedback", false, "Select the training protocol.", fb_idle),
    spec("stability.set", "Stability settings", "feedback", false, "Band Stability window (1..=30) and difficulty (0..=0.5).", fb_idle),
    spec(
        "streaming.set",
        "Streaming settings",
        "streaming",
        false,
        "OSC out over UDP: enabled, ip, port, prefix (/muse), separate_groups (PPG/IMU/bands too).",
        always,
    ),
    spec(
        "feedback.trust",
        "Live trust trace",
        "feedback",
        true,
        "Per-second trust rows (clean/dirty reason, percentile vs threshold, held back, guard) and totals of the current run.",
        always,
    ),
    spec(
        "feedback.nerd",
        "Nerd sheet",
        "feedback",
        true,
        "Reward pile and guard internals: histograms, threshold, live value, mean, spread, success rate.",
        always,
    ),
    spec("history.trust", "Session trust", "history", true, "Trust rows, totals and gesture marks of a saved session.", always),
    spec("ai.status", "AI status", "ai", true, "AI models (install/load state, folder, guide), scorer, threshold mode and the live head scores.", always),
    spec(
        "ai.set",
        "AI settings",
        "ai",
        false,
        "model (cbramod_a_vig|reve_base) or scorer (ai.a_vig|ai.wake_light|ai.a_vig_reve|ai.wake_light_reve), threshold_mode (fixed|percentile), fixed_threshold 0.05..=0.95, auto_load.",
        has_ai,
    ),
    spec("ai.install", "Install AI model", "ai", false, "Download the model (CBraMod), or import a weights file by path (REVE is gated: import). SHA-256 checked.", has_ai),
    spec("ai.load", "Load AI model", "ai", false, "Load an installed model; it then scores once per second.", has_ai),
    spec("ai.unload", "Unload AI model", "ai", false, "Unload the model (stays installed).", ai_loaded),
    spec("ai.remove", "Remove AI model", "ai", false, "Delete a model's files; requires confirm=true.", ai_idle),
    spec("streaming.status", "Streaming status", "streaming", true, "OSC settings, groups/addresses, packets and bytes sent.", always),
    spec(
        "audio.set",
        "Audio settings",
        "audio",
        false,
        "Reward output (chime|rain|binaural|music|none), background, guard sound, volumes.",
        always,
    ),
    spec(
        "audio.status",
        "Audio status",
        "audio",
        true,
        "Audio settings, what should sound now (cue), guard state and binaural presets.",
        always,
    ),
    spec(
        "guard.set",
        "Drowsiness guard",
        "feedback",
        false,
        "Band-math (delta, p75) drowsiness guard on/off; warns and may mute reward.",
        crate::audio::can_set_guard,
    ),
    spec("feedback.start", "Start session", "feedback", false, "Start a session (fit check first).", fb_can_start),
    spec("feedback.stop", "End session", "feedback", false, "End the session and build the summary.", fb_active),
    spec("feedback.override", "Feature override", "feedback", false, "Debug: force the feature value (null = off).", debug_on),
    spec("feedback.pause", "Pause training", "feedback", false, "Pause training.", fb_playing),
    spec("feedback.resume", "Resume training", "feedback", false, "Resume a user pause.", fb_paused),
    spec("feedback.status", "Session status", "feedback", true, "Phase, fit, calibration, last second, summary.", always),
    spec("feedback.result.get", "Session results", "feedback", true, "Per-second results of the current or last session.", always),
    spec("calibration.start", "Calibrate", "feedback", false, "Start calibration (45 good s, max 60 s).", fb_fit),
    spec("calibration.skip", "Start now", "feedback", false, "Finish calibration early with what was collected.", fb_calibrating),
    spec("calibration.reuse", "Reuse last baseline", "feedback", false, "Skip calibration using the last baseline.", fb_reuse),
    spec("threshold.set", "Difficulty", "feedback", false, "Reward percentile 1..=99 (live while training).", fb_threshold),
    spec(
        "sim.fault",
        "Simulate faults",
        "device",
        false,
        "Corrupt pads, drop data, inject motion/blink/clench artifacts or drowsy delta on a simulator (tests).",
        sim_device,
    ),
    spec(
        "sim.fault.add",
        "Add simulated fault",
        "device",
        false,
        "Timed fault: disconnect (auto-reconnect), movement, blink, clench, noise (clean_fraction), spikes, glitch, out_of_range.",
        sim_device,
    ),
    spec("sim.fault.clear", "Clear simulated faults", "device", false, "Clear one fault by id, or all.", always),
    spec("clock.advance", "Advance clock", "time", false, "Advance session time (headless/tests). Max 3600 s per call.", always),
    spec("events.drain", "Drain events", "app", false, "Return and clear events since the last drain.", always),
];

pub fn find(id: &str) -> Option<&'static CommandSpec> {
    SPECS.iter().find(|s| s.id == id)
}

/// JSON Schema (2020-12, inlined) of a command's params, without the tag.
pub fn input_schema(id: &str) -> Option<Value> {
    let spec = find(id)?;
    let gen = schemars::generate::SchemaSettings::draft2020_12().with(|s| s.inline_subschemas = true).into_generator();
    let root = if spec.read_only { gen.into_root_schema_for::<Query>() } else { gen.into_root_schema_for::<Command>() };
    let root = root.to_value();
    let variants = root.get("oneOf").and_then(Value::as_array)?;
    let mut v = variants.iter().find(|v| v.pointer("/properties/cmd/const").and_then(Value::as_str) == Some(id))?.clone();
    let obj = v.as_object_mut()?;
    if let Some(p) = obj.get_mut("properties").and_then(Value::as_object_mut) {
        p.remove("cmd");
    }
    if let Some(r) = obj.get_mut("required").and_then(Value::as_array_mut) {
        r.retain(|x| x != "cmd");
    }
    obj.entry("properties").or_insert_with(|| Value::Object(Default::default()));
    obj.insert("additionalProperties".into(), Value::Bool(false));
    Some(v)
}

fn ai_examples() -> Vec<Request> {
    use Request::{Command as C, Query as Q};
    vec![
        Q(Query::AiStatus),
        C(Command::AiSet(crate::ai::AiPatch { scorer: Some("ai.a_vig".into()), fixed_threshold: Some(0.5), ..Default::default() })),
        C(Command::AiInstall { model: Some(nf_types::AiModel::ReveBase), path: Some("/home/me/Downloads/model.safetensors".into()) }),
        C(Command::AiLoad { model: None }),
        C(Command::AiUnload),
        C(Command::AiRemove { model: nf_types::AiModel::ReveBase, confirm: true }),
    ]
}

/// One instance of every variant (keeps tests honest).
pub fn examples() -> Vec<Request> {
    let mut v = base_examples();
    v.extend(ai_examples());
    v
}

// Flat example list, one line per request (AGENTS.md, complexity exception).
#[allow(clippy::too_many_lines)]
fn base_examples() -> Vec<Request> {
    use Request::{Command as C, Query as Q};
    vec![
        C(Command::ViewSet { view: View::Psd }),
        C(Command::SidebarSet { open: false }),
        C(Command::StreamPause),
        C(Command::StreamResume),
        C(Command::ScaleSet { scale: BandScale::Relative }),
        C(Command::MonitorViewport {
            monitor: crate::monitor::MonitorId::Bands,
            window_s: Some(60.0),
            mode: Some(crate::monitor::ViewportMode::Inspect),
            end_s: None,
        }),
        C(Command::MonitorZoom { monitor: crate::monitor::MonitorId::Bands, factor: 2.0, focal: Some(0.5) }),
        C(Command::MonitorPan { monitor: crate::monitor::MonitorId::Bands, seconds: -5.0 }),
        C(Command::MonitorDisplay { electrodes: Some(vec!["AF7".into()]), hidden_bands: Some(vec![nf_types::Band::Gamma]) }),
        C(Command::MonitorRaw {
            mode: Some(crate::monitor::RawMode::Scroll),
            scale: Some(crate::monitor::RawScale::Uv100),
            electrodes: Some(vec!["TP9".into(), "TP10".into()]),
        }),
        Q(Query::MonitorGet),
        C(Command::MonitorPsd { range: Some(crate::monitor::PsdRange::Hz100), electrodes: Some(vec!["AF7".into(), "AF8".into()]) }),
        C(Command::MonitorOverview { monitor: crate::monitor::MonitorId::Bands, on: true }),
        C(Command::MonitorHistogram { range: Some(crate::monitor::HistRange::Uv200), electrodes: Some(vec!["AF7".into()]) }),
        C(Command::MonitorSpectrogram { electrodes: None, db_min: Some(-20.0), db_max: Some(30.0), auto: None }),
        Q(Query::AnalysisGet),
        C(Command::AnalysisExclude { channel: "AF7".into(), confirm: true, remember: false }),
        C(Command::AnalysisInclude { channel: "AF7".into() }),
        C(Command::AnalysisHintDismiss),
        C(Command::AnalysisAckRestored),
        Q(Query::PsdAverage { window_s: Some(4.0), end_s: None, electrodes: None, max_hz: Some(60.0) }),
        C(Command::DeviceConnect { id: "sim:muse".into() }),
        C(Command::DeviceDisconnect),
        C(Command::DeviceDialog { open: true }),
        C(Command::DeviceScan { seconds: Some(5.0) }),
        C(Command::SimConfigure {
            seed: Some(1),
            alpha_uv: Some(20.0),
            noise_uv: None,
            mains_uv: None,
            mains_hz: None,
            dc_uv: None,
            hr_bpm: Some(72.0),
            spo2_pct: None,
            hrv_ms: None,
        }),
        C(Command::ClockAdvance { seconds: 1.0 }),
        C(Command::EventsDrain),
        C(Command::RecordingStart { wall_clock_unix_ms: Some(1_793_000_000_000.0) }),
        C(Command::RecordingStop),
        C(Command::MainsSet { mode: MainsMode::Hz60 }),
        C(Command::ChannelSet { channel: "AF7".into() }),
        C(Command::ProtocolSet { id: "openMonitor".into(), minutes: Some(20) }),
        C(Command::StabilitySet { window: Some(12), difficulty: Some(0.2), reset: false }),
        C(Command::FeedbackStart { minutes: Some(5), wall_clock_unix_ms: None }),
        C(Command::FeedbackStop),
        C(Command::HistoryOpen { id: 1 }),
        C(Command::RecoveryRestore),
        C(Command::RecoveryDiscard),
        C(Command::HistoryDelete { id: 1, confirm: true }),
        C(Command::SettingsSet(crate::settings::SettingsPatch { subject: Some("p01".into()), ..Default::default() })),
        Q(Query::SettingsGet),
        Q(Query::FeedbackNerd),
        C(Command::HistoryNotes { id: 1, notes: "felt calm".into() }),
        C(Command::FeedbackPause),
        C(Command::FeedbackOverride { value: Some(0.4) }),
        C(Command::FeedbackResume),
        C(Command::CalibrationStart { anyway: false }),
        C(Command::CalibrationSkip),
        C(Command::CalibrationReuse),
        C(Command::ThresholdSet { percentile: 50 }),
        C(Command::SimFault { bad_pads: vec!["AF7".into()], dropout: false, motion: false, blink: false, clench: false, drowsy: false }),
        C(Command::SimFaultAdd {
            kind: crate::faults::FaultTag::Noise,
            reconnect_after_s: None,
            clean_fraction: Some(0.2),
            value: None,
            duration_s: Some(30.0),
            channels: vec!["AF7".into()],
        }),
        C(Command::SimFaultClear { id: None }),
        Q(Query::ProtocolList),
        Q(Query::ProtocolGet { id: None }),
        Q(Query::ProtocolDraft { id: Some("restAwake".into()) }),
        Q(Query::ProtocolValidate { draft: crate::protocols::example_draft(), replace: false }),
        C(Command::ProtocolSave { draft: crate::protocols::example_draft(), replace: false }),
        C(Command::ProtocolDelete { id: "calm-focus".into(), confirm: true }),
        Q(Query::FeedbackStatus),
        Q(Query::AudioStatus),
        Q(Query::StreamingStatus),
        Q(Query::FeedbackTrust),
        Q(Query::HistoryTrust { id: 1 }),
        C(Command::StreamingSet(crate::streaming::StreamPatch {
            ip: Some("127.0.0.1".into()),
            port: Some(9000),
            separate_groups: Some(true),
            ..Default::default()
        })),
        C(Command::AudioSet(crate::audio::AudioPatch {
            reward_output: Some(nf_audio::RewardOutput::Rain),
            feedback_volume: Some(0.8),
            ..Default::default()
        })),
        C(Command::GuardSet { enabled: true }),
        C(Command::HistoryImport(crate::import::ImportRequest {
            file_name: "session.edf".into(),
            data_base64: "MCAgICAgIA==".into(),
            utc_offset_minutes: Some(60),
        })),
        Q(Query::HistoryImportPreview(crate::import::ImportRequest {
            file_name: "mind_monitor.csv".into(),
            data_base64: "VGltZVN0YW1w".into(),
            utc_offset_minutes: None,
        })),
        Q(Query::FeedbackResultGet { last: Some(10) }),
        Q(Query::SignalStatus),
        Q(Query::ArtifactStatus),
        Q(Query::HrGet),
        Q(Query::Spo2Get),
        Q(Query::PpgGet { seconds: Some(3.0) }),
        Q(Query::FeaturesGet),
        Q(Query::HistogramGet { seconds: Some(1.0), bins: Some(32), half_range_uv: None, end_s: None }),
        Q(Query::SpectrogramGet { channel: None, seconds: Some(30.0), max_hz: Some(40.0) }),
        Q(Query::AppStatus),
        Q(Query::ViewList),
        Q(Query::BandsGet { scale: None }),
        Q(Query::DeviceList),
        Q(Query::DeviceStatus),
        Q(Query::RawGet { seconds: Some(2.0), filtered: None }),
        Q(Query::PsdGet { channel: Some("TP9".into()), max_hz: None }),
        Q(Query::RecordingStatus),
        Q(Query::HistoryList),
        Q(Query::HistoryGet { id: 1 }),
        Q(Query::HistoryExport { id: 1, format: ExportFormat::Nfed6 }),
        Q(Query::RecordingExport { format: ExportFormat::Edf, start: None }),
    ]
}

/// Param names a schema accepts: its `properties`, plus those of any
/// `oneOf` / `anyOf` / `allOf` branch (flattened tagged enums).
fn schema_keys(schema: &Value) -> std::collections::BTreeSet<&str> {
    let mut keys: std::collections::BTreeSet<&str> =
        schema.get("properties").and_then(Value::as_object).map(|p| p.keys().map(String::as_str).collect()).unwrap_or_default();
    for branch in ["oneOf", "anyOf", "allOf"].iter().filter_map(|k| schema.get(*k).and_then(Value::as_array)).flatten() {
        keys.extend(schema_keys(branch));
    }
    keys
}

impl Request {
    pub fn id(&self) -> String {
        let v = match self {
            Request::Command(c) => serde_json::to_value(c),
            Request::Query(q) => serde_json::to_value(q),
        };
        v.ok().and_then(|v| v.get("cmd").and_then(Value::as_str).map(str::to_owned)).unwrap_or_default()
    }

    /// Parse `id` plus a JSON object of params (or null). Strict: unknown
    /// keys are rejected.
    pub fn parse(id: &str, params: Value) -> Result<Request, CoreError> {
        let spec = find(id).ok_or_else(|| CoreError::UnknownCommand(id.to_owned()))?;
        let mut map = match params {
            Value::Null => serde_json::Map::new(),
            Value::Object(m) => m,
            _ => return Err(CoreError::InvalidArgs("params must be an object".into())),
        };
        let schema = input_schema(id).unwrap_or_default();
        let allowed = schema_keys(&schema);
        if let Some(key) = map.keys().find(|k| !allowed.contains(k.as_str())) {
            return Err(CoreError::InvalidArgs(format!("unknown param `{key}` for {id}")));
        }
        map.insert("cmd".into(), Value::String(id.to_owned()));
        let v = Value::Object(map);
        let bad = |e: serde_json::Error| CoreError::InvalidArgs(format!("{id}: {e}"));
        Ok(if spec.read_only {
            Request::Query(serde_json::from_value(v).map_err(bad)?)
        } else {
            Request::Command(serde_json::from_value(v).map_err(bad)?)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn catalog_matches_variants() {
        let ids: Vec<String> = examples().iter().map(Request::id).collect();
        assert_eq!(ids.len(), SPECS.len());
        for id in &ids {
            let spec = find(id).unwrap_or_else(|| panic!("{id} has no spec"));
            let ex = examples().into_iter().find(|e| &e.id() == id);
            assert_eq!(spec.read_only, matches!(ex, Some(Request::Query(_))), "{id} read_only mismatch");
            assert!(input_schema(id).is_some(), "{id} has no schema");
        }
    }

    #[test]
    fn examples_roundtrip_through_parse() {
        for ex in examples() {
            let mut v = match &ex {
                Request::Command(c) => serde_json::to_value(c),
                Request::Query(q) => serde_json::to_value(q),
            }
            .unwrap_or(Value::Null);
            if let Some(m) = v.as_object_mut() {
                m.remove("cmd");
            }
            assert_eq!(Request::parse(&ex.id(), v), Ok(ex));
        }
    }

    #[test]
    fn rejects_unknown_and_bad_params() {
        assert!(matches!(Request::parse("nope", Value::Null), Err(CoreError::UnknownCommand(_))));
        assert!(Request::parse("view.set", json!({ "view": "nowhere" })).is_err());
        assert!(Request::parse("stream.pause", json!({ "extra": 1 })).is_err());
        assert!(Request::parse("view.set", json!({ "view": "psd", "x": 1 })).is_err());
    }

    #[test]
    fn schema_is_typed() {
        let s = input_schema("view.set").unwrap_or_default();
        assert_eq!(s["required"], json!(["view"]));
        assert!(s.pointer("/properties/view/enum").is_some() || s.pointer("/properties/view/oneOf").is_some(), "{s}");
    }
}
