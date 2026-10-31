//! REVE base on the RLX CPU runtime (`reve-rs`), reused from the legacy app.
//! 4 rows with approximate 3-D electrode positions → pooled 512-d latent.

use anyhow::Context;
use reve_rs::ReveEncoder;
use std::path::Path;

/// 2 s @ 256 Hz, as in the head packs' manifests (legacy app used 4 s).
pub const WINDOW_SAMPLES: usize = 512;

/// AF7, AF8, TP9, TP10 (mm), in model row order (legacy `MODEL_POSITIONS`).
const POSITIONS: [f32; 12] = [-36.0, 30.0, 90.0, 36.0, 30.0, 90.0, -75.0, -18.0, -15.0, 75.0, -18.0, -15.0];

pub struct Reve(ReveEncoder);

impl Reve {
    /// Load `config.json` + `model.safetensors` from `dir`.
    pub fn load(dir: &Path) -> anyhow::Result<(Self, String)> {
        let (cfg, w) = (dir.join("config.json"), dir.join("model.safetensors"));
        let (enc, ms) = ReveEncoder::load(&cfg, &w, rlx::Device::Cpu).with_context(|| format!("REVE load failed ({})", dir.display()))?;
        let desc = format!("{} — loaded in {ms:.0} ms", enc.describe());
        Ok((Self(enc), desc))
    }

    pub fn embed(&mut self, signal: &[f32], n_times: usize) -> anyhow::Result<Vec<f32>> {
        anyhow::ensure!(signal.len() == 4 * n_times, "REVE expects 4 rows × {n_times}");
        Ok(self.0.run_one(signal.to_vec(), POSITIONS.to_vec(), 4, n_times)?.output)
    }
}

/// App-written `config.json` (byte-identical to the public HF config of
/// `brain-bzh/reve-base`; only the weights are gated).
pub fn config_json() -> &'static str {
    r#"{
  "architectures": [
    "Reve"
  ],
  "auto_map": {
    "AutoConfig": "configuration_reve.ReveConfig",
    "AutoModel": "modeling_reve.Reve"
  },
  "depth": 22,
  "dtype": "float32",
  "embed_dim": 512,
  "freqs": 4,
  "head_dim": 64,
  "heads": 8,
  "mlp_dim_ratio": 2.66,
  "model_type": "reve",
  "noise_ratio": 0.0025,
  "patch_overlap": 20,
  "patch_size": 200,
  "transformers_version": "4.56.2",
  "use_geglu": true
}"#
}
