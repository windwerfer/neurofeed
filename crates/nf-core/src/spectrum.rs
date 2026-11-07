//! Averaged power spectrum of a time window of the conditioned EEG
//! (PSD monitor, `psd.average`; later the Histogram's sibling).
//!
//! Welch: 1 s Hamming segments (`signal::WINDOW_S`, the band/PSD window),
//! 50 % hop, over `[start, end]` of each selected channel. Segments that
//! touch a gap or bad sample are skipped (never zero-filled). The **linear**
//! densities (µV²/Hz) of every valid (channel, segment) are averaged first;
//! dB (`10·log10`, re 1 µV²/Hz) is taken of the mean, never a mean of dB.

use crate::signal::{Signal, FLAG_OK, WINDOW_S};

#[derive(Debug, Clone, PartialEq)]
pub struct Averaged {
    /// Bin spacing (Hz); bin `k` is at `k·df`.
    pub df: f64,
    /// Mean linear density per bin (µV²/Hz).
    pub power: Vec<f64>,
    /// Valid (channel, segment) pairs averaged.
    pub segments: usize,
    /// Channels that contributed at least one segment.
    pub channels: Vec<usize>,
    /// Window actually covered (session seconds).
    pub start: f64,
    pub end: f64,
}

impl Averaged {
    /// dB re 1 µV²/Hz of the averaged linear density.
    pub fn db(&self) -> Vec<f32> {
        self.power.iter().map(|&v| (10.0 * v.max(1e-12).log10()) as f32).collect()
    }

    /// Frequency of the largest bin in `[lo, hi)` Hz.
    pub fn peak(&self, lo: f64, hi: f64) -> Option<f64> {
        nf_dsp::peak_frequency(&nf_dsp::Psd { df: self.df, power: self.power.clone() }, lo, hi)
    }

    /// Density at `hz` (nearest bin).
    pub fn at(&self, hz: f64) -> Option<f64> {
        let k = (hz / self.df).round();
        (k >= 0.0).then(|| self.power.get(k as usize).copied()).flatten()
    }
}

/// Averaged spectrum of `channels` over `[start, end]` session seconds;
/// `None` without one full valid segment.
pub fn average(sig: &Signal, channels: &[usize], start: f64, end: f64) -> Option<Averaged> {
    let rate = sig.rate;
    let seg = (WINDOW_S * rate).round() as usize;
    let hop = (seg / 2).max(1);
    if end.partial_cmp(&start) != Some(std::cmp::Ordering::Greater) || seg < 16 {
        return None;
    }
    let mut acc: Vec<f64> = Vec::new();
    let mut df = 0.0;
    let mut segments = 0;
    let mut used = Vec::new();
    for &ch in channels {
        let Some(t_last) = sig.channel_time(ch) else { continue };
        let skip = ((t_last - end) * rate).round().max(0.0) as usize;
        let n = ((end.min(t_last) - start) * rate).round().max(0.0) as usize;
        let (x, f) = sig.slice(ch, skip, n, true);
        let mut any = false;
        let mut i = 0;
        while i + seg <= x.len().min(f.len()) {
            if f[i..i + seg].iter().all(|&g| g == FLAG_OK) {
                if let Some(p) = nf_dsp::psd(&x[i..i + seg], rate) {
                    if acc.is_empty() {
                        acc = vec![0.0; p.power.len()];
                        df = p.df;
                    }
                    acc.iter_mut().zip(&p.power).for_each(|(a, v)| *a += v);
                    segments += 1;
                    any = true;
                }
            }
            i += hop;
        }
        if any {
            used.push(ch);
        }
    }
    (segments > 0).then(|| Averaged { df, power: acc.iter().map(|a| a / segments as f64).collect(), segments, channels: used, start, end })
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use nf_types::EegPacket;

    fn sig_with(amps: &[f32], seconds: f64) -> Signal {
        let mut info = nf_sim::sim_info(nf_types::DeviceKind::Muse);
        info.channels.truncate(amps.len());
        let mut s = Signal::new(&info, crate::MainsMode::Off);
        let rate = 256.0;
        let total = (seconds * rate) as usize;
        let mut i = 0;
        while i < total {
            for (ch, a) in amps.iter().enumerate() {
                let samples: Vec<f32> = (i..i + 16).map(|k| a * (2.0 * std::f32::consts::PI * 10.0 * k as f32 / 256.0).sin()).collect();
                s.push(&EegPacket { electrode: u16::try_from(ch).unwrap(), time: (i + 16) as f64 / rate, samples });
            }
            i += 16;
        }
        s
    }

    #[test]
    fn linear_mean_then_db_not_mean_of_db() {
        let s = sig_with(&[10.0, 40.0], 12.0);
        let t = s.time.unwrap();
        let a = average(&s, &[0], t - 4.0, t).unwrap();
        let b = average(&s, &[1], t - 4.0, t).unwrap();
        let both = average(&s, &[0, 1], t - 4.0, t).unwrap();
        let k = (10.0 / both.df).round() as usize;
        let lin = (a.power[k] + b.power[k]) / 2.0;
        assert!((both.power[k] - lin).abs() / lin < 1e-9, "linear mean");
        let mean_db = (10.0 * a.power[k].log10() + 10.0 * b.power[k].log10()) / 2.0;
        assert!((f64::from(both.db()[k]) - 10.0 * lin.log10()).abs() < 1e-3);
        assert!((f64::from(both.db()[k]) - mean_db).abs() > 1.0, "differs from a dB mean");
        assert_eq!(both.peak(8.0, 13.0), Some(10.0));
        // 4 s, 1 s segments, 50 % hop: 7 per channel.
        assert_eq!(both.segments, 14);
    }

    #[test]
    fn uses_the_requested_window_not_the_newest() {
        let s = sig_with(&[20.0], 30.0);
        let t = s.time.unwrap();
        let old = average(&s, &[0], t - 20.0, t - 18.0).unwrap();
        assert_eq!((old.start, old.end), (t - 20.0, t - 18.0));
        assert_eq!(old.segments, 3);
        assert!(average(&s, &[0], t + 1.0, t + 3.0).is_none(), "future: no data, no zeros");
        assert!(average(&s, &[], t - 4.0, t).is_none(), "no channel, no spectrum");
    }
}
