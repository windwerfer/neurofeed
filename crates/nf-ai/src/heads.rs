//! Linear classification heads on pooled embeddings (`logits = W·emb + b`).
//!
//! The four head packs ship inside the binary (they are tiny); each is
//! checked against its pinned SHA-256 when parsed. The guard value of a head
//! is **P(class 1)** (P(hypnagogic) for A-vig, P(light) for wake/light), never
//! the argmax, so percentile thresholds stay meaningful.

use anyhow::{ensure, Context};
use nf_types::AiModel;
use sha2::{Digest, Sha256};

/// Embedding size of CBraMod (mean-pooled `d_model`).
pub const CBRAMOD_DIM: usize = 200;
/// Embedding size of REVE base.
pub const REVE_DIM: usize = 512;
const N_CLASSES: usize = 2;

/// A bundled head pack.
pub struct Pack {
    pub scorer: &'static str,
    pub pack_id: &'static str,
    pub model: AiModel,
    pub in_dim: usize,
    pub sha256: &'static str,
    bytes: &'static [u8],
}

macro_rules! pack_bytes {
    ($p:literal) => {
        include_bytes!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../assets/packs/", $p))
    };
}

/// All shipped heads.
pub const PACKS: [Pack; 4] = [
    Pack {
        scorer: "ai.a_vig",
        pack_id: "cbramod-a-vig-full",
        model: AiModel::CbramodAVig,
        in_dim: CBRAMOD_DIM,
        sha256: "2695ce91cc5e9cbb8d6f29fc4bfff9b6f1294c106cced6fa2657d4bf6c26ba96",
        bytes: pack_bytes!("cbramod-a-vig-full/heads/head_a_vig_linear.f32bin"),
    },
    Pack {
        scorer: "ai.wake_light",
        pack_id: "cbramod-head-c-wake-light",
        model: AiModel::CbramodAVig,
        in_dim: CBRAMOD_DIM,
        sha256: "cc0415bc1d3fac7c5f7113315b609185b9d1dbc30ffec77c4448c99b060dc925",
        bytes: pack_bytes!("cbramod-head-c-wake-light/heads/head_c_wake_light_linear.f32bin"),
    },
    Pack {
        scorer: "ai.a_vig_reve",
        pack_id: "reve-a-vig-subsample",
        model: AiModel::ReveBase,
        in_dim: REVE_DIM,
        sha256: "c032abbfa40fb148d3830b41bde4a65bc09144c99106b401872d080daa008256",
        bytes: pack_bytes!("reve-a-vig-subsample/heads/head_a_vig_reve_linear.f32bin"),
    },
    Pack {
        scorer: "ai.wake_light_reve",
        pack_id: "reve-head-c-wake-light-subsample",
        model: AiModel::ReveBase,
        in_dim: REVE_DIM,
        sha256: "329ad140681ebe8354257bcb63d6d557596b71a3d41fcd4947001e494b825fe9",
        bytes: pack_bytes!("reve-head-c-wake-light-subsample/heads/head_c_wake_light_reve_linear.f32bin"),
    },
];

/// `W` row-major `[n_classes × in_dim]`, `b` `[n_classes]`.
#[derive(Debug, Clone, PartialEq)]
pub struct LinearHead {
    pub scorer: &'static str,
    pub in_dim: usize,
    pub weight: Vec<f32>,
    pub bias: Vec<f32>,
}

impl LinearHead {
    /// Parse a `.f32bin` (little-endian `W` then `b`), verifying its SHA-256.
    pub fn parse(pack: &Pack, bytes: &[u8]) -> anyhow::Result<Self> {
        let hex = sha256_hex(bytes);
        ensure!(hex == pack.sha256, "{} head SHA-256 mismatch: got {hex}", pack.pack_id);
        let n = N_CLASSES * pack.in_dim + N_CLASSES;
        ensure!(bytes.len() == n * 4, "{} head is {} bytes, expected {}", pack.pack_id, bytes.len(), n * 4);
        let floats: Vec<f32> = bytes.as_chunks::<4>().0.iter().map(|c| f32::from_le_bytes(*c)).collect();
        let (w, b) = floats.split_at(N_CLASSES * pack.in_dim);
        Ok(Self { scorer: pack.scorer, in_dim: pack.in_dim, weight: w.to_vec(), bias: b.to_vec() })
    }

    /// The bundled head for `pack`.
    pub fn bundled(pack: &Pack) -> anyhow::Result<Self> {
        Self::parse(pack, pack.bytes)
    }

    pub fn logits(&self, emb: &[f32]) -> anyhow::Result<Vec<f32>> {
        ensure!(emb.len() == self.in_dim, "{}: embedding has {} values, head expects {}", self.scorer, emb.len(), self.in_dim);
        Ok(self
            .weight
            .chunks_exact(self.in_dim)
            .zip(&self.bias)
            .map(|(row, b)| (f64::from(*b) + row.iter().zip(emb).map(|(w, x)| f64::from(*w) * f64::from(*x)).sum::<f64>()) as f32)
            .collect())
    }

    /// P(class 1).
    pub fn score(&self, emb: &[f32]) -> anyhow::Result<f32> {
        let p = softmax(&self.logits(emb)?);
        p.get(1).copied().filter(|v| v.is_finite()).context("non-finite head output")
    }
}

/// Numerically stable softmax.
pub fn softmax(logits: &[f32]) -> Vec<f32> {
    let max = logits.iter().copied().fold(f32::NEG_INFINITY, f32::max);
    let exps: Vec<f64> = logits.iter().map(|v| f64::from(*v - max).exp()).collect();
    let sum: f64 = exps.iter().sum();
    exps.into_iter().map(|e| (e / sum) as f32).collect()
}

/// All bundled heads of `model`.
pub fn for_model(model: AiModel) -> anyhow::Result<Vec<LinearHead>> {
    PACKS.iter().filter(|p| p.model == model).map(LinearHead::bundled).collect()
}

/// Score every head on `emb` → `(scorer, P(class 1))`.
pub fn score_all(heads: &[LinearHead], emb: &[f32]) -> Vec<(String, f32)> {
    heads.iter().filter_map(|h| h.score(emb).ok().map(|s| (h.scorer.to_owned(), s))).collect()
}

pub(crate) fn sha256_hex(bytes: &[u8]) -> String {
    let d = Sha256::digest(bytes);
    d.iter().map(|b| format!("{b:02x}")).collect()
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn bundled_heads_parse_and_score_in_unit_range() {
        for m in AiModel::ALL {
            let hs = for_model(m).unwrap();
            assert_eq!(hs.len(), 2);
            let emb = vec![0.05; hs[0].in_dim];
            for (_, s) in score_all(&hs, &emb) {
                assert!((0.0..=1.0).contains(&s));
            }
        }
    }

    #[test]
    fn tampered_head_is_rejected() {
        let mut b = PACKS[0].bytes.to_vec();
        b[0] ^= 1;
        assert!(LinearHead::parse(&PACKS[0], &b).unwrap_err().to_string().contains("SHA-256"));
    }

    #[test]
    fn logits_are_w_dot_x_plus_b() {
        let h = LinearHead { scorer: "t", in_dim: 2, weight: vec![1.0, 2.0, -1.0, 0.0], bias: vec![0.5, 1.0] };
        assert_eq!(h.logits(&[1.0, 1.0]).unwrap(), vec![3.5, 0.0]);
        assert!(h.logits(&[1.0]).is_err());
        let p = softmax(&[1.0, 3.0]);
        assert!((p[0] + p[1] - 1.0).abs() < 1e-6 && p[1] > p[0]);
    }
}
