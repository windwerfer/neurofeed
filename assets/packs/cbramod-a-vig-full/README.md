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

Encoder forward runs in-process via Candle CPU (Rust). Place the SHA-pinned
`pretrained_weights.pth` in the model dir (do not commit the blob).
**CPU/mobile forward latency is TBD** — not yet profiled on-device; treat as
unbudgeted until measured.


## Feature IDs

| ID | Head |
|----|------|
| `ai.a_vig` | A-vig (primary sleep/drowsy) |
| `ai.wake_light` | Head C wake/light (also mirrored here) |
| `ai.drowsiness` | Deprecated alias of `ai.a_vig` |

Ready requires verified encoder weights **and** a successful Candle load
(`encoder_forward_ready` in Rust). SHA OK with a failed Candle load is
**not** Ready. `ai.a_vig` / `ai.wake_light` / `ai.drowsiness` are then
selectable live scorers. Mean-pool embedding (200-d) feeds HeadALinear;
FeatureDto value is P(class 1).
