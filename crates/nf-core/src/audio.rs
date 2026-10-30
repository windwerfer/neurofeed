//! Feedback audio: settings commands, the guard toggle and the [`Cue`] the
//! shells render (`nf_audio::Mixer`). Core decides *what* sounds; shells
//! only play it.

use crate::feedback::Phase;
use crate::state::AppState;
use crate::CoreError;
use nf_audio::{AudioSettings, Background, BinauralPreset, Cue, GuardSound, RewardOutput};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// `audio.set` params; omitted fields keep their value. Volumes 0..=1.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AudioPatch {
    /// chime | rain | binaural | music | none.
    #[serde(default)]
    pub reward_output: Option<RewardOutput>,
    /// drone | drone_loop | rain | binaural | none.
    #[serde(default)]
    pub background: Option<Background>,
    /// soft_bowl | chime | cough | alarm | none.
    #[serde(default)]
    pub guard_sound: Option<GuardSound>,
    #[serde(default)]
    pub master_volume: Option<f64>,
    #[serde(default)]
    pub feedback_volume: Option<f64>,
    #[serde(default)]
    pub background_volume: Option<f64>,
    #[serde(default)]
    pub guard_volume: Option<f64>,
    #[serde(default)]
    pub binaural_preset: Option<BinauralPreset>,
    /// Music low-pass range, Hz (min 50..=8000, max 200..=16000).
    #[serde(default)]
    pub music_min_hz: Option<f64>,
    #[serde(default)]
    pub music_max_hz: Option<f64>,
    /// Filter closes (instead of opens) as the percentile rises.
    #[serde(default)]
    pub music_invert: Option<bool>,
    #[serde(default)]
    pub muted: Option<bool>,
    /// Desktop: folder with .ogg/.mp3/.flac/.wav for the `music` output;
    /// "" clears it.
    #[serde(default)]
    pub music_dir: Option<String>,
    /// Restore the defaults first.
    #[serde(default)]
    pub reset: bool,
}

fn volume(name: &str, v: Option<f64>) -> Result<Option<f64>, CoreError> {
    match v {
        Some(x) if !(0.0..=1.0).contains(&x) => Err(CoreError::InvalidArgs(format!("{name} must be in [0, 1]"))),
        _ => Ok(v),
    }
}

/// Apply an `audio.set`; returns the new settings.
pub fn set(state: &mut AppState, p: &AudioPatch) -> Result<Value, CoreError> {
    let mut a = if p.reset { AudioSettings::default() } else { state.audio };
    a.master = volume("master_volume", p.master_volume)?.unwrap_or(a.master);
    a.feedback = volume("feedback_volume", p.feedback_volume)?.unwrap_or(a.feedback);
    a.background_volume = volume("background_volume", p.background_volume)?.unwrap_or(a.background_volume);
    a.guard_volume = volume("guard_volume", p.guard_volume)?.unwrap_or(a.guard_volume);
    a.reward = p.reward_output.unwrap_or(a.reward);
    a.background = p.background.unwrap_or(a.background);
    a.guard = p.guard_sound.unwrap_or(a.guard);
    a.binaural = p.binaural_preset.unwrap_or(a.binaural);
    a.music_min_hz = p.music_min_hz.unwrap_or(a.music_min_hz);
    a.music_max_hz = p.music_max_hz.unwrap_or(a.music_max_hz);
    a.music_invert = p.music_invert.unwrap_or(a.music_invert);
    a.muted = p.muted.unwrap_or(a.muted);
    state.audio = a.sanitized();
    if let Some(d) = &p.music_dir {
        state.music_dir = Some(d.trim().to_owned()).filter(|d| !d.is_empty());
    }
    Ok(json!(state.audio))
}

/// What should sound now.
pub fn cue(state: &AppState) -> Cue {
    let f = &state.feedback;
    let reward_on = f.phase == Phase::Playing;
    let rec = f.last().and_then(|r| r.record.as_ref()).filter(|_| reward_on);
    Cue {
        background_on: matches!(f.phase, Phase::Calibrating | Phase::Playing),
        reward_on,
        pct: rec.and_then(|r| r.pct),
        muffle: rec.and_then(|r| r.muted) == Some(true),
        warning: rec.and_then(|r| r.warn) == Some(true),
        settings: state.audio,
    }
}

/// `audio.status`.
pub fn status(state: &AppState) -> Value {
    let f = &state.feedback;
    let presets: Vec<Value> = BinauralPreset::ALL
        .iter()
        .map(|p| {
            let (label, about, beat, carrier) = p.spec();
            json!({ "id": p, "label": label, "about": about, "beat_hz": beat, "carrier_hz": carrier })
        })
        .collect();
    json!({
        "settings": state.audio,
        "music_dir": state.music_dir,
        "cue": cue(state),
        "guard": guard_status(state),
        "binaural_presets": presets,
        "phase": f.phase,
    })
}

pub fn guard_status(state: &AppState) -> Value {
    let f = &state.feedback;
    let ai = f.ai_guard.is_some() && f.protocol.guard.is_some();
    json!({
        "available": f.protocol.guard.is_some(),
        "enabled": (ai || f.guard) && f.protocol.guard.is_some(),
        "band_math": f.guard,
        "scorer": if ai { state.ai.settings.scorer.as_str() } else if f.guard { "band.delta" } else { "none" },
        "threshold_mode": if ai { serde_json::to_value(state.ai.settings.threshold_mode).unwrap_or_default() } else { json!("percentile") },
        "percentile": nf_feedback::GUARD_PERCENTILE,
        "muffle_reward": f.protocol.guard.map(|g| g.muffle_reward),
        "threshold": f.guard_threshold(),
        "warning": cue(state).warning,
    })
}

/// `guard.set` enabled check.
pub fn can_set_guard(s: &AppState) -> Result<(), String> {
    if s.feedback.protocol.guard.is_none() {
        return Err("this protocol has no guard".into());
    }
    if s.feedback.phase.active() {
        return Err("locked during a session".into());
    }
    Ok(())
}
