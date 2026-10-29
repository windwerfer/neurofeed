use crate::fft::fft_in_place;
use std::f64::consts::PI;

/// Band edges in Hz, same order as `nf_types::Band::ALL`
/// (δ θ α β γ; half-open `[lo, hi)`).
pub const BANDS_HZ: [(f64, f64); 5] = [(1.0, 4.0), (4.0, 8.0), (8.0, 13.0), (13.0, 30.0), (30.0, 44.0)];

/// Highest frequency `psd` reports.
pub const MAX_PSD_HZ: f64 = 64.0;

/// One-sided power spectral density of a single window.
#[derive(Debug, Clone, PartialEq)]
pub struct Psd {
    /// Bin spacing in Hz.
    pub df: f64,
    /// Power density per bin (µV²/Hz), bin `k` is at `k * df` Hz.
    pub power: Vec<f64>,
}

impl Psd {
    pub fn freq(&self, bin: usize) -> f64 {
        bin as f64 * self.df
    }

    /// Mean density over `[lo, hi)`; `None` when no bin falls inside.
    pub fn mean_in(&self, lo: f64, hi: f64) -> Option<f64> {
        let (sum, n) = self
            .power
            .iter()
            .enumerate()
            .filter(|(k, _)| {
                let f = self.freq(*k);
                f >= lo && f < hi
            })
            .fold((0.0, 0usize), |(s, n), (_, p)| (s + p, n + 1));
        (n > 0).then(|| sum / n as f64)
    }
}

/// Hann-windowed, mean-removed periodogram of the largest power-of-two
/// prefix of the **last** samples (at least 16). Bins up to `MAX_PSD_HZ`.
pub fn psd(samples: &[f32], rate_hz: f64) -> Option<Psd> {
    if rate_hz <= 0.0 || samples.len() < 16 {
        return None;
    }
    let n = 1usize << (usize::BITS - 1 - samples.len().leading_zeros());
    let tail = &samples[samples.len() - n..];
    let mean = tail.iter().map(|&x| f64::from(x)).sum::<f64>() / n as f64;
    let mut re = Vec::with_capacity(n);
    let mut wsum = 0.0;
    for (i, &x) in tail.iter().enumerate() {
        let w = 0.5 - 0.5 * (2.0 * PI * i as f64 / n as f64).cos();
        wsum += w * w;
        re.push((f64::from(x) - mean) * w);
    }
    let mut im = vec![0.0; n];
    if !fft_in_place(&mut re, &mut im) {
        return None;
    }
    let df = rate_hz / n as f64;
    let last = ((MAX_PSD_HZ / df) as usize).min(n / 2);
    let scale = 1.0 / (rate_hz * wsum);
    let power = (0..=last)
        .map(|k| {
            let p = (re[k] * re[k] + im[k] * im[k]) * scale;
            if k == 0 || k == n / 2 {
                p
            } else {
                2.0 * p
            }
        })
        .collect();
    Some(Psd { df, power })
}

/// log10 of the mean PSD in each band (δ θ α β γ), floored at 1e-6 µV²/Hz.
/// This is the scale the Bands view plots ("absolute").
pub fn band_powers(samples: &[f32], rate_hz: f64) -> Option<[f32; 5]> {
    let p = psd(samples, rate_hz)?;
    let mut out = [0.0_f32; 5];
    for (o, (lo, hi)) in out.iter_mut().zip(BANDS_HZ) {
        *o = p.mean_in(lo, hi).unwrap_or(0.0).max(1e-6).log10() as f32;
    }
    Some(out)
}

/// Index of the band with the largest **total** power (density × width).
pub fn dominant_band(samples: &[f32], rate_hz: f64) -> Option<usize> {
    let p = psd(samples, rate_hz)?;
    BANDS_HZ
        .iter()
        .enumerate()
        .map(|(i, (lo, hi))| (i, p.mean_in(*lo, *hi).unwrap_or(0.0) * (hi - lo)))
        .max_by(|a, b| a.1.total_cmp(&b.1))
        .map(|(i, _)| i)
}

/// Frequency of the strongest bin in `[lo, hi)`.
pub fn peak_frequency(p: &Psd, lo: f64, hi: f64) -> Option<f64> {
    p.power.iter().enumerate().filter(|(k, _)| (lo..hi).contains(&p.freq(*k))).max_by(|a, b| a.1.total_cmp(b.1)).map(|(k, _)| p.freq(k))
}

/// Mains bins (±1 bin at `mains_hz`) relative to the median of the
/// neighbouring non-mains bins (±8 Hz), as in the legacy line-noise ratio.
pub fn line_noise_ratio(p: &Psd, mains_hz: f64) -> Option<f64> {
    let c = (mains_hz / p.df).round() as i64;
    let at = |k: i64| usize::try_from(k).ok().and_then(|k| p.power.get(k).copied());
    let peak: Vec<f64> = (c - 1..=c + 1).filter_map(at).collect();
    let span = (8.0 / p.df).round() as i64;
    let mut side: Vec<f64> = (c - span..=c + span).filter(|k| (k - c).abs() > 1).filter_map(at).collect();
    if peak.is_empty() || side.is_empty() {
        return None;
    }
    side.sort_by(f64::total_cmp);
    let median = side[side.len() / 2];
    (median > 0.0).then(|| peak.iter().sum::<f64>() / peak.len() as f64 / median)
}
