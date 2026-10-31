//! Live signal path: raw packets → mains detection + per-channel
//! conditioning (nf-dsp) → rolling buffers → band snapshots every
//! `BAND_INTERVAL_S`, pad quality, and spectrogram columns every `SPEC_HOP_S`.

use nf_dsp::{
    band_powers_linear, line_noise_fraction, pad_quality, psd, psd_db, sample_std, EegFilter, Mains, MainsDetector, USABLE_QUALITY,
};
use nf_types::{BandSnapshot, DeviceInfo, EegPacket};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

/// Seconds of raw and filtered signal kept per channel.
pub const BUFFER_S: f64 = 10.0;
/// FFT window for bands / PSD / quality (1 s at 256 Hz).
pub const WINDOW_S: f64 = 1.0;
/// Band snapshot cadence (matches the legacy 10 Hz band stream).
pub const BAND_INTERVAL_S: f64 = 0.1;
/// Spectrogram hop (legacy STFT hop 64 samples at 256 Hz).
pub const SPEC_HOP_S: f64 = 0.25;
/// Spectrogram columns kept per channel (30 s).
pub const SPEC_COLUMNS: usize = 120;

/// User notch choice. `Auto` follows the detector.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum MainsMode {
    #[default]
    Auto,
    #[serde(rename = "50")]
    Hz50,
    #[serde(rename = "60")]
    Hz60,
    Off,
}

/// Mains as a stable string for status / UI.
pub fn mains_name(m: Mains) -> &'static str {
    match m {
        Mains::Unknown => "unknown",
        Mains::Hz50 => "50",
        Mains::Hz60 => "60",
        Mains::None => "none",
    }
}

pub const FLAG_OK: u8 = 0;
/// No data arrived for this sample time.
pub const FLAG_GAP: u8 = 1;
/// The device sent NaN / inf / beyond-ADC values (shown zeroed).
pub const FLAG_BAD: u8 = 2;
/// Fewer missing samples than this are jitter, not a gap.
const GAP_MIN_SAMPLES: f64 = 3.0;

#[derive(Debug, Clone)]
pub struct Signal {
    pub rate: f64,
    cap: usize,
    filters: Vec<EegFilter>,
    pub raw: Vec<VecDeque<f32>>,
    pub filtered: Vec<VecDeque<f32>>,
    /// Per sample, aligned with `raw`: [`FLAG_OK`], [`FLAG_GAP`] or [`FLAG_BAD`].
    pub flags: Vec<VecDeque<u8>>,
    /// Per channel, time of its newest sample (gap detection).
    last_t: Vec<Option<f64>>,
    /// Time of the newest sample.
    pub time: Option<f64>,
    next_band: Option<f64>,
    next_spec: Option<f64>,
    detector: MainsDetector,
    mode: MainsMode,
    /// Notch frozen by a running recording.
    lock: Option<Mains>,
    applied: Mains,
    /// Per channel, 0..=100 (legacy pad quality of the last 1 s).
    pub quality: Vec<f32>,
    /// Per channel, fraction of power in the mains bins (unfiltered).
    pub line_noise: Vec<f32>,
    /// Per channel, linear band powers (µV²) of the last snapshot.
    pub bands_linear: Vec<[f64; 5]>,
    /// Per channel, columns of PSD dB (0..=`MAX_PSD_HZ`, df = 1/WINDOW_S).
    pub spectrogram: Vec<VecDeque<Vec<f32>>>,
}

impl Signal {
    pub fn new(info: &DeviceInfo, mode: MainsMode) -> Self {
        let n = info.channels.len();
        let rate = info.sample_rate_hz;
        let cap = (BUFFER_S * rate).ceil() as usize;
        let mut s = Self {
            rate,
            cap,
            filters: Vec::new(),
            raw: vec![VecDeque::with_capacity(cap); n],
            filtered: vec![VecDeque::with_capacity(cap); n],
            flags: vec![VecDeque::with_capacity(cap); n],
            last_t: vec![None; n],
            time: None,
            next_band: None,
            next_spec: None,
            detector: MainsDetector::new(rate, n),
            mode,
            lock: None,
            applied: Mains::Unknown,
            quality: vec![0.0; n],
            line_noise: vec![0.0; n],
            bands_linear: vec![[0.0; 5]; n],
            spectrogram: vec![VecDeque::new(); n],
        };
        s.applied = s.wanted();
        s.filters = vec![EegFilter::new(rate, s.applied); n];
        s
    }

    pub fn detected(&self) -> Mains {
        self.detector.mains()
    }
    pub fn applied(&self) -> Mains {
        self.applied
    }
    pub fn locked(&self) -> bool {
        self.lock.is_some()
    }
    pub fn mode(&self) -> MainsMode {
        self.mode
    }
    pub fn usable(&self, ch: usize) -> bool {
        self.quality.get(ch).is_some_and(|&q| f64::from(q) >= USABLE_QUALITY)
    }

    fn wanted(&self) -> Mains {
        self.lock.unwrap_or(match self.mode {
            MainsMode::Auto => self.detector.mains(),
            MainsMode::Hz50 => Mains::Hz50,
            MainsMode::Hz60 => Mains::Hz60,
            MainsMode::Off => Mains::None,
        })
    }

    /// Rebuild the filters when the wanted notch changed. Returns true if so.
    fn reapply(&mut self) -> bool {
        let want = self.wanted();
        if want == self.applied {
            return false;
        }
        self.applied = want;
        // Warm the new filters on the last 2 s of raw input (no restart transient).
        let warm = (2.0 * self.rate) as usize;
        self.filters = self
            .raw
            .iter()
            .map(|r| {
                let mut f = EegFilter::new(self.rate, want);
                r.iter().skip(r.len().saturating_sub(warm)).for_each(|&x| {
                    f.process(f64::from(x));
                });
                f
            })
            .collect();
        true
    }

    pub fn set_mode(&mut self, mode: MainsMode) -> bool {
        self.mode = mode;
        self.reapply()
    }

    /// Freeze (Some) or release (None) the notch for a recording.
    pub fn lock(&mut self, on: bool) -> bool {
        self.lock = on.then_some(self.applied);
        self.reapply()
    }

    pub fn window_len(&self) -> usize {
        (WINDOW_S * self.rate).round() as usize
    }

    /// Ingest one packet; returns a band snapshot when one is due.
    pub fn push(&mut self, p: &EegPacket) -> Option<BandSnapshot> {
        self.push_flagged(p, false)
    }

    /// Fill a time gap (dropped packets, disconnect) with flagged zeros so
    /// plots show the hole instead of splicing the two sides together.
    fn fill_gap(&mut self, ch: usize, first_sample: f64) {
        let Some(t) = self.last_t[ch] else { return };
        let missing = ((first_sample - t) * self.rate).round() - 1.0;
        if missing < GAP_MIN_SAMPLES {
            return;
        }
        let n = (missing as usize).min(self.cap);
        for _ in 0..n {
            push_capped(&mut self.raw[ch], 0.0, self.cap);
            push_capped(&mut self.filtered[ch], 0.0, self.cap);
            push_capped(&mut self.flags[ch], FLAG_GAP, self.cap);
        }
    }

    /// While no data arrives (disconnect): extend every channel's gap up to
    /// `now` so plots keep scrolling and show the dropout as it happens.
    pub fn pad_to(&mut self, now: f64) {
        for ch in 0..self.raw.len() {
            let Some(t) = self.last_t[ch] else { continue };
            let n = ((now - t) * self.rate).floor();
            if n >= GAP_MIN_SAMPLES {
                self.quality[ch] = 0.0;
                self.fill_gap(ch, t + (n + 1.0) / self.rate);
                self.last_t[ch] = Some(t + n / self.rate);
            }
        }
    }

    /// [`Self::push`], marking the packet's samples bad (they were NaN / inf
    /// / beyond the ADC and got zeroed) when `bad`.
    pub fn push_flagged(&mut self, p: &EegPacket, bad: bool) -> Option<BandSnapshot> {
        let ch = usize::from(p.electrode);
        if ch >= self.filters.len() {
            return None;
        }
        self.fill_gap(ch, p.time - (p.samples.len() as f64 - 1.0) / self.rate);
        self.last_t[ch] = Some(p.time);
        let flag = if bad { FLAG_BAD } else { FLAG_OK };
        for _ in &p.samples {
            push_capped(&mut self.flags[ch], flag, self.cap);
        }
        if self.detector.feed(ch, &p.samples).is_some() {
            self.reapply();
        }
        let (f, raw, out) = (&mut self.filters[ch], &mut self.raw[ch], &mut self.filtered[ch]);
        for &x in &p.samples {
            push_capped(raw, x, self.cap);
            push_capped(out, f.process(f64::from(x)) as f32, self.cap);
        }
        // Derived data on the last channel of a packet group so all channels are current.
        if ch + 1 != self.filters.len() {
            return None;
        }
        self.time = Some(p.time);
        if due(&mut self.next_spec, p.time, SPEC_HOP_S) {
            self.spectrogram_column();
        }
        if !due(&mut self.next_band, p.time, BAND_INTERVAL_S) {
            return None;
        }
        let w = self.window_len();
        // A window spanning a dropout has no meaningful band powers: no
        // snapshot (plots break the line) and those pads score 0.
        let gapped: Vec<bool> = self.flags.iter().map(|f| f.iter().rev().take(w).any(|x| *x == FLAG_GAP)).collect();
        if gapped.iter().any(|g| *g) {
            for (q, g) in self.quality.iter_mut().zip(&gapped) {
                if *g {
                    *q = 0.0;
                }
            }
            return None;
        }
        let mut powers = Vec::with_capacity(self.filters.len());
        for i in 0..self.filters.len() {
            let fp = psd(&tail(&self.filtered[i], w)?, self.rate)?;
            let raw = tail(&self.raw[i], w)?;
            let noise = psd(&raw, self.rate).map_or(-1.0, |rp| line_noise_fraction(&rp));
            let std = sample_std(&tail(&self.filtered[i], w)?);
            self.quality[i] = std.map_or(0.0, |s| pad_quality(s, noise)) as f32;
            self.line_noise[i] = noise as f32;
            let lin = band_powers_linear(&fp);
            self.bands_linear[i] = lin;
            powers.push(lin.map(|v| v.max(1e-6).log10() as f32));
        }
        Some(BandSnapshot { time: p.time, powers })
    }

    fn spectrogram_column(&mut self) {
        let w = self.window_len();
        for i in 0..self.filtered.len() {
            let Some(col) = tail(&self.filtered[i], w).and_then(|t| psd(&t, self.rate)).map(|p| psd_db(&p)) else { continue };
            let s = &mut self.spectrogram[i];
            if s.len() >= SPEC_COLUMNS {
                s.pop_front();
            }
            s.push_back(col);
        }
    }

    /// Flags of the last `n` samples of channel `ch`.
    pub fn last_flags(&self, ch: usize, n: usize) -> Vec<u8> {
        self.flags.get(ch).map(|b| b.iter().skip(b.len().saturating_sub(n)).copied().collect()).unwrap_or_default()
    }

    /// Last `n` samples of channel `ch` (fewer if not buffered yet).
    pub fn last(&self, ch: usize, n: usize, filtered: bool) -> Vec<f32> {
        let buf = if filtered { &self.filtered } else { &self.raw };
        buf.get(ch).map(|b| b.iter().skip(b.len().saturating_sub(n)).copied().collect()).unwrap_or_default()
    }
}

/// True when `next` is reached; then schedules the following tick on the grid.
fn due(next: &mut Option<f64>, t: f64, step: f64) -> bool {
    let d = *next.get_or_insert(t);
    if t + 1e-9 < d {
        return false;
    }
    *next = Some(d + step * ((t - d) / step).floor().max(0.0) + step);
    true
}

fn push_capped<T>(b: &mut VecDeque<T>, x: T, cap: usize) {
    if b.len() >= cap {
        b.pop_front();
    }
    b.push_back(x);
}

fn tail(b: &VecDeque<f32>, n: usize) -> Option<Vec<f32>> {
    (b.len() >= n).then(|| b.iter().skip(b.len() - n).copied().collect())
}

/// Crown `signalQuality` that counts as adequate (legacy crown_quality.rs).
pub const CROWN_QUALITY_ADEQUATE: f64 = 0.75;

/// Map a Crown quality 0..=1 onto the app's 0..=100 pad score so "adequate"
/// lands exactly on [`USABLE_QUALITY`].
pub fn crown_quality_to_score(q: f64) -> f64 {
    let q = q.clamp(0.0, 1.0);
    if q <= CROWN_QUALITY_ADEQUATE {
        q / CROWN_QUALITY_ADEQUATE * USABLE_QUALITY
    } else {
        USABLE_QUALITY + (q - CROWN_QUALITY_ADEQUATE) / (1.0 - CROWN_QUALITY_ADEQUATE) * (100.0 - USABLE_QUALITY)
    }
}
