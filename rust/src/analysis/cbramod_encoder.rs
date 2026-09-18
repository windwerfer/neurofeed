//! Frozen CBraMod encoder forward (Candle CPU).
//!
//! Architecture mirrors `muse-eeg-heads` `cbramod_backbone.py` + criss-cross
//! layers: PatchEmbedding → 12× TransformerEncoderLayer → Linear proj_out.
//! Weights load from `pretrained_weights.pth` via candle pickle (or
//! `pretrained_weights.safetensors` if present). Mean-pool over (C, S) → 200-d.

use std::collections::HashMap;
use std::path::Path;
use std::sync::Mutex;

use anyhow::{bail, Context};
use candle_core::{DType, Device, Tensor};
use candle_nn::{GroupNorm, Linear, Module};
use rustfft::{num_complex::Complex, FftPlanner};

const D_MODEL: usize = 200;
const N_LAYER: usize = 12;
const N_HEAD: usize = 8;
const HALF: usize = D_MODEL / 2;
const FF: usize = 800;
const PATCH: usize = 200;
const SPEC_BINS: usize = 101;
const EPS: f64 = 1e-5;

pub struct CbramodEncoder {
    device: Device,
    patch: PatchEmbedding,
    layers: Vec<CrissCrossLayer>,
    proj_out: Linear,
}

struct PatchEmbedding {
    pos_w: Tensor,
    pos_b: Tensor,
    proj0_w: Tensor,
    proj0_b: Tensor,
    gn0: GroupNorm,
    proj1_w: Tensor,
    proj1_b: Tensor,
    gn1: GroupNorm,
    proj2_w: Tensor,
    proj2_b: Tensor,
    gn2: GroupNorm,
    spectral: Linear,
}

struct Mha {
    in_w: Tensor,
    in_b: Tensor,
    out_w: Tensor,
    out_b: Tensor,
    n_head: usize,
    head_dim: usize,
}

struct CrissCrossLayer {
    attn_s: Mha,
    attn_t: Mha,
    linear1: Linear,
    linear2: Linear,
    norm1_w: Tensor,
    norm1_b: Tensor,
    norm2_w: Tensor,
    norm2_b: Tensor,
}

fn tget(map: &HashMap<String, Tensor>, key: &str) -> anyhow::Result<Tensor> {
    map.get(key)
        .cloned()
        .with_context(|| format!("missing weight {key}"))
}

fn load_weight_map(path: &Path) -> anyhow::Result<HashMap<String, Tensor>> {
    let name = path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if name.ends_with(".safetensors") {
        let data = candle_core::safetensors::load(path, &Device::Cpu)
            .map_err(|e| anyhow::anyhow!("safetensors load: {e}"))?;
        return Ok(data);
    }
    let pth = candle_core::pickle::PthTensors::new(path, None)
        .map_err(|e| anyhow::anyhow!("pth open: {e}"))?;
    let mut out = HashMap::new();
    for key in pth.tensor_infos().keys() {
        if let Some(t) = pth
            .get(key)
            .map_err(|e| anyhow::anyhow!("pth get {key}: {e}"))?
        {
            out.insert(key.clone(), t);
        }
    }
    if out.is_empty() {
        bail!("no tensors in {}", path.display());
    }
    Ok(out)
}

impl CbramodEncoder {
    pub fn load(path: &Path) -> anyhow::Result<Self> {
        let device = Device::Cpu;
        let map = load_weight_map(path)?;
        anyhow::ensure!(
            map.len() >= 200,
            "expected ~211 CBraMod tensors, got {}",
            map.len()
        );

        let patch = PatchEmbedding {
            pos_w: tget(&map, "patch_embedding.positional_encoding.0.weight")?,
            pos_b: tget(&map, "patch_embedding.positional_encoding.0.bias")?,
            proj0_w: tget(&map, "patch_embedding.proj_in.0.weight")?,
            proj0_b: tget(&map, "patch_embedding.proj_in.0.bias")?,
            gn0: GroupNorm::new(
                tget(&map, "patch_embedding.proj_in.1.weight")?,
                tget(&map, "patch_embedding.proj_in.1.bias")?,
                25,
                5,
                EPS,
            )
            .map_err(|e| anyhow::anyhow!("{e}"))?,
            proj1_w: tget(&map, "patch_embedding.proj_in.3.weight")?,
            proj1_b: tget(&map, "patch_embedding.proj_in.3.bias")?,
            gn1: GroupNorm::new(
                tget(&map, "patch_embedding.proj_in.4.weight")?,
                tget(&map, "patch_embedding.proj_in.4.bias")?,
                25,
                5,
                EPS,
            )
            .map_err(|e| anyhow::anyhow!("{e}"))?,
            proj2_w: tget(&map, "patch_embedding.proj_in.6.weight")?,
            proj2_b: tget(&map, "patch_embedding.proj_in.6.bias")?,
            gn2: GroupNorm::new(
                tget(&map, "patch_embedding.proj_in.7.weight")?,
                tget(&map, "patch_embedding.proj_in.7.bias")?,
                25,
                5,
                EPS,
            )
            .map_err(|e| anyhow::anyhow!("{e}"))?,
            spectral: Linear::new(
                tget(&map, "patch_embedding.spectral_proj.0.weight")?,
                Some(tget(&map, "patch_embedding.spectral_proj.0.bias")?),
            ),
        };

        let mut layers = Vec::with_capacity(N_LAYER);
        for i in 0..N_LAYER {
            let p = format!("encoder.layers.{i}");
            layers.push(CrissCrossLayer {
                attn_s: Mha::load(&map, &format!("{p}.self_attn_s"), N_HEAD / 2)?,
                attn_t: Mha::load(&map, &format!("{p}.self_attn_t"), N_HEAD / 2)?,
                linear1: Linear::new(
                    tget(&map, &format!("{p}.linear1.weight"))?,
                    Some(tget(&map, &format!("{p}.linear1.bias"))?),
                ),
                linear2: Linear::new(
                    tget(&map, &format!("{p}.linear2.weight"))?,
                    Some(tget(&map, &format!("{p}.linear2.bias"))?),
                ),
                norm1_w: tget(&map, &format!("{p}.norm1.weight"))?,
                norm1_b: tget(&map, &format!("{p}.norm1.bias"))?,
                norm2_w: tget(&map, &format!("{p}.norm2.weight"))?,
                norm2_b: tget(&map, &format!("{p}.norm2.bias"))?,
            });
        }

        let proj_out = Linear::new(
            tget(&map, "proj_out.0.weight")?,
            Some(tget(&map, "proj_out.0.bias")?),
        );

        let _ = FF;
        Ok(Self {
            device,
            patch,
            layers,
            proj_out,
        })
    }

    /// patches: flattened `[C * n_patches * 200]` for one window (batch=1).
    pub fn encode_mean_pool(
        &self,
        patches_flat: &[f32],
        n_channels: usize,
        n_patches: usize,
    ) -> anyhow::Result<Vec<f32>> {
        anyhow::ensure!(
            patches_flat.len() == n_channels * n_patches * PATCH,
            "patches len {} != {n_channels}*{n_patches}*{PATCH}",
            patches_flat.len()
        );
        let x = Tensor::from_slice(
            patches_flat,
            (1usize, n_channels, n_patches, PATCH),
            &self.device,
        )
        .map_err(|e| anyhow::anyhow!("{e}"))?;
        let feats = self.forward_patches(&x)?;
        // (1, C, S, D) → mean over C,S → (1, D)
        let emb = feats
            .mean(1)?
            .mean(1)?
            .squeeze(0)
            .map_err(|e| anyhow::anyhow!("{e}"))?;
        emb.to_vec1::<f32>()
            .map_err(|e| anyhow::anyhow!("emb to_vec: {e}"))
    }

    fn forward_patches(&self, x: &Tensor) -> anyhow::Result<Tensor> {
        let mut h = self.patch.forward(x)?;
        for layer in &self.layers {
            h = layer.forward(&h)?;
        }
        self.proj_out
            .forward(&h)
            .map_err(|e| anyhow::anyhow!("proj_out: {e}"))
    }
}

impl Mha {
    fn load(map: &HashMap<String, Tensor>, prefix: &str, n_head: usize) -> anyhow::Result<Self> {
        let in_w = tget(map, &format!("{prefix}.in_proj_weight"))?;
        let dims = in_w.dims();
        anyhow::ensure!(dims.len() == 2 && dims[0] == 3 * HALF && dims[1] == HALF);
        Ok(Self {
            in_w,
            in_b: tget(map, &format!("{prefix}.in_proj_bias"))?,
            out_w: tget(map, &format!("{prefix}.out_proj.weight"))?,
            out_b: tget(map, &format!("{prefix}.out_proj.bias"))?,
            n_head,
            head_dim: HALF / n_head,
        })
    }

    /// x: (B, L, E) batch_first, E=HALF
    fn forward(&self, x: &Tensor) -> anyhow::Result<Tensor> {
        let (b, l, e) = x.dims3().map_err(|e| anyhow::anyhow!("{e}"))?;
        anyhow::ensure!(e == HALF);
        let flat = x.reshape((b * l, e))?;
        let qkv = flat
            .matmul(&self.in_w.t()?)?
            .broadcast_add(&self.in_b)?;
        let qkv = qkv.reshape((b, l, 3, self.n_head, self.head_dim))?;
        let qkv = qkv.permute((2, 0, 3, 1, 4))?; // (3, B, H, L, D)
        let q = qkv.get(0)?;
        let k = qkv.get(1)?;
        let v = qkv.get(2)?;
        let scale = (self.head_dim as f64).sqrt();
        let k_t = k.transpose(2, 3)?;
        let scores = (q.matmul(&k_t)? / scale)?;
        let attn = candle_nn::ops::softmax_last_dim(&scores)?;
        let ctx = attn.matmul(&v)?; // (B, H, L, D)
        let ctx = ctx.transpose(1, 2)?.contiguous()?.reshape((b, l, e))?;
        let out = ctx
            .reshape((b * l, e))?
            .matmul(&self.out_w.t()?)?
            .broadcast_add(&self.out_b)?
            .reshape((b, l, e))?;
        Ok(out)
    }
}

impl CrissCrossLayer {
    fn layer_norm(x: &Tensor, w: &Tensor, b: &Tensor) -> anyhow::Result<Tensor> {
        let x_dtype = x.dtype();
        let x = x.to_dtype(DType::F32)?;
        let mean = x.mean_keepdim(candle_core::D::Minus1)?;
        let x0 = x.broadcast_sub(&mean)?;
        let var = x0.sqr()?.mean_keepdim(candle_core::D::Minus1)?;
        let x_hat = x0.broadcast_div(&(var + EPS)?.sqrt()?)?;
        let y = x_hat
            .to_dtype(x_dtype)?
            .broadcast_mul(w)?
            .broadcast_add(b)?;
        Ok(y)
    }

    fn forward(&self, src: &Tensor) -> anyhow::Result<Tensor> {
        let x = Self::layer_norm(src, &self.norm1_w, &self.norm1_b)?;
        let sa = self.sa_block(&x)?;
        let x = (src + sa)?;
        let y = Self::layer_norm(&x, &self.norm2_w, &self.norm2_b)?;
        let ff = self
            .linear2
            .forward(&self.linear1.forward(&y)?.gelu_erf()?)?;
        Ok((x + ff)?)
    }

    fn sa_block(&self, x: &Tensor) -> anyhow::Result<Tensor> {
        let (bz, ch_num, patch_num, d) = x.dims4().map_err(|e| anyhow::anyhow!("{e}"))?;
        anyhow::ensure!(d == D_MODEL);
        let xs = x.narrow(3, 0, HALF)?;
        let xt = x.narrow(3, HALF, HALF)?;
        // spatial: (bz*patch, ch, half)
        let xs = xs
            .transpose(1, 2)?
            .contiguous()?
            .reshape((bz * patch_num, ch_num, HALF))?;
        let xs = self.attn_s.forward(&xs)?;
        let xs = xs
            .reshape((bz, patch_num, ch_num, HALF))?
            .transpose(1, 2)?;
        // temporal: (bz*ch, patch, half)
        let xt = xt.contiguous()?.reshape((bz * ch_num, patch_num, HALF))?;
        let xt = self.attn_t.forward(&xt)?;
        let xt = xt.reshape((bz, ch_num, patch_num, HALF))?;
        Tensor::cat(&[&xs, &xt], 3).map_err(|e| anyhow::anyhow!("{e}"))
    }
}

impl PatchEmbedding {
    fn forward(&self, x: &Tensor) -> anyhow::Result<Tensor> {
        let (bz, ch_num, patch_num, patch_size) =
            x.dims4().map_err(|e| anyhow::anyhow!("{e}"))?;
        anyhow::ensure!(patch_size == PATCH);
        // (B, 1, C*S, P)
        let mask_x = x
            .contiguous()?
            .reshape((bz, 1, ch_num * patch_num, patch_size))?;

        let mut patch_emb = conv2d_1d_along_w(
            &mask_x,
            &self.proj0_w,
            &self.proj0_b,
            /*pad_w*/ 24,
            /*stride_w*/ 25,
        )?;
        patch_emb = self.gn0.forward(&patch_emb)?.gelu_erf()?;
        patch_emb = conv2d_1d_along_w(&patch_emb, &self.proj1_w, &self.proj1_b, 1, 1)?;
        patch_emb = self.gn1.forward(&patch_emb)?.gelu_erf()?;
        patch_emb = conv2d_1d_along_w(&patch_emb, &self.proj2_w, &self.proj2_b, 1, 1)?;
        patch_emb = self.gn2.forward(&patch_emb)?.gelu_erf()?;
        // (B, 25, C*S, 8) → (B, C*S, 25, 8) → (B, C, S, 200)
        patch_emb = patch_emb
            .permute((0, 2, 1, 3))?
            .contiguous()?
            .reshape((bz, ch_num, patch_num, D_MODEL))?;

        let spectral = rfft_abs_forward_norm(x)?; // (B, C, S, 101)
        let spectral_emb = self.spectral.forward(&spectral)?;
        let patch_emb = (patch_emb + spectral_emb)?;

        // positional: depthwise conv2d k=(19,7) pad=(9,3) groups=200
        let pos_in = patch_emb.permute((0, 3, 1, 2))?; // (B, D, C, S)
        let pos_in = pos_in
            .pad_with_zeros(2, 9, 9)?
            .pad_with_zeros(3, 3, 3)?;
        let pos = pos_in.conv2d(&self.pos_w, 0, 1, 1, D_MODEL)?;
        let pos = pos.broadcast_add(&self.pos_b.reshape((1, D_MODEL, 1, 1))?)?;
        let pos = pos.permute((0, 2, 3, 1))?;
        Ok((patch_emb + pos)?)
    }
}

/// Conv2d with kernel height 1 → Conv1d on width after reshape.
fn conv2d_1d_along_w(
    x: &Tensor,
    weight: &Tensor,
    bias: &Tensor,
    pad_w: usize,
    stride_w: usize,
) -> anyhow::Result<Tensor> {
    let (n, c_in, h, _w) = x.dims4().map_err(|e| anyhow::anyhow!("{e}"))?;
    let (c_out, c_per_g, k_h, k_w) = weight.dims4().map_err(|e| anyhow::anyhow!("{e}"))?;
    anyhow::ensure!(k_h == 1, "expected kH=1, got {k_h}");
    anyhow::ensure!(c_per_g * 1 == c_in || c_per_g == c_in / 1);
    let x = if pad_w > 0 {
        x.pad_with_zeros(3, pad_w, pad_w)?
    } else {
        x.clone()
    };
    let w_pad = x.dim(3)?;
    let x = x.permute((0, 2, 1, 3))?.contiguous()?.reshape((n * h, c_in, w_pad))?;
    let kern = weight.reshape((c_out, c_per_g, k_w))?;
    let y = x.conv1d(&kern, 0, stride_w, 1, 1)?;
    let y = y.broadcast_add(&bias.reshape((1, c_out, 1))?)?;
    let w_out = y.dim(2)?;
    Ok(y.reshape((n, h, c_out, w_out))?.permute((0, 2, 1, 3))?.contiguous()?)
}

fn rfft_abs_forward_norm(x: &Tensor) -> anyhow::Result<Tensor> {
    // x: (B, C, S, P=200) → abs(rfft)/P → (B, C, S, 101)
    let (b, c, s, p) = x.dims4().map_err(|e| anyhow::anyhow!("{e}"))?;
    anyhow::ensure!(p == PATCH);
    let flat = x
        .contiguous()?
        .flatten_all()?
        .to_vec1::<f32>()
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    let n_rows = b * c * s;
    let mut out = vec![0f32; n_rows * SPEC_BINS];
    let mut planner = FftPlanner::<f32>::new();
    let fft = planner.plan_fft_forward(p);
    let mut buf = vec![Complex::new(0.0, 0.0); p];
    let scale = 1.0f32 / p as f32;
    for row in 0..n_rows {
        let src = &flat[row * p..(row + 1) * p];
        for i in 0..p {
            buf[i] = Complex::new(src[i], 0.0);
        }
        fft.process(&mut buf);
        let dest = &mut out[row * SPEC_BINS..(row + 1) * SPEC_BINS];
        for k in 0..SPEC_BINS {
            dest[k] = buf[k].norm() * scale;
        }
    }
    Tensor::from_vec(out, (b, c, s, SPEC_BINS), &Device::Cpu)
        .map_err(|e| anyhow::anyhow!("{e}"))
}

static ENCODER: Mutex<Option<CbramodEncoder>> = Mutex::new(None);

pub fn load_into_global(path: &Path) -> anyhow::Result<()> {
    let enc = CbramodEncoder::load(path)?;
    *ENCODER.lock().unwrap_or_else(|e| e.into_inner()) = Some(enc);
    Ok(())
}

pub fn unload_global() {
    *ENCODER.lock().unwrap_or_else(|e| e.into_inner()) = None;
}

pub fn is_loaded() -> bool {
    ENCODER.lock().unwrap_or_else(|e| e.into_inner()).is_some()
}

pub fn encode_mean_pool_global(
    patches_flat: &[f32],
    n_channels: usize,
    n_patches: usize,
) -> anyhow::Result<Vec<f32>> {
    let guard = ENCODER.lock().unwrap_or_else(|e| e.into_inner());
    let enc = guard.as_ref().context("CBraMod encoder not loaded")?;
    enc.encode_mean_pool(patches_flat, n_channels, n_patches)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn fixture_pth() -> Option<PathBuf> {
        let candidates = [
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../.local/cbramod-fixtures/pretrained_weights.pth"),
            PathBuf::from(
                "/workspace/muse-eeg-heads/kaggle_datasets/muse-eeg-heads-cache/models/CBraMod/pretrained_weights.pth",
            ),
        ];
        candidates.into_iter().find(|p| p.is_file())
    }

    #[test]
    fn load_and_forward_shapes() {
        let Some(path) = fixture_pth() else {
            eprintln!("skip: no pretrained_weights.pth fixture");
            return;
        };
        let enc = CbramodEncoder::load(&path).expect("load");
        let patches = vec![0.1f32; 4 * 2 * PATCH];
        let emb = enc.encode_mean_pool(&patches, 4, 2).expect("forward");
        assert_eq!(emb.len(), D_MODEL);
        assert!(emb.iter().all(|v| v.is_finite()));
    }

    #[test]
    fn matches_python_const01_embedding() {
        let Some(path) = fixture_pth() else {
            eprintln!("skip: no pretrained_weights.pth fixture");
            return;
        };
        let ref_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../.local/cbramod-fixtures/ref_emb_const01.npy");
        if !ref_path.is_file() {
            eprintln!("skip: no ref_emb_const01.npy");
            return;
        }
        // Minimal npy f32 reader (C-order, little-endian header).
        let bytes = std::fs::read(&ref_path).unwrap();
        let emb_ref = parse_npy_f32_1d(&bytes);
        assert_eq!(emb_ref.len(), D_MODEL);

        let enc = CbramodEncoder::load(&path).expect("load");
        // Python path: const 0.1 @ 256Hz 4×512 → patches then encode.
        // Use the saved patches fixture when present.
        let patches_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../.local/cbramod-fixtures/ref_patches_const01.npy");
        let patches = if patches_path.is_file() {
            let b = std::fs::read(&patches_path).unwrap();
            parse_npy_f32_flat(&b)
        } else {
            vec![0.1f32; 4 * 2 * PATCH]
        };
        assert_eq!(patches.len(), 4 * 2 * PATCH);
        let emb = enc.encode_mean_pool(&patches, 4, 2).expect("forward");
        let mut max_abs = 0f32;
        let mut sum_sq = 0f64;
        for (a, b) in emb.iter().zip(emb_ref.iter()) {
            let d = (a - b).abs();
            max_abs = max_abs.max(d);
            sum_sq += (d as f64) * (d as f64);
        }
        let rmse = (sum_sq / D_MODEL as f64).sqrt();
        eprintln!("const01 max_abs={max_abs} rmse={rmse}");
        assert!(
            max_abs < 2e-3 && rmse < 5e-4,
            "embedding drift max_abs={max_abs} rmse={rmse}"
        );
    }

    fn parse_npy_f32_1d(bytes: &[u8]) -> Vec<f32> {
        parse_npy_f32_flat(bytes)
    }

    fn parse_npy_f32_flat(bytes: &[u8]) -> Vec<f32> {
        assert_eq!(&bytes[0..6], b"\x93NUMPY");
        let header_len = u16::from_le_bytes([bytes[8], bytes[9]]) as usize;
        let data = &bytes[10 + header_len..];
        let mut out = Vec::with_capacity(data.len() / 4);
        for chunk in data.chunks_exact(4) {
            out.push(f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
        }
        out
    }
}
