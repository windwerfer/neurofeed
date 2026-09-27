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
        let frames = values.len() / CROWN_CHANNELS;
        for (i, frame) in values.chunks_exact(CROWN_CHANNELS).enumerate() {
            let sample_ms = arrival_ms - (frames - 1 - i) as f64 * period_ms;
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
            SignalQuality::PerChannel(values) => {
                for (ch, q) in values.iter().enumerate() {
                    features::set_crown_quality(ch, *q);
                }
            }
            SignalQuality::Overall(q) => log::trace!("[crown_osc] overall signalQuality {q}"),
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
