//! NeuroFeed AI sleep scorers.
//!
//! - [`heads`]: the bundled linear heads (A-vig, wake/light; CBraMod + REVE),
//!   SHA-pinned, pure Rust and WASM-clean.
//! - `cbramod` / `reve` (features): the encoders, reused from the legacy app
//!   (Candle and the vendored RLX CPU runtime).
//! - [`store`]: model folders, download / import with checksum.
//! - [`NativeAi`]: the desktop [`nf_types::AiRuntime`] (worker thread).
//!
//! Guard logic (thresholds, anchors, warnings) lives in `nf-feedback` /
//! `nf-core`; this crate only turns EEG windows into embeddings and scores.

pub mod heads;
pub mod store;

#[cfg(feature = "cbramod")]
pub mod cbramod;
#[cfg(feature = "reve")]
pub mod reve;

mod runtime;
pub use runtime::NativeAi;

use nf_types::AiModel;
use std::path::Path;

/// A loaded encoder.
pub enum Model {
    #[cfg(feature = "cbramod")]
    Cbramod(Box<cbramod::Cbramod>),
    #[cfg(feature = "reve")]
    Reve(Box<reve::Reve>),
}

impl Model {
    /// Load `model` from its folder; returns a description.
    pub fn load(model: AiModel, dir: &Path) -> anyhow::Result<(Self, String)> {
        match model {
            #[cfg(feature = "cbramod")]
            AiModel::CbramodAVig => {
                let t0 = std::time::Instant::now();
                let enc = cbramod::Cbramod::load(&dir.join(model.weights_file()))?;
                Ok((
                    Self::Cbramod(Box::new(enc)),
                    format!("CBraMod encoder (Candle CPU) — loaded in {:.0} ms", t0.elapsed().as_secs_f64() * 1000.0),
                ))
            }
            #[cfg(feature = "reve")]
            AiModel::ReveBase => reve::Reve::load(dir).map(|(r, d)| (Self::Reve(Box::new(r)), d)),
            #[allow(unreachable_patterns)]
            other => anyhow::bail!("{} is not built into this app", other.label()),
        }
    }

    /// Pooled embedding of a `[4 × n_times]` window.
    pub fn embed(&mut self, signal: &[f32], n_times: usize) -> anyhow::Result<Vec<f32>> {
        match self {
            #[cfg(feature = "cbramod")]
            Self::Cbramod(c) => c.embed(signal, n_times),
            #[cfg(feature = "reve")]
            Self::Reve(r) => r.embed(signal, n_times),
            #[allow(unreachable_patterns)]
            _ => anyhow::bail!("no encoder built in"),
        }
    }
}
