//! AI-engine FFI surface: model download/load bookkeeping.
//!
//! The app ships no weights. LUNA (`PulpBio/LUNA`, un-gated, Apache-2.0) is
//! downloaded directly by the app; REVE (`brain-bzh/reve-base`, gated by a
//! responsible-use agreement, ~280 MB) is imported by the user after accepting
//! the terms. Either way the files land as `config.json` + `model.safetensors`
//! in a per-model directory under app storage and are loaded here via the
//! vendored `reve-rs` / `luna-rs` crates (RLX CPU backend). Scoring itself runs
//! in `crate::analysis::{reve,luna}` from the event forwarder, not across FFI.

use crate::analysis::{guardrail, luna, reve};

/// Load a model of [kind] (`reve_base` | `luna_base` | `luna_large`) from
/// [model_dir] (must contain `config.json` and `model.safetensors`) and keep
/// it ready for scoring. Returns a description of the loaded model (inference
/// runs on CPU). Re-loads replace any prior model.
pub fn model_load(model_dir: String, kind: String) -> anyhow::Result<String> {
    match kind.as_str() {
        luna::KIND_REVE_BASE => reve::load_model(&model_dir),
        luna::KIND_LUNA_BASE | luna::KIND_LUNA_LARGE => luna::load_model(&model_dir),
        other => anyhow::bail!("unknown model kind: {other}"),
    }
}

/// Drop the loaded model and free its memory.
pub fn model_unload() {
    // Drop whichever backend is loaded; unloading both is harmless.
    reve::unload_model();
    luna::unload_model();
}

/// Whether a model is currently loaded.
pub fn model_loaded() -> bool {
    reve::is_loaded() || luna::is_loaded()
}

/// JSON content of the app-generated `config.json` for [kind]. The app writes
/// this file next to the weights so the loader can describe the graph without
/// depending on the Hub's own (sometimes partial) config.
pub fn model_config_json(kind: String) -> anyhow::Result<String> {
    match kind.as_str() {
        luna::KIND_REVE_BASE => Ok(reve::generated_config_json()),
        luna::KIND_LUNA_BASE | luna::KIND_LUNA_LARGE => luna::config_json(&kind),
        other => anyhow::bail!("unknown model kind: {other}"),
    }
}

/// Enable the sleep-guardrail scorer for [kind], clearing any prior anchors and
/// live vector. The forwarder starts scoring the next 1 Hz tick once a model of
/// that kind is loaded and the headset is streaming. Returns false for an
/// unknown kind.
pub fn guardrail_enable(kind: String) -> bool {
    guardrail::enable(&kind)
}

/// Disable the sleep-guardrail scorer and drop its anchors/live vector.
pub fn guardrail_disable() {
    guardrail::disable();
}

/// Reset the guardrail anchors (fresh calibration pass on the same model).
pub fn guardrail_reset_anchors() {
    guardrail::reset_anchors();
}

/// Capture the current live embedding as a calibration anchor: `clear` uses the
/// latest scored vector; `sleep` uses the deepest-rest sample seen since the
/// guardrail was enabled (or since the last `clear` capture). Errors when no
/// window has been scored yet, or when the model no longer matches the enabled
/// kind.
pub fn guardrail_capture_anchor(name: String) -> anyhow::Result<String> {
    guardrail::capture_anchor(&name)
}

/// Dim of the current live embedding, or 0 before the first scored window.
pub fn guardrail_live_dim() -> u32 {
    guardrail::live_dim()
}
