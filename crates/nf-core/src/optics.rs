//! PPG path: optical packets → per-channel native-rate waveform (5 min,
//! time-stamped segments) → heart rate and SpO2 once per second (legacy
//! cadence), kept as a bounded one-hour 1 Hz summary.
//!
//! Two separate stores, on purpose:
//! - [`Wave`]: the raw optical samples (sensor counts, *not* bpm) at the
//!   device rate for every PPG channel, [`PPG_DETAIL_S`] long. Gaps (BLE
//!   drop-outs, reconnects) start a new segment, so a sample's time is
//!   always its real acquisition time and nothing is stitched over a gap.
//! - [`Estimate`] series: one HR and one SpO2 estimate per second while the
//!   estimator finds a pulse, [`HISTORY_S`] long. Seconds without a pulse
//!   have no entry (a gap), never a zero or a repeated value.
//!
//! Means (`HR ⌀`, `SpO2 ⌀`) are plain arithmetic means of the *reliable*
//! 1 Hz estimates ([`Estimate::reliable`]), each estimate counted once:
//! over the whole retained hour (kept incrementally, updated on push and
//! eviction) or, while a recording runs, over that recording so far
//! (running sum/count reset on every recording start, dropped on stop).
//! No samples are kept for the means. The estimates are 1 s apart, so the
//! count-mean equals the time-weighted mean over the covered seconds.

use nf_types::{DeviceInfo, PpgPacket};
use serde::Serialize;
use std::collections::VecDeque;

/// Seconds of native-rate optical samples kept per channel (5 min).
pub const PPG_DETAIL_S: f64 = 300.0;
/// Legacy name of the raw buffer length (now the 5 min detail).
pub const PPG_BUFFER_S: f64 = PPG_DETAIL_S;
/// HR / SpO2 estimates kept (1 Hz while a pulse is found): one hour.
pub const HISTORY_LEN: usize = 3600;
/// Seconds of estimates kept (gaps without a pulse still count).
pub const HISTORY_S: f64 = 3600.0;
/// An estimate older than this is not "current" (signal lost).
pub const CURRENT_S: f64 = 5.0;
/// Consecutive estimates further apart than this are drawn with a gap.
pub const GAP_S: f64 = 2.5;
/// Cursor read-out: nearest estimate within this many seconds, else none.
pub const READOUT_TOL_S: f64 = 1.0;
/// Below this confidence an HR estimate is unreliable: not drawn, not in
/// means (confidence = 1 − CV of the beat intervals).
pub const HR_MIN_CONFIDENCE: f64 = 0.6;
/// Below this an SpO2 estimate is unreliable. Its confidence is a
/// perfusion heuristic (`min(1, 20·AC_rms/DC)` of IR and red, geometric
/// mean): 0.1 ≈ 0.5 % RMS perfusion. SpO2 itself is an **uncalibrated**
/// ratio-of-ratios estimate (`110 − 25·R`, legacy constants, not
/// calibrated for Muse optics); the gate only drops flat / dark signal.
pub const SPO2_MIN_CONFIDENCE: f64 = 0.1;

#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct Estimate {
    pub time: f64,
    pub value: f64,
    pub confidence: f64,
}

/// Which series an estimate belongs to (reliability threshold).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Series {
    Hr,
    Spo2,
}

impl Series {
    pub fn min_confidence(self) -> f64 {
        match self {
            Series::Hr => HR_MIN_CONFIDENCE,
            Series::Spo2 => SPO2_MIN_CONFIDENCE,
        }
    }
}

impl Estimate {
    pub fn reliable(&self, s: Series) -> bool {
        self.value.is_finite() && self.confidence >= s.min_confidence()
    }
}

/// Running mean: sum and count of reliable estimates.
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize)]
pub struct Mean {
    pub sum: f64,
    pub count: u64,
}

impl Mean {
    pub fn value(&self) -> Option<f64> {
        (self.count > 0).then(|| self.sum / self.count as f64)
    }
    fn add(&mut self, v: f64) {
        self.sum += v;
        self.count += 1;
    }
    fn remove(&mut self, v: f64) {
        self.count = self.count.saturating_sub(1);
        self.sum = if self.count == 0 { 0.0 } else { self.sum - v };
    }
}

/// Means of the current recording, from its start.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct RunMeans {
    pub since: f64,
    pub hr: Mean,
    pub spo2: Mean,
}

/// A contiguous run of samples: global index of its first sample and that
/// sample's session time.
#[derive(Debug, Clone, Copy, PartialEq)]
struct Seg {
    idx: u64,
    t0: f64,
}

/// One optical channel at its native rate, [`PPG_DETAIL_S`] long.
#[derive(Debug, Clone)]
pub struct Wave {
    rate: f64,
    cap: usize,
    samples: VecDeque<f32>,
    /// Global index of `samples[0]`.
    first: u64,
    segs: VecDeque<Seg>,
}

impl Wave {
    pub fn new(rate: f64, seconds: f64) -> Self {
        let cap = (seconds * rate).ceil() as usize;
        Self { rate, cap, samples: VecDeque::with_capacity(cap), first: 0, segs: VecDeque::new() }
    }

    fn end(&self) -> u64 {
        self.first + self.samples.len() as u64
    }

    /// Bytes reserved for samples (the bound; segments are a few dozen B).
    pub fn bytes(&self) -> usize {
        self.samples.capacity() * std::mem::size_of::<f32>() + self.segs.capacity() * std::mem::size_of::<Seg>()
    }

    pub fn len(&self) -> usize {
        self.samples.len()
    }

    pub fn is_empty(&self) -> bool {
        self.samples.is_empty()
    }

    /// Number of contiguous segments retained (1 + gaps).
    pub fn segments(&self) -> usize {
        self.segs.len()
    }

    fn seg_of(&self, idx: u64) -> Option<&Seg> {
        let k = self.segs.partition_point(|s| s.idx <= idx);
        k.checked_sub(1).and_then(|k| self.segs.get(k))
    }

    fn time_of(&self, idx: u64) -> Option<f64> {
        self.seg_of(idx).map(|s| s.t0 + (idx - s.idx) as f64 / self.rate)
    }

    pub fn oldest(&self) -> Option<f64> {
        self.time_of(self.first).filter(|_| !self.samples.is_empty())
    }

    pub fn newest(&self) -> Option<f64> {
        self.end().checked_sub(1).filter(|_| !self.samples.is_empty()).and_then(|i| self.time_of(i))
    }

    /// Append a block whose **last** sample is at `time`.
    pub fn push(&mut self, time: f64, block: &[f32]) {
        if block.is_empty() || !time.is_finite() {
            return;
        }
        let t_first = time - (block.len() - 1) as f64 / self.rate;
        let expected = self.newest().map(|t| t + 1.0 / self.rate);
        if expected.is_none_or(|e| (t_first - e).abs() > 0.5 / self.rate) {
            self.segs.push_back(Seg { idx: self.end(), t0: t_first });
        }
        for &x in block {
            if self.samples.len() >= self.cap {
                self.samples.pop_front();
                self.first += 1;
            }
            self.samples.push_back(x);
        }
        while self.segs.len() > 1 && self.segs.get(1).is_some_and(|s| s.idx <= self.first) {
            self.segs.pop_front();
        }
    }

    /// Samples of the newest contiguous segment (at most `n`).
    pub fn tail_contiguous(&self, n: usize) -> Vec<f64> {
        let start = self.segs.back().map_or(self.first, |s| s.idx.max(self.first));
        let avail = (self.end() - start) as usize;
        let skip = self.samples.len() - avail.min(n);
        self.samples.range(skip..).map(|&x| f64::from(x)).collect()
    }

    /// Visit `(time, value)` of the samples in `[t0, t1]` plus one beyond
    /// each side of every segment (so a trace reaches the plot edges); a
    /// `None` between two segments marks a gap. Only the window's samples
    /// are touched. Returns how many samples were visited.
    pub fn visit(&self, t0: f64, t1: f64, mut f: impl FnMut(Option<(f64, f32)>)) -> usize {
        let mut n = 0;
        for (k, s) in self.segs.iter().enumerate() {
            let s_end = self.segs.get(k + 1).map_or(self.end(), |x| x.idx);
            let lo = s.idx.max(self.first);
            if lo >= s_end {
                continue;
            }
            let t_lo = s.t0 + (lo - s.idx) as f64 / self.rate;
            let t_hi = s.t0 + (s_end - 1 - s.idx) as f64 / self.rate;
            if t_hi < t0 || t_lo > t1 {
                continue;
            }
            let a = (((t0 - s.t0) * self.rate).floor() as i64 - 1).max(lo as i64 - s.idx as i64).max(0) as u64 + s.idx;
            let b = ((((t1 - s.t0) * self.rate).ceil() as i64 + 1) as u64 + s.idx).min(s_end - 1);
            if n > 0 {
                f(None);
            }
            for idx in a.max(lo)..=b {
                let v = self.samples[(idx - self.first) as usize];
                f(Some((s.t0 + (idx - s.idx) as f64 / self.rate, v)));
                n += 1;
            }
        }
        n
    }

    /// Up to `max` samples in `(t0, t1]`: `(segments of (t_first, samples))`.
    pub fn slice(&self, t0: f64, t1: f64, max: usize) -> Vec<(f64, Vec<f32>)> {
        let mut out: Vec<(f64, Vec<f32>)> = Vec::new();
        let mut fresh = true;
        let mut total = 0;
        self.visit(t0, t1, |s| match s {
            None => fresh = true,
            Some((t, v)) if t > t0 + 1e-9 && t <= t1 + 1e-9 && total < max => {
                if fresh {
                    out.push((t, Vec::new()));
                    fresh = false;
                }
                if let Some(last) = out.last_mut() {
                    last.1.push(v);
                }
                total += 1;
            }
            Some(_) => {}
        });
        out
    }
}

#[derive(Debug, Clone)]
pub struct Optics {
    pub rate: f64,
    pub waves: Vec<Wave>,
    ir: Option<usize>,
    red: Option<usize>,
    next_eval: Option<f64>,
    /// Session time of the newest optical sample.
    pub time: Option<f64>,
    /// What the HR view presents as "now": follows `time`, frozen while the
    /// stream is paused (Pause freezes graphs; acquisition, estimates and
    /// the recording's means continue).
    pub view_time: Option<f64>,
    pub hr: VecDeque<Estimate>,
    pub spo2: VecDeque<Estimate>,
    hour_hr: Mean,
    hour_spo2: Mean,
    run: Option<RunMeans>,
}

impl Optics {
    /// `None` when the device has no PPG.
    pub fn new(info: &DeviceInfo) -> Option<Self> {
        let rate = info.ppg_rate_hz.filter(|_| info.has_ppg())?;
        Some(Self {
            rate,
            // One by one: cloning a VecDeque does not keep its exact capacity.
            waves: (0..info.ppg_channels.len()).map(|_| Wave::new(rate, PPG_DETAIL_S)).collect(),
            ir: info.ppg_index("infrared"),
            red: info.ppg_index("red"),
            next_eval: None,
            time: None,
            view_time: None,
            hr: VecDeque::with_capacity(HISTORY_LEN),
            spo2: VecDeque::with_capacity(HISTORY_LEN),
            hour_hr: Mean::default(),
            hour_spo2: Mean::default(),
            run: None,
        })
    }

    pub fn ir_index(&self) -> Option<usize> {
        self.ir
    }

    pub fn red_index(&self) -> Option<usize> {
        self.red
    }

    /// Bytes reserved for the raw optical detail (all channels).
    pub fn wave_bytes(&self) -> usize {
        self.waves.iter().map(Wave::bytes).sum()
    }

    /// Oldest / newest raw sample time over all channels.
    pub fn wave_span(&self) -> Option<(f64, f64)> {
        let o = self.waves.iter().filter_map(Wave::oldest).reduce(f64::max)?;
        let n = self.waves.iter().filter_map(Wave::newest).reduce(f64::max)?;
        Some((o, n))
    }

    /// Ingest one packet; estimates every 1 s on the last channel of a group.
    pub fn push(&mut self, p: &PpgPacket) {
        let ch = usize::from(p.channel);
        let Some(w) = self.waves.get_mut(ch) else { return };
        w.push(p.time, &p.samples);
        if ch + 1 != self.waves.len() {
            return;
        }
        self.time = Some(p.time);
        let due = *self.next_eval.get_or_insert(p.time + 1.0);
        if p.time + 1e-9 < due {
            return;
        }
        // After a long gap evaluate on the next second, not once per
        // missed second (no repeated estimates from the same window).
        self.next_eval = Some(if p.time - due > 1.0 { p.time + 1.0 } else { due + 1.0 });
        let n = (nf_dsp::PPG_WINDOW_S * self.rate).ceil() as usize;
        // Only the newest contiguous segment: never estimate across a gap.
        let get = |i: Option<usize>| -> Vec<f64> { i.and_then(|i| self.waves.get(i)).map(|w| w.tail_contiguous(n)).unwrap_or_default() };
        let (ir, red) = (get(self.ir), get(self.red));
        if let Some((v, c)) = nf_dsp::heart_rate(&ir, self.rate) {
            self.add(Series::Hr, Estimate { time: p.time, value: v, confidence: c });
        }
        if let Some((v, c)) = nf_dsp::spo2(&ir, &red, self.rate) {
            self.add(Series::Spo2, Estimate { time: p.time, value: v, confidence: c });
        }
    }

    fn add(&mut self, s: Series, e: Estimate) {
        let (h, mean) = match s {
            Series::Hr => (&mut self.hr, &mut self.hour_hr),
            Series::Spo2 => (&mut self.spo2, &mut self.hour_spo2),
        };
        for gone in push_capped(h, e) {
            if gone.reliable(s) {
                mean.remove(gone.value);
            }
        }
        if e.reliable(s) {
            mean.add(e.value);
            if let Some(r) = self.run.as_mut().filter(|r| e.time >= r.since) {
                match s {
                    Series::Hr => r.hr.add(e.value),
                    Series::Spo2 => r.spo2.add(e.value),
                }
            }
        }
    }

    /// A recording started at `since`: running means start empty.
    pub fn begin_run(&mut self, since: f64) {
        self.run = Some(RunMeans { since, hr: Mean::default(), spo2: Mean::default() });
    }

    /// The recording stopped: means are the retained hour's again.
    pub fn end_run(&mut self) {
        self.run = None;
    }

    pub fn run(&self) -> Option<RunMeans> {
        self.run
    }

    /// Mean of the reliable estimates: the recording so far while one
    /// runs, else the whole retained hour.
    pub fn mean(&self, s: Series) -> Mean {
        match (self.run, s) {
            (Some(r), Series::Hr) => r.hr,
            (Some(r), Series::Spo2) => r.spo2,
            (None, Series::Hr) => self.hour_hr,
            (None, Series::Spo2) => self.hour_spo2,
        }
    }

    pub fn series(&self, s: Series) -> &VecDeque<Estimate> {
        match s {
            Series::Hr => &self.hr,
            Series::Spo2 => &self.spo2,
        }
    }

    /// Latest **reliable** estimate unless older than [`CURRENT_S`].
    pub fn current_of(&self, s: Series) -> Option<Estimate> {
        let now = self.view_time.or(self.time)?;
        let h = self.series(s);
        let k = h.partition_point(|e| e.time <= now + 1e-9);
        h.range(..k).rev().take_while(|e| now - e.time <= CURRENT_S).find(|e| e.reliable(s)).copied()
    }

    /// Latest estimate unless older than 5 s (signal lost).
    pub fn current(h: &VecDeque<Estimate>, now: Option<f64>) -> Option<Estimate> {
        h.back().copied().filter(|e| now.is_some_and(|t| t - e.time <= CURRENT_S))
    }

    /// Nearest reliable estimate to `t` within [`READOUT_TOL_S`] (no value
    /// is carried across a gap).
    pub fn at(&self, s: Series, t: f64) -> Option<Estimate> {
        let h = self.series(s);
        let k = h.partition_point(|e| e.time < t);
        [k.checked_sub(1), Some(k)]
            .into_iter()
            .flatten()
            .filter_map(|i| h.get(i))
            .filter(|e| e.reliable(s) && (e.time - t).abs() <= READOUT_TOL_S)
            .min_by(|a, b| (a.time - t).abs().total_cmp(&(b.time - t).abs()))
            .copied()
    }
}

/// Push, evicting by count and age; returns the evicted estimates.
fn push_capped(h: &mut VecDeque<Estimate>, e: Estimate) -> Vec<Estimate> {
    if h.capacity() < HISTORY_LEN {
        h.reserve_exact(HISTORY_LEN - h.len());
    }
    let mut gone = Vec::new();
    while h.len() >= HISTORY_LEN || h.front().is_some_and(|f| f.time < e.time - HISTORY_S) {
        if let Some(g) = h.pop_front() {
            gone.push(g);
        }
    }
    h.push_back(e);
    gone
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

    fn wave_with_gap() -> Wave {
        let mut w = Wave::new(64.0, 300.0);
        // 10 s contiguous at 64 Hz in 6-sample blocks, then a 3 s gap.
        let mut i = 0u64;
        while i + 6 <= 640 {
            let last = (i + 5) as f64 / 64.0;
            w.push(last, &[i as f32; 6]);
            i += 6;
        }
        let t = 13.0;
        w.push(t + 5.0 / 64.0, &[-1.0; 6]);
        w
    }

    #[test]
    fn wave_segments_keep_real_times_across_gaps() {
        let w = wave_with_gap();
        assert_eq!(w.segments(), 2);
        assert_eq!(w.oldest(), Some(0.0));
        assert!((w.newest().unwrap() - (13.0 + 5.0 / 64.0)).abs() < 1e-9);
        let s = w.slice(9.0, 14.0, 10_000);
        assert_eq!(s.len(), 2, "a gap splits the slice");
        assert!((s[1].0 - 13.0).abs() < 1e-9);
        assert!(s[1].1.iter().all(|&v| v == -1.0));
        // The estimator never sees across the gap.
        assert_eq!(w.tail_contiguous(1000).len(), 6);
    }

    #[test]
    fn wave_memory_is_exact_and_bounded() {
        let mut w = Wave::new(64.0, PPG_DETAIL_S);
        for k in 0..(400 * 64 / 6) {
            w.push((k * 6 + 5) as f64 / 64.0, &[1.0; 6]);
        }
        assert_eq!(w.len(), 19_200);
        assert_eq!(w.samples.capacity(), 19_200);
        assert!(w.oldest().unwrap() > 99.0);
        assert_eq!(w.segments(), 1);
        // 300 s × 64 Hz × 4 B = 76 800 B per channel (+ one 16 B segment).
        assert_eq!(w.bytes(), 76_800 + w.segs.capacity() * 16);
        assert!(w.bytes() < 77_000);
    }

    #[test]
    fn wave_visit_touches_only_the_window() {
        let mut w = Wave::new(64.0, PPG_DETAIL_S);
        for k in 0..(300 * 64 / 6) {
            w.push((k * 6 + 5) as f64 / 64.0, &[1.0; 6]);
        }
        let n = w.visit(100.0, 110.0, |_| {});
        assert!((641..=644).contains(&n), "10 s ± one sample each side: {n}");
    }

    fn info() -> DeviceInfo {
        DeviceInfo {
            id: "t".into(),
            name: "t".into(),
            kind: nf_types::DeviceKind::Muse,
            channels: vec!["TP9".into()],
            sample_rate_hz: 256.0,
            simulated: true,
            ppg_channels: vec!["ambient".into(), "infrared".into(), "red".into()],
            ppg_rate_hz: Some(64.0),
            accel_rate_hz: None,
            aux_channels: Vec::new(),
            rssi: None,
        }
    }

    /// 72 bpm synthetic optics from `t0` for `secs` (6-sample packets).
    fn feed(o: &mut Optics, t0: f64, secs: f64) {
        let n = (secs * 64.0 / 6.0) as u64;
        for k in 0..n {
            let first = t0 + (k * 6) as f64 / 64.0;
            for ch in 0..3u16 {
                let s: Vec<f32> = (0..6)
                    .map(|i| {
                        let t = first + f64::from(i) / 64.0;
                        let pulse = (2.0 * std::f64::consts::PI * 1.2 * t).sin();
                        match ch {
                            0 => 2000.0,
                            1 => (100_000.0 + 3000.0 * pulse) as f32,
                            _ => (80_000.0 + 1500.0 * pulse) as f32,
                        }
                    })
                    .collect();
                o.push(&PpgPacket { time: first + 5.0 / 64.0, channel: ch, samples: s });
            }
        }
    }

    #[test]
    fn gaps_have_no_estimates_no_carry_and_no_burst() {
        let mut o = Optics::new(&info()).unwrap();
        feed(&mut o, 0.0, 20.0);
        feed(&mut o, 30.0, 20.0);
        let hr: Vec<f64> = o.hr.iter().map(|e| e.time).collect();
        assert!(hr.len() > 25, "{}", hr.len());
        assert!(hr.iter().all(|&t| !(20.1..30.0 + nf_dsp::PULSE_MIN_S).contains(&t)), "nothing in or right after the gap: {hr:?}");
        assert!(hr.windows(2).all(|w| w[1] - w[0] >= 0.9), "≤ 1 estimate per second (packet-quantised): {hr:?}");
        assert!(o.hr.iter().all(|e| (e.value - 72.0).abs() < 3.0 && e.reliable(Series::Hr)), "{:?}", o.hr.front());
        assert!(o.at(Series::Hr, 25.0).is_none(), "no value carried into the gap");
        assert!(o.at(Series::Hr, 15.0).is_some());
        assert_eq!(o.waves[1].segments(), 2);
        // Reading never counts again.
        let m = o.mean(Series::Hr);
        for _ in 0..100 {
            let _ = o.current_of(Series::Hr);
        }
        assert_eq!(o.mean(Series::Hr), m);
        assert_eq!(m.count as usize, o.hr.iter().filter(|e| e.reliable(Series::Hr)).count());
        // SpO2 (uncalibrated): estimated, ratio R = (1500/80000)/(3000/100000).
        let sp = o.current_of(Series::Spo2).unwrap();
        assert!((sp.value - (SPO2_A - SPO2_B * 0.625)).abs() < 1.0, "{sp:?}");
    }

    use nf_dsp::{SPO2_A, SPO2_B};

    #[test]
    fn hour_mean_follows_eviction_and_skips_unreliable() {
        let mut o = Optics::new(&info()).unwrap();
        for i in 0..5000 {
            let conf = if i % 10 == 0 { 0.1 } else { 0.9 };
            o.add(Series::Hr, Estimate { time: f64::from(i), value: f64::from(i % 100), confidence: conf });
        }
        let kept: Vec<f64> = o.hr.iter().filter(|e| e.reliable(Series::Hr)).map(|e| e.value).collect();
        let m = o.mean(Series::Hr);
        assert_eq!(o.hr.len(), HISTORY_LEN);
        assert_eq!(m.count as usize, kept.len());
        assert!((m.value().unwrap() - kept.iter().sum::<f64>() / kept.len() as f64).abs() < 1e-6);
    }

    #[test]
    fn recording_means_start_empty_and_end_with_the_recording() {
        let mut o = Optics::new(&info()).unwrap();
        let e = |t: f64, v: f64| Estimate { time: t, value: v, confidence: 0.9 };
        for t in 0..100 {
            o.add(Series::Hr, e(f64::from(t), 60.0));
        }
        o.begin_run(100.0);
        assert_eq!(o.mean(Series::Hr).count, 0, "no prior data leaks into the recording");
        assert_eq!(o.mean(Series::Spo2).value(), None);
        for t in 100..110 {
            o.add(Series::Hr, e(f64::from(t), 90.0));
        }
        assert_eq!(o.mean(Series::Hr), Mean { sum: 900.0, count: 10 });
        o.begin_run(110.0);
        assert_eq!(o.mean(Series::Hr).count, 0, "restart resets");
        o.end_run();
        assert_eq!(o.mean(Series::Hr).count, 110, "back to the retained hour");
    }

    #[test]
    fn readout_tolerance_is_one_second() {
        let mut o = Optics::new(&info()).unwrap();
        o.add(Series::Hr, Estimate { time: 10.0, value: 70.0, confidence: 0.9 });
        o.add(Series::Hr, Estimate { time: 11.0, value: 80.0, confidence: 0.9 });
        o.add(Series::Hr, Estimate { time: 12.0, value: 99.0, confidence: 0.1 });
        assert_eq!(o.at(Series::Hr, 10.4).map(|e| e.value), Some(70.0));
        assert_eq!(o.at(Series::Hr, 10.6).map(|e| e.value), Some(80.0));
        assert_eq!(o.at(Series::Hr, 11.9).map(|e| e.value), Some(80.0), "unreliable 12 s is skipped");
        assert_eq!(o.at(Series::Hr, 12.5), None);
        assert_eq!(o.at(Series::Hr, 8.9), None);
    }

    #[test]
    fn muse_raw_detail_memory() {
        let mut o = Optics::new(&info()).unwrap();
        feed(&mut o, 0.0, 320.0);
        // 3 channels × 300 s × 64 Hz × 4 B = 230 400 B (+ a few segments).
        assert!(o.wave_bytes() >= 230_400 && o.wave_bytes() < 230_600, "{}", o.wave_bytes());
        let (a, b) = o.wave_span().unwrap();
        assert!((b - a - 300.0).abs() < 0.05, "{a} {b}");
    }
}
