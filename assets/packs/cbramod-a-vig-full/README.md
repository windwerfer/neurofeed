# Pack: cbramod-a-vig-full (Spur A)

Frozen **CBraMod** encoder + full-corpus **A-vig** linear head (`drowsy` / `hypnagogic`).

## Enable in the app

1. Select **CBraMod A-vig** as the Guardrail AI engine (default when this pack is present).
2. Head files are bundled under `assets/packs/cbramod-a-vig-full/` and copied into
   `<sessionFolder>/ai_models/cbramod_a_vig/` on first install.
3. Download the encoder (~20 MB Apache-2.0) from Hugging Face
   `weighting666/CBraMod` → `pretrained_weights.pth`, or place a cache copy at
   that model directory. SHA-256 must match `encoder/EXPECTED.json`:
   `0792cb808c14e6b7a2bb2ce1dff379bc47bc54c49a779825bdfeb33bf8157178`.
4. Window contract: **2 s @ 256 Hz** (512 samples) Muse AF7/AF8/TP9/TP10 →
   resample/patch → mean-pool → HeadALinear → **argmax** (not the older 0.53
   precision-tuned threshold).

## Files

| Path | Role |
|------|------|
| `heads/head_a_vig_linear.pt` | Torch state_dict (net.1.weight/bias) |
| `heads/head_a_vig_linear.f32bin` | Same weights as raw f32 (400+2) for Rust |
| `pack_manifest.json` | Pack id + decode policy |
| `app_integration.json` | App contract |
| `encoder/EXPECTED.json` | Encoder pin only (no `.pth` in git) |

Encoder forward still requires a native backend follow-up; this pack wires load,
SHA pin, head apply, and guardrail kind selection.
