//! LUNA model state + config generation (analysis-side).
//!
//! Mirrors `analysis::reve` for the LUNA foundation model (`PulpBio/LUNA`,
//! Apache-2.0, un-gated — the app can download the weights directly). The
//! `api::reve` FFI layer delegates here for load/unload/loaded; the forwarder
//! will later borrow an encoder to embed windows, exactly like the REVE path.

use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard};

use anyhow::Context;
use luna_rs::rlx::LunaEncoder;

/// Model-kind identifiers shared with the Dart side (`ModelKind.ffId`).
pub const KIND_REVE_BASE: &str = "reve_base";
pub const KIND_LUNA_BASE: &str = "luna_base";
pub const KIND_LUNA_LARGE: &str = "luna_large";

/// Loaded LUNA encoder, guarded so the forwarder can borrow it across threads.
static ENCODER: Mutex<Option<LunaEncoder>> = Mutex::new(None);

/// Load the LUNA model from [model_dir] (must contain `config.json` and
/// `model.safetensors`) and keep it ready for scoring. Returns a description
/// of the loaded model (inference runs on CPU). Re-loads replace any prior
/// model.
pub fn load_model(model_dir: &str) -> anyhow::Result<String> {
    let dir = PathBuf::from(model_dir);
    let config_path = dir.join("config.json");
    let weights_path = dir.join("model.safetensors");
    let (encoder, ms_load) =
        LunaEncoder::load(&config_path, &weights_path, rlx::Device::Cpu).with_context(|| {
            format!(
                "LUNA load failed (config={}, weights={})",
                config_path.display(),
                weights_path.display()
            )
        })?;
    let desc = encoder.describe();
    *ENCODER.lock().unwrap_or_else(|e| e.into_inner()) = Some(encoder);
    log::info!("[luna] loaded: {desc} ({ms_load:.0} ms)");
    Ok(format!("{desc} — loaded in {ms_load:.0} ms"))
}

/// Drop the loaded model and free its memory.
pub fn unload_model() {
    *ENCODER.lock().unwrap_or_else(|e| e.into_inner()) = None;
    log::info!("[luna] unloaded");
}

/// Whether a model is currently loaded.
pub fn is_loaded() -> bool {
    ENCODER.lock().map(|g| g.is_some()).unwrap_or(false)
}

/// JSON content of the app-generated LUNA `config.json` for [kind] (`luna_base`
/// or `luna_large`).
///
/// The Hub's own `config.json` (`{"model_type":"luna","architectures":["LUNA"]}`)
/// relies on serde defaults, which only describe LUNA-Base. LUNA-Large has a
/// different architecture (embed_dim 96, 6 queries, 10 encoder blocks), so the
/// app writes the explicit hyperparameters next to the downloaded weights. The
/// loader (`LunaEncoder::load`) reads these same field names.
pub fn config_json(kind: &str) -> anyhow::Result<String> {
    let (embed_dim, num_queries, depth) = match kind {
        KIND_LUNA_BASE => (64usize, 4usize, 8usize),
        KIND_LUNA_LARGE => (96usize, 6usize, 10usize),
        _ => anyhow::bail!("unknown LUNA kind: {kind}"),
    };
    Ok(format!(
        r#"{{
  "architectures": [
    "LUNA"
  ],
  "model_type": "luna",
  "patch_size": 40,
  "num_queries": {num_queries},
  "embed_dim": {embed_dim},
  "depth": {depth},
  "num_heads": 2,
  "mlp_ratio": 4.0,
  "num_classes": 0
}}"#
    ))
}

/// Borrow the loaded encoder for a single inference, or None when no model is
/// loaded. The caller must not call `load_model`/`unload_model` while holding
/// the guard.
#[allow(unused)]
pub fn encoder_guard() -> MutexGuard<'static, Option<LunaEncoder>> {
    ENCODER.lock().unwrap_or_else(|e| e.into_inner())
}

/// Run the loaded LUNA encoder over one aligned epoch and return the **mean-
/// pooled latent embedding** — the encoder hidden state `[B, S, Q*D]` pooled
/// over the sequence dimension `S` into a fixed-size `[Q*D]` vector. The
/// forwarder calls this from a blocking thread once per second; returns an
/// error when no model is loaded.
pub fn score_window(
    signal: Vec<f32>,
    chan_pos: Vec<f32>,
    n_channels: usize,
    n_times: usize,
) -> anyhow::Result<Vec<f32>> {
    let mut guard = encoder_guard();
    let encoder = guard.as_mut().context("no LUNA model loaded")?;
    let out = encoder.run_epoch_latent(&signal, &chan_pos, None, n_channels, n_times)?;
    // out.shape = [B=1, S, Q*D]; output is flattened [S * Q*D].
    let s = *out.shape.get(1).context("latent shape missing S")?;
    let dim = *out.shape.get(2).context("latent shape missing Q*D")?;
    anyhow::ensure!(
        out.output.len() == s * dim,
        "latent length {} != S={s} * Q*D={dim}",
        out.output.len()
    );
    let mut pooled = vec![0f32; dim];
    for (i, v) in out.output.iter().enumerate() {
        pooled[i % dim] += v;
    }
    for v in pooled.iter_mut() {
        *v /= s as f32;
    }
    if log_once() {
        log::info!(
            "[luna] score_window: latent shape={:?} pooled [Q*D]={dim} (first 4: {:?})",
            out.shape,
            &pooled[..pooled.len().min(4)]
        );
    }
    Ok(pooled)
}

/// Log the embedding shape exactly once per process (the forwarder emits a
/// score every second; only the first call is interesting).
fn log_once() -> bool {
    use std::sync::atomic::{AtomicBool, Ordering};
    static LOGGED: AtomicBool = AtomicBool::new(false);
    !LOGGED.swap(true, Ordering::Relaxed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    /// Load the real LUNA-Base weights with the generated `config.json` and
    /// run one 4-channel inference. Uses the local copy:
    /// `.local/luna-base-dl/LUNA_base.safetensors`.
    ///
    /// Run with: `cargo test --lib -- --ignored luna_smoke -- --nocapture`
    #[test]
    #[ignore]
    fn luna_smoke() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        let model_src =
            root.join("../.local/luna-base-dl/LUNA_base.safetensors");
        assert!(
            model_src.exists(),
            "model not found at {} — copy it from the HF repo first",
            model_src.display()
        );

        let smoke_dir = root.join("target/luna-smoke");
        fs::create_dir_all(&smoke_dir).unwrap();
        fs::write(
            smoke_dir.join("config.json"),
            config_json(KIND_LUNA_BASE).unwrap(),
        )
        .unwrap();
        let link = smoke_dir.join("model.safetensors");
        if std::fs::symlink_metadata(&link).is_ok() {
            fs::remove_file(&link).unwrap();
        }
        std::os::unix::fs::symlink(&model_src, &link).unwrap();

        let desc = load_model(&smoke_dir.to_string_lossy()).unwrap();
        println!("loaded: {desc}");
        assert!(is_loaded(), "model not registered as loaded");

        // 4-channel Muse-style input, one 5 s epoch at 256 Hz (LUNA epoch).
        let n_channels = 4usize;
        let n_times = 1280usize;
        let mut signal = Vec::with_capacity(n_channels * n_times);
        let mut phase = 0.3f32;
        for c in 0..n_channels {
            for _ in 0..n_times {
                phase += 0.05;
                signal.push((phase * (1.0 + 0.1 * c as f32)).sin() * 12.0);
            }
        }
        // AF7 / AF8 / TP9 / TP10 approximate EEG coordinates in mm.
        let chan_pos = vec![
            -36.0, 30.0, 90.0, 36.0, 30.0, 90.0, -75.0, -18.0, -15.0, 75.0, -18.0, -15.0,
        ];

        {
            let mut guard = encoder_guard();
            let encoder = guard.as_mut().expect("encoder loaded");
            let t0 = std::time::Instant::now();
            let out = encoder
                .run_epoch(&signal, &chan_pos, None, n_channels, n_times)
                .expect("run_epoch failed");
            eprintln!(
                "run_epoch ok: out len={} shape={:?} in {:.0} ms",
                out.output.len(),
                out.shape,
                t0.elapsed().as_secs_f64() * 1000.0
            );
            let t1 = std::time::Instant::now();
            let latent = encoder
                .run_epoch_latent(&signal, &chan_pos, None, n_channels, n_times)
                .expect("run_epoch_latent failed");
            eprintln!(
                "run_epoch_latent ok: out len={} shape={:?} in {:.0} ms",
                latent.output.len(),
                latent.shape,
                t1.elapsed().as_secs_f64() * 1000.0
            );
            // latent is [B, S, Q*D]; verify output length matches the shape.
            let expected: usize = latent.shape.iter().product();
            assert_eq!(latent.output.len(), expected, "latent length != shape product");
            let pooled = pool_latent(&latent.output, latent.shape[1]);
            eprintln!("latent pooled [Q*D] (mean over S, first 4): {:?}", &pooled[..4]);
        }

        println!("luna_smoke: OK");
    }

    /// Mean-pool a `[B, S, Q*D]` latent over the sequence dim → `[Q*D]`.
    fn pool_latent(output: &[f32], s: usize) -> Vec<f32> {
        let dim = output.len() / s;
        let mut pooled = vec![0f32; dim];
        for (i, v) in output.iter().enumerate() {
            pooled[i % dim] += v;
        }
        for v in pooled.iter_mut() {
            *v /= s as f32;
        }
        pooled
    }
}
