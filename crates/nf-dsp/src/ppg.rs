//! Heart rate and SpO2 from PPG, ported from `compute_pulse`,
//! `compute_spo2` and `pulse_ac` in `rust/src/api/muse.rs`. The legacy code
//! hard-coded 64 Hz; here the rate is a parameter and windows are seconds.

/// Seconds of infrared needed before a pulse estimate.
pub const PULSE_MIN_S: f64 = 2.0;
/// Seconds of IR + red needed before an SpO2 estimate.
pub const SPO2_MIN_S: f64 = 4.0;
/// Analysis window (most recent seconds).
pub const PPG_WINDOW_S: f64 = 8.0;
/// Ratio-of-ratios calibration `SpO2 = A - B·R` (legacy best guess, not
/// Muse-calibrated).
pub const SPO2_A: f64 = 110.0;
pub const SPO2_B: f64 = 25.0;

/// One-pole 0.5 Hz high-pass, dropping the first 0.5 s of settle.
pub fn pulse_ac(samples: &[f64], rate: f64) -> Vec<f64> {
    let dt = 1.0 / rate;
    let rc = 1.0 / (2.0 * std::f64::consts::PI * 0.5);
    let a = rc / (rc + dt);
    let mut hp = vec![0.0; samples.len()];
    for i in 1..samples.len() {
        hp[i] = a * (hp[i - 1] + samples[i] - samples[i - 1]);
    }
    let settle = ((0.5 * rate) as usize).min(hp.len());
    hp.split_off(settle)
}

fn tail(x: &[f64], n: usize) -> &[f64] {
    &x[x.len().saturating_sub(n)..]
}

/// `(bpm, confidence 0..1)` from the infrared channel: local maxima above
/// the median |AC|, inter-beat intervals 0.3–1.5 s, confidence = 1 - CV.
pub fn heart_rate(ir: &[f64], rate: f64) -> Option<(f64, f64)> {
    if ir.len() < (PULSE_MIN_S * rate) as usize {
        return None;
    }
    let ac = pulse_ac(tail(ir, (PPG_WINDOW_S * rate) as usize), rate);
    if ac.len() < rate as usize {
        return None;
    }
    let mut mags: Vec<f64> = ac.iter().map(|s| s.abs()).collect();
    let mid = mags.len() / 2;
    mags.select_nth_unstable_by(mid, f64::total_cmp);
    let threshold = mags[mid];
    if threshold < 1.0 {
        return None;
    }
    let peaks: Vec<usize> = (1..ac.len() - 1).filter(|&i| ac[i] > threshold && ac[i] > ac[i - 1] && ac[i] > ac[i + 1]).collect();
    let ibis: Vec<f64> = peaks.windows(2).map(|p| (p[1] - p[0]) as f64 / rate).filter(|i| (0.3..1.5).contains(i)).collect();
    if ibis.len() < 2 {
        return None;
    }
    let avg = ibis.iter().sum::<f64>() / ibis.len() as f64;
    let var = ibis.iter().map(|i| (i - avg).powi(2)).sum::<f64>() / ibis.len() as f64;
    Some((60.0 / avg, (1.0 - var.sqrt() / avg).max(0.0)))
}

/// `(percent, confidence 0..1)` by ratio of ratios on IR + red. `None` for
/// flat or dark light, too little data, or a result outside 50–100 %.
pub fn spo2(ir: &[f64], red: &[f64], rate: f64) -> Option<(f64, f64)> {
    let min = (SPO2_MIN_S * rate) as usize;
    if ir.len() < min || red.len() < min {
        return None;
    }
    let n = ir.len().min(red.len()).min((PPG_WINDOW_S * rate) as usize);
    let (ir, red) = (tail(ir, n), tail(red, n));
    let dc = |x: &[f64]| x.iter().sum::<f64>() / x.len() as f64;
    let rms = |x: &[f64]| (x.iter().map(|s| s * s).sum::<f64>() / x.len().max(1) as f64).sqrt();
    let (ir_dc, red_dc) = (dc(ir), dc(red));
    let (ir_ac, red_ac) = (rms(&pulse_ac(ir, rate)), rms(&pulse_ac(red, rate)));
    if ir_dc < 100.0 || red_dc < 100.0 || ir_ac < 1.0 || red_ac < 1.0 {
        return None;
    }
    let r = (red_ac / red_dc) / (ir_ac / ir_dc);
    let v = SPO2_A - SPO2_B * r;
    if !r.is_finite() || !(50.0..=100.0).contains(&v) {
        return None;
    }
    let q = |ac: f64, dc: f64| (ac / dc * 20.0).min(1.0);
    Some((v, (q(ir_ac, ir_dc) * q(red_ac, red_dc)).sqrt().clamp(0.0, 1.0)))
}
