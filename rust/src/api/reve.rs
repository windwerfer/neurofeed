//! AI-engine FFI surface: model download/load bookkeeping.
//!
//! The app ships the Spur A **head pack** (`cbramod-a-vig-full`) but not the
//! ~20 MB CBraMod encoder blob (SHA-pinned; fetch from HF Apache-2.0). REVE
//! (`brain-bzh/reve-base`, gated) remains an optional user-imported path.
//! LUNA has been removed from the ship path.
//!
//! Scoring runs in `crate::analysis::{cbramod,reve}` from the event forwarder.

use crate::analysis::{cbramod, guardrail, reve};

/// Load a model of [kind] (`cbramod_a_vig` | `reve_base`) from [model_dir]
/// and keep it ready for scoring. Returns a description of the loaded model
/// (inference runs on CPU). Re-loads replace any prior model.
pub fn model_load(model_dir: String, kind: String) -> anyhow::Result<String> {
    // Only one AI backend active at a time.
    match kind.as_str() {
        cbramod::KIND_CBRAMOD_A_VIG => {
            reve::unload_model();
            cbramod::load_model(&model_dir)
        }
        reve::KIND_REVE_BASE => {
            cbramod::unload_model();
            reve::load_model(&model_dir)
        }
        "luna_base" | "luna_large" => anyhow::bail!(
            "LUNA is disabled — use cbramod_a_vig (Spur A) or reve_base"
        ),
        other => anyhow::bail!("unknown model kind: {other}"),
    }
}

/// Drop the loaded model and free its memory.
pub fn model_unload() {
    reve::unload_model();
    cbramod::unload_model();
}

/// Whether a model is currently loaded.
pub fn model_loaded() -> bool {
    reve::is_loaded() || cbramod::is_loaded()
}

/// JSON content of the app-generated `config.json` for [kind].
pub fn model_config_json(kind: String) -> anyhow::Result<String> {
    match kind.as_str() {
        cbramod::KIND_CBRAMOD_A_VIG => Ok(cbramod::generated_config_json()),
        reve::KIND_REVE_BASE => Ok(reve::generated_config_json()),
        "luna_base" | "luna_large" => anyhow::bail!("LUNA is disabled"),
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
