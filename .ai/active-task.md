# Active Task

**Branch:** `feat/spur-a-cbramod-guardrail`

**Now:** Spur A — frozen **CBraMod** encoder (Candle CPU) + A-vig HeadALinear
guardrail path. Pack `assets/packs/cbramod-a-vig-full/`. Encoder weights are
SHA-pinned Apache-2.0 (`pretrained_weights.pth`); **not** committed — load from
model dir / `.local/cbramod-fixtures/` for tests. Ready gate: Rust
`encoder_forward_ready` (Candle load must succeed; Dart
`kCbramodEncoderForwardReady` is compile-time link only). **CPU/mobile Candle
forward latency TBD** (not profiled). Feature IDs: `ai.a_vig`, `ai.wake_light`,
deprecated alias `ai.drowsiness`. Optional REVE remains gated import (RLX CPU).
**LUNA removed** from ship path.

Window: **2 s @ 256 Hz** (512 samples) Muse AF7/AF8/TP9/TP10 → resample/patch →
mean-pool 200-d → head → FeatureDto **P(class 1)**.

Do not reopen pipeline-contract Key Decisions, Crown Start, Connect UX,
or the v5 68-byte header. Bands Y is **dB display** (storage linear).
Do not add averaging, a Bands strip on Spectrogram, Spectrogram FFT-window
chrome, or `SMOOTH` / `REAL TIME` Bands chrome. Do not pause `SweepBuffer`
/ `BandCache` on view change.

## Queued elsewhere (not this branch)

- Crown *run* (quality vectors, computed frames, charts device-aware).
- Making Crown / Notion OSC connect (or OSC discovery) work.
- Android foreground service so recording survives app background.
- On-device QA leftover boxes in [feedback/todos.md](feedback/todos.md).
- Publish `third_party/edf_export` to git+tag once export proves out on device.
- Athena optics raw stream (muse-rs `Optics`, session tag 11). Queued:
  [TODO/athena-optics-contract.md](TODO/athena-optics-contract.md).

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_muse_ml:*:*:D`. See [testing-guide.md](testing-guide.md).
