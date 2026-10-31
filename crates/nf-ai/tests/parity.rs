//! Parity with the Python reference (CBraMod) and REVE smoke + timing on the
//! real weights. Skips when the local fixtures are absent (`NF_AI_FIXTURES`,
//! `NF_AI_REVE_DIR`).
#![allow(clippy::unwrap_used, clippy::expect_used)]

use nf_ai::{heads, Model};
use nf_types::AiModel;
use std::path::PathBuf;
use std::time::Instant;

fn fixtures() -> Option<PathBuf> {
    let d = std::env::var_os("NF_AI_FIXTURES").map_or_else(|| PathBuf::from("/workspace/neurofeed/.local/cbramod-fixtures"), PathBuf::from);
    d.join("pretrained_weights.pth").is_file().then_some(d)
}

fn npy_f32(p: &std::path::Path) -> Vec<f32> {
    let b = std::fs::read(p).unwrap();
    assert_eq!(&b[..6], b"\x93NUMPY");
    let h = u16::from_le_bytes([b[8], b[9]]) as usize;
    b[10 + h..].as_chunks::<4>().0.iter().map(|c| f32::from_le_bytes(*c)).collect()
}

#[test]
fn cbramod_matches_python_reference() {
    let Some(d) = fixtures() else { return eprintln!("skip: no CBraMod fixtures") };
    let dir = std::env::temp_dir().join(format!("nf-ai-par-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::copy(d.join("pretrained_weights.pth"), dir.join("pretrained_weights.pth")).unwrap();
    let (mut m, desc) = Model::load(AiModel::CbramodAVig, &dir).unwrap();
    eprintln!("{desc}");
    let input = npy_f32(&d.join("ref_input_const01.npy"));
    let want = npy_f32(&d.join("ref_emb_const01.npy"));
    let t0 = Instant::now();
    let got = m.embed(&input, 512).unwrap();
    eprintln!("cbramod window: {:.1} ms", t0.elapsed().as_secs_f64() * 1e3);
    let (mut max_abs, mut ss) = (0f32, 0f64);
    for (a, b) in got.iter().zip(&want) {
        max_abs = max_abs.max((a - b).abs());
        ss += f64::from(a - b).powi(2);
    }
    let rmse = (ss / want.len() as f64).sqrt();
    eprintln!("const01 max_abs={max_abs:.2e} rmse={rmse:.2e}");
    assert!(max_abs < 2e-3 && rmse < 5e-4, "drift max_abs={max_abs} rmse={rmse}");
    let scores = heads::score_all(&heads::for_model(AiModel::CbramodAVig).unwrap(), &got);
    eprintln!("heads: {scores:?}");
    assert!(scores.iter().all(|(_, p)| (0.0..=1.0).contains(p)));
    std::fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn reve_runs_on_the_real_weights() {
    let dir = std::env::var_os("NF_AI_REVE_DIR").map_or_else(
        || PathBuf::from("/workspace/muse-eeg-heads/kaggle_datasets/muse-eeg-heads-crown-vig/models/reve-base"),
        PathBuf::from,
    );
    if !dir.join("model.safetensors").is_file() {
        return eprintln!("skip: no REVE weights");
    }
    let (mut m, desc) = Model::load(AiModel::ReveBase, &dir).unwrap();
    eprintln!("{desc}");
    let n = AiModel::ReveBase.window_samples();
    let sig: Vec<f32> = (0..4 * n).map(|i| (i as f32 * 0.05).sin() * 10.0).collect();
    let t0 = Instant::now();
    let emb = m.embed(&sig, n).unwrap();
    eprintln!("reve window: {:.1} ms, dim {}", t0.elapsed().as_secs_f64() * 1e3, emb.len());
    assert_eq!(emb.len(), 512);
    assert!(emb.iter().all(|v| v.is_finite()));
    let scores = heads::score_all(&heads::for_model(AiModel::ReveBase).unwrap(), &emb);
    eprintln!("heads: {scores:?}");
    assert_eq!(scores.len(), 2);
}
