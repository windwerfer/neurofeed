//! Commands (change state) and queries (read state), plus their catalog.
//!
//! Ids are dotted (`area.verb`); MCP reaches them via `command_run`.
//! Adding an action: add a variant (serde rename = id), a `spec()` entry and
//! an `examples()` entry, then handle it in `Session`. Tests fail on drift.
//! Input schemas are derived with schemars from the variant fields.

use crate::recording::ExportFormat;
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
    },
    /// Advance session time (0 < seconds <= 3600) in 0.1 s steps.
    #[serde(rename = "clock.advance")]
    ClockAdvance { seconds: f64 },
    #[serde(rename = "events.drain")]
    EventsDrain,
    /// Start recording the connected device (raw EEG + bands) in memory.
    #[serde(rename = "recording.start")]
    RecordingStart,
    #[serde(rename = "recording.stop")]
    RecordingStop,
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
    #[serde(rename = "recording.status")]
    RecordingStatus,
    /// Encode the last finished recording; returns base64 bytes.
    #[serde(rename = "recording.export")]
    RecordingExport {
        format: ExportFormat,
        /// EDF start (year, month, day, hour, minute, second); the core has
        /// no wall clock. Default 1985-01-01 00:00:00.
        #[serde(default)]
        start: Option<[u16; 6]>,
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
    spec("recording.status", "Recording status", "recording", true, "Active or last recording: device, duration, samples, bytes.", always),
    spec(
        "recording.export",
        "Export recording",
        "recording",
        true,
        "Encode the last recording as nfed6, raw_body or edf (base64).",
        has_recording,
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
        C(Command::SimConfigure { seed: Some(1), alpha_uv: Some(20.0), noise_uv: None, mains_uv: None, mains_hz: None, dc_uv: None }),
        C(Command::ClockAdvance { seconds: 1.0 }),
        C(Command::EventsDrain),
        C(Command::RecordingStart),
        C(Command::RecordingStop),
        Q(Query::AppStatus),
        Q(Query::ViewList),
        Q(Query::BandsGet { scale: None }),
        Q(Query::DeviceList),
        Q(Query::DeviceStatus),
        Q(Query::RawGet { seconds: Some(2.0), filtered: None }),
        Q(Query::PsdGet { channel: Some("TP9".into()), max_hz: None }),
        Q(Query::RecordingStatus),
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
