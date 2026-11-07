//! AI sleep guard state (legacy `lib/src/reve/*`, `guard_lane.dart`):
//! model install / load status mirrored from the shell's [`AiRuntime`], the
//! user's scorer and threshold choice, and the live head scores. Inference
//! itself runs in the runtime (desktop only, `nf-ai`).

use crate::CoreError;
use nf_types::{AiModel, AiModelState};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// Warn cut for AI probabilities.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ThresholdMode {
    /// Warn while P > `fixed_threshold` (legacy default 0.50).
    #[default]
    Fixed,
    /// Warn above the guard percentile of the eyes-closed calibration.
    Percentile,
}

/// Persisted AI choices.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct AiSettings {
    /// Scorer id (head): `ai.a_vig`, `ai.wake_light`, `ai.a_vig_reve`, `ai.wake_light_reve`.
    pub scorer: String,
    pub threshold_mode: ThresholdMode,
    pub fixed_threshold: f64,
    /// Load the selected model at startup / after install (set and forget).
    pub auto_load: bool,
}

impl Default for AiSettings {
    fn default() -> Self {
        Self {
            scorer: "ai.a_vig".into(),
            threshold_mode: ThresholdMode::Fixed,
            fixed_threshold: nf_feedback::AI_FIXED_THRESHOLD,
            auto_load: true,
        }
    }
}

impl AiSettings {
    pub fn model(&self) -> AiModel {
        AiModel::for_scorer(&self.scorer).unwrap_or(AiModel::CbramodAVig)
    }
    /// Engine `fixed` cut (`None` = percentile).
    pub fn fixed(&self) -> Option<f64> {
        (self.threshold_mode == ThresholdMode::Fixed).then_some(self.fixed_threshold)
    }
}

/// One model as the settings card shows it.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct ModelStatus {
    pub model: AiModel,
    pub label: &'static str,
    pub description: &'static str,
    pub size_mb: u32,
    pub window_s: f64,
    pub scorers: &'static [&'static str],
    pub page_url: &'static str,
    /// `None` = gated: download in the browser, then import.
    pub download_url: Option<&'static str>,
    pub guide: &'static str,
    pub weights_file: &'static str,
    pub folder: Option<String>,
    #[serde(flatten)]
    pub state: AiModelState,
}

/// Latest scored window.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct AiLive {
    /// Session time the score arrived.
    pub t: f64,
    pub model: AiModel,
    pub heads: Vec<(String, f32)>,
    /// The selected scorer's P(class 1), when this model produced it.
    pub value: Option<f32>,
    pub ms: f64,
    /// Anchor extras (after the eyes-open stage captured `V_clear`).
    pub clarity: Option<f32>,
    pub sleep_dir: Option<f32>,
    pub windows: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct AiState {
    /// A runtime is registered (desktop builds).
    pub runtime: bool,
    pub settings: AiSettings,
    pub models: Vec<ModelStatus>,
    pub live: Option<AiLive>,
    pub clear_anchor: bool,
    pub sleep_anchor: bool,
    /// The model's fixed input channels include an analysis-excluded one:
    /// no windows are scored (the channel schema is never changed).
    pub blocked: Option<String>,
}

impl Default for AiState {
    fn default() -> Self {
        Self {
            runtime: false,
            settings: AiSettings::default(),
            models: AiModel::ALL.iter().map(|&m| status(m, AiModelState::Missing, None)).collect(),
            live: None,
            clear_anchor: false,
            sleep_anchor: false,
            blocked: None,
        }
    }
}

/// Why AI is not available in this build.
pub const NO_RUNTIME: &str = "AI models run in the desktop app only (the web build has no model runtime)";

pub fn status(m: AiModel, state: AiModelState, folder: Option<String>) -> ModelStatus {
    ModelStatus {
        model: m,
        label: m.label(),
        description: m.description(),
        size_mb: m.size_mb(),
        window_s: m.window_samples() as f64 / 256.0,
        scorers: m.scorers(),
        page_url: m.page_url(),
        download_url: m.download_url(),
        guide: m.guide(),
        weights_file: m.weights_file(),
        folder,
        state,
    }
}

impl AiState {
    /// The model that is loaded or loading, if any.
    pub fn loaded(&self) -> Option<AiModel> {
        self.models.iter().find(|m| matches!(m.state, AiModelState::Ready { .. } | AiModelState::Loading)).map(|m| m.model)
    }

    pub fn model_state(&self, m: AiModel) -> Option<&AiModelState> {
        self.models.iter().find(|s| s.model == m).map(|s| &s.state)
    }
    /// The selected model is loaded and scoring.
    pub fn ready(&self) -> bool {
        matches!(self.model_state(self.settings.model()), Some(AiModelState::Ready { .. }))
    }
    /// `Ok` when the AI guard can run, else a plain reason.
    pub fn ready_reason(&self) -> Result<(), String> {
        if !self.runtime {
            return Err(NO_RUNTIME.into());
        }
        let m = self.settings.model();
        match self.model_state(m) {
            Some(AiModelState::Ready { .. }) => Ok(()),
            Some(AiModelState::Missing) | None => Err(format!("{} is not installed (Settings → AI)", m.label())),
            Some(AiModelState::Installing { .. }) => Err(format!("{} is still installing", m.label())),
            Some(AiModelState::Installed) => Err(format!("{} is installed but not loaded (Settings → AI → Load)", m.label())),
            Some(AiModelState::Loading) => Err(format!("{} is loading", m.label())),
            Some(AiModelState::Failed { message }) => Err(format!("{}: {message}", m.label())),
        }
    }
    /// Fresh selected-scorer value at session time `now` (≤ 2.5 s old).
    pub fn value_at(&self, now: f64) -> Option<f64> {
        self.live.as_ref().filter(|l| now - l.t <= 2.5 && l.model == self.settings.model()).and_then(|l| l.value).map(f64::from)
    }
}

/// `ai.set` arguments (all optional).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AiPatch {
    /// Pick a model (selects its first scorer unless `scorer` is given).
    #[serde(default)]
    pub model: Option<AiModel>,
    /// Scorer id; `ai.drowsiness` is accepted as `ai.a_vig`.
    #[serde(default)]
    pub scorer: Option<String>,
    #[serde(default)]
    pub threshold_mode: Option<ThresholdMode>,
    /// 0.05..=0.95 (rounded to 2 decimals).
    #[serde(default)]
    pub fixed_threshold: Option<f64>,
    #[serde(default)]
    pub auto_load: Option<bool>,
}

/// Apply a patch; `locked` = a session is running (model / scorer fixed).
pub fn set(s: &mut AiSettings, p: &AiPatch, locked: bool) -> Result<(), CoreError> {
    let mut n = s.clone();
    if let Some(m) = p.model {
        n.scorer = m.scorers()[0].into();
    }
    if let Some(id) = &p.scorer {
        let id = if id == "ai.drowsiness" { "ai.a_vig" } else { id.as_str() };
        let m = AiModel::for_scorer(id).ok_or_else(|| CoreError::InvalidArgs(format!("unknown scorer `{id}`")))?;
        if p.model.is_some_and(|pm| pm != m) {
            return Err(CoreError::InvalidArgs(format!("`{id}` is not a {} head", p.model.map_or("", AiModel::label))));
        }
        n.scorer = id.into();
    }
    if let Some(v) = p.fixed_threshold {
        let (lo, hi) = nf_feedback::AI_FIXED_RANGE;
        if !(lo..=hi).contains(&v) {
            return Err(CoreError::InvalidArgs(format!("fixed_threshold must be {lo}..={hi}")));
        }
        n.fixed_threshold = (v * 100.0).round() / 100.0;
    }
    n.threshold_mode = p.threshold_mode.unwrap_or(n.threshold_mode);
    n.auto_load = p.auto_load.unwrap_or(n.auto_load);
    if locked && n.scorer != s.scorer {
        return Err(CoreError::BadRequest("the scorer is locked during a session; stop it first".into()));
    }
    *s = n;
    Ok(())
}

pub fn status_json(a: &AiState) -> Value {
    json!({
        "runtime": a.runtime,
        "available": a.runtime,
        "unavailable_reason": (!a.runtime).then_some(NO_RUNTIME),
        "ready": a.ready(),
        "ready_reason": a.ready_reason().err(),
        "settings": a.settings,
        "model": a.settings.model(),
        "models": a.models,
        "live": a.live,
        "anchors": { "clear": a.clear_anchor, "sleep": a.sleep_anchor },
        "blocked_reason": a.blocked,
    })
}

/// Model rows in head order (frontal L/R, temporal L/R) for a device.
pub fn model_rows(channels: &[String]) -> Option<[usize; 4]> {
    const SETS: [[&str; 4]; 2] = [["AF7", "AF8", "TP9", "TP10"], ["F5", "F6", "CP3", "CP4"]];
    SETS.iter().find_map(|set| {
        let idx: Vec<usize> = set.iter().map(|n| channels.iter().position(|c| c == n)).collect::<Option<_>>()?;
        Some([idx[0], idx[1], idx[2], idx[3]])
    })
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn patch_rules() {
        let mut s = AiSettings::default();
        set(&mut s, &AiPatch { model: Some(AiModel::ReveBase), ..AiPatch::default() }, false).unwrap();
        assert_eq!(s.scorer, "ai.a_vig_reve");
        set(&mut s, &AiPatch { scorer: Some("ai.drowsiness".into()), fixed_threshold: Some(0.333), ..AiPatch::default() }, false).unwrap();
        assert_eq!((s.scorer.as_str(), s.fixed_threshold), ("ai.a_vig", 0.33));
        assert!(set(&mut s, &AiPatch { fixed_threshold: Some(0.99), ..AiPatch::default() }, false).is_err());
        assert!(set(&mut s, &AiPatch { scorer: Some("ai.wake_light".into()), ..AiPatch::default() }, true).is_err());
        set(&mut s, &AiPatch { threshold_mode: Some(ThresholdMode::Percentile), ..AiPatch::default() }, true).unwrap();
        assert_eq!(s.fixed(), None);
    }

    #[test]
    fn rows_for_muse_and_crown() {
        let c = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(model_rows(&c(&["TP9", "AF7", "AF8", "TP10"])), Some([1, 2, 0, 3]));
        assert_eq!(model_rows(&c(&["CP3", "C3", "F5", "PO3", "PO4", "F6", "C4", "CP4"])), Some([2, 5, 0, 7]));
        assert_eq!(model_rows(&c(&["Fp1"])), None);
    }
}
