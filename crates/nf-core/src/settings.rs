//! User settings (appearance, subject, onboarding, debug) and the persisted
//! settings document that also carries audio, mains, band scale, music folder
//! and Band Stability. Saved as the store doc `settings` after every
//! successful command that changed it; restored by a rolled-back batch.

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

pub const DOC_KEY: &str = "settings";
pub const MAX_SUBJECT: usize = 40;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum Appearance {
    System,
    Light,
    #[default]
    Dark,
}

/// UI layout: `auto` picks compact below ~600 logical px of width.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum LayoutMode {
    #[default]
    Auto,
    /// Phone layout: compact top bar, hamburger drawer, full-screen sheets;
    /// in landscape, monitor screens show the graph only.
    Compact,
    /// Desktop layout: sidebar + top bar.
    Regular,
}

/// UI language: `auto` follows the system locale (English fallback).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum Language {
    #[default]
    Auto,
    En,
    De,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(default)]
pub struct UserSettings {
    pub appearance: Appearance,
    /// Pseudonymous subject id written into recordings ("" = anonymous).
    pub subject: String,
    /// The first-run tour was finished or skipped.
    pub onboarded: bool,
    /// Debug mode: simulator devices and fault injection in the device list.
    pub debug: bool,
    /// Draw gesture markers (blink / clench) on trust plots.
    pub gesture_markers: bool,
    /// Run the staged calibration (artifacts, eyes open, baseline) for
    /// every protocol, not only Sleep Guard (legacy "Always staged").
    pub always_staged: bool,
    /// Detect eye up/down movements as gesture marks (experimental).
    pub eye_markers: bool,
    /// Save gesture marks with feedback sessions.
    pub markers_in_feedback: bool,
    /// Show Muse AUX inputs in the status bar and monitors (applies on connect).
    pub muse_aux: bool,
    /// Save AUX in recordings (only while `muse_aux` is on).
    pub record_aux: bool,
    /// Neurosity Crown pad quality: the Crown's own or the app's score.
    pub crown_quality: QualitySource,
    /// UI layout (`auto` | `compact` | `regular`).
    pub layout: LayoutMode,
    /// UI language (`auto` | `en` | `de`).
    pub language: Language,
    /// Debug: frame-rate overlay (FPS, frame interval, CPU time) in a corner.
    pub perf_overlay: bool,
}

/// Where Crown pad signal quality comes from (applies from the next second).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum QualitySource {
    #[default]
    Crown,
    App,
}

impl Default for UserSettings {
    fn default() -> Self {
        Self {
            appearance: Appearance::Dark,
            subject: String::new(),
            onboarded: false,
            debug: true,
            gesture_markers: true,
            always_staged: false,
            eye_markers: false,
            markers_in_feedback: true,
            muse_aux: false,
            record_aux: true,
            crown_quality: QualitySource::Crown,
            layout: LayoutMode::Auto,
            language: Language::Auto,
            perf_overlay: false,
        }
    }
}

/// `settings.set` params; omitted fields stay.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SettingsPatch {
    #[serde(default)]
    pub appearance: Option<Appearance>,
    #[serde(default)]
    pub subject: Option<String>,
    #[serde(default)]
    pub onboarded: Option<bool>,
    #[serde(default)]
    pub debug: Option<bool>,
    #[serde(default)]
    pub gesture_markers: Option<bool>,
    #[serde(default)]
    pub always_staged: Option<bool>,
    #[serde(default)]
    pub eye_markers: Option<bool>,
    #[serde(default)]
    pub markers_in_feedback: Option<bool>,
    #[serde(default)]
    pub muse_aux: Option<bool>,
    #[serde(default)]
    pub record_aux: Option<bool>,
    #[serde(default)]
    pub crown_quality: Option<QualitySource>,
    #[serde(default)]
    pub layout: Option<LayoutMode>,
    #[serde(default)]
    pub language: Option<Language>,
    #[serde(default)]
    pub perf_overlay: Option<bool>,
}

/// Apply `p` to `s`, validating first (nothing changes on error).
pub fn apply(s: &mut UserSettings, p: &SettingsPatch) -> Result<(), String> {
    if let Some(sub) = &p.subject {
        let sub = sub.trim();
        if sub.chars().count() > MAX_SUBJECT {
            return Err(format!("subject is limited to {MAX_SUBJECT} characters"));
        }
        if !sub.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | ' ')) {
            return Err("subject may only use letters, digits, space, '-', '_' and '.'".into());
        }
    }
    if let Some(v) = p.appearance {
        s.appearance = v;
    }
    if let Some(v) = &p.subject {
        v.trim().clone_into(&mut s.subject);
    }
    if let Some(v) = p.onboarded {
        s.onboarded = v;
    }
    if let Some(v) = p.debug {
        s.debug = v;
    }
    if let Some(v) = p.muse_aux {
        s.muse_aux = v;
    }
    if let Some(v) = p.record_aux {
        s.record_aux = v;
    }
    if let Some(v) = p.crown_quality {
        s.crown_quality = v;
    }
    if let Some(v) = p.eye_markers {
        s.eye_markers = v;
    }
    if let Some(v) = p.markers_in_feedback {
        s.markers_in_feedback = v;
    }
    if let Some(v) = p.always_staged {
        s.always_staged = v;
    }
    if let Some(v) = p.language {
        s.language = v;
    }
    if let Some(v) = p.layout {
        s.layout = v;
    }
    if let Some(v) = p.gesture_markers {
        s.gesture_markers = v;
    }
    if let Some(v) = p.perf_overlay {
        s.perf_overlay = v;
    }
    Ok(())
}

/// Everything persisted across launches.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Persisted {
    pub user: UserSettings,
    pub audio: nf_audio::AudioSettings,
    pub mains: crate::MainsMode,
    pub band_scale: crate::BandScale,
    pub music_dir: Option<String>,
    pub stability: nf_feedback::StabilityConfig,
    pub guard: bool,
    /// Streaming destination and protocol; `enabled` is never restored on (always starts off).
    pub streaming: crate::streaming::StreamSettings,
    #[serde(default)]
    pub ai: crate::ai::AiSettings,
    /// Auto-reconnect target: the last device (real or simulator) that streamed.
    pub last_device: Option<String>,
    /// The user's Disconnect suspends auto-reconnect, across restarts too.
    #[serde(default)]
    pub auto_suspended: bool,
    /// Monitor window length per monitor (seconds).
    #[serde(default)]
    pub monitor_windows: std::collections::BTreeMap<crate::monitor::MonitorId, f64>,
    /// Bands monitor: hidden bands.
    #[serde(default)]
    pub hidden_bands: Vec<nf_types::Band>,
}

impl Default for Persisted {
    fn default() -> Self {
        let s = crate::AppState::default();
        Self::of(&s)
    }
}

impl Persisted {
    pub fn of(s: &crate::AppState) -> Self {
        Self {
            user: s.settings.clone(),
            audio: s.audio,
            mains: s.mains_mode,
            band_scale: s.band_scale,
            music_dir: s.music_dir.clone(),
            stability: s.feedback.stability,
            guard: s.feedback.guard,
            streaming: crate::streaming::StreamSettings { enabled: false, ..s.streaming.settings.clone() },
            ai: s.ai.settings.clone(),
            last_device: s.auto.target.clone(),
            auto_suspended: s.auto.suspended,
            monitor_windows: s.monitors.windows(),
            hidden_bands: s.monitors.bands.hidden_bands.clone(),
        }
    }

    pub fn restore(self, s: &mut crate::AppState) {
        s.settings = self.user;
        s.audio = self.audio;
        s.mains_mode = self.mains;
        s.band_scale = self.band_scale;
        s.music_dir = self.music_dir;
        s.feedback.stability = self.stability;
        s.feedback.guard = self.guard;
        s.streaming.settings = crate::streaming::StreamSettings { enabled: s.streaming.settings.enabled, ..self.streaming };
        s.ai.settings = self.ai;
        s.auto.target = self.last_device;
        s.auto.suspended = self.auto_suspended;
        s.monitors.restore_windows(&self.monitor_windows);
        s.monitors.bands.hidden_bands = self.hidden_bands;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subject_is_validated_before_anything_changes() {
        let mut s = UserSettings::default();
        let bad = SettingsPatch { appearance: Some(Appearance::Light), subject: Some("a/b".into()), ..Default::default() };
        assert!(apply(&mut s, &bad).is_err());
        assert_eq!(s.appearance, Appearance::Dark);
        apply(&mut s, &SettingsPatch { subject: Some("  p-07 ".into()), ..Default::default() }).unwrap();
        assert_eq!(s.subject, "p-07");
    }

    #[test]
    fn persisted_round_trips_and_tolerates_missing_fields() {
        let p: Persisted = serde_json::from_str(r#"{"user":{"subject":"x"}}"#).unwrap();
        assert_eq!((p.user.subject.as_str(), p.user.appearance), ("x", Appearance::Dark));
        let j = serde_json::to_string(&p).unwrap();
        assert_eq!(serde_json::from_str::<Persisted>(&j).unwrap(), p);
    }
}
