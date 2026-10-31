//! Baseline distribution statistics (legacy-exact formulas).

/// Sorted baseline samples with legacy percentile/threshold rules.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Baseline {
    samples: Vec<f64>,
}

impl Baseline {
    pub fn new(samples: Vec<f64>) -> Self {
        Self { samples }
    }
    pub fn samples(&self) -> &[f64] {
        &self.samples
    }
    pub fn len(&self) -> usize {
        self.samples.len()
    }
    pub fn is_empty(&self) -> bool {
        self.samples.is_empty()
    }
    pub fn mean(&self) -> Option<f64> {
        if self.samples.is_empty() {
            return None;
        }
        Some(self.samples.iter().sum::<f64>() / self.samples.len() as f64)
    }
    /// Population standard deviation; `None` below two samples.
    pub fn sd(&self) -> Option<f64> {
        if self.samples.len() < 2 {
            return None;
        }
        let m = self.mean()?;
        let var = self.samples.iter().map(|s| (s - m).powi(2)).sum::<f64>() / self.samples.len() as f64;
        Some(var.sqrt())
    }
    /// Value at `p` percent: index `round(p/100 · (n−1))` of the sorted pile.
    pub fn at_percentile(&self, p: f64) -> Option<f64> {
        if self.samples.is_empty() {
            return None;
        }
        let mut s = self.samples.clone();
        s.sort_by(f64::total_cmp);
        let last = s.len() - 1;
        let idx = ((p / 100.0) * last as f64).round().clamp(0.0, last as f64) as usize;
        s.get(idx).copied()
    }
    /// Percentile rank: share of samples strictly below `v`, × 100.
    pub fn rank(&self, v: f64) -> Option<f64> {
        if self.samples.is_empty() {
            return None;
        }
        let below = self.samples.iter().filter(|s| **s < v).count();
        Some(below as f64 / self.samples.len() as f64 * 100.0)
    }
}

/// Population CV (sd / |mean|); `None` below two values or near-zero mean.
pub fn coefficient_of_variation(values: &[f64]) -> Option<f64> {
    if values.len() < 2 {
        return None;
    }
    let n = values.len() as f64;
    let mean = values.iter().sum::<f64>() / n;
    if mean.abs() < 1e-12 {
        return None;
    }
    let ss: f64 = values.iter().map(|v| (v - mean) * (v - mean)).sum();
    Some((ss / n).sqrt() / mean.abs())
}

/// CVs of every full window (or of all values when fewer than `window`).
pub fn rolling_cvs(values: &[f64], window: usize) -> Vec<f64> {
    let w = window.max(2);
    if values.len() < 2 {
        return Vec::new();
    }
    if values.len() < w {
        return coefficient_of_variation(values).into_iter().collect();
    }
    values.windows(w).filter_map(coefficient_of_variation).collect()
}

/// Map a stability ratio r to the 0–100 output scale (threshold → 60).
pub fn stability_output_percentile(r: f64, threshold: Option<f64>) -> f64 {
    let thr = threshold.unwrap_or(0.9).clamp(0.0, 1.4);
    if !r.is_finite() {
        return 0.0;
    }
    if r >= thr {
        return (60.0 * (1.5 - r) / (1.5 - thr)).clamp(0.0, 60.0);
    }
    let span = if thr < 0.3 { thr } else { 0.3 };
    if span <= 0.0 {
        return 100.0;
    }
    (60.0 + 40.0 * (thr - r) / span).clamp(60.0, 100.0)
}
