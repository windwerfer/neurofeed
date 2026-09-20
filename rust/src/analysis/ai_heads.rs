//! Per-feature linear heads for Spur A / Head C (CBraMod + REVE subsample).
//!
//! Feature IDs (stable):
//! - `ai.a_vig` — CBraMod A-vig full (`cbramod-a-vig-full`)
//! - `ai.wake_light` — CBraMod Head C wake/light (`cbramod-head-c-wake-light`)
//! - `ai.a_vig_reve` — REVE A-vig subsample (`reve-a-vig-subsample`)
//! - `ai.wake_light_reve` — REVE Head C subsample (`reve-head-c-wake-light-subsample`)
//!
//! `ai.drowsiness` is a deprecated protocol alias of `ai.a_vig`.
//!
//! Encoder forward (CBraMod Torch/Candle, gated REVE) is separate: this module
//! loads + verifies packs and runs **head-linear** forward on embeddings so
//! each feature ID can be unit-tested without libtorch.

use std::collections::HashMap;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use flutter_rust_bridge::frb;

use anyhow::{bail, Context};

/// Primary CBraMod A-vig (sleep/drowsy) score.
pub const ID_A_VIG: &str = "ai.a_vig";
/// CBraMod Head C wake/light.
pub const ID_WAKE_LIGHT: &str = "ai.wake_light";
/// REVE A-vig subsample (experimental; needs gated REVE base).
pub const ID_A_VIG_REVE: &str = "ai.a_vig_reve";
/// REVE Head C subsample (experimental).
pub const ID_WAKE_LIGHT_REVE: &str = "ai.wake_light_reve";
/// Deprecated alias → [`ID_A_VIG`].
pub const ID_DROWSINESS_ALIAS: &str = "ai.drowsiness";

pub const PACK_CBRAMOD_A_VIG: &str = "cbramod-a-vig-full";
pub const PACK_CBRAMOD_WAKE_LIGHT: &str = "cbramod-head-c-wake-light";
pub const PACK_REVE_A_VIG: &str = "reve-a-vig-subsample";
pub const PACK_REVE_WAKE_LIGHT: &str = "reve-head-c-wake-light-subsample";

const CBRAMOD_DIM: usize = 200;
const REVE_DIM: usize = 512;
const N_CLASSES: usize = 2;

/// Pinned SHA-256 for shipped f32bin heads (matches pack_manifest head_f32bin_sha256).
const F32BIN_SHA256: &[(&str, &str)] = &[
    (
        "head_a_vig_linear.f32bin",
        "2695ce91cc5e9cbb8d6f29fc4bfff9b6f1294c106cced6fa2657d4bf6c26ba96",
    ),
    (
        "head_c_wake_light_linear.f32bin",
        "cc0415bc1d3fac7c5f7113315b609185b9d1dbc30ffec77c4448c99b060dc925",
    ),
    (
        "head_a_vig_reve_linear.f32bin",
        "c032abbfa40fb148d3830b41bde4a65bc09144c99106b401872d080daa008256",
    ),
    (
        "head_c_wake_light_reve_linear.f32bin",
        "329ad140681ebe8354257bcb63d6d557596b71a3d41fcd4947001e494b825fe9",
    ),
];

#[derive(Clone, Debug)]
pub struct LinearHead {
    pub in_dim: usize,
    pub n_classes: usize,
    pub weight: Vec<f32>, // row-major [n_classes * in_dim]
    pub bias: Vec<f32>,
    pub pack_id: String,
    pub feature_id: String,
}

impl LinearHead {
    pub fn forward(&self, emb: &[f32]) -> anyhow::Result<Vec<f32>> {
        anyhow::ensure!(
            emb.len() == self.in_dim,
            "embedding len {} != {} for {}",
            emb.len(),
            self.in_dim,
            self.feature_id
        );
        anyhow::ensure!(
            self.weight.len() == self.n_classes * self.in_dim && self.bias.len() == self.n_classes,
            "head shape mismatch for {}",
            self.feature_id
        );
        let mut logits = vec![0f32; self.n_classes];
        for c in 0..self.n_classes {
            let mut sum = self.bias[c] as f64;
            let row = &self.weight[c * self.in_dim..(c + 1) * self.in_dim];
            for (w, x) in row.iter().zip(emb.iter()) {
                sum += (*w as f64) * (*x as f64);
            }
            logits[c] = sum as f32;
        }
        Ok(logits)
    }
}

pub fn softmax(logits: &[f32]) -> Vec<f32> {
    let max = logits.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
    let exps: Vec<f64> = logits.iter().map(|v| ((*v - max) as f64).exp()).collect();
    let sum: f64 = exps.iter().sum();
    exps.into_iter().map(|e| (e / sum) as f32).collect()
}

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

/// Canonical scoring id (`ai.drowsiness` → `ai.a_vig`).
pub fn canonical_feature_id(id: &str) -> &str {
    if id == ID_DROWSINESS_ALIAS {
        ID_A_VIG
    } else {
        id
    }
}

/// All AI feature ids that may appear in the registry / enable-set.
pub fn all_feature_ids() -> &'static [&'static str] {
    &[
        ID_A_VIG,
        ID_WAKE_LIGHT,
        ID_A_VIG_REVE,
        ID_WAKE_LIGHT_REVE,
        ID_DROWSINESS_ALIAS,
    ]
}

pub fn is_ai_feature_id(id: &str) -> bool {
    all_feature_ids().contains(&id) || id.starts_with("ai.")
}

fn expected_dim(feature_id: &str) -> Option<usize> {
    match canonical_feature_id(feature_id) {
        ID_A_VIG | ID_WAKE_LIGHT => Some(CBRAMOD_DIM),
        ID_A_VIG_REVE | ID_WAKE_LIGHT_REVE => Some(REVE_DIM),
        _ => None,
    }
}

#[frb(ignore)]
struct Registry {
    heads: HashMap<String, LinearHead>,
}

fn registry() -> &'static Mutex<Registry> {
    static REG: OnceLock<Mutex<Registry>> = OnceLock::new();
    REG.get_or_init(|| {
        Mutex::new(Registry {
            heads: HashMap::new(),
        })
    })
}

fn lock() -> std::sync::MutexGuard<'static, Registry> {
    registry().lock().unwrap_or_else(|e| e.into_inner())
}

/// Drop all loaded heads.
pub fn unload_all() {
    lock().heads.clear();
}

pub fn is_head_loaded(feature_id: &str) -> bool {
    let id = canonical_feature_id(feature_id);
    lock().heads.contains_key(id)
}

pub fn loaded_feature_ids() -> Vec<String> {
    lock().heads.keys().cloned().collect()
}

/// Load a single pack directory for [feature_id].
///
/// Looks for `heads/*.f32bin` first, then `heads/*.pt` (zip storages).
pub fn load_pack(feature_id: &str, pack_dir: &Path) -> anyhow::Result<String> {
    let id = canonical_feature_id(feature_id).to_string();
    let in_dim =
        expected_dim(&id).with_context(|| format!("unknown AI feature id: {feature_id}"))?;
    let (head_path, head) = load_head_from_dir(pack_dir, in_dim, N_CLASSES, &id)?;
    let pack_id = pack_dir
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("pack")
        .to_string();
    let desc = format!(
        "{id} ← {pack_id} ({in_dim}→{N_CLASSES}) from {}",
        head_path.display()
    );
    let mut head = head;
    head.pack_id = pack_id;
    head.feature_id = id.clone();
    lock().heads.insert(id, head);
    log::info!("[ai_heads] loaded: {desc}");
    Ok(desc)
}

/// Load CBraMod heads from a Spur A model directory (A-vig required; Head C optional).
pub fn load_cbramod_model_dir(model_dir: &Path) -> anyhow::Result<Vec<String>> {
    let mut out = Vec::new();
    // Prefer dedicated f32bin names.
    let a_vig = try_load_named(
        ID_A_VIG,
        model_dir,
        &[
            "heads/head_a_vig_linear.f32bin",
            "head_a_vig_linear.f32bin",
            "heads/head_a_vig_linear.pt",
            "head_a_vig_linear.pt",
        ],
        CBRAMOD_DIM,
    )?;
    out.push(a_vig);

    if let Ok(wl) = try_load_named(
        ID_WAKE_LIGHT,
        model_dir,
        &[
            "heads/head_c_wake_light_linear.f32bin",
            "head_c_wake_light_linear.f32bin",
            "heads/head_c_wake_light_linear.pt",
            "head_c_wake_light_linear.pt",
        ],
        CBRAMOD_DIM,
    ) {
        out.push(wl);
    } else {
        log::info!(
            "[ai_heads] Head C wake/light not found under {} — ai.wake_light unavailable until pack present",
            model_dir.display()
        );
    }
    Ok(out)
}

/// Load REVE subsample heads from sibling pack dirs or `model_dir/heads/`.
pub fn load_reve_heads(model_dir: &Path, pack_roots: &[&Path]) -> anyhow::Result<Vec<String>> {
    let mut out = Vec::new();
    // Prefer files already copied next to REVE weights.
    if let Ok(d) = try_load_named(
        ID_A_VIG_REVE,
        model_dir,
        &[
            "heads/head_a_vig_reve_linear.f32bin",
            "heads/head_a_vig_reve_linear.pt",
        ],
        REVE_DIM,
    ) {
        out.push(d);
    }
    if let Ok(d) = try_load_named(
        ID_WAKE_LIGHT_REVE,
        model_dir,
        &[
            "heads/head_c_wake_light_reve_linear.f32bin",
            "heads/head_c_wake_light_reve_linear.pt",
        ],
        REVE_DIM,
    ) {
        out.push(d);
    }

    for root in pack_roots {
        let a = root.join(PACK_REVE_A_VIG);
        if a.is_dir() && !is_head_loaded(ID_A_VIG_REVE) {
            out.push(load_pack(ID_A_VIG_REVE, &a)?);
        }
        let c = root.join(PACK_REVE_WAKE_LIGHT);
        if c.is_dir() && !is_head_loaded(ID_WAKE_LIGHT_REVE) {
            out.push(load_pack(ID_WAKE_LIGHT_REVE, &c)?);
        }
    }
    Ok(out)
}

fn try_load_named(
    feature_id: &str,
    dir: &Path,
    rels: &[&str],
    in_dim: usize,
) -> anyhow::Result<String> {
    for rel in rels {
        let p = dir.join(rel);
        if p.is_file() {
            let head = if p.extension().and_then(|e| e.to_str()) == Some("f32bin") {
                load_head_f32bin(&p, in_dim, N_CLASSES)?
            } else {
                load_head_pt_zip(&p, in_dim, N_CLASSES)?
            };
            let pack_id = dir
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("model")
                .to_string();
            let id = canonical_feature_id(feature_id).to_string();
            let desc = format!(
                "{id} ← {pack_id} ({in_dim}→{N_CLASSES}) from {}",
                p.display()
            );
            let mut head = head;
            head.pack_id = pack_id;
            head.feature_id = id.clone();
            lock().heads.insert(id, head);
            log::info!("[ai_heads] loaded: {desc}");
            return Ok(desc);
        }
    }
    bail!(
        "no head file for {feature_id} under {} (tried {})",
        dir.display(),
        rels.join(", ")
    )
}

fn load_head_from_dir(
    dir: &Path,
    in_dim: usize,
    n_classes: usize,
    feature_id: &str,
) -> anyhow::Result<(PathBuf, LinearHead)> {
    let mut f32s = Vec::new();
    let mut pts = Vec::new();
    let heads = dir.join("heads");
    let search = if heads.is_dir() {
        heads
    } else {
        dir.to_path_buf()
    };
    if search.is_dir() {
        for ent in fs::read_dir(&search)? {
            let ent = ent?;
            let p = ent.path();
            let name = p.file_name().and_then(|s| s.to_str()).unwrap_or("");
            if name.ends_with(".f32bin") {
                f32s.push(p);
            } else if name.ends_with(".pt") {
                pts.push(p);
            }
        }
    }
    if let Some(p) = f32s.into_iter().next() {
        return Ok((p.clone(), load_head_f32bin(&p, in_dim, n_classes)?));
    }
    if let Some(p) = pts.into_iter().next() {
        return Ok((p.clone(), load_head_pt_zip(&p, in_dim, n_classes)?));
    }
    bail!(
        "no head .f32bin/.pt for {feature_id} under {}",
        dir.display()
    )
}

fn load_head_f32bin(path: &Path, in_dim: usize, n_classes: usize) -> anyhow::Result<LinearHead> {
    if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
        if let Some((_, expect)) = F32BIN_SHA256.iter().find(|(n, _)| *n == name) {
            let hex = file_sha256(path)?;
            anyhow::ensure!(
                &hex == expect,
                "head f32bin SHA mismatch for {name}\nGot      {hex}\nExpected {expect}"
            );
        }
    }
    let bytes = fs::read(path).with_context(|| format!("read {}", path.display()))?;
    let expect = (n_classes * in_dim + n_classes) * 4;
    anyhow::ensure!(
        bytes.len() == expect,
        "f32bin size {} != {expect} for {}",
        bytes.len(),
        path.display()
    );
    let mut floats = Vec::with_capacity(bytes.len() / 4);
    for chunk in bytes.chunks_exact(4) {
        floats.push(f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
    }
    let (w, b) = floats.split_at(n_classes * in_dim);
    Ok(LinearHead {
        in_dim,
        n_classes,
        weight: w.to_vec(),
        bias: b.to_vec(),
        pack_id: String::new(),
        feature_id: String::new(),
    })
}

fn load_head_pt_zip(path: &Path, in_dim: usize, n_classes: usize) -> anyhow::Result<LinearHead> {
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
    anyhow::ensure!(
        w.len() == in_dim * n_classes * 4,
        "weight bytes {}",
        w.len()
    );
    anyhow::ensure!(b.len() == n_classes * 4, "bias bytes {}", b.len());
    let mut weight = Vec::with_capacity(in_dim * n_classes);
    for chunk in w.chunks_exact(4) {
        weight.push(f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
    }
    let mut bias = Vec::with_capacity(n_classes);
    for chunk in b.chunks_exact(4) {
        bias.push(f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
    }
    Ok(LinearHead {
        in_dim,
        n_classes,
        weight,
        bias,
        pack_id: String::new(),
        feature_id: String::new(),
    })
}

/// Apply the head for [feature_id] to [emb].
///
/// Returns `(logits, probs, pred_class, score)` where:
/// - `pred_class` = argmax(logits) (eval / debug)
/// - `score` = **P(class 1)** — P(hypnagogic) for A-vig, P(light) for wake/light.
///   This continuous scalar is what `FeatureDto.value` carries so guardrail
///   percentile thresholds stay meaningful (do not emit argmax 0/1 as the DTO).
pub fn apply_feature(
    feature_id: &str,
    emb: &[f32],
) -> anyhow::Result<(Vec<f32>, Vec<f32>, usize, f32)> {
    let id = canonical_feature_id(feature_id);
    let guard = lock();
    let head = guard
        .heads
        .get(id)
        .with_context(|| format!("no head loaded for {feature_id} (canonical {id})"))?;
    let logits = head.forward(emb)?;
    let probs = softmax(&logits);
    let pred = argmax(&logits);
    let score = probs.get(1).copied().unwrap_or(0.0);
    anyhow::ensure!(score.is_finite(), "non-finite score for {id}");
    Ok((logits, probs, pred, score))
}

/// Whether [feature_id] is backed by the CBraMod encoder (needs native forward).
pub fn is_cbramod_backed(feature_id: &str) -> bool {
    matches!(canonical_feature_id(feature_id), ID_A_VIG | ID_WAKE_LIGHT)
}

/// Whether [feature_id] is backed by REVE (gated base + subsample heads).
pub fn is_reve_backed(feature_id: &str) -> bool {
    matches!(
        canonical_feature_id(feature_id),
        ID_A_VIG_REVE | ID_WAKE_LIGHT_REVE
    )
}

/// Score every loaded head whose embedding dim matches [emb].
/// Returns `(feature_id, P(class1))` pairs — never argmax, never cross-encoder.
pub fn score_matching_heads(emb: &[f32]) -> Vec<(String, f32)> {
    let guard = lock();
    let mut out = Vec::new();
    for (id, head) in guard.heads.iter() {
        // Dim gate keeps CBraMod (200) and REVE (512) packs on their own encoder.
        if head.in_dim != emb.len() {
            continue;
        }
        if let Ok(logits) = head.forward(emb) {
            let probs = softmax(&logits);
            if let Some(s) = probs.get(1).copied() {
                if s.is_finite() {
                    out.push((id.clone(), s));
                }
            }
        }
    }
    out
}

/// Asset-pack roots used by unit tests (repo `assets/packs`).
pub fn bundled_packs_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../assets/packs")
}

#[cfg(test)]
mod tests {
    use super::*;

    static TEST_LOCK: Mutex<()> = Mutex::new(());

    fn load_all_bundled() -> std::sync::MutexGuard<'static, ()> {
        let lock = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        unload_all();
        let root = bundled_packs_root();
        load_pack(ID_A_VIG, &root.join(PACK_CBRAMOD_A_VIG)).unwrap();
        load_pack(ID_WAKE_LIGHT, &root.join(PACK_CBRAMOD_WAKE_LIGHT)).unwrap();
        load_pack(ID_A_VIG_REVE, &root.join(PACK_REVE_A_VIG)).unwrap();
        load_pack(ID_WAKE_LIGHT_REVE, &root.join(PACK_REVE_WAKE_LIGHT)).unwrap();
        lock
    }

    #[test]
    fn alias_canonicalizes_drowsiness() {
        assert_eq!(canonical_feature_id(ID_DROWSINESS_ALIAS), ID_A_VIG);
        assert_eq!(canonical_feature_id(ID_A_VIG), ID_A_VIG);
    }

    #[test]
    fn each_feature_id_scores_finite_from_synthetic_emb() {
        let _lock = load_all_bundled();
        let cbramod_emb = vec![0.01f32; CBRAMOD_DIM];
        let reve_emb = vec![0.01f32; REVE_DIM];

        for id in [ID_A_VIG, ID_WAKE_LIGHT, ID_DROWSINESS_ALIAS] {
            let (logits, probs, pred, score) = apply_feature(id, &cbramod_emb).unwrap();
            assert_eq!(logits.len(), 2, "{id}");
            assert_eq!(probs.len(), 2, "{id}");
            assert!(pred == 0 || pred == 1, "{id}");
            assert!(score.is_finite(), "{id} score={score}");
            assert!((0.0..=1.0).contains(&score), "{id} score={score}");
        }
        for id in [ID_A_VIG_REVE, ID_WAKE_LIGHT_REVE] {
            let (_, _, _, score) = apply_feature(id, &reve_emb).unwrap();
            assert!(score.is_finite(), "{id} score={score}");
            assert!((0.0..=1.0).contains(&score), "{id} score={score}");
        }

        // Wrong dim fails clearly.
        assert!(apply_feature(ID_A_VIG, &reve_emb).is_err());
        unload_all();
    }

    #[test]
    fn load_cbramod_model_dir_picks_a_vig_and_head_c() {
        let _lock = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        unload_all();
        let dir = bundled_packs_root().join(PACK_CBRAMOD_A_VIG);
        let descs = load_cbramod_model_dir(&dir).unwrap();
        assert!(descs.iter().any(|d| d.contains(ID_A_VIG)));
        assert!(is_head_loaded(ID_A_VIG));
        assert!(
            is_head_loaded(ID_WAKE_LIGHT),
            "mirrored head_c should load from a-vig-full pack"
        );
        let emb = vec![0.0f32; CBRAMOD_DIM];
        let scores = score_matching_heads(&emb);
        assert!(scores.len() >= 2);
        for (id, s) in scores {
            assert!(s.is_finite(), "{id}");
        }
        unload_all();
    }

    #[test]
    fn reve_embedding_does_not_score_cbramod_ids() {
        let _lock = load_all_bundled();
        let reve_emb = vec![0.01f32; REVE_DIM];
        let scores = score_matching_heads(&reve_emb);
        assert!(!scores.is_empty());
        for (id, s) in &scores {
            assert!(is_reve_backed(id), "unexpected id {id}");
            assert!((0.0..=1.0).contains(s));
        }
        assert!(!scores.iter().any(|(id, _)| is_cbramod_backed(id)));
        unload_all();
    }

    #[test]
    fn feature_dto_score_is_p_class1_not_argmax() {
        let _lock = load_all_bundled();
        let emb = vec![0.01f32; CBRAMOD_DIM];
        let (logits, probs, pred, score) = apply_feature(ID_A_VIG, &emb).unwrap();
        assert_eq!(score, probs[1], "FeatureDto scalar must be P(class1)");
        assert!((0.0..=1.0).contains(&score));
        assert!(pred == 0 || pred == 1);
        // Argmax class index is not the live FeatureDto value (unless by chance
        // P≈0/1 exactly — still assert we publish the probability field).
        assert_eq!(probs.len(), 2);
        assert_eq!(logits.len(), 2);
        unload_all();
    }

    #[test]
    fn missing_pack_path_errors_with_real_path() {
        let _lock = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        unload_all();
        let bogus = PathBuf::from("/tmp/neurofeed-missing-pack-xyz");
        let err = load_pack(ID_A_VIG, &bogus).unwrap_err().to_string();
        assert!(
            err.contains("neurofeed-missing-pack-xyz") || err.contains("no head"),
            "err={err}"
        );
    }
}

fn file_sha256(path: &Path) -> anyhow::Result<String> {
    use sha2::{Digest, Sha256};
    use std::io::Read;
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}
