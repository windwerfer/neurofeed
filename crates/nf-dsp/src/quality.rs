//! Pad (contact) quality, ported from `rust/src/api/features.rs`
//! (`pad_quality_from_std_and_noise`, `sample_std`).

/// Minimum samples for a quality score.
pub const MIN_QUALITY_SAMPLES: usize = 10;
/// Score at or above which a pad is usable (Dart `kUsableSignalThreshold`).
pub const USABLE_QUALITY: f64 = 80.0;

/// Population standard deviation; `None` below `MIN_QUALITY_SAMPLES`.
pub fn sample_std(samples: &[f32]) -> Option<f64> {
    let n = samples.len();
    if n < MIN_QUALITY_SAMPLES {
        return None;
    }
    let mean = samples.iter().map(|&x| f64::from(x)).sum::<f64>() / n as f64;
    Some((samples.iter().map(|&x| (f64::from(x) - mean).powi(2)).sum::<f64>() / n as f64).sqrt())
}

/// 0..=100 from the conditioned 1 s std (µV) and the line-noise fraction
/// (`noise < 0` = unknown, no penalty). 1 < std < 15 µV scores >= 80.
pub fn pad_quality(std: f64, noise: f64) -> f64 {
    let mut score = if !(1.0..=100.0).contains(&std) {
        0.0
    } else if std < 15.0 {
        80.0 + (15.0 - std) / 15.0 * 20.0
    } else if std < 40.0 {
        50.0 + (40.0 - std) / 25.0 * 25.0
    } else {
        (40.0 * (100.0 - std) / 60.0).max(0.0)
    };
    if noise >= 0.0 {
        score *= 1.0 - 0.6 * ((noise - 0.2) / 0.3).clamp(0.0, 1.0);
    }
    score
}
