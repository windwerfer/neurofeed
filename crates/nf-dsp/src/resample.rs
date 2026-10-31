//! Offline band-limited resampling (Hann-windowed sinc) for imports, e.g.
//! Mind Monitor 220 Hz or EDF 500 Hz EEG → 256 Hz. Legacy used rubato; this
//! is the same idea without the dependency.

/// Input samples each side of the kernel centre (at the input rate when
/// upsampling, widened by the decimation factor when downsampling).
pub const RESAMPLE_HALF_TAPS: f64 = 16.0;

/// `x` at `from_hz` → `to_hz`. Output length is `round(len · to/from)`.
/// Cutoff is 0.95 × the lower Nyquist so nothing aliases.
pub fn resample(x: &[f32], from_hz: f64, to_hz: f64) -> Vec<f32> {
    if x.is_empty() || from_hz <= 0.0 || to_hz <= 0.0 || (from_hz - to_hz).abs() < 1e-9 {
        return x.to_vec();
    }
    let ratio = from_hz / to_hz;
    let fc = 0.95 * (1.0 / ratio).min(1.0);
    let half = RESAMPLE_HALF_TAPS / fc;
    let n_out = ((x.len() as f64) / ratio).round() as usize;
    (0..n_out).map(|n| sample_at(x, n as f64 * ratio, fc, half)).collect()
}

fn sample_at(x: &[f32], t: f64, fc: f64, half: f64) -> f32 {
    let lo = (t - half).ceil().max(0.0) as usize;
    let hi = ((t + half).floor() as usize).min(x.len() - 1);
    let (mut acc, mut wsum) = (0.0, 0.0);
    for (k, &v) in x.iter().enumerate().take(hi + 1).skip(lo) {
        let d = k as f64 - t;
        let w = fc * sinc(fc * d) * hann(d / half);
        acc += f64::from(v) * w;
        wsum += w;
    }
    // Normalising keeps DC exact at the edges where the kernel is cut.
    if wsum.abs() > 1e-12 {
        (acc / wsum) as f32
    } else {
        0.0
    }
}

fn sinc(x: f64) -> f64 {
    if x.abs() < 1e-12 {
        1.0
    } else {
        (std::f64::consts::PI * x).sin() / (std::f64::consts::PI * x)
    }
}

fn hann(u: f64) -> f64 {
    if u.abs() >= 1.0 {
        0.0
    } else {
        0.5 * (1.0 + (std::f64::consts::PI * u).cos())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sine(hz: f64, rate: f64, n: usize) -> Vec<f32> {
        (0..n).map(|i| (2.0 * std::f64::consts::PI * hz * i as f64 / rate).sin() as f32).collect()
    }

    #[test]
    fn upsample_220_keeps_a_10hz_sine() {
        let y = resample(&sine(10.0, 220.0, 2200), 220.0, 256.0);
        assert_eq!(y.len(), 2560);
        let want = sine(10.0, 256.0, 2560);
        let err = y[100..2460].iter().zip(&want[100..2460]).map(|(a, b)| (a - b).abs()).fold(0.0, f32::max);
        assert!(err < 0.01, "max err {err}");
    }

    #[test]
    fn downsample_removes_content_above_nyquist() {
        let y = resample(&sine(200.0, 512.0, 5120), 512.0, 256.0);
        assert_eq!(y.len(), 2560);
        let rms = (y[200..2360].iter().map(|v| v * v).sum::<f32>() / 2160.0).sqrt();
        assert!(rms < 0.02, "rms {rms}");
    }

    #[test]
    fn same_rate_and_dc() {
        assert_eq!(resample(&[1.0, 2.0], 256.0, 256.0), vec![1.0, 2.0]);
        assert!(resample(&[3.0; 500], 500.0, 256.0).iter().all(|v| (v - 3.0).abs() < 1e-4));
    }
}
