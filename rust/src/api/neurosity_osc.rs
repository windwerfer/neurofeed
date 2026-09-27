use crate::api::device_config::DeviceKind;
use crate::api::features::{self, FeatureDto};
use crate::api::muse::{ConnectionStatus, DeviceInfo, EegDto, MuseEventDto, TelemetrySnapshot};
use anyhow::Result;
use flutter_rust_bridge::frb;
use rosc::{OscMessage, OscPacket, OscType};
use std::collections::HashMap;
use std::net::{Ipv4Addr, SocketAddrV4};
use std::sync::{Mutex, MutexGuard, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::net::UdpSocket;
use tokio::sync::mpsc::error::TrySendError;
use tokio::sync::{mpsc, oneshot};

/// Crown electrode order matches `DeviceConfig::neurosity_crown()`:
/// 0=CP3, 1=C3, 2=F5, 3=PO3, 4=PO4, 5=F6, 6=C4, 7=CP4.
/// `/raw` carries one or more 8-float frames (sample-major, µV) in this order,
/// usually as a single OSC array. Band powers come only from our own FFT of
/// `/raw` (muse.rs forwarder); Crown band messages are not used.
const CROWN_CHANNELS: usize = 8;
const CROWN_SAMPLE_RATE: f64 = 256.0;
const CROWN_OSC_PORT: u16 = 9000;
const SEEN_TTL: Duration = Duration::from_secs(5);
const EEG_BATCH_SAMPLES: usize = 16;
const EEG_GAP_MS: f64 = 100.0;
const WARN_INTERVAL: Duration = Duration::from_secs(10);
const ROUTE_CAPACITY: usize = 1024;

fn now_ms() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
        * 1000.0
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CrownAddr<'a> {
    /// `/neurosity/notion/{deviceId}/{leaf}`
    Device { id: &'a str, leaf: &'a str },
    /// `/crown{idPrefix}/{leaf}`
    Metric { id_prefix: &'a str, leaf: &'a str },
}

impl<'a> CrownAddr<'a> {
    fn parse(addr: &'a str) -> Option<Self> {
        if let Some(rest) = addr.strip_prefix("/neurosity/notion/") {
            let (id, leaf) = rest.split_once('/')?;
            return (!id.is_empty() && !leaf.is_empty()).then_some(Self::Device { id, leaf });
        }
        let (id_prefix, leaf) = addr.strip_prefix("/crown")?.split_once('/')?;
        (!id_prefix.is_empty() && !leaf.is_empty()).then_some(Self::Metric { id_prefix, leaf })
    }

    fn is_for(&self, device_id: &str) -> bool {
        match self {
            Self::Device { id, .. } => *id == device_id,
            Self::Metric { id_prefix, .. } => device_id.starts_with(id_prefix),
        }
    }

    fn leaf(&self) -> &'a str {
        match self {
            Self::Device { leaf, .. } | Self::Metric { leaf, .. } => leaf,
        }
    }
}

fn collect_floats(args: &[OscType], out: &mut Vec<f32>) {
    for arg in args {
        match arg {
            OscType::Float(f) => out.push(*f),
            OscType::Double(d) => out.push(*d as f32),
            OscType::Array(array) => collect_floats(&array.content, out),
            _ => {}
        }
    }
}

fn floats(args: &[OscType]) -> Vec<f32> {
    let mut out = Vec::new();
    collect_floats(args, &mut out);
    out
}

fn flatten_packet(packet: OscPacket, out: &mut Vec<OscMessage>) {
    match packet {
        OscPacket::Message(msg) => out.push(msg),
        OscPacket::Bundle(bundle) => {
            for inner in bundle.content {
                flatten_packet(inner, out);
            }
        }
    }
}

#[frb(ignore)]
#[derive(Default)]
struct LogLimiter {
    last: Option<Instant>,
    suppressed: u64,
}

impl LogLimiter {
    fn warn(&mut self, message: impl FnOnce() -> String) {
        let now = Instant::now();
        if self
            .last
            .is_some_and(|t| now.duration_since(t) < WARN_INTERVAL)
        {
            self.suppressed += 1;
            return;
        }
        self.last = Some(now);
        match std::mem::take(&mut self.suppressed) {
            0 => log::warn!("[crown_osc] {}", message()),
            n => log::warn!("[crown_osc] {} ({n} similar suppressed)", message()),
        }
    }
}

/// Channel order inside a multi-sample `/raw` packet.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RawLayout {
    /// ch0_s0, ch1_s0, …, ch7_s0, ch0_s1, …
    SampleMajor,
    /// ch0_s0, ch0_s1, …, ch0_sN, ch1_s0, …
    ChannelMajor,
}

const LAYOUT_AGREE_PACKETS: u32 = 3;

/// The real Crown `/raw` layout is unverified: Neurosity's OSC docs describe
/// 16-sample epochs, while Neurosity's simulator and BrainFlow send one
/// sample per packet. Multi-sample packets are read whichever way gives the
/// smoother per-channel signal (256 Hz EEG moves little between samples);
/// the choice sticks once [LAYOUT_AGREE_PACKETS] packets in a row agree.
#[frb(ignore)]
#[derive(Default)]
struct RawLayoutDetector {
    locked: Option<RawLayout>,
    streak: Option<(RawLayout, u32)>,
}

impl RawLayoutDetector {
    /// Sample-major frames of 8 channels. `values.len()` is a multiple of 8.
    fn frames(&mut self, values: &[f32]) -> Vec<[f32; CROWN_CHANNELS]> {
        let n = values.len() / CROWN_CHANNELS;
        let at = |layout, s: usize, ch: usize| match layout {
            RawLayout::SampleMajor => values[s * CROWN_CHANNELS + ch],
            RawLayout::ChannelMajor => values[ch * n + s],
        };
        let jumps = |layout| -> f64 {
            (0..CROWN_CHANNELS)
                .flat_map(|ch| (1..n).map(move |s| (ch, s)))
                .map(|(ch, s)| (at(layout, s, ch) as f64 - at(layout, s - 1, ch) as f64).abs())
                .sum()
        };
        let layout = match self.locked {
            Some(l) => l,
            None if n < 2 => RawLayout::SampleMajor,
            None => {
                let (sm, cm) = (jumps(RawLayout::SampleMajor), jumps(RawLayout::ChannelMajor));
                let vote = if cm < sm { RawLayout::ChannelMajor } else { RawLayout::SampleMajor };
                let count = match self.streak {
                    Some((l, c)) if l == vote => c + 1,
                    _ => 1,
                };
                self.streak = Some((vote, count));
                if count >= LAYOUT_AGREE_PACKETS {
                    self.locked = Some(vote);
                    log::info!("[crown_osc] /raw layout: {n} samples per packet, {vote:?}");
                }
                vote
            }
        };
        (0..n).map(|s| std::array::from_fn(|ch| at(layout, s, ch))).collect()
    }
}

struct SeenCrown {
    nickname: Option<String>,
    model: Option<String>,
    last_seen: Instant,
}

#[frb(ignore)]
#[derive(Default)]
struct CrownRegistry {
    seen: HashMap<String, SeenCrown>,
}

impl CrownRegistry {
    fn observe(&mut self, msg: &OscMessage, now: Instant) {
        let Some(CrownAddr::Device { id, leaf }) = CrownAddr::parse(&msg.addr) else {
            return;
        };
        if !self.seen.contains_key(id) {
            self.seen.insert(
                id.to_string(),
                SeenCrown {
                    nickname: None,
                    model: None,
                    last_seen: now,
                },
            );
        }
        let Some(entry) = self.seen.get_mut(id) else {
            return;
        };
        entry.last_seen = now;
        if leaf != "info" {
            return;
        }
        let text = |i: usize| match msg.args.get(i) {
            Some(OscType::String(s)) if !s.is_empty() => Some(s.clone()),
            _ => None,
        };
        if let Some(nickname) = text(1) {
            entry.nickname = Some(nickname);
        }
        if let Some(model) = text(2) {
            entry.model = Some(model);
        }
    }

    fn visible(&mut self, now: Instant) -> Vec<DeviceInfo> {
        self.seen
            .retain(|_, c| now.saturating_duration_since(c.last_seen) <= SEEN_TTL);
        let mut out: Vec<DeviceInfo> = self
            .seen
            .iter()
            .map(|(id, c)| DeviceInfo {
                name: c.nickname.clone().unwrap_or_else(|| id.clone()),
                id: id.clone(),
                kind: DeviceKind::Neurosity,
            })
            .collect();
        out.sort_by(|a, b| a.id.cmp(&b.id));
        out
    }
}

struct Route {
    generation: u64,
    device_id: String,
    tx: mpsc::Sender<OscMessage>,
}

/// One UDP socket on port 9000 shared by LAN discovery and the data
/// receiver. The socket task runs while discovery is on or a route exists.
#[frb(ignore)]
#[derive(Default)]
struct Hub {
    registry: CrownRegistry,
    route: Option<Route>,
    discovery: bool,
    socket_stop: Option<oneshot::Sender<()>>,
    next_generation: u64,
    route_full: LogLimiter,
}

fn hub() -> MutexGuard<'static, Hub> {
    static HUB: OnceLock<Mutex<Hub>> = OnceLock::new();
    HUB.get_or_init(Mutex::default)
        .lock()
        .unwrap_or_else(|e| e.into_inner())
}

fn bind_socket(port: u16) -> Result<UdpSocket> {
    use socket2::{Domain, Protocol, Socket, Type};
    let socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    socket.set_reuse_address(true)?;
    socket.set_broadcast(true)?;
    socket.set_nonblocking(true)?;
    socket.bind(&SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, port).into())?;
    Ok(UdpSocket::from_std(socket.into())?)
}

impl Hub {
    fn ensure_socket(&mut self) -> Result<()> {
        if self.socket_stop.as_ref().is_some_and(|s| !s.is_closed()) {
            return Ok(());
        }
        let socket = bind_socket(CROWN_OSC_PORT)?;
        log::info!("[crown_osc] listening on 0.0.0.0:{CROWN_OSC_PORT}");
        let (stop_tx, stop_rx) = oneshot::channel();
        tokio::spawn(run_socket(socket, stop_rx));
        self.socket_stop = Some(stop_tx);
        Ok(())
    }

    fn stop_socket_if_idle(&mut self) {
        if self.discovery || self.route.is_some() {
            return;
        }
        if let Some(stop) = self.socket_stop.take() {
            let _ = stop.send(());
            log::info!("[crown_osc] socket closed");
        }
    }

    fn dispatch(&mut self, messages: Vec<OscMessage>, now: Instant) {
        let Hub {
            registry,
            route,
            route_full,
            ..
        } = self;
        for msg in messages {
            registry.observe(&msg, now);
            let Some(route) = route.as_ref() else {
                continue;
            };
            let routed = CrownAddr::parse(&msg.addr).is_some_and(|a| a.is_for(&route.device_id));
            if !routed {
                continue;
            }
            if let Err(TrySendError::Full(_)) = route.tx.try_send(msg) {
                route_full.warn(|| "receiver queue full; dropping OSC messages".to_string());
            }
        }
    }
}

async fn run_socket(socket: UdpSocket, mut stop: oneshot::Receiver<()>) {
    let mut buf = vec![0u8; 65536];
    let mut decode_errors = LogLimiter::default();
    loop {
        tokio::select! {
            _ = &mut stop => break,
            received = socket.recv_from(&mut buf) => match received {
                Ok((len, _)) => match rosc::decoder::decode_udp(&buf[..len]) {
                    Ok((_, packet)) => {
                        let mut messages = Vec::new();
                        flatten_packet(packet, &mut messages);
                        hub().dispatch(messages, Instant::now());
                    }
                    Err(e) => decode_errors.warn(|| format!("undecodable OSC packet ({len} bytes): {e:?}")),
                },
                Err(e) => {
                    log::warn!("[crown_osc] UDP recv error: {e}");
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }
            }
        }
    }
}

/// Start listening for Crowns broadcasting OSC on the local network
/// (UDP port 9000). Poll [discovered_crowns] for the list.
pub async fn start_crown_discovery() -> Result<()> {
    let mut hub = hub();
    hub.discovery = true;
    let started = hub.ensure_socket();
    if started.is_err() {
        hub.discovery = false;
    }
    started
}

/// Stop LAN discovery. The socket stays open while a Crown is connected.
pub fn stop_crown_discovery() {
    let mut hub = hub();
    hub.discovery = false;
    hub.stop_socket_if_idle();
}

/// Crowns that sent any `/neurosity/notion/{deviceId}/…` packet within the
/// last few seconds. Name is the `/info` nickname, else the device id.
pub fn discovered_crowns() -> Vec<DeviceInfo> {
    hub().registry.visible(Instant::now())
}

/// Live Crown OSC stream. Dropping it (or [CrownOscHandle::disconnect])
/// stops the receiver and releases the shared socket when idle.
#[frb(ignore)]
pub struct CrownOscHandle {
    stop: Mutex<Option<oneshot::Sender<()>>>,
}

impl CrownOscHandle {
    pub fn disconnect(&self) {
        let stop = self.stop.lock().unwrap_or_else(|e| e.into_inner()).take();
        if let Some(stop) = stop {
            let _ = stop.send(());
        }
    }
}

fn release_route(generation: u64) {
    let mut hub = hub();
    if hub
        .route
        .as_ref()
        .is_some_and(|r| r.generation == generation)
    {
        hub.route = None;
    }
    hub.stop_socket_if_idle();
}

fn start_crown_receiver(
    device_id: String,
    tx: mpsc::Sender<MuseEventDto>,
) -> Result<CrownOscHandle> {
    let (route_tx, route_rx) = mpsc::channel(ROUTE_CAPACITY);
    let generation = {
        let mut hub = hub();
        hub.ensure_socket()?;
        hub.next_generation += 1;
        let generation = hub.next_generation;
        hub.route = Some(Route {
            generation,
            device_id: device_id.clone(),
            tx: route_tx,
        });
        generation
    };
    log::info!("[crown_osc] receiving device {device_id}");
    let (stop_tx, stop_rx) = oneshot::channel();
    tokio::spawn(async move {
        CrownStream::new(tx).run(route_rx, stop_rx).await;
        release_route(generation);
        log::info!("[crown_osc] receiver for {device_id} stopped");
    });
    Ok(CrownOscHandle {
        stop: Mutex::new(Some(stop_tx)),
    })
}

#[derive(Debug, PartialEq)]
enum SignalQuality {
    PerChannel([f32; CROWN_CHANNELS]),
    Overall(f32),
    Unexpected(usize),
}

impl SignalQuality {
    fn parse(args: &[OscType]) -> Self {
        let values = floats(args);
        match values.len() {
            1 => Self::Overall(values[0]),
            CROWN_CHANNELS => {
                let mut per_channel = [0.0; CROWN_CHANNELS];
                per_channel.copy_from_slice(&values);
                Self::PerChannel(per_channel)
            }
            n => Self::Unexpected(n),
        }
    }
}

struct ChannelClosed;

struct CrownStream {
    tx: mpsc::Sender<MuseEventDto>,
    pending: Vec<Vec<f64>>,
    pending_start_ms: f64,
    batch_index: u16,
    battery: Option<f32>,
    raw_warn: LogLimiter,
    quality_warn: LogLimiter,
    layout: RawLayoutDetector,
}

impl CrownStream {
    fn new(tx: mpsc::Sender<MuseEventDto>) -> Self {
        Self {
            tx,
            pending: vec![Vec::with_capacity(EEG_BATCH_SAMPLES); CROWN_CHANNELS],
            pending_start_ms: 0.0,
            batch_index: 0,
            battery: None,
            raw_warn: LogLimiter::default(),
            quality_warn: LogLimiter::default(),
            layout: RawLayoutDetector::default(),
        }
    }

    async fn run(mut self, mut rx: mpsc::Receiver<OscMessage>, mut stop: oneshot::Receiver<()>) {
        let mut telemetry = tokio::time::interval(Duration::from_secs(5));
        loop {
            let step = tokio::select! {
                _ = &mut stop => break,
                msg = rx.recv() => match msg {
                    Some(msg) => self.on_message(msg).await,
                    None => break,
                },
                _ = telemetry.tick() => self.emit_battery().await,
            };
            if step.is_err() {
                break;
            }
        }
    }

    async fn send(&self, event: MuseEventDto) -> Result<(), ChannelClosed> {
        self.tx.send(event).await.map_err(|_| ChannelClosed)
    }

    async fn on_message(&mut self, msg: OscMessage) -> Result<(), ChannelClosed> {
        let Some(addr) = CrownAddr::parse(&msg.addr) else {
            return Ok(());
        };
        match addr.leaf() {
            "raw" => self.on_raw(&msg.args, now_ms()).await,
            "signalQuality" => {
                self.on_signal_quality(&msg.args);
                Ok(())
            }
            "battery" => {
                if let Some(level) = floats(&msg.args).first() {
                    self.battery = Some(level.clamp(0.0, 100.0));
                }
                Ok(())
            }
            "focus" => self.on_feature(features::ID_FOCUS, &msg.args).await,
            "calm" => self.on_feature(features::ID_CALM, &msg.args).await,
            _ => Ok(()),
        }
    }

    async fn on_raw(&mut self, args: &[OscType], arrival_ms: f64) -> Result<(), ChannelClosed> {
        let values = floats(args);
        if values.is_empty() || values.len() % CROWN_CHANNELS != 0 {
            self.raw_warn.warn(|| {
                format!(
                    "unexpected /raw float count {} (expected a multiple of {CROWN_CHANNELS})",
                    values.len()
                )
            });
            return Ok(());
        }
        let period_ms = 1000.0 / CROWN_SAMPLE_RATE;
        let frames = self.layout.frames(&values);
        let count = frames.len();
        for (i, frame) in frames.iter().enumerate() {
            let sample_ms = arrival_ms - (count - 1 - i) as f64 * period_ms;
            let queued = self.pending[0].len();
            if queued > 0
                && sample_ms - (self.pending_start_ms + queued as f64 * period_ms) > EEG_GAP_MS
            {
                self.flush().await?;
            }
            if self.pending[0].is_empty() {
                self.pending_start_ms = sample_ms;
            }
            for (ch, v) in frame.iter().enumerate() {
                self.pending[ch].push(*v as f64);
            }
            if self.pending[0].len() >= EEG_BATCH_SAMPLES {
                self.flush().await?;
            }
        }
        Ok(())
    }

    async fn flush(&mut self) -> Result<(), ChannelClosed> {
        let index = self.batch_index;
        self.batch_index = self.batch_index.wrapping_add(1);
        for ch in 0..CROWN_CHANNELS {
            let samples =
                std::mem::replace(&mut self.pending[ch], Vec::with_capacity(EEG_BATCH_SAMPLES));
            self.send(MuseEventDto::Eeg(EegDto {
                index,
                electrode: ch as i32,
                timestamp: self.pending_start_ms,
                samples,
            }))
            .await?;
        }
        Ok(())
    }

    fn on_signal_quality(&mut self, args: &[OscType]) {
        match SignalQuality::parse(args) {
            SignalQuality::PerChannel(values) => features::add_crown_quality(&values),
            SignalQuality::Overall(q) => {
                log::trace!("[crown_osc] overall signalQuality {q} (not used for pads)")
            }
            SignalQuality::Unexpected(n) => self
                .quality_warn
                .warn(|| format!("unexpected signalQuality float count {n}")),
        }
    }

    async fn on_feature(&self, id: &str, args: &[OscType]) -> Result<(), ChannelClosed> {
        let Some(value) = floats(args).first().copied() else {
            return Ok(());
        };
        if !features::is_enabled(id) {
            return Ok(());
        }
        self.send(MuseEventDto::Feature(FeatureDto {
            id: id.to_string(),
            timestamp: now_ms(),
            value: value as f64,
        }))
        .await
    }

    async fn emit_battery(&self) -> Result<(), ChannelClosed> {
        let Some(level) = self.battery else {
            return Ok(());
        };
        self.send(MuseEventDto::Telemetry(TelemetrySnapshot {
            battery_level: level,
            fuel_gauge_voltage: 0.0,
            temperature: 0,
        }))
        .await
    }
}

/// Start receiving the Crown `device_id` over OSC. Name and firmware come
/// from its `/info` broadcast when discovery has seen one.
#[frb(ignore)]
pub async fn connect_crown_osc(
    device_id: String,
    tx: mpsc::Sender<MuseEventDto>,
) -> Result<(CrownOscHandle, ConnectionStatus)> {
    let handle = start_crown_receiver(device_id.clone(), tx)?;
    let (name, firmware) = {
        let hub = hub();
        let seen = hub.registry.seen.get(&device_id);
        (
            seen.and_then(|c| c.nickname.clone())
                .unwrap_or_else(|| "Crown".to_string()),
            seen.and_then(|c| c.model.clone())
                .unwrap_or_else(|| "Crown".to_string()),
        )
    };
    Ok((
        handle,
        ConnectionStatus {
            connected: true,
            name,
            id: device_id,
            firmware,
            aux_channels: 0,
        },
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "local7cca794fb5f4675a69371e949b2";

    fn pad(mut bytes: Vec<u8>) -> Vec<u8> {
        bytes.push(0);
        while bytes.len() % 4 != 0 {
            bytes.push(0);
        }
        bytes
    }

    fn osc_string(s: &str) -> Vec<u8> {
        pad(s.as_bytes().to_vec())
    }

    /// Byte layout the Node `osc` package emits for the notion-osc-server
    /// brainflow `/raw` message: array of 8 floats, then s, i, s.
    fn node_raw_packet(device_id: &str, samples: [f32; 8], timestamp: &str, count: i32) -> Vec<u8> {
        let mut out = osc_string(&format!("/neurosity/notion/{device_id}/raw"));
        out.extend(osc_string(",[ffffffff]sis"));
        for v in samples {
            out.extend(v.to_be_bytes());
        }
        out.extend(osc_string(timestamp));
        out.extend(count.to_be_bytes());
        out.extend(osc_string(""));
        out
    }

    fn node_info_packet(device_id: &str, nickname: &str) -> Vec<u8> {
        let mut out = osc_string(&format!("/neurosity/notion/{device_id}/info"));
        out.extend(osc_string(",ssssssiis"));
        for s in [
            device_id,
            nickname,
            "Crown 3",
            "Crown",
            "3",
            "Neurosity, Inc",
        ] {
            out.extend(osc_string(s));
        }
        out.extend(256i32.to_be_bytes());
        out.extend(8i32.to_be_bytes());
        out.extend(osc_string("CP3,C3,F5,PO3,PO4,F6,C4,CP4"));
        out
    }

    fn decode(bytes: &[u8]) -> OscMessage {
        let (rest, packet) = rosc::decoder::decode_udp(bytes).expect("decodes");
        assert!(rest.is_empty());
        let mut msgs = Vec::new();
        flatten_packet(packet, &mut msgs);
        assert_eq!(msgs.len(), 1);
        msgs.remove(0)
    }

    fn msg(addr: &str, args: Vec<OscType>) -> OscMessage {
        OscMessage {
            addr: addr.to_string(),
            args,
        }
    }

    async fn drain(rx: &mut mpsc::Receiver<MuseEventDto>) -> Vec<EegDto> {
        let mut out = Vec::new();
        while let Ok(ev) = rx.try_recv() {
            if let MuseEventDto::Eeg(e) = ev {
                out.push(e);
            }
        }
        out
    }

    #[test]
    fn node_raw_packet_decodes_array_floats() {
        let samples = [1.5, -2.25, 3.0, -4.0, 50.0, -50.0, 0.125, 7.75];
        let bytes = node_raw_packet(ID, samples, "1695812345.123", 17);
        assert_eq!(bytes.len() % 4, 0);
        let m = decode(&bytes);
        assert_eq!(m.addr, format!("/neurosity/notion/{ID}/raw"));
        assert_eq!(m.args.len(), 4);
        assert!(matches!(&m.args[0], OscType::Array(a) if a.content.len() == 8));
        assert_eq!(m.args[1], OscType::String("1695812345.123".into()));
        assert_eq!(m.args[2], OscType::Int(17));
        assert_eq!(m.args[3], OscType::String(String::new()));
        assert_eq!(floats(&m.args), samples.to_vec());
    }

    #[test]
    fn node_info_packet_registers_nickname_and_model() {
        let m = decode(&node_info_packet(ID, "Crown-LOC"));
        let mut reg = CrownRegistry::default();
        let t0 = Instant::now();
        reg.observe(&m, t0);
        let list = reg.visible(t0);
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].id, ID);
        assert_eq!(list[0].name, "Crown-LOC");
        assert_eq!(list[0].kind, DeviceKind::Neurosity);
        assert_eq!(reg.seen[ID].model.as_deref(), Some("Crown 3"));
    }

    #[test]
    fn registry_lists_raw_only_crowns_by_id_and_expires() {
        let mut reg = CrownRegistry::default();
        let t0 = Instant::now();
        reg.observe(&decode(&node_raw_packet("abc123", [0.0; 8], "1", 0)), t0);
        reg.observe(
            &msg("/crownabc/signalQuality", vec![OscType::Float(1.0)]),
            t0,
        );
        reg.observe(&msg("/muse/eeg", vec![]), t0);
        let list = reg.visible(t0);
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].name, "abc123");
        assert!(reg
            .visible(t0 + SEEN_TTL + Duration::from_millis(1))
            .is_empty());
    }

    #[test]
    fn device_segment_matches_exactly() {
        let addr = format!("/neurosity/notion/{ID}/raw");
        let a = CrownAddr::parse(&addr).unwrap();
        assert_eq!(
            a,
            CrownAddr::Device {
                id: ID,
                leaf: "raw"
            }
        );
        assert!(a.is_for(ID));
        assert!(!a.is_for("local7cca"));
        assert!(!a.is_for(&format!("{ID}x")));
        let other =
            CrownAddr::parse("/neurosity/notion/xlocal7cca794fb5f4675a69371e949b2/raw").unwrap();
        assert!(!other.is_for(ID));
        assert!(CrownAddr::parse("/neurosity/notion//raw").is_none());
        assert!(CrownAddr::parse("/neurosity/notion/abc").is_none());
        assert!(CrownAddr::parse(&format!("/other/{ID}/raw")).is_none());
    }

    #[test]
    fn crown_metric_prefix_matches() {
        let a = CrownAddr::parse("/crownlocal7cc/signalQuality").unwrap();
        assert_eq!(
            a,
            CrownAddr::Metric {
                id_prefix: "local7cc",
                leaf: "signalQuality"
            }
        );
        assert!(a.is_for(ID));
        assert!(CrownAddr::parse(&format!("/crown{ID}/signalQuality"))
            .unwrap()
            .is_for(ID));
        assert!(!CrownAddr::parse("/crownlocal8/signalQuality")
            .unwrap()
            .is_for(ID));
        assert!(CrownAddr::parse("/crown/signalQuality").is_none());
        assert!(CrownAddr::parse("/crownabc").is_none());
    }

    /// Smooth 256 Hz EEG with per-channel DC offsets and mains hum, like an
    /// unfiltered Crown pad.
    fn smooth_sample(s: usize, ch: usize) -> f32 {
        let t = s as f64 / CROWN_SAMPLE_RATE;
        let alpha = 10.0 * (2.0 * std::f64::consts::PI * 10.0 * t + ch as f64).sin();
        let hum = 60.0 * (2.0 * std::f64::consts::PI * 50.0 * t).sin();
        (-2000.0 - 300.0 * ch as f64 + alpha + hum) as f32
    }

    fn epoch(first: usize, n: usize, layout: RawLayout) -> Vec<f32> {
        let mut out = vec![0.0; n * CROWN_CHANNELS];
        for s in 0..n {
            for ch in 0..CROWN_CHANNELS {
                let i = match layout {
                    RawLayout::SampleMajor => s * CROWN_CHANNELS + ch,
                    RawLayout::ChannelMajor => ch * n + s,
                };
                out[i] = smooth_sample(first + s, ch);
            }
        }
        out
    }

    fn expected(first: usize, n: usize) -> Vec<[f32; CROWN_CHANNELS]> {
        (0..n)
            .map(|s| std::array::from_fn(|ch| smooth_sample(first + s, ch)))
            .collect()
    }

    #[test]
    fn raw_layout_detects_both_epoch_orders() {
        for layout in [RawLayout::SampleMajor, RawLayout::ChannelMajor] {
            let mut det = RawLayoutDetector::default();
            for p in 0..LAYOUT_AGREE_PACKETS as usize {
                let frames = det.frames(&epoch(p * 16, 16, layout));
                assert_eq!(frames, expected(p * 16, 16), "{layout:?} packet {p}");
            }
            assert_eq!(det.locked, Some(layout));
        }
    }

    #[test]
    fn raw_layout_single_sample_packets_do_not_vote() {
        let mut det = RawLayoutDetector::default();
        for s in 0..10 {
            let frames = det.frames(&epoch(s, 1, RawLayout::SampleMajor));
            assert_eq!(frames, expected(s, 1));
        }
        assert_eq!(det.locked, None);
        assert_eq!(det.streak, None);
    }

    #[test]
    fn raw_layout_is_sticky_once_locked() {
        let mut det = RawLayoutDetector::default();
        det.frames(&epoch(0, 16, RawLayout::ChannelMajor));
        det.frames(&epoch(16, 16, RawLayout::SampleMajor));
        assert_eq!(det.locked, None, "a disagreeing packet resets the streak");
        for p in 2..2 + LAYOUT_AGREE_PACKETS as usize {
            det.frames(&epoch(p * 16, 16, RawLayout::ChannelMajor));
        }
        assert_eq!(det.locked, Some(RawLayout::ChannelMajor));
        let odd = epoch(100, 16, RawLayout::SampleMajor);
        let frames = det.frames(&odd);
        assert_ne!(frames, expected(100, 16), "no flip after lock");
        assert_eq!(frames[0][1], odd[16]);
        assert_eq!(det.locked, Some(RawLayout::ChannelMajor));
    }

    #[test]
    fn collect_floats_flattens_nested_arrays_and_skips_other_types() {
        let nested = OscType::Array(rosc::OscArray {
            content: vec![
                OscType::Float(1.0),
                OscType::Array(rosc::OscArray {
                    content: vec![OscType::Double(2.0), OscType::Int(9)],
                }),
            ],
        });
        let args = vec![nested, OscType::String("x".into()), OscType::Float(3.0)];
        assert_eq!(floats(&args), vec![1.0, 2.0, 3.0]);
    }

    #[tokio::test]
    async fn per_sample_packets_batch_into_16_sample_epochs() {
        let (tx, mut rx) = mpsc::channel(64);
        let mut stream = CrownStream::new(tx);
        let period = 1000.0 / CROWN_SAMPLE_RATE;
        for n in 0..40 {
            let m = decode(&node_raw_packet(ID, [n as f32; 8], "1", n));
            assert!(stream
                .on_raw(&m.args, 1000.0 + n as f64 * period)
                .await
                .is_ok());
        }
        let eeg = drain(&mut rx).await;
        assert_eq!(eeg.len(), 2 * CROWN_CHANNELS);
        for (i, e) in eeg.iter().enumerate() {
            let batch = i / CROWN_CHANNELS;
            assert_eq!(e.electrode as usize, i % CROWN_CHANNELS);
            assert_eq!(e.samples.len(), EEG_BATCH_SAMPLES);
            assert_eq!(e.samples[0], (batch * EEG_BATCH_SAMPLES) as f64);
            assert!(
                (e.timestamp - (1000.0 + (batch * EEG_BATCH_SAMPLES) as f64 * period)).abs() < 1e-6
            );
        }
        assert_eq!(stream.pending[0].len(), 8);
    }

    #[tokio::test]
    async fn multi_sample_packet_is_sample_major() {
        let (tx, mut rx) = mpsc::channel(64);
        let mut stream = CrownStream::new(tx);
        let mut values = Vec::new();
        for s in 0..16 {
            for ch in 0..8 {
                values.push(OscType::Float((ch * 100 + s) as f32));
            }
        }
        let args = vec![OscType::Array(rosc::OscArray { content: values })];
        assert!(stream.on_raw(&args, 5000.0).await.is_ok());
        let eeg = drain(&mut rx).await;
        assert_eq!(eeg.len(), 8);
        for e in &eeg {
            let base = (e.electrode * 100) as f64;
            assert_eq!(
                e.samples,
                (0..16).map(|s| base + s as f64).collect::<Vec<_>>()
            );
            assert!((e.timestamp - (5000.0 - 15.0 * 1000.0 / CROWN_SAMPLE_RATE)).abs() < 1e-6);
        }
    }

    #[tokio::test]
    async fn gap_flushes_partial_batch_and_bad_counts_are_ignored() {
        let (tx, mut rx) = mpsc::channel(64);
        let mut stream = CrownStream::new(tx);
        let frame = |v: f32| {
            vec![OscType::Array(rosc::OscArray {
                content: vec![OscType::Float(v); 8],
            })]
        };
        assert!(stream.on_raw(&frame(1.0), 0.0).await.is_ok());
        assert!(stream.on_raw(&frame(2.0), 4.0).await.is_ok());
        assert!(stream
            .on_raw(&vec![OscType::Float(1.0); 7], 5.0)
            .await
            .is_ok());
        assert!(stream
            .on_raw(&[OscType::String("x".into())], 6.0)
            .await
            .is_ok());
        assert!(drain(&mut rx).await.is_empty());
        assert!(stream.on_raw(&frame(3.0), 500.0).await.is_ok());
        let eeg = drain(&mut rx).await;
        assert_eq!(eeg.len(), 8);
        assert_eq!(eeg[0].samples, vec![1.0, 2.0]);
        assert_eq!(eeg[0].timestamp, 0.0);
        assert_eq!(stream.pending[0], vec![3.0]);
        assert_eq!(stream.pending_start_ms, 500.0);
    }

    #[test]
    fn signal_quality_accepts_eight_or_one_float() {
        assert_eq!(
            SignalQuality::parse(&[OscType::Float(0.5)]),
            SignalQuality::Overall(0.5)
        );
        assert_eq!(
            SignalQuality::parse(&vec![OscType::Float(0.5); 3]),
            SignalQuality::Unexpected(3)
        );
        assert_eq!(SignalQuality::parse(&[]), SignalQuality::Unexpected(0));
        let per_channel: Vec<OscType> = (0..8).map(|ch| OscType::Float(ch as f32)).collect();
        assert_eq!(
            SignalQuality::parse(&[OscType::Array(rosc::OscArray {
                content: per_channel.clone()
            })]),
            SignalQuality::PerChannel([0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0])
        );
        assert_eq!(
            SignalQuality::parse(&per_channel),
            SignalQuality::PerChannel([0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0])
        );
    }

    #[test]
    fn hub_routes_only_the_connected_device() {
        let (tx, mut rx) = mpsc::channel(8);
        let mut hub = Hub {
            route: Some(Route {
                generation: 1,
                device_id: ID.to_string(),
                tx,
            }),
            ..Hub::default()
        };
        hub.dispatch(
            vec![
                msg(&format!("/neurosity/notion/{ID}/raw"), vec![]),
                msg("/neurosity/notion/local7cca/raw", vec![]),
                msg("/crownlocal7/signalQuality", vec![OscType::Float(1.0)]),
                msg("/crownzzz/signalQuality", vec![OscType::Float(1.0)]),
            ],
            Instant::now(),
        );
        let mut routed = Vec::new();
        while let Ok(m) = rx.try_recv() {
            routed.push(m.addr);
        }
        assert_eq!(
            routed,
            vec![
                format!("/neurosity/notion/{ID}/raw"),
                "/crownlocal7/signalQuality".to_string()
            ]
        );
        assert_eq!(hub.registry.visible(Instant::now()).len(), 2);
    }
}

/// End-to-end over loopback with `tools/crown_osc_sim.py` (binds UDP 9000).
/// `cargo test --lib crown_osc_sim -- --ignored --nocapture --test-threads=1`
#[cfg(test)]
mod sim_loopback_tests {
    use super::*;
    use crate::api::device_config::QualitySource;
    use std::process::{Child, Command};

    const ID: &str = "local7cca794fb5f4675a69371e949b2";

    struct Sim(Child);

    impl Drop for Sim {
        fn drop(&mut self) {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }

    fn sim(args: &[&str]) -> Sim {
        let script = concat!(env!("CARGO_MANIFEST_DIR"), "/../tools/crown_osc_sim.py");
        Sim(Command::new("python3")
            .arg(script)
            .args(["--target", "127.0.0.1"])
            .args(args)
            .spawn()
            .expect("python3 tools/crown_osc_sim.py"))
    }

    #[derive(Default)]
    struct Collected {
        samples: Vec<Vec<f64>>,
        batches: Vec<(f64, usize)>,
    }

    async fn collect(rx: &mut mpsc::Receiver<MuseEventDto>, secs: f64) -> Collected {
        let mut out = Collected {
            samples: vec![Vec::new(); CROWN_CHANNELS],
            ..Default::default()
        };
        let deadline = tokio::time::Instant::now() + Duration::from_secs_f64(secs);
        while let Ok(Some(ev)) = tokio::time::timeout_at(deadline, rx.recv()).await {
            if let MuseEventDto::Eeg(e) = ev {
                if e.electrode == 0 {
                    out.batches.push((e.timestamp, e.samples.len()));
                }
                out.samples[e.electrode as usize].extend(e.samples);
            }
        }
        out
    }

    fn std_dev(v: &[f64]) -> f64 {
        let mean = v.iter().sum::<f64>() / v.len() as f64;
        (v.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / v.len() as f64).sqrt()
    }

    fn max_abs(v: &[f64]) -> f64 {
        v.iter().fold(0.0, |m, x| m.max(x.abs()))
    }

    async fn connect(
        secs_after_start: f64,
    ) -> (
        CrownOscHandle,
        ConnectionStatus,
        mpsc::Receiver<MuseEventDto>,
    ) {
        tokio::time::sleep(Duration::from_secs_f64(secs_after_start)).await;
        let (tx, rx) = mpsc::channel(4096);
        let (handle, status) = connect_crown_osc(ID.to_string(), tx)
            .await
            .expect("connect");
        (handle, status, rx)
    }

    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn crown_osc_sim_discovery_rate_bad_pads_and_decoy() {
        start_crown_discovery().await.expect("bind 9000");
        let decoy_id = format!("{ID}ff");
        let _main = sim(&[
            "--duration",
            "6",
            "--bad-pads",
            "3",
            "--quality",
        ]);
        let _decoy = sim(&[
            "--duration",
            "6",
            "--device-id",
            &decoy_id,
            "--noise",
            "--quality",
        ]);
        let (handle, status, mut rx) = connect(1.5).await;
        let crowns = discovered_crowns();
        println!(
            "discovered: {:?}",
            crowns.iter().map(|d| (&d.name, &d.id)).collect::<Vec<_>>()
        );
        assert!(crowns
            .iter()
            .any(|d| d.id == ID && d.name == "Crown-LOC" && d.kind == DeviceKind::Neurosity));
        assert!(crowns
            .iter()
            .any(|d| d.id == decoy_id && d.name == "Crown-LOC"));
        assert_eq!(
            (status.name.as_str(), status.firmware.as_str()),
            ("Crown-LOC", "Crown 3")
        );

        let secs = 3.0;
        let got = collect(&mut rx, secs).await;
        for (ch, s) in got.samples.iter().enumerate() {
            let rate = s.len() as f64 / secs;
            println!(
                "ch{ch}: {:.1} samples/s std={:.2} uV max|v|={:.1} uV",
                rate,
                std_dev(s),
                max_abs(s)
            );
            assert!((rate - 256.0).abs() < 256.0 * 0.06, "ch{ch} rate {rate}");
            if ch == 3 {
                assert!(std_dev(s) > 100.0, "bad pad should be huge noise");
            } else {
                assert!(
                    max_abs(s) < 12.0,
                    "ch{ch} out of the app-model range (decoy leaked?)"
                );
                let sd = std_dev(s);
                assert!(sd > 1.0 && sd < 15.0);
            }
        }
        assert!(got.batches.iter().all(|(_, n)| *n == EEG_BATCH_SAMPLES));
        features::set_quality_source(QualitySource::Crown);
        let second = features::resolve_neurosity_second(&[Some(50.0); CROWN_CHANNELS]);
        println!("crown quality second: {:?}", second.crown);
        assert_eq!(second.source, QualitySource::Crown);
        let crown = second.crown.expect("per-pad Crown quality");
        assert!(crown[3] < 0.3 && crown[0] > 0.75);
        assert!(second.scores[3].unwrap() < 80.0 && second.scores[0].unwrap() >= 80.0);
        drop(handle);
        stop_crown_discovery();
    }

    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn crown_osc_sim_dropout_keeps_discovery() {
        start_crown_discovery().await.expect("bind 9000");
        let _main = sim(&[
            "--duration",
            "7",
            "--dropout",
            "2:1",
            "--bad-pads",
            "5",
            "--bad-mode",
            "flat",
        ]);
        let (handle, _status, mut rx) = connect(0.5).await;
        let secs = 6.0;
        let collector = tokio::spawn(async move { collect(&mut rx, secs).await });
        let mut visible_polls = 0;
        for _ in 0..12 {
            tokio::time::sleep(Duration::from_millis(500)).await;
            if discovered_crowns().iter().any(|d| d.id == ID) {
                visible_polls += 1;
            }
        }
        let got = collector.await.unwrap();
        let rate = got.samples[0].len() as f64 / secs;
        let gaps: Vec<f64> = got
            .batches
            .windows(2)
            .map(|w| w[1].0 - w[0].0)
            .filter(|dt| *dt > 500.0)
            .collect();
        println!(
            "dropout: {rate:.1} samples/s, gaps(ms)={gaps:?}, visible {visible_polls}/12 polls"
        );
        assert!((rate - 128.0).abs() < 25.0, "rate {rate}");
        assert!(gaps.len() >= 2 && gaps.iter().all(|g| (*g - 1000.0).abs() < 150.0));
        assert_eq!(
            visible_polls, 12,
            "info keeps the Crown listed during dropout"
        );
        assert!(got.samples[5].iter().all(|v| *v == 0.0));
        drop(handle);
        stop_crown_discovery();
    }

    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn crown_osc_sim_epoch_packets_both_layouts() {
        for extra in [&[][..], &["--channel-major"][..]] {
            let mut args = vec!["--duration", "3", "--epoch", "16", "--bad-pads", "3"];
            args.extend_from_slice(extra);
            let _main = sim(&args);
            let (handle, _status, mut rx) = connect(0.2).await;
            let secs = 2.0;
            let got = collect(&mut rx, secs).await;
            for (ch, s) in got.samples.iter().enumerate() {
                let rate = s.len() as f64 / secs;
                println!(
                    "epoch16 {extra:?} ch{ch}: {rate:.1} samples/s std={:.2} max|v|={:.1}",
                    std_dev(s),
                    max_abs(s)
                );
                assert!((rate - 256.0).abs() < 256.0 * 0.08, "ch{ch} rate {rate}");
                if ch == 3 {
                    assert!(std_dev(s) > 100.0);
                } else {
                    assert!(max_abs(s) < 12.0, "ch{ch}: bad pad leaked (wrong layout?)");
                }
            }
            drop(handle);
            tokio::time::sleep(Duration::from_millis(300)).await;
        }
    }

    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn crown_osc_sim_overall_quality_falls_back_to_app() {
        let _main = sim(&["--duration", "3", "--quality-overall"]);
        let (handle, _status, mut rx) = connect(0.2).await;
        let got = collect(&mut rx, 2.0).await;
        assert!(got.samples[0].len() > 400);
        features::set_quality_source(QualitySource::Crown);
        let app = [Some(42.0); CROWN_CHANNELS];
        let second = features::resolve_neurosity_second(&app);
        println!("overall-only: source={:?} scores={:?}", second.source, second.scores);
        assert_eq!(second.source, QualitySource::App);
        assert_eq!(second.crown, None);
        assert_eq!(second.scores, app);
        drop(handle);
    }

    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn crown_osc_sim_neurosity_noise_mode() {
        let _main = sim(&["--duration", "3", "--noise"]);
        let (handle, status, mut rx) = connect(0.2).await;
        let got = collect(&mut rx, 2.0).await;
        let all: Vec<f64> = got.samples.concat();
        let (lo, hi) = all
            .iter()
            .fold((f64::MAX, f64::MIN), |(l, h), v| (l.min(*v), h.max(*v)));
        println!(
            "noise: {} samples, range {lo:.2}..{hi:.2} uV, name={}",
            all.len(),
            status.name
        );
        assert!(lo >= -50.0 && hi <= 51.0 && lo < -40.0 && hi > 40.0);
        assert!(all.len() > 8 * 400);
        drop(handle);
    }
}
