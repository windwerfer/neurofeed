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
   resample/patch → mean-pool → HeadALinear → softmax. Live **FeatureDto.value
   is P(hypnagogic)** (class 1) for guardrail percentiles; argmax remains the
   offline eval decode (not the older 0.53 precision-tuned threshold).

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


## Feature IDs

| ID | Head |
|----|------|
| `ai.a_vig` | A-vig (primary sleep/drowsy) |
| `ai.wake_light` | Head C wake/light (also mirrored here) |
| `ai.drowsiness` | Deprecated alias of `ai.a_vig` |

Encoder forward still needs a native Torch/Candle backend — until then the
app marks `ai.a_vig` / `ai.wake_light` / `ai.drowsiness` **unavailable** and
hides them from the ship scorer picker. Head-linear forward runs in-process
for unit tests once a synthetic/real embedding is available.
