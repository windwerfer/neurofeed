//! CBraMod (Spur A): 2 s @ 256 Hz, 4 Muse-order rows → linear resample to
//! 200 Hz → 200-sample patches → frozen encoder → mean-pool (200-d).

mod encoder;

use anyhow::ensure;
use encoder::CbramodEncoder;
use std::path::Path;

pub const WINDOW_SAMPLES: usize = 512;
const SOURCE_HZ: f32 = 256.0;
const NATIVE_HZ: f32 = 200.0;
const PATCH: usize = 200;

/// A loaded encoder.
pub struct Cbramod(CbramodEncoder);

impl Cbramod {
    /// Load `pretrained_weights.pth` (or `.safetensors`).
    pub fn load(weights: &Path) -> anyhow::Result<Self> {
        CbramodEncoder::load(weights).map(Self)
    }

    /// Pooled embedding of one `[4 × n_times]` window.
    pub fn embed(&self, signal: &[f32], n_times: usize) -> anyhow::Result<Vec<f32>> {
        ensure!(n_times == WINDOW_SAMPLES, "CBraMod scores {WINDOW_SAMPLES}-sample windows, got {n_times}");
        ensure!(signal.len() == 4 * n_times, "CBraMod expects 4 rows × {n_times}");
        let patches = to_patches(signal, 4, n_times);
        let n_patches = patches.len() / (4 * PATCH);
        self.0.encode_mean_pool(&patches, 4, n_patches)
    }
}

/// Linear-resample each row 256 → 200 Hz, zero-pad to one patch, cut to whole
/// patches. Output `[C × n_patches × 200]`.
pub fn to_patches(signal: &[f32], n_channels: usize, n_times: usize) -> Vec<f32> {
    let t_new = ((n_times as f32 / SOURCE_HZ) * NATIVE_HZ).round().max(1.0) as usize;
    let t_pad = t_new.max(PATCH);
    let keep = (t_pad / PATCH) * PATCH;
    let mut out = Vec::with_capacity(n_channels * keep);
    for row in signal.chunks_exact(n_times).take(n_channels) {
        let mut r: Vec<f32> = (0..t_new)
            .map(|i| {
                let src = i as f32 * (n_times - 1) as f32 / (t_new - 1).max(1) as f32;
                let i0 = src.floor() as usize;
                let i1 = (i0 + 1).min(n_times - 1);
                let f = src - i0 as f32;
                row[i0] * (1.0 - f) + row[i1] * f
            })
            .collect();
        r.resize(t_pad, 0.0);
        out.extend_from_slice(&r[..keep]);
    }
    out
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn two_seconds_make_two_patches_per_row() {
        let p = to_patches(&vec![0.1; 4 * WINDOW_SAMPLES], 4, WINDOW_SAMPLES);
        assert_eq!(p.len(), 4 * 2 * PATCH);
        assert!(p.iter().all(|v| (v - 0.1).abs() < 1e-6));
    }

    #[test]
    fn resample_keeps_endpoints() {
        let row: Vec<f32> = (0..WINDOW_SAMPLES).map(|i| i as f32).collect();
        let sig = [row.clone(), row.clone(), row.clone(), row].concat();
        let p = to_patches(&sig, 4, WINDOW_SAMPLES);
        assert_eq!(p[0], 0.0);
        assert!((p[399] - 511.0).abs() < 1e-3);
    }
}
