//! Streaming out over OSC (UDP) or Lab Streaming Layer (LSL outlets, desktop only). The core decides *what* goes on the wire
//! and encodes the datagrams; a shell-registered [`DatagramSink`] sends them
//! (desktop: `nf_device::UdpSink`; the web build has no UDP).
//!
//! Wire format (legacy `streaming_osc.dart`): one message per chunk of one
//! group, address `<prefix>/<group>`, all args float32:
//! `[t_first, row0 ch0..chN, row1 …]`. Chunks: EEG 12 rows, PPG 6, IMU 3,
//! Bands 1. EEG is the conditioned signal; time is session seconds of the
//! chunk's first row. Without `separate_groups` only EEG is sent.

use crate::CoreError;
use nf_types::{AccelPacket, BandSnapshot, DeviceInfo, PpgPacket};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::VecDeque;

pub use nf_types::DatagramSink;

/// Max queued samples per channel before the oldest are dropped (lead/lag).
pub const MAX_QUEUED: usize = 128;
/// Nominal accelerometer rate (Muse), used to spread per-row timestamps.
const ACCEL_HZ: f64 = 52.0;

/// Wire protocol for streaming out.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum StreamProtocol {
    /// OSC datagrams to one ip:port.
    #[default]
    Osc,
    /// One LSL outlet per group, discoverable on the network (LabRecorder, pylsl, OpenViBE).
    Lsl,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct StreamSettings {
    pub enabled: bool,
    #[serde(default)]
    pub protocol: StreamProtocol,
    pub ip: String,
    pub port: u16,
    /// OSC address prefix, e.g. `/muse` → `/muse/eeg`.
    pub prefix: String,
    /// Also stream PPG, IMU (accelerometer) and bands as their own groups.
    pub separate_groups: bool,
}

impl Default for StreamSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            protocol: StreamProtocol::Osc,
            ip: "192.168.1.100".into(),
            port: 9000,
            prefix: "/muse".into(),
            separate_groups: false,
        }
    }
}

/// `streaming.set` params; omitted fields keep their value.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct StreamPatch {
    #[serde(default)]
    pub enabled: Option<bool>,
    /// osc | lsl (lsl needs the desktop app).
    #[serde(default)]
    pub protocol: Option<StreamProtocol>,
    /// IPv4 or IPv6 destination.
    #[serde(default)]
    pub ip: Option<String>,
    /// 1..=65535.
    #[serde(default)]
    pub port: Option<u16>,
    #[serde(default)]
    pub prefix: Option<String>,
    #[serde(default)]
    pub separate_groups: Option<bool>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct StreamStats {
    pub packets_sent: u64,
    pub bytes_sent: u64,
    /// Samples dropped because one channel ran ahead of the others.
    pub dropped_samples: u64,
    /// LSL: inlets connected right now (LabRecorder, pylsl, ...).
    #[serde(default)]
    pub lsl_consumers: usize,
    pub last_error: Option<String>,
}

/// Streaming settings + counters in `AppState`.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct StreamState {
    pub settings: StreamSettings,
    /// A shell registered a network transport.
    pub transport: bool,
    /// A shell registered an LSL outlet transport.
    #[serde(default)]
    pub lsl_transport: bool,
    pub stats: StreamStats,
}

impl StreamState {
    /// `"LSL"` / `"OSC"` while a stream server is actually running (enabled
    /// and the shell registered that transport), else `None`.
    pub fn running(&self) -> Option<&'static str> {
        if !self.settings.enabled {
            return None;
        }
        match self.settings.protocol {
            StreamProtocol::Lsl => self.lsl_transport.then_some("LSL"),
            StreamProtocol::Osc => self.transport.then_some("OSC"),
        }
    }
}

/// Validate and apply a patch.
pub fn set(st: &mut StreamState, p: &StreamPatch) -> Result<Value, CoreError> {
    let mut s = st.settings.clone();
    if let Some(ip) = &p.ip {
        let ip = ip.trim();
        ip.parse::<std::net::IpAddr>().map_err(|_| CoreError::InvalidArgs(format!("`{ip}` is not an IP address")))?;
        s.ip = ip.to_owned();
    }
    if let Some(port) = p.port {
        if port == 0 {
            return Err(CoreError::InvalidArgs("port must be 1..=65535".into()));
        }
        s.port = port;
    }
    if let Some(pre) = &p.prefix {
        s.prefix = normalize_prefix(pre)?;
    }
    s.separate_groups = p.separate_groups.unwrap_or(s.separate_groups);
    s.protocol = p.protocol.unwrap_or(s.protocol);
    let available = match s.protocol {
        StreamProtocol::Osc => st.transport,
        StreamProtocol::Lsl => st.lsl_transport,
    };
    if p.enabled.unwrap_or(s.enabled) && !available {
        let reason = match s.protocol {
            StreamProtocol::Osc => "no network transport in this build (the web app cannot send UDP)",
            StreamProtocol::Lsl => "LSL needs the desktop app (no LSL transport in this build)",
        };
        return Err(CoreError::Disabled { id: "streaming.set".into(), reason: reason.into() });
    }
    s.enabled = p.enabled.unwrap_or(s.enabled);
    if s.enabled && !st.settings.enabled {
        st.stats = StreamStats::default();
    }
    st.settings = s;
    Ok(json!(st.settings))
}

fn normalize_prefix(p: &str) -> Result<String, CoreError> {
    let p = p.trim().trim_end_matches('/');
    let ok = p.starts_with('/') && p.len() > 1 && p.chars().all(|c| c.is_ascii_alphanumeric() || "/_-.".contains(c));
    if ok {
        Ok(p.to_owned())
    } else {
        Err(CoreError::InvalidArgs(format!("prefix `{p}` must look like /muse (letters, digits, / _ - .)")))
    }
}

/// `streaming.status`.
pub fn status(st: &StreamState, dev: Option<&DeviceInfo>) -> Value {
    let groups: Vec<Value> = groups(dev, st.settings.separate_groups)
        .iter()
        .map(|g| json!({ "id": g.id, "address": format!("{}/{}", st.settings.prefix, g.id), "channels": g.channels, "rate_hz": g.rate, "chunk": g.chunk }))
        .collect();
    json!({
        "protocol": st.settings.protocol,
        "settings": st.settings,
        "transport": st.transport,
        "lsl_transport": st.lsl_transport,
        "lsl_streams": outlet_specs(dev, st.settings.separate_groups).iter().map(|o| json!({ "name": o.name, "type": o.kind, "source_id": o.source_id })).collect::<Vec<_>>(),
        "active": st.settings.enabled && dev.is_some(),
        "stats": st.stats,
        "groups": groups,
    })
}

/// One streamed group.
#[derive(Debug, Clone, PartialEq)]
pub struct Group {
    pub id: &'static str,
    pub channels: Vec<String>,
    pub rate: f64,
    pub chunk: usize,
}

pub fn groups(dev: Option<&DeviceInfo>, separate: bool) -> Vec<Group> {
    let Some(d) = dev else { return Vec::new() };
    let mut g = vec![Group { id: "eeg", channels: d.channels.clone(), rate: d.sample_rate_hz, chunk: 12 }];
    if !separate {
        return g;
    }
    if let Some(rate) = d.ppg_rate_hz.filter(|_| d.has_ppg()) {
        g.push(Group { id: "ppg", channels: d.ppg_channels.clone(), rate, chunk: 6 });
    }
    let imu = ["accel_x", "accel_y", "accel_z"].map(String::from).to_vec();
    g.push(Group { id: "imu", channels: imu, rate: ACCEL_HZ, chunk: 3 });
    let bands = d.channels.iter().flat_map(|c| ["delta", "theta", "alpha", "beta", "gamma"].map(|b| format!("{c}_{b}"))).collect();
    g.push(Group { id: "bands", channels: bands, rate: 10.0, chunk: 1 });
    g
}

/// LSL outlets for the streamed groups (one per group).
pub fn outlet_specs(dev: Option<&DeviceInfo>, separate: bool) -> Vec<nf_types::OutletSpec> {
    let Some(d) = dev else { return Vec::new() };
    groups(dev, separate)
        .into_iter()
        .map(|g| {
            let (kind, unit) = match g.id {
                "eeg" => ("EEG", "microvolts"),
                "ppg" => ("PPG", "raw"),
                "imu" => ("Accelerometer", "g"),
                _ => ("EEG-bands", "log-power"),
            };
            nf_types::OutletSpec {
                name: format!("NeuroFeed {} {}", d.name, kind),
                kind: kind.into(),
                channels: g.channels,
                unit: unit.into(),
                rate_hz: g.rate,
                source_id: format!("neurofeed:{}:{}", d.id, g.id),
            }
        })
        .collect()
}

/// Per-channel queues recombined into lockstep rows (legacy `GroupMixer`).
#[derive(Debug, Clone)]
struct Mixer {
    group: Group,
    queues: Vec<VecDeque<(f64, f32)>>,
    rows: Vec<f32>,
    first_t: f64,
    dropped: u64,
}

impl Mixer {
    fn new(group: Group) -> Self {
        let queues = vec![VecDeque::new(); group.channels.len()];
        Self { group, queues, rows: Vec::new(), first_t: 0.0, dropped: 0 }
    }

    /// `t_last` is the time of the last sample.
    fn add(&mut self, ch: usize, t_last: f64, samples: impl ExactSizeIterator<Item = f32>) {
        let Some(q) = self.queues.get_mut(ch) else { return };
        let n = samples.len();
        let dt = 1.0 / self.group.rate.max(1e-9);
        for (k, x) in samples.enumerate() {
            q.push_back((t_last - (n - 1 - k) as f64 * dt, x));
        }
        while q.len() > MAX_QUEUED {
            q.pop_front();
            self.dropped += 1;
        }
    }

    /// Complete chunks as (first time, row-major values).
    fn drain(&mut self, out: &mut Vec<(f64, Vec<f32>)>) {
        let width = self.queues.len();
        while width > 0 && self.queues.iter().all(|q| !q.is_empty()) {
            for (c, q) in self.queues.iter_mut().enumerate() {
                if let Some((t, x)) = q.pop_front() {
                    if self.rows.is_empty() && c == 0 {
                        self.first_t = t;
                    }
                    self.rows.push(x);
                }
            }
            if self.rows.len() >= self.group.chunk * width {
                out.push((self.first_t, std::mem::take(&mut self.rows)));
            }
        }
    }
}

/// Turns live data into OSC datagrams (`take` hands them to the sink).
#[derive(Debug, Clone, Default)]
pub struct Streamer {
    key: Option<(String, bool)>,
    mixers: Vec<Mixer>,
    outbox: Vec<Vec<u8>>,
    prefix: String,
}

impl Streamer {
    /// (Re)build the groups when the device or group setting changes.
    pub fn sync(&mut self, dev: &DeviceInfo, s: &StreamSettings) {
        let key = Some((dev.id.clone(), s.separate_groups));
        if self.key != key {
            self.key = key;
            self.mixers = groups(Some(dev), s.separate_groups).into_iter().map(Mixer::new).collect();
        }
        self.prefix.clone_from(&s.prefix);
    }

    fn mixer(&mut self, id: &str) -> Option<&mut Mixer> {
        self.mixers.iter_mut().find(|m| m.group.id == id)
    }

    pub fn eeg(&mut self, ch: usize, t_last: f64, conditioned: &[f32]) {
        if let Some(m) = self.mixer("eeg") {
            m.add(ch, t_last, conditioned.iter().copied());
        }
    }

    pub fn ppg(&mut self, p: &PpgPacket) {
        if let Some(m) = self.mixer("ppg") {
            m.add(usize::from(p.channel), p.time, p.samples.iter().copied());
        }
    }

    pub fn accel(&mut self, p: &AccelPacket) {
        if let Some(m) = self.mixer("imu") {
            for axis in 0..3 {
                m.add(axis, p.time, p.samples.iter().map(|s| s[axis]));
            }
        }
    }

    pub fn bands(&mut self, b: &BandSnapshot) {
        if let Some(m) = self.mixer("bands") {
            for (i, x) in b.powers.iter().flatten().enumerate() {
                m.add(i, b.time, std::iter::once(*x));
            }
        }
    }

    /// Complete chunks as (group index, row-major values) and samples dropped.
    pub fn take_rows(&mut self) -> (Vec<(usize, Vec<f32>)>, u64) {
        let mut dropped = 0;
        let mut out = Vec::new();
        let mut chunks = Vec::new();
        for (i, m) in self.mixers.iter_mut().enumerate() {
            m.drain(&mut chunks);
            out.extend(chunks.drain(..).map(|(_, v)| (i, v)));
            dropped += std::mem::take(&mut m.dropped);
        }
        (out, dropped)
    }

    /// Encode complete chunks; returns the datagrams and samples dropped.
    pub fn take(&mut self) -> (Vec<Vec<u8>>, u64) {
        let mut dropped = 0;
        let mut chunks = Vec::new();
        for m in &mut self.mixers {
            m.drain(&mut chunks);
            let addr = format!("{}/{}", self.prefix, m.group.id);
            for (t, v) in chunks.drain(..) {
                self.outbox.push(encode(&addr, t as f32, &v));
            }
            dropped += std::mem::take(&mut m.dropped);
        }
        (std::mem::take(&mut self.outbox), dropped)
    }
}

/// OSC 1.0 message: padded address, padded `,fff…` tag, big-endian f32 args.
pub fn encode(address: &str, t: f32, values: &[f32]) -> Vec<u8> {
    let mut b = Vec::with_capacity(address.len() + values.len() * 5 + 16);
    pad_str(&mut b, address);
    let tag: String = std::iter::once(',').chain(std::iter::repeat_n('f', values.len() + 1)).collect();
    pad_str(&mut b, &tag);
    for x in std::iter::once(t).chain(values.iter().copied()) {
        b.extend_from_slice(&x.to_be_bytes());
    }
    b
}

fn pad_str(b: &mut Vec<u8>, s: &str) {
    b.extend_from_slice(s.as_bytes());
    b.extend(std::iter::repeat_n(0, 4 - s.len() % 4));
}

/// Decode an all-float OSC message (tests and the loopback check).
pub fn decode(b: &[u8]) -> Option<(String, Vec<f32>)> {
    let (addr, rest) = read_str(b)?;
    let (tag, mut rest) = read_str(rest)?;
    let n = tag.strip_prefix(',')?.len();
    let mut v = Vec::with_capacity(n);
    for _ in 0..n {
        let (x, r) = rest.split_first_chunk::<4>()?;
        v.push(f32::from_be_bytes(*x));
        rest = r;
    }
    Some((addr, v))
}

fn read_str(b: &[u8]) -> Option<(String, &[u8])> {
    let end = b.iter().position(|&c| c == 0)?;
    let s = std::str::from_utf8(&b[..end]).ok()?.to_owned();
    let next = (end / 4 + 1) * 4;
    Some((s, b.get(next..)?))
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn osc_encoding_is_padded_big_endian() {
        let b = encode("/muse/eeg", 1.5, &[2.0]);
        assert_eq!(&b[..12], b"/muse/eeg\0\0\0");
        assert_eq!(&b[12..16], b",ff\0");
        assert_eq!(&b[16..20], &1.5f32.to_be_bytes());
        assert_eq!(b.len(), 24);
        assert_eq!(decode(&b), Some(("/muse/eeg".into(), vec![1.5, 2.0])));
        assert_eq!(encode("/abc", 0.0, &[]).len(), 8 + 4 + 4);
    }

    #[test]
    fn mixer_aligns_channels_into_chunks() {
        let g = Group { id: "eeg", channels: vec!["a".into(), "b".into()], rate: 4.0, chunk: 2 };
        let mut m = Mixer::new(g);
        let mut out = Vec::new();
        m.add(0, 1.0, [1.0, 2.0, 3.0].into_iter());
        m.drain(&mut out);
        assert!(out.is_empty(), "channel b missing");
        m.add(1, 1.0, [10.0, 20.0, 30.0].into_iter());
        m.drain(&mut out);
        assert_eq!(out, vec![(0.5, vec![1.0, 10.0, 2.0, 20.0])]);
        m.add(0, 1.0, std::iter::repeat_n(0.0, 200));
        assert_eq!(m.dropped, 200 - MAX_QUEUED as u64, "third row already pending");
    }

    #[test]
    fn settings_validate() {
        let mut st = StreamState::default();
        assert!(set(&mut st, &StreamPatch { ip: Some("nope".into()), ..Default::default() }).is_err());
        assert!(set(&mut st, &StreamPatch { enabled: Some(true), ..Default::default() }).unwrap_err().to_string().contains("web"));
        st.transport = true;
        let v = set(&mut st, &StreamPatch { enabled: Some(true), prefix: Some("/nf/".into()), ..Default::default() }).unwrap();
        assert_eq!((v["prefix"].as_str(), v["enabled"].as_bool()), (Some("/nf"), Some(true)));
        assert!(set(&mut st, &StreamPatch { prefix: Some("x y".into()), ..Default::default() }).is_err());
        let lsl = StreamPatch { protocol: Some(StreamProtocol::Lsl), ..Default::default() };
        assert!(set(&mut st, &lsl).unwrap_err().to_string().contains("desktop"), "still enabled, no LSL transport");
        st.lsl_transport = true;
        assert_eq!(set(&mut st, &lsl).unwrap()["protocol"], "lsl");
    }
}
