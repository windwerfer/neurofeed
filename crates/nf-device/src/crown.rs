//! Neurosity Crown over OSC/UDP (ported from `rust/src/api/neurosity_osc.rs`).
//!
//! One UDP socket (default port [`CROWN_OSC_PORT`]) serves LAN discovery and
//! data; its thread runs while a scan is active or a Crown is open. Addresses:
//! `/neurosity/notion/{deviceId}/{leaf}` (`raw`, `info`, ...). `/raw` carries
//! one or more 8-float frames (µV) in `CROWN_CHANNELS` order; multi-sample
//! packets are read sample- or channel-major, whichever is smoother, locked
//! after 3 agreeing packets (the real layout is unverified).

use std::collections::HashMap;
use std::net::UdpSocket;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use rosc::{OscPacket, OscType};

use crate::{crown_info, lock, DeviceInfo, DeviceProvider, DeviceSource, Feed, LinkState, LiveSource, CROWN_CHANNELS};

pub const CROWN_OSC_PORT: u16 = 9000;
const N: usize = CROWN_CHANNELS.len();
const SEEN_TTL: Duration = Duration::from_secs(5);
const BATCH: usize = 16;
const LAYOUT_AGREE: u32 = 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Layout {
    SampleMajor,
    ChannelMajor,
}

#[derive(Default)]
struct LayoutDetector {
    locked: Option<Layout>,
    streak: Option<(Layout, u32)>,
}

impl LayoutDetector {
    fn frames(&mut self, v: &[f32]) -> Vec<[f32; N]> {
        let n = v.len() / N;
        let at = |l, s: usize, ch: usize| match l {
            Layout::SampleMajor => v[s * N + ch],
            Layout::ChannelMajor => v[ch * n + s],
        };
        let jumps = |l| -> f64 {
            (0..N).flat_map(|ch| (1..n).map(move |s| (ch, s))).map(|(ch, s)| f64::from((at(l, s, ch) - at(l, s - 1, ch)).abs())).sum()
        };
        let layout = match self.locked {
            Some(l) => l,
            None if n < 2 => Layout::SampleMajor,
            None => {
                let vote =
                    if jumps(Layout::ChannelMajor) < jumps(Layout::SampleMajor) { Layout::ChannelMajor } else { Layout::SampleMajor };
                let c = match self.streak {
                    Some((l, c)) if l == vote => c + 1,
                    _ => 1,
                };
                self.streak = Some((vote, c));
                if c >= LAYOUT_AGREE {
                    self.locked = Some(vote);
                }
                vote
            }
        };
        (0..n).map(|s| std::array::from_fn(|ch| at(layout, s, ch))).collect()
    }
}

/// `(device id, leaf)` of a `/neurosity/notion/{id}/{leaf}` address.
fn parse_addr(addr: &str) -> Option<(&str, &str)> {
    let (id, leaf) = addr.strip_prefix("/neurosity/notion/")?.split_once('/')?;
    (!id.is_empty() && !leaf.is_empty()).then_some((id, leaf))
}

fn floats(args: &[OscType], out: &mut Vec<f32>) {
    for a in args {
        match a {
            OscType::Float(f) => out.push(*f),
            OscType::Double(d) => out.push(*d as f32),
            OscType::Array(arr) => floats(&arr.content, out),
            _ => {}
        }
    }
}

fn flatten(p: OscPacket, out: &mut Vec<rosc::OscMessage>) {
    match p {
        OscPacket::Message(m) => out.push(m),
        OscPacket::Bundle(b) => b.content.into_iter().for_each(|p| flatten(p, out)),
    }
}

struct Route {
    id: String,
    feed: Feed,
    layout: LayoutDetector,
    pending: Vec<Vec<f32>>,
    gen: u64,
}

impl Route {
    fn raw(&mut self, args: &[OscType]) -> bool {
        let mut v = Vec::new();
        floats(args, &mut v);
        if v.is_empty() || v.len() % N != 0 {
            return true;
        }
        for f in self.layout.frames(&v) {
            for (ch, x) in f.iter().enumerate() {
                self.pending[ch].push(*x);
            }
        }
        if self.pending[0].len() >= BATCH {
            for (ch, buf) in self.pending.iter_mut().enumerate() {
                if !self.feed.eeg(ch as u16, std::mem::take(buf)) {
                    return false;
                }
            }
        }
        true
    }
}

#[derive(Default)]
struct Hub {
    seen: HashMap<String, (Option<String>, Instant)>,
    routes: Vec<Route>,
    /// Timed discovery deadline. Ignored while `hold` is set.
    discover_until: Option<Instant>,
    /// Device dialog: keep listening until [`DeviceProvider::stop_scan`].
    hold: bool,
    running: bool,
    error: Option<String>,
    next_gen: u64,
}

impl Hub {
    fn active(&self, now: Instant) -> bool {
        !self.routes.is_empty() || self.hold || self.discover_until.is_some_and(|t| now < t)
    }
    fn on_message(&mut self, m: &rosc::OscMessage, now: Instant) {
        let Some((id, leaf)) = parse_addr(&m.addr) else { return };
        let e = self.seen.entry(id.to_owned()).or_insert((None, now));
        e.1 = now;
        if leaf == "info" {
            if let Some(OscType::String(nick)) = m.args.get(1).filter(|a| !matches!(a, OscType::String(s) if s.is_empty())) {
                e.0 = Some(nick.clone());
            }
        }
        if leaf == "raw" {
            self.routes.retain_mut(|r| r.id != id || r.raw(&m.args));
        }
        if leaf == "signalQuality" {
            let mut v = Vec::new();
            floats(&m.args, &mut v);
            // 8 per-pad values 0..=1; a single overall value is not per pad.
            if v.len() == N && v.iter().all(|q| (0.0..=1.0).contains(q)) {
                self.routes.retain(|r| r.id != id || r.feed.quality(v.clone()));
            }
        }
    }
}

/// Crown provider (`crown:<deviceId>`).
pub struct CrownProvider {
    port: u16,
    hub: Arc<Mutex<Hub>>,
}

impl Default for CrownProvider {
    fn default() -> Self {
        Self::with_port(CROWN_OSC_PORT)
    }
}

impl CrownProvider {
    pub fn with_port(port: u16) -> Self {
        Self { port, hub: Arc::default() }
    }

    /// Last socket error (e.g. port in use).
    pub fn error(&self) -> Option<String> {
        lock(&self.hub).error.clone()
    }

    fn ensure_thread(&self) {
        let mut h = lock(&self.hub);
        if h.running {
            return;
        }
        let sock =
            match UdpSocket::bind(("0.0.0.0", self.port)).and_then(|s| s.set_read_timeout(Some(Duration::from_millis(100))).map(|()| s)) {
                Ok(s) => s,
                Err(e) => {
                    h.error = Some(format!("UDP port {}: {e}", self.port));
                    return;
                }
            };
        h.running = true;
        h.error = None;
        drop(h);
        let hub = self.hub.clone();
        std::thread::Builder::new()
            .name("crown-osc".into())
            .spawn(move || {
                let mut buf = vec![0u8; 65_536];
                loop {
                    let got = sock.recv(&mut buf);
                    let now = Instant::now();
                    let mut h = lock(&hub);
                    if let Ok(n) = got {
                        if let Ok((_, p)) = rosc::decoder::decode_udp(&buf[..n]) {
                            let mut msgs = Vec::new();
                            flatten(p, &mut msgs);
                            msgs.iter().for_each(|m| h.on_message(m, now));
                        }
                    }
                    if !h.active(now) {
                        h.running = false;
                        return;
                    }
                }
            })
            .map(|_| ())
            .unwrap_or_else(|e| lock(&self.hub).error = Some(e.to_string()));
    }
}

impl DeviceProvider for CrownProvider {
    fn scheme(&self) -> &'static str {
        "crown"
    }
    fn list(&self) -> Vec<DeviceInfo> {
        let now = Instant::now();
        let mut h = lock(&self.hub);
        h.seen.retain(|_, (_, t)| now.saturating_duration_since(*t) <= SEEN_TTL);
        let mut v: Vec<DeviceInfo> =
            h.seen.iter().map(|(id, (nick, _))| crown_info(&format!("crown:{id}"), nick.as_deref().unwrap_or(id))).collect();
        v.sort_by(|a, b| a.id.cmp(&b.id));
        v
    }
    fn open(&mut self, id: &str) -> Result<Box<dyn DeviceSource>, String> {
        let dev = id.strip_prefix("crown:").filter(|d| !d.is_empty()).ok_or_else(|| format!("bad Crown id `{id}`"))?;
        let name = lock(&self.hub).seen.get(dev).and_then(|(n, _)| n.clone()).unwrap_or_else(|| format!("Crown {dev}"));
        let (src, feed) = LiveSource::new(crown_info(id, &name));
        feed.link(LinkState::Connecting);
        let gen = {
            let mut h = lock(&self.hub);
            h.next_gen += 1;
            let gen = h.next_gen;
            h.routes.push(Route { id: dev.to_owned(), feed, layout: LayoutDetector::default(), pending: vec![Vec::new(); N], gen });
            gen
        };
        self.ensure_thread();
        if let Some(e) = self.error() {
            lock(&self.hub).routes.retain(|r| r.gen != gen);
            return Err(e);
        }
        let hub = self.hub.clone();
        Ok(Box::new(src.on_drop(move || lock(&hub).routes.retain(|r| r.gen != gen))))
    }
    fn can_scan(&self) -> bool {
        true
    }
    fn last_error(&self) -> Option<String> {
        self.error()
    }
    fn scan(&mut self, seconds: f64) -> Result<(), String> {
        {
            let mut h = lock(&self.hub);
            // The dialog's watch owns the socket; a timed scan must not cut it short.
            if !h.hold {
                h.discover_until = Some(Instant::now() + Duration::from_secs_f64(seconds.clamp(0.5, 120.0)));
                h.error = None;
            }
        }
        self.ensure_thread();
        self.error().map_or(Ok(()), Err)
    }
    fn watch(&mut self) -> Result<(), String> {
        {
            let mut h = lock(&self.hub);
            h.hold = true;
            h.discover_until = None;
            h.error = None;
        }
        self.ensure_thread();
        if let Some(e) = self.error() {
            lock(&self.hub).hold = false;
            return Err(e);
        }
        Ok(())
    }
    fn stop_scan(&mut self) {
        let mut h = lock(&self.hub);
        h.hold = false;
        h.discover_until = None;
    }
    fn scanning(&self) -> bool {
        let h = lock(&self.hub);
        h.hold || h.discover_until.is_some_and(|t| Instant::now() < t)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn layout_detector_prefers_the_smooth_reading() {
        let smooth = |s: usize, ch: usize| (s as f32) * 0.1 + ch as f32 * 100.0;
        let n = 16;
        let cm: Vec<f32> = (0..N).flat_map(|ch| (0..n).map(move |s| smooth(s, ch))).collect();
        let mut d = LayoutDetector::default();
        for _ in 0..3 {
            let f = d.frames(&cm);
            assert_eq!(f[5][2], smooth(5, 2));
        }
        assert_eq!(d.locked, Some(Layout::ChannelMajor));
    }

    #[test]
    fn watch_stays_up_until_stop() {
        let port = std::net::UdpSocket::bind("127.0.0.1:0").expect("port").local_addr().expect("addr").port();
        let mut p = CrownProvider::with_port(port);
        p.watch().expect("watch");
        assert!(p.scanning(), "watch does not expire on its own");
        p.stop_scan();
        assert!(!p.scanning());
    }

    #[test]
    fn address_parsing() {
        assert_eq!(parse_addr("/neurosity/notion/abc/raw"), Some(("abc", "raw")));
        assert_eq!(parse_addr("/neurosity/notion//raw"), None);
        assert_eq!(parse_addr("/muse/eeg"), None);
    }
}
