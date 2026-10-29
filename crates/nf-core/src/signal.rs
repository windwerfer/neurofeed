//! Live signal path: raw packets → per-channel conditioning (nf-dsp) →
//! rolling buffers → band snapshots every `BAND_INTERVAL_S`.

use nf_dsp::{band_powers, EegFilter, Mains};
use nf_types::{BandSnapshot, DeviceInfo, EegPacket};
use std::collections::VecDeque;

/// Seconds of raw and filtered signal kept per channel.
pub const BUFFER_S: f64 = 10.0;
/// FFT window for bands / PSD (1 s at 256 Hz).
pub const WINDOW_S: f64 = 1.0;
/// Band snapshot cadence (matches the legacy 10 Hz band stream).
pub const BAND_INTERVAL_S: f64 = 0.1;

#[derive(Debug, Clone)]
pub struct Signal {
    pub rate: f64,
    cap: usize,
    filters: Vec<EegFilter>,
    pub raw: Vec<VecDeque<f32>>,
    pub filtered: Vec<VecDeque<f32>>,
    /// Time of the newest sample.
    pub time: Option<f64>,
    next_band: Option<f64>,
}

impl Signal {
    pub fn new(info: &DeviceInfo) -> Self {
        let n = info.channels.len();
        let rate = info.sample_rate_hz;
        let cap = (BUFFER_S * rate).ceil() as usize;
        Self {
            rate,
            cap,
            // Mains detection is not ported yet: notch both 50 and 60 Hz.
            filters: vec![EegFilter::new(rate, Mains::Unknown); n],
            raw: vec![VecDeque::with_capacity(cap); n],
            filtered: vec![VecDeque::with_capacity(cap); n],
            time: None,
            next_band: None,
        }
    }

    pub fn window_len(&self) -> usize {
        (WINDOW_S * self.rate).round() as usize
    }

    /// Ingest one packet; returns a band snapshot when one is due.
    pub fn push(&mut self, p: &EegPacket) -> Option<BandSnapshot> {
        let ch = usize::from(p.electrode);
        let (Some(f), Some(raw), Some(out)) = (self.filters.get_mut(ch), self.raw.get_mut(ch), self.filtered.get_mut(ch)) else {
            return None;
        };
        for &x in &p.samples {
            push_capped(raw, x, self.cap);
            push_capped(out, f.process(f64::from(x)) as f32, self.cap);
        }
        // Snapshot on the last channel of a packet group so all channels are current.
        if ch + 1 != self.filters.len() {
            return None;
        }
        self.time = Some(p.time);
        let due = *self.next_band.get_or_insert(p.time);
        if p.time + 1e-9 < due {
            return None;
        }
        self.next_band = Some(due + BAND_INTERVAL_S * ((p.time - due) / BAND_INTERVAL_S).floor().max(0.0) + BAND_INTERVAL_S);
        let w = self.window_len();
        let powers = self.filtered.iter().map(|b| tail(b, w).and_then(|t| band_powers(&t, self.rate))).collect::<Option<Vec<_>>>()?;
        Some(BandSnapshot { time: p.time, powers })
    }

    /// Last `n` samples of channel `ch` (fewer if not buffered yet).
    pub fn last(&self, ch: usize, n: usize, filtered: bool) -> Vec<f32> {
        let buf = if filtered { &self.filtered } else { &self.raw };
        buf.get(ch).map(|b| b.iter().skip(b.len().saturating_sub(n)).copied().collect()).unwrap_or_default()
    }
}

fn push_capped(b: &mut VecDeque<f32>, x: f32, cap: usize) {
    if b.len() >= cap {
        b.pop_front();
    }
    b.push_back(x);
}

fn tail(b: &VecDeque<f32>, n: usize) -> Option<Vec<f32>> {
    (b.len() >= n).then(|| b.iter().skip(b.len() - n).copied().collect())
}
