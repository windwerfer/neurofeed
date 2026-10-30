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
    /// Connect a device by id (`sim:muse`, `sim:crown`, ...).
    #[serde(rename = "device.connect")]
    DeviceConnect { id: String },
    #[serde(rename = "device.disconnect")]
    DeviceDisconnect,
    /// Start background discovery on every scanning provider (BLE Muse,
    /// Crown OSC); results appear in `device.list` as they arrive.
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
    #[serde(rename = "history.delete")]
    HistoryDelete {
        id: u64,
        #[serde(default)]
        confirm: bool,
    },
    /// End the session now and build the summary.
    #[serde(rename = "feedback.stop")]
    FeedbackStop,
    #[serde(rename = "feedback.pause")]
    FeedbackPause,
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
    },
    /// Spectrogram columns (oldest first, every 0.25 s, last 30 s) for one channel.
    #[serde(rename = "spectrogram.get")]
    SpectrogramGet {
        /// Channel name; default the selected channel.
        #[serde(default)]
        channel: Option<String>,
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
    /// Phase, fit, calibration progress, last second, summary.
    #[serde(rename = "feedback.status")]
    FeedbackStatus,
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
    match s.feedback.protocol.unavailable {
        Some(r) => Err(format!("{}: {r}", s.feedback.protocol.title)),
        None => Ok(()),
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
    spec("device.list", "List devices", "device", true, "Connectable devices (simulators and registered providers).", always),
    spec("device.connect", "Connect", "device", false, "Connect a device by id, e.g. sim:muse or sim:crown.", always),
    spec("device.scan", "Scan", "device", false, "Discover real devices (Muse BLE, Crown OSC) in the background.", can_scan),
    spec("device.disconnect", "Disconnect", "device", false, "Disconnect the current device.", needs_device),
    spec("device.status", "Device status", "device", true, "Connected device and buffered snapshot count.", always),
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
    spec("histogram.get", "Histogram", "signal", true, "Amplitude histogram of the conditioned signal per channel.", has_signal),
    spec("spectrogram.get", "Spectrogram", "signal", true, "PSD dB columns every 0.25 s for one channel (last 30 s).", has_signal),
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
    spec("history.export", "Export session", "history", true, "Export a saved session as nfed6 | raw_body | edf (base64).", always),
    spec("history.delete", "Delete session", "history", false, "Permanently delete a saved session; requires confirm=true.", has_history),
    spec("recording.status", "Recording status", "recording", true, "Active or last recording: device, duration, samples, bytes.", always),
    spec(
        "recording.export",
        "Export recording",
        "recording",
        true,
        "Encode the last recording as nfed6, raw_body or edf (base64).",
        has_recording,
    ),
    spec("protocol.list", "Protocols", "feedback", true, "Built-in protocols with availability.", always),
    spec("protocol.get", "Protocol", "feedback", true, "One protocol (default the selected one).", always),
    spec("protocol.set", "Choose protocol", "feedback", false, "Select the training protocol.", fb_idle),
    spec("stability.set", "Stability settings", "feedback", false, "Band Stability window (1..=30) and difficulty (0..=0.5).", fb_idle),
    spec("feedback.start", "Start session", "feedback", false, "Start a session (fit check first).", fb_can_start),
    spec("feedback.stop", "End session", "feedback", false, "End the session and build the summary.", fb_active),
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
        "Corrupt pads, drop data, or inject motion/blink/clench artifacts on a simulator (tests).",
        sim_device,
    ),
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

/// One instance of every variant (keeps tests honest).
pub fn examples() -> Vec<Request> {
    use Request::{Command as C, Query as Q};
    vec![
        C(Command::ViewSet { view: View::Psd }),
        C(Command::SidebarSet { open: false }),
        C(Command::StreamPause),
        C(Command::StreamResume),
        C(Command::ScaleSet { scale: BandScale::Relative }),
        C(Command::DeviceConnect { id: "sim:muse".into() }),
        C(Command::DeviceDisconnect),
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
        C(Command::HistoryDelete { id: 1, confirm: true }),
        C(Command::FeedbackPause),
        C(Command::FeedbackResume),
        C(Command::CalibrationStart { anyway: false }),
        C(Command::CalibrationSkip),
        C(Command::CalibrationReuse),
        C(Command::ThresholdSet { percentile: 50 }),
        C(Command::SimFault { bad_pads: vec!["AF7".into()], dropout: false, motion: false, blink: false, clench: false }),
        Q(Query::ProtocolList),
        Q(Query::ProtocolGet { id: None }),
        Q(Query::FeedbackStatus),
        Q(Query::FeedbackResultGet { last: Some(10) }),
        Q(Query::SignalStatus),
        Q(Query::ArtifactStatus),
        Q(Query::HrGet),
        Q(Query::Spo2Get),
        Q(Query::PpgGet { seconds: Some(3.0) }),
        Q(Query::FeaturesGet),
        Q(Query::HistogramGet { seconds: Some(1.0), bins: Some(32), half_range_uv: None }),
        Q(Query::SpectrogramGet { channel: None, max_hz: Some(40.0) }),
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
        let allowed = schema.get("properties").and_then(Value::as_object);
        if let Some(key) = map.keys().find(|k| !allowed.is_some_and(|p| p.contains_key(*k))) {
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
