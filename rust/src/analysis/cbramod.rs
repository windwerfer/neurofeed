//! Spur A — frozen CBraMod encoder + A-vig HeadALinear (analysis-side).
//!
//! Pack id: `cbramod-a-vig-full` (neurofeed_heads). Window: 2 s @ 256 Hz
//! (512 samples) Muse AF7/AF8/TP9/TP10 → resample to 200 Hz patches → frozen
//! CBraMod → mean-pool (200-d) → HeadALinear → **argmax** over
//! `drowsy` / `hypnagogic`.
//!
//! Encoder weights (~20 MB Apache-2.0) are **not** bundled; pin SHA-256 and
//! load from the model directory / HF cache (same pattern as REVE user-local
//! weights). Full encoder forward needs a native Torch/Candle backend —
//! this module loads + verifies the pack, applies the linear head, and exposes
//! a clear error from [`score_window`] until that backend is linked.

use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use anyhow::{bail, Context};
use sha2::{Digest, Sha256};

/// Model-kind id shared with Dart (`ModelKind.ffId`).
pub const KIND_CBRAMOD_A_VIG: &str = "cbramod_a_vig";

/// Published pack id under `neurofeed_heads/packs/` / app `assets/packs/`.
pub const PACK_ID: &str = "cbramod-a-vig-full";

/// Expected SHA-256 of `pretrained_weights.pth` (weighting666/CBraMod).
pub const ENCODER_SHA256: &str =
    "0792cb808c14e6b7a2bb2ce1dff379bc47bc54c49a779825bdfeb33bf8157178";

/// Expected SHA-256 of the shipped full-corpus head `.pt`.
pub const HEAD_PT_SHA256: &str =
    "b34730c8eb1415427119bda368394b0b5dfa7d991c5b46cd22f863912efdd62b";

pub const EMBED_DIM: usize = 200;
pub const N_CLASSES: usize = 2;
/// 2 s @ 256 Hz.
pub const WINDOW_SAMPLES: usize = 512;
pub const SOURCE_SR_HZ: f32 = 256.0;
pub const NATIVE_SR_HZ: f32 = 200.0;
pub const PATCH_SAMPLES: usize = 200;

const LABEL_DROWSY: usize = 0;
const LABEL_HYPNAGOGIC: usize = 1;

/// HeadALinear: `logits = W @ emb + b` with W shape [n_classes, in_dim].
#[derive(Clone, Debug)]
pub struct HeadALinear {
    pub weight: Vec<f32>, // row-major [N_CLASSES * EMBED_DIM]
    pub bias: Vec<f32>,   // [N_CLASSES]
}

impl HeadALinear {
    pub fn forward(&self, emb: &[f32]) -> anyhow::Result<Vec<f32>> {
        anyhow::ensure!(
            emb.len() == EMBED_DIM,
            "embedding len {} != {EMBED_DIM}",
            emb.len()
        );
        anyhow::ensure!(
            self.weight.len() == N_CLASSES * EMBED_DIM && self.bias.len() == N_CLASSES,
            "head weight/bias shape mismatch"
        );
        let mut logits = vec![0f32; N_CLASSES];
        for c in 0..N_CLASSES {
            let mut sum = self.bias[c] as f64;
            let row = &self.weight[c * EMBED_DIM..(c + 1) * EMBED_DIM];
            for (w, x) in row.iter().zip(emb.iter()) {
                sum += (*w as f64) * (*x as f64);
            }
            logits[c] = sum as f32;
        }
        Ok(logits)
    }
}

/// Softmax → class probabilities (stable).
pub fn softmax(logits: &[f32]) -> Vec<f32> {
    let max = logits.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
    let exps: Vec<f64> = logits.iter().map(|v| ((*v - max) as f64).exp()).collect();
    let sum: f64 = exps.iter().sum();
    exps.into_iter().map(|e| (e / sum) as f32).collect()
}

/// Argmax class index (ties → lower index).
pub fn argmax(v: &[f32]) -> usize {
    let mut best_i = 0;
    let mut best = f32::NEG_INFINITY;
    for (i, x) in v.iter().enumerate() {
        if *x > best {
            best = *x;
            best_i = i;
        }
    }
    best_i
}

struct Loaded {
    head: HeadALinear,
    model_dir: PathBuf,
    #[allow(dead_code)]
    encoder_path: Option<PathBuf>,
    encoder_verified: bool,
}

static STATE: Mutex<Option<Loaded>> = Mutex::new(None);

/// Last classification probabilities `[p_drowsy, p_hypnagogic]` from a
/// successful head apply (tests / future forwarder overlay).
static LAST_PROBS: Mutex<Option<Vec<f32>>> = Mutex::new(None);

fn lock() -> std::sync::MutexGuard<'static, Option<Loaded>> {
    STATE.lock().unwrap_or_else(|e| e.into_inner())
}

/// Load Spur A from [model_dir].
///
/// Expected layout (either works):
/// - `heads/head_a_vig_linear.f32bin` (preferred) or `.pt`
/// - `pretrained_weights.pth` (optional until encoder forward is linked)
/// - `pack_manifest.json` / `encoder/EXPECTED.json` (informational)
pub fn load_model(model_dir: &str) -> anyhow::Result<String> {
    let dir = PathBuf::from(model_dir);
    let head = load_head(&dir)?;
    let encoder_path = find_encoder(&dir);
    let mut encoder_verified = false;
    if let Some(ref p) = encoder_path {
        let hex = file_sha256(p)?;
        if hex != ENCODER_SHA256 {
            bail!(
                "CBraMod encoder SHA mismatch\nGot      {hex}\nExpected {ENCODER_SHA256}\n{}",
                p.display()
            );
        }
        encoder_verified = true;
    }
    *lock() = Some(Loaded {
        head,
        model_dir: dir.clone(),
        encoder_path: encoder_path.clone(),
        encoder_verified,
    });
    *LAST_PROBS.lock().unwrap_or_else(|e| e.into_inner()) = None;

    let enc_status = if encoder_verified {
        "encoder weights verified (forward backend pending)"
    } else {
        "encoder weights missing — download pretrained_weights.pth (Apache-2.0) into the model dir"
    };
    let desc = format!(
        "CBraMod A-vig ({PACK_ID}) — HeadALinear {EMBED_DIM}→{N_CLASSES}, decode=argmax; {enc_status}"
    );
    log::info!("[cbramod] loaded: {desc} (dir={})", dir.display());
    Ok(desc)
}

pub fn unload_model() {
    *lock() = None;
    *LAST_PROBS.lock().unwrap_or_else(|e| e.into_inner()) = None;
    log::info!("[cbramod] unloaded");
}

pub fn is_loaded() -> bool {
    lock().is_some()
}

/// Generated config.json for the pack (written next to weights by Dart).
pub fn generated_config_json() -> String {
    format!(
        r#"{{
  "model_type": "cbramod_a_vig",
  "pack_id": "{PACK_ID}",
  "encoder_family": "CBraMod",
  "encoder_sha256": "{ENCODER_SHA256}",
  "head_arch": "HeadALinear",
  "in_dim": {EMBED_DIM},
  "n_classes": {N_CLASSES},
  "labels": ["drowsy", "hypnagogic"],
  "decode": "argmax",
  "window_sec": 2.0,
  "input_sr_hz": {SOURCE_SR_HZ},
  "n_times": {WINDOW_SAMPLES},
  "native_sr_hz": {NATIVE_SR_HZ},
  "patch_samples": {PATCH_SAMPLES},
  "pool": "mean",
  "muse_channels": ["AF7", "AF8", "TP9", "TP10"]
}}"#
    )
}

/// Apply the loaded head to a 200-d embedding. Updates [`last_probs`].
pub fn apply_head(emb: &[f32]) -> anyhow::Result<(Vec<f32>, Vec<f32>, usize)> {
    let guard = lock();
    let loaded = guard.as_ref().context("no CBraMod model loaded")?;
    let logits = loaded.head.forward(emb)?;
    let probs = softmax(&logits);
    let pred = argmax(&logits);
    *LAST_PROBS.lock().unwrap_or_else(|e| e.into_inner()) = Some(probs.clone());
    Ok((logits, probs, pred))
}

pub fn last_probs() -> Option<Vec<f32>> {
    LAST_PROBS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .clone()
}

/// P(hypnagogic) from the last head apply, if any.
pub fn last_hypnagogic_p() -> Option<f32> {
    last_probs().and_then(|p| p.get(LABEL_HYPNAGOGIC).copied())
}

/// Score one Muse window. Adapter + head are implemented; frozen encoder
/// forward is not yet linked in-process (no tch/Candle dep in this PR).
pub fn score_window(
    signal: Vec<f32>,
    _positions: Vec<f32>,
    n_channels: usize,
    n_times: usize,
) -> anyhow::Result<Vec<f32>> {
    anyhow::ensure!(n_channels == 4, "CBraMod Spur A expects 4 Muse channels");
    anyhow::ensure!(
        n_times == WINDOW_SAMPLES,
        "CBraMod Spur A window is {WINDOW_SAMPLES} samples (2 s @ 256 Hz), got {n_times}"
    );
    anyhow::ensure!(
        signal.len() == n_channels * n_times,
        "signal len {} != 4*{n_times}",
        signal.len()
    );
    let guard = lock();
    let loaded = guard.as_ref().context("no CBraMod model loaded")?;
    // Prove the adapter path compiles / runs (patches ready for encoder).
    let patches = to_cbramod_patches(&signal, n_channels, n_times)?;
    let _ = patches;
    if !loaded.encoder_verified {
        bail!(
            "CBraMod encoder weights not present/verified in {} — place pretrained_weights.pth (SHA {ENCODER_SHA256})",
            loaded.model_dir.display()
        );
    }
    bail!(
        "CBraMod encoder forward not linked yet (head + SHA pin OK at {}). \
         Follow-up: native Torch/Candle backend for frozen CBraMod; head apply is ready via apply_head.",
        loaded.model_dir.display()
    );
}

/// Resample (C,T) @ 256 Hz → patches (C, n_patches, 200) @ 200 Hz.
/// Returns flattened `[C * n_patches * 200]` for a future encoder call.
pub fn to_cbramod_patches(
    signal: &[f32],
    n_channels: usize,
    n_times: usize,
) -> anyhow::Result<Vec<f32>> {
    anyhow::ensure!(signal.len() == n_channels * n_times);
    // Per-channel linear resample 256 → 200 Hz.
    let duration = n_times as f32 / SOURCE_SR_HZ;
    let t_new = (duration * NATIVE_SR_HZ).round().max(1.0) as usize;
    let mut resampled = Vec::with_capacity(n_channels * t_new);
    for c in 0..n_channels {
        let row = &signal[c * n_times..(c + 1) * n_times];
        for i in 0..t_new {
            let src = i as f32 * (n_times - 1) as f32 / (t_new - 1).max(1) as f32;
            let i0 = src.floor() as usize;
            let i1 = (i0 + 1).min(n_times - 1);
            let t = src - i0 as f32;
            resampled.push(row[i0] * (1.0 - t) + row[i1] * t);
        }
    }
    let mut t = t_new;
    if t < PATCH_SAMPLES {
        let pad = PATCH_SAMPLES - t;
        let mut padded = Vec::with_capacity(n_channels * PATCH_SAMPLES);
        for c in 0..n_channels {
            padded.extend_from_slice(&resampled[c * t_new..(c + 1) * t_new]);
            padded.extend(std::iter::repeat(0f32).take(pad));
        }
        resampled = padded;
        t = PATCH_SAMPLES;
    }
    let n_patches = t / PATCH_SAMPLES;
    let t_keep = n_patches * PATCH_SAMPLES;
    let mut out = Vec::with_capacity(n_channels * t_keep);
    for c in 0..n_channels {
        out.extend_from_slice(&resampled[c * t_new..c * t_new + t_keep]);
    }
    Ok(out)
}

fn find_encoder(dir: &Path) -> Option<PathBuf> {
    let candidates = [
        dir.join("pretrained_weights.pth"),
        dir.join("encoder").join("pretrained_weights.pth"),
        dir.join("models").join("CBraMod").join("pretrained_weights.pth"),
    ];
    candidates.into_iter().find(|p| p.is_file())
}

fn load_head(dir: &Path) -> anyhow::Result<HeadALinear> {
    let f32bin_candidates = [
        dir.join("heads").join("head_a_vig_linear.f32bin"),
        dir.join("head_a_vig_linear.f32bin"),
    ];
    for p in &f32bin_candidates {
        if p.is_file() {
            return load_head_f32bin(p);
        }
    }
    let pt_candidates = [
        dir.join("heads").join("head_a_vig_linear.pt"),
        dir.join("head_a_vig_linear.pt"),
    ];
    for p in &pt_candidates {
        if p.is_file() {
            // Prefer verifying .pt checksum when present.
            if let Ok(hex) = file_sha256(p) {
                if hex != HEAD_PT_SHA256 {
                    log::warn!(
                        "[cbramod] head .pt SHA {hex} != pinned {HEAD_PT_SHA256} — loading anyway if storages parse"
                    );
                }
            }
            return load_head_pt_zip(p);
        }
    }
    bail!(
        "CBraMod head not found under {} (need heads/head_a_vig_linear.f32bin or .pt)",
        dir.display()
    );
}

fn load_head_f32bin(path: &Path) -> anyhow::Result<HeadALinear> {
    let bytes = fs::read(path).with_context(|| format!("read {}", path.display()))?;
    anyhow::ensure!(
        bytes.len() == (N_CLASSES * EMBED_DIM + N_CLASSES) * 4,
        "f32bin size {} unexpected",
        bytes.len()
    );
    let mut floats = Vec::with_capacity(bytes.len() / 4);
    for chunk in bytes.chunks_exact(4) {
        floats.push(f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
    }
    let (w, b) = floats.split_at(N_CLASSES * EMBED_DIM);
    Ok(HeadALinear {
        weight: w.to_vec(),
        bias: b.to_vec(),
    })
}

/// Minimal PyTorch zip reader for this head export (storages `data/0`, `data/1`).
fn load_head_pt_zip(path: &Path) -> anyhow::Result<HeadALinear> {
    let file = fs::File::open(path).with_context(|| format!("open {}", path.display()))?;
    let mut archive = zip::ZipArchive::new(file).context("open head .pt as zip")?;
    let mut weight_bytes = None;
    let mut bias_bytes = None;
    for i in 0..archive.len() {
        let mut f = archive.by_index(i)?;
        let name = f.name().to_string();
        if name.ends_with("/data/0") || name == "data/0" {
            let mut buf = Vec::new();
            f.read_to_end(&mut buf)?;
            weight_bytes = Some(buf);
        } else if name.ends_with("/data/1") || name == "data/1" {
            let mut buf = Vec::new();
            f.read_to_end(&mut buf)?;
            bias_bytes = Some(buf);
        }
    }
    let w = weight_bytes.context("head .pt missing data/0 (weight)")?;
    let b = bias_bytes.context("head .pt missing data/1 (bias)")?;
    anyhow::ensure!(w.len() == N_CLASSES * EMBED_DIM * 4, "weight bytes {}", w.len());
    anyhow::ensure!(b.len() == N_CLASSES * 4, "bias bytes {}", b.len());
    let mut weight = Vec::with_capacity(N_CLASSES * EMBED_DIM);
    for chunk in w.chunks_exact(4) {
        weight.push(f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
    }
    let mut bias = Vec::with_capacity(N_CLASSES);
    for chunk in b.chunks_exact(4) {
        bias.push(f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
    }
    let _ = LABEL_DROWSY; // documented class index 0
    Ok(HeadALinear { weight, bias })
}

fn file_sha256(path: &Path) -> anyhow::Result<String> {
    let mut file = fs::File::open(path).with_context(|| format!("sha open {}", path.display()))?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 1024 * 64];
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn softmax_argmax_roundtrip() {
        let logits = vec![1.0f32, 3.0];
        let p = softmax(&logits);
        assert!((p[0] + p[1] - 1.0).abs() < 1e-5);
        assert!(p[1] > p[0]);
        assert_eq!(argmax(&logits), 1);
        assert_eq!(argmax(&p), LABEL_HYPNAGOGIC);
    }

    #[test]
    fn head_forward_shapes() {
        let head = HeadALinear {
            weight: vec![0.0; N_CLASSES * EMBED_DIM],
            bias: vec![-1.0, 2.0],
        };
        let emb = vec![0.0; EMBED_DIM];
        let logits = head.forward(&emb).unwrap();
        assert_eq!(logits, vec![-1.0, 2.0]);
        assert_eq!(argmax(&logits), 1);
    }

    #[test]
    fn patches_2s_256hz() {
        let n_times = WINDOW_SAMPLES;
        let signal = vec![0.1f32; 4 * n_times];
        let patches = to_cbramod_patches(&signal, 4, n_times).unwrap();
        // 2 s @ 200 Hz = 400 samples → 2 patches × 200.
        assert_eq!(patches.len(), 4 * 2 * PATCH_SAMPLES);
    }

    #[test]
    fn load_bundled_f32bin_if_present() {
        // Dev tree: assets pack relative to crate.
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../assets/packs/cbramod-a-vig-full");
        if !root.join("heads/head_a_vig_linear.f32bin").is_file() {
            eprintln!("skip: bundled pack not at {}", root.display());
            return;
        }
        unload_model();
        let desc = load_model(&root.to_string_lossy()).unwrap();
        assert!(desc.contains("CBraMod"));
        assert!(is_loaded());
        let emb = vec![0.0f32; EMBED_DIM];
        let (logits, probs, pred) = apply_head(&emb).unwrap();
        assert_eq!(logits.len(), 2);
        assert_eq!(probs.len(), 2);
        assert!(pred == 0 || pred == 1);
        // Bias-dominated zero embedding → class from bias sign.
        assert_eq!(pred, argmax(&logits));
        unload_model();
    }
}
