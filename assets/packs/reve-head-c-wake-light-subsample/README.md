# Pack: reve-head-c-wake-light-subsample

Head-only pack from neurofeed_heads (≥0.70). See `pack_manifest.json`.

Feature ID and f32bin head are registered in Rust `analysis/ai_heads.rs` for
in-process linear forward (no libtorch). Encoder forward is separate.

Live FeatureDto.value is **P(light)** (not argmax).
