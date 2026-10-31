//! Replay a saved session as a device (`replay:<id>`): the stored EEG, AUX,
//! PPG and accelerometer blocks are delivered in real time so every graph
//! view works on a recording. Replays are never recorded again.

use nf_format::Record;
use nf_types::{AccelPacket, DeviceInfo, DeviceSource, EegPacket, LinkState, PpgPacket};

/// Id scheme for replays.
pub const SCHEME: &str = "replay";

pub fn is_replay(id: &str) -> bool {
    id.split(':').next() == Some(SCHEME)
}

/// One stream: packets with times relative to the recording start, and a cursor.
struct Lane<T> {
    items: Vec<(f64, T)>,
    next: usize,
}

impl<T: Clone> Lane<T> {
    fn new(mut items: Vec<(f64, T)>, t0: f64) -> Self {
        items.sort_by(|a, b| a.0.total_cmp(&b.0));
        items.iter_mut().for_each(|i| i.0 -= t0);
        Self { items, next: 0 }
    }
    /// Due items, with their absolute session time.
    fn take(&mut self, start: f64, now: f64) -> Vec<(f64, T)> {
        let n = self.items[self.next..].partition_point(|i| i.0 + start <= now);
        let out = self.items[self.next..self.next + n].iter().map(|(t, x)| (t + start, x.clone())).collect();
        self.next += n;
        out
    }
    fn done(&self) -> bool {
        self.next >= self.items.len()
    }
}

pub struct Replay {
    info: DeviceInfo,
    eeg: Lane<(u16, Vec<f32>)>,
    ppg: Lane<(u16, Vec<f32>)>,
    accel: Lane<Vec<[f32; 3]>>,
    start: Option<f64>,
}

impl Replay {
    /// Build from a stored session's device JSON and NFEDBIN body.
    pub fn new(id: u64, device_json: &str, body: &[u8]) -> Result<Self, String> {
        let mut info: DeviceInfo = serde_json::from_str(device_json).map_err(|e| format!("device info: {e}"))?;
        let (mut eeg, mut ppg, mut accel) = (Vec::new(), Vec::new(), Vec::new());
        for r in nf_format::parse_body(body).map_err(|e| e.to_string())? {
            match r {
                Record::Eeg { ts, electrode, samples } => eeg.extend(u16::try_from(electrode).ok().map(|e| (ts, (e, samples)))),
                Record::Ppg { ts, channel, samples } => ppg.extend(u16::try_from(channel).ok().map(|c| (ts, (c, samples)))),
                Record::Accelerometer { ts, xyz, .. } => accel.push((ts, xyz)),
                _ => {}
            }
        }
        let Some(t0) = eeg.iter().map(|e| e.0).min_by(f64::total_cmp) else {
            return Err(format!("session {id} has no EEG to replay"));
        };
        info.id = format!("{SCHEME}:{id}");
        info.name = format!("Replay · {}", info.name);
        Ok(Self { info, eeg: Lane::new(eeg, t0), ppg: Lane::new(ppg, t0), accel: Lane::new(accel, t0), start: None })
    }

    /// Seconds of EEG.
    pub fn duration(&self) -> f64 {
        self.eeg.items.last().map_or(0.0, |i| i.0)
    }
}

impl DeviceSource for Replay {
    fn info(&self) -> DeviceInfo {
        self.info.clone()
    }
    fn poll(&mut self, now: f64) -> Vec<EegPacket> {
        let start = *self.start.get_or_insert(now);
        self.eeg.take(start, now).into_iter().map(|(time, (electrode, samples))| EegPacket { time, electrode, samples }).collect()
    }
    fn poll_ppg(&mut self, now: f64) -> Vec<PpgPacket> {
        let start = *self.start.get_or_insert(now);
        self.ppg.take(start, now).into_iter().map(|(time, (channel, samples))| PpgPacket { time, channel, samples }).collect()
    }
    fn poll_accel(&mut self, now: f64) -> Vec<AccelPacket> {
        let start = *self.start.get_or_insert(now);
        self.accel.take(start, now).into_iter().map(|(time, samples)| AccelPacket { time, samples }).collect()
    }
    fn link(&self) -> LinkState {
        if self.start.is_some() && self.eeg.done() {
            LinkState::Lost { reason: "end of recording".into() }
        } else {
            LinkState::Streaming
        }
    }
}
