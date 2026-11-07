//! PPG path: optical packets → 30 s buffers per channel → heart rate and
//! SpO2 once per second (legacy cadence), plus a 120 s history.

use nf_types::{DeviceInfo, PpgPacket};
use serde::Serialize;
use std::collections::VecDeque;

/// Seconds of optical samples kept (legacy kept 1920 samples = 30 s @ 64 Hz).
pub const PPG_BUFFER_S: f64 = 30.0;
/// Estimates kept for the HR / SpO2 trend.
/// HR / SpO2 estimates kept (1 Hz while a pulse is found): one hour.
pub const HISTORY_LEN: usize = 3600;
/// Seconds of estimates kept (gaps without a pulse still count).
pub const HISTORY_S: f64 = 3600.0;

#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct Estimate {
    pub time: f64,
    pub value: f64,
    pub confidence: f64,
}

#[derive(Debug, Clone)]
pub struct Optics {
    pub rate: f64,
    cap: usize,
    pub channels: Vec<VecDeque<f32>>,
    ir: Option<usize>,
    red: Option<usize>,
    next_eval: Option<f64>,
    pub time: Option<f64>,
    pub hr: VecDeque<Estimate>,
    pub spo2: VecDeque<Estimate>,
}

impl Optics {
    /// `None` when the device has no PPG.
    pub fn new(info: &DeviceInfo) -> Option<Self> {
        let rate = info.ppg_rate_hz.filter(|_| info.has_ppg())?;
        let cap = (PPG_BUFFER_S * rate).ceil() as usize;
        Some(Self {
            rate,
            cap,
            channels: vec![VecDeque::with_capacity(cap); info.ppg_channels.len()],
            ir: info.ppg_index("infrared"),
            red: info.ppg_index("red"),
            next_eval: None,
            time: None,
            hr: VecDeque::new(),
            spo2: VecDeque::new(),
        })
    }

    pub fn ir_index(&self) -> Option<usize> {
        self.ir
    }

    /// Ingest one packet; estimates every 1 s on the last channel of a group.
    pub fn push(&mut self, p: &PpgPacket) {
        let ch = usize::from(p.channel);
        let Some(buf) = self.channels.get_mut(ch) else { return };
        for &x in &p.samples {
            if buf.len() >= self.cap {
                buf.pop_front();
            }
            buf.push_back(x);
        }
        if ch + 1 != self.channels.len() {
            return;
        }
        self.time = Some(p.time);
        let due = *self.next_eval.get_or_insert(p.time + 1.0);
        if p.time + 1e-9 < due {
            return;
        }
        self.next_eval = Some(due + 1.0);
        let get = |i: Option<usize>| -> Vec<f64> {
            i.and_then(|i| self.channels.get(i)).map(|b| b.iter().map(|&x| f64::from(x)).collect()).unwrap_or_default()
        };
        let (ir, red) = (get(self.ir), get(self.red));
        if let Some((v, c)) = nf_dsp::heart_rate(&ir, self.rate) {
            push_capped(&mut self.hr, Estimate { time: p.time, value: v, confidence: c });
        }
        if let Some((v, c)) = nf_dsp::spo2(&ir, &red, self.rate) {
            push_capped(&mut self.spo2, Estimate { time: p.time, value: v, confidence: c });
        }
    }

    /// Last `n` samples of channel `ch`.
    pub fn last(&self, ch: usize, n: usize) -> Vec<f32> {
        self.channels.get(ch).map(|b| b.iter().skip(b.len().saturating_sub(n)).copied().collect()).unwrap_or_default()
    }

    /// Latest estimate unless older than 5 s (signal lost).
    pub fn current(h: &VecDeque<Estimate>, now: Option<f64>) -> Option<Estimate> {
        h.back().copied().filter(|e| now.is_some_and(|t| t - e.time <= 5.0))
    }
}

fn push_capped(h: &mut VecDeque<Estimate>, e: Estimate) {
    if h.capacity() < HISTORY_LEN {
        h.reserve_exact(HISTORY_LEN - h.len());
    }
    while h.len() >= HISTORY_LEN || h.front().is_some_and(|f| f.time < e.time - HISTORY_S) {
        h.pop_front();
    }
    h.push_back(e);
}

#[cfg(test)]
mod history_tests {
    use super::*;

    #[test]
    fn estimates_keep_one_hour_bounded() {
        let mut h = VecDeque::new();
        for i in 0..5000 {
            push_capped(&mut h, Estimate { time: f64::from(i), value: 60.0, confidence: 1.0 });
        }
        assert_eq!(h.len(), HISTORY_LEN);
        assert_eq!(h.front().map(|e| e.time), Some(1400.0));
        assert_eq!(h.capacity(), HISTORY_LEN, "{} slots", h.capacity());
        // 3600 × 24 B = 86 400 B per series.
        assert_eq!(h.capacity() * std::mem::size_of::<Estimate>(), 86_400);
        // A long pause without pulse: age eviction, not only count.
        push_capped(&mut h, Estimate { time: 9000.0, value: 60.0, confidence: 1.0 });
        assert!(h.front().is_some_and(|e| e.time >= 9000.0 - HISTORY_S));
    }
}
