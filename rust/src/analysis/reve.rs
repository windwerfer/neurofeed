//! REVE model state + scoring support (analysis-side).
//!
//! The `api::reve` FFI layer delegates here for load/unload/loaded; the
//! forwarder (`api::muse`) borrows [encoder_guard] once per second to score an
//! aligned 4 s window and emit a `MuseEventDto::Reve`.

use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard};

use anyhow::Context;
use reve_rs::ReveEncoder;

/// Loaded REVE encoder, guarded so the forwarder can borrow it across threads.
static ENCODER: Mutex<Option<ReveEncoder>> = Mutex::new(None);

/// Load the REVE model from [model_dir] (must contain `config.json` and
/// `model.safetensors`) and keep it ready for scoring. Returns a description
/// of the loaded model (inference runs on CPU). Re-loads replace any prior
/// model.
pub fn load_model(model_dir: &str) -> anyhow::Result<String> {
    let dir = PathBuf::from(model_dir);
    let config_path = dir.join("config.json");
    let weights_path = dir.join("model.safetensors");
    let (encoder, ms_load) =
        ReveEncoder::load(&config_path, &weights_path, rlx::Device::Cpu)
            .with_context(|| {
                format!(
                    "REVE load failed (config={}, weights={})",
                    config_path.display(),
                    weights_path.display()
                )
            })?;
    let desc = encoder.describe();
    debug_assert!(encoder.params().len() > 0, "empty REVE parameter map");
    *ENCODER.lock().unwrap_or_else(|e| e.into_inner()) = Some(encoder);
    log::info!("[reve] loaded: {desc} ({ms_load:.0} ms)");
    Ok(format!("{desc} — loaded in {ms_load:.0} ms"))
}

/// Drop the loaded model and free its memory.
pub fn unload_model() {
    *ENCODER.lock().unwrap_or_else(|e| e.into_inner()) = None;
    log::info!("[reve] unloaded");
}

/// Whether a model is currently loaded.
pub fn is_loaded() -> bool {
    ENCODER.lock().map(|g| g.is_some()).unwrap_or(false)
}

/// JSON content of the app-generated REVE `config.json`.
///
/// Byte-identical to the HF `config.json` for `brain-bzh/reve-base` (the
/// architecture is public; only the *weights* are gated). The app writes this
/// file next to an imported `model.safetensors` so the loader can describe
/// the graph without the user needing to fetch the Hub's own config. Reve-rs
/// reads the top level and ignores the transformer fields it doesn't need.
pub fn generated_config_json() -> String {
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
    .to_string()
}

/// Borrow the loaded encoder for a single inference, or None when no model is
/// loaded. The caller must not call `load_model`/`unload_model` while holding
/// the guard.
#[allow(unused)]
pub fn encoder_guard() -> MutexGuard<'static, Option<ReveEncoder>> {
    ENCODER.lock().unwrap_or_else(|e| e.into_inner())
}

/// Run the loaded REVE encoder over one aligned window and return the pooled
/// embedding vector (the `[embed_dim]` latent when the checkpoint has no
/// classifier head, as `reve-base` does). The forwarder calls this from a
/// blocking thread once per second; returns an error when no model is loaded.
pub fn score_window(
    signal: Vec<f32>,
    positions: Vec<f32>,
    n_channels: usize,
    n_times: usize,
) -> anyhow::Result<Vec<f32>> {
    let mut guard = encoder_guard();
    let encoder = guard.as_mut().context("no REVE model loaded")?;
    let out = encoder.run_one(signal, positions, n_channels, n_times)?;
    if log_once() {
        log::info!(
            "[reve] score_window: embedding len={} shape={:?} (first 4: {:?})",
            out.output.len(),
            out.shape,
            &out.output[..out.output.len().min(4)]
        );
    }
    Ok(out.output)
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

    /// Load the real REVE weights with the app-generated `config.json` and run
    /// one 4-channel inference. Requires a local copy of the gated weights:
    /// `.local/reve-base-dl/model.safetensors`.
    ///
    /// Run with: `cargo test --lib -- --ignored reveal_smoke -- --nocapture`
    #[test]
    #[ignore]
    fn reveal_smoke() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        let model_src = root.join("../.local/reve-base-dl/model.safetensors");
        assert!(
            model_src.exists(),
            "model not found at {} — copy it from the HF repo first",
            model_src.display()
        );

        let smoke_dir = root.join("target/reve-smoke");
        fs::create_dir_all(&smoke_dir).unwrap();
        fs::write(smoke_dir.join("config.json"), generated_config_json()).unwrap();
        let link = smoke_dir.join("model.safetensors");
        if std::fs::symlink_metadata(&link).is_ok() {
            fs::remove_file(&link).unwrap();
        }
        std::os::unix::fs::symlink(&model_src, &link).unwrap();

        let desc = load_model(&smoke_dir.to_string_lossy()).unwrap();
        println!("loaded: {desc}");
        assert!(is_loaded(), "model not registered as loaded");

        // 4-channel Muse-style input, one 4 s aligned window at 256 Hz.
        let n_channels = 4usize;
        let n_times = 1024usize;
        let mut signal = Vec::with_capacity(n_channels * n_times);
        let mut phase = 0.3f32;
        for c in 0..n_channels {
            for _ in 0..n_times {
                phase += 0.05;
                signal.push((phase * (1.0 + 0.1 * c as f32)).sin() * 12.0);
            }
        }
        // AF7 / AF8 / TP9 / TP10 approximate EEG coordinates in mm.
        let positions = vec![
            -36.0, 30.0, 90.0, 36.0, 30.0, 90.0, -75.0, -18.0, -15.0, 75.0, -18.0, -15.0,
        ];

        {
            let mut guard = encoder_guard();
            let encoder = guard.as_mut().expect("encoder loaded");
            let out = encoder
                .run_one(signal, positions, n_channels, n_times)
                .expect("run_one failed");
            println!(
                "run_one ok: out len={} shape={:?} (first 4: {:?})",
                out.output.len(),
                out.shape,
                &out.output[..out.output.len().min(4)]
            );
        }

        println!("reveal_smoke: OK");
    }
}