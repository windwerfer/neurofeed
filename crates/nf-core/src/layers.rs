//! The session's layer stack: what sounds and guards during a session.
//!
//! A protocol is only the *template* that seeds the stack ([`LayerStack::seed`]);
//! every edit afterwards belongs to the session. The stack is always sorted
//! Background → Feedback → Guardrail (new layers slot into their section, in
//! insertion order), each kind may appear several times, and a kind with no
//! layer is simply absent.
//!
//! Stage 1: the audio / feedback engine still has one slot per kind
//! (`AudioSettings`, `Trainer::guard`). The *first* layer of a kind is mapped
//! onto that slot ([`push`] after layer commands, [`pull`] after `audio.set` /
//! `guard.set`), so the existing path behaves as before. Further layers are
//! stored and shown but not rendered yet.

use nf_audio::{AudioSettings, Background, BinauralPreset, GuardSound, RewardOutput};
use nf_feedback::Protocol;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Most layers of one kind, and in total.
pub const MAX_PER_KIND: usize = 4;
pub const MAX_LAYERS: usize = 8;

/// Section of the stack, in display order (the derived `Ord` is the sort key).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum LayerKind {
    /// Static sound, no feedback.
    Background,
    /// Sound that follows the reward (classic feedback, binaural, music).
    Feedback,
    /// Drowsiness / quality guard warning.
    Guardrail,
}

impl LayerKind {
    pub const ALL: [LayerKind; 3] = [Self::Background, Self::Feedback, Self::Guardrail];

    pub fn label(self) -> &'static str {
        match self {
            Self::Background => "Background sounds",
            Self::Feedback => "Feedback",
            Self::Guardrail => "Guardrail",
        }
    }
}

/// Per-kind settings of one layer. Volumes are 0..=1.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum LayerConfig {
    Background { sound: Background, volume: f64 },
    Feedback { output: RewardOutput, binaural: BinauralPreset, volume: f64 },
    Guardrail { sound: GuardSound, volume: f64 },
}

impl LayerConfig {
    pub fn kind(&self) -> LayerKind {
        match self {
            Self::Background { .. } => LayerKind::Background,
            Self::Feedback { .. } => LayerKind::Feedback,
            Self::Guardrail { .. } => LayerKind::Guardrail,
        }
    }

    /// A new layer of `kind` with the engine defaults.
    pub fn default_of(kind: LayerKind) -> Self {
        let d = AudioSettings::default();
        match kind {
            LayerKind::Background => Self::Background { sound: d.background, volume: d.background_volume },
            LayerKind::Feedback => Self::Feedback { output: d.reward, binaural: d.binaural, volume: d.feedback },
            LayerKind::Guardrail => Self::Guardrail { sound: d.guard, volume: d.guard_volume },
        }
    }

    /// One-line summary for the tile subtitle.
    pub fn summary(&self) -> String {
        match self {
            Self::Background { sound, .. } => format!("{sound:?}"),
            Self::Feedback { output: RewardOutput::Binaural, binaural, .. } => format!("Binaural · {}", binaural.label()),
            Self::Feedback { output, .. } => format!("{output:?}"),
            Self::Guardrail { sound, .. } => format!("{sound:?}"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct Layer {
    /// Stable within the session; never reused.
    pub id: u32,
    #[serde(flatten)]
    pub config: LayerConfig,
}

/// `layers.set` / `layers.add` settings; omitted fields keep their value. A
/// field that does not belong to the layer's kind is an error.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LayerPatch {
    /// Background: drone | drone_loop | rain | binaural (remove the layer for none).
    #[serde(default)]
    pub sound: Option<Background>,
    /// Feedback: chime | rain | binaural | music | none.
    #[serde(default)]
    pub output: Option<RewardOutput>,
    /// Feedback with output `binaural`.
    #[serde(default)]
    pub binaural: Option<BinauralPreset>,
    /// Guardrail: soft_bowl | chime | cough | alarm | none.
    #[serde(default)]
    pub guard_sound: Option<GuardSound>,
    /// All kinds, 0..=1.
    #[serde(default)]
    pub volume: Option<f64>,
}

fn wrong(field: &str, kind: LayerKind) -> String {
    format!("`{field}` does not apply to a {} layer", kind.label().to_lowercase())
}

impl LayerPatch {
    /// First set field that belongs to another kind.
    fn foreign_field(&self, kind: LayerKind) -> Option<&'static str> {
        let set = [
            ("sound", self.sound.is_some(), LayerKind::Background),
            ("output", self.output.is_some(), LayerKind::Feedback),
            ("binaural", self.binaural.is_some(), LayerKind::Feedback),
            ("guard_sound", self.guard_sound.is_some(), LayerKind::Guardrail),
        ];
        set.iter().find(|(_, on, k)| *on && *k != kind).map(|(f, ..)| *f)
    }

    /// `cfg` with the patch applied; nothing changes on error.
    pub fn apply(&self, cfg: LayerConfig) -> Result<LayerConfig, String> {
        let kind = cfg.kind();
        if let Some(v) = self.volume.filter(|v| !(0.0..=1.0).contains(v)) {
            return Err(format!("volume must be in [0, 1], got {v}"));
        }
        if let Some(f) = self.foreign_field(kind) {
            return Err(wrong(f, kind));
        }
        let vol = self.volume;
        Ok(match cfg {
            LayerConfig::Background { sound, volume } => {
                let sound = self.sound.unwrap_or(sound);
                if sound == Background::None {
                    return Err("a background layer needs a sound; remove the layer for none".into());
                }
                LayerConfig::Background { sound, volume: vol.unwrap_or(volume) }
            }
            LayerConfig::Feedback { output, binaural, volume } => LayerConfig::Feedback {
                output: self.output.unwrap_or(output),
                binaural: self.binaural.unwrap_or(binaural),
                volume: vol.unwrap_or(volume),
            },
            LayerConfig::Guardrail { sound, volume } => {
                LayerConfig::Guardrail { sound: self.guard_sound.unwrap_or(sound), volume: vol.unwrap_or(volume) }
            }
        })
    }
}

/// The stack, always sorted by [`LayerKind`].
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct LayerStack {
    layers: Vec<Layer>,
    next_id: u32,
    /// Protocol that seeded the stack (the template; edits do not follow it).
    pub seeded_from: String,
}

/// What the current protocol allows the engine to do (stage 1 mapping).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Caps {
    /// The protocol has a guard lane (`guard.set` works).
    pub guard: bool,
    /// No reward lane (Sleep Guard).
    pub guard_only: bool,
}

impl Caps {
    pub fn of(p: &Protocol) -> Self {
        Self { guard: p.guard.is_some(), guard_only: p.guard_only }
    }
}

impl LayerStack {
    /// The template: the protocol's lanes, with the sounds the user has chosen
    /// (`audio`) and the guard switch (`guard`).
    pub fn seed(p: &Protocol, audio: &AudioSettings, guard: bool) -> Self {
        let mut s = Self { seeded_from: p.id.clone(), ..Self::default() };
        if audio.background != Background::None {
            s.insert(LayerConfig::Background { sound: audio.background, volume: audio.background_volume });
        }
        if !p.guard_only {
            s.insert(LayerConfig::Feedback { output: audio.reward, binaural: audio.binaural, volume: audio.feedback });
        }
        if p.guard.is_some() && guard {
            s.insert(LayerConfig::Guardrail { sound: audio.guard, volume: audio.guard_volume });
        }
        s
    }

    /// Sorted: Background, Feedback, Guardrail; insertion order inside a kind.
    pub fn layers(&self) -> &[Layer] {
        &self.layers
    }

    pub fn of_kind(&self, kind: LayerKind) -> impl Iterator<Item = &Layer> {
        self.layers.iter().filter(move |l| l.config.kind() == kind)
    }

    pub fn count(&self, kind: LayerKind) -> usize {
        self.of_kind(kind).count()
    }

    pub fn get(&self, id: u32) -> Option<&Layer> {
        self.layers.iter().find(|l| l.id == id)
    }

    /// The layer the engine renders for `kind`.
    pub fn primary(&self, kind: LayerKind) -> Option<&Layer> {
        self.of_kind(kind).next()
    }

    fn insert(&mut self, config: LayerConfig) -> u32 {
        self.next_id = self.next_id.saturating_add(1);
        let layer = Layer { id: self.next_id, config };
        let at = self.layers.partition_point(|l| l.config.kind() <= config.kind());
        self.layers.insert(at, layer);
        layer.id
    }

    /// Add a layer into its section; returns its id.
    pub fn add(&mut self, config: LayerConfig) -> Result<u32, String> {
        let kind = config.kind();
        if self.count(kind) >= MAX_PER_KIND {
            return Err(format!("at most {MAX_PER_KIND} {} layers", kind.label().to_lowercase()));
        }
        if self.layers.len() >= MAX_LAYERS {
            return Err(format!("at most {MAX_LAYERS} layers"));
        }
        Ok(self.insert(config))
    }

    pub fn remove(&mut self, id: u32) -> Result<Layer, String> {
        let at = self.layers.iter().position(|l| l.id == id).ok_or_else(|| format!("no layer {id}"))?;
        Ok(self.layers.remove(at))
    }

    pub fn configure(&mut self, id: u32, patch: &LayerPatch) -> Result<Layer, String> {
        let layer = self.layers.iter_mut().find(|l| l.id == id).ok_or_else(|| format!("no layer {id}"))?;
        layer.config = patch.apply(layer.config)?;
        Ok(*layer)
    }

    fn remove_kind(&mut self, kind: LayerKind) {
        self.layers.retain(|l| l.config.kind() != kind);
    }

    fn set_primary(&mut self, config: LayerConfig) {
        let kind = config.kind();
        match self.layers.iter_mut().find(|l| l.config.kind() == kind) {
            Some(l) => l.config = config,
            None => {
                self.insert(config);
            }
        }
    }
}

/// Stack → engine slots (after a layer command): the first layer of a kind
/// drives its slot; no layer of a kind silences / disables it.
pub fn push(stack: &LayerStack, audio: &mut AudioSettings, guard: &mut bool, caps: Caps) {
    match stack.primary(LayerKind::Background).map(|l| l.config) {
        Some(LayerConfig::Background { sound, volume }) => (audio.background, audio.background_volume) = (sound, volume),
        _ => audio.background = Background::None,
    }
    match stack.primary(LayerKind::Feedback).map(|l| l.config) {
        Some(LayerConfig::Feedback { output, binaural, volume }) => {
            (audio.reward, audio.binaural, audio.feedback) = (output, binaural, volume)
        }
        _ => audio.reward = RewardOutput::None,
    }
    match stack.primary(LayerKind::Guardrail).map(|l| l.config) {
        Some(LayerConfig::Guardrail { sound, volume }) => {
            (audio.guard, audio.guard_volume) = (sound, volume);
            *guard = *guard || caps.guard;
        }
        _ if caps.guard => *guard = false,
        _ => {}
    }
    *audio = audio.sanitized();
}

/// Engine slots → stack (after `audio.set` / `guard.set`), so the old path and
/// the layers never disagree. Idempotent: `push` after `pull` changes nothing.
pub fn pull(stack: &mut LayerStack, audio: &AudioSettings, guard: bool, caps: Caps) {
    if audio.background == Background::None {
        stack.remove_kind(LayerKind::Background);
    } else {
        stack.set_primary(LayerConfig::Background { sound: audio.background, volume: audio.background_volume });
    }
    if !caps.guard_only && (audio.reward != RewardOutput::None || stack.primary(LayerKind::Feedback).is_some()) {
        stack.set_primary(LayerConfig::Feedback { output: audio.reward, binaural: audio.binaural, volume: audio.feedback });
    }
    if caps.guard && !guard {
        stack.remove_kind(LayerKind::Guardrail);
    } else if caps.guard {
        stack.set_primary(LayerConfig::Guardrail { sound: audio.guard, volume: audio.guard_volume });
    }
}

/// Most recently used protocols kept (the start screen shows [`RECENT_SHOWN`]).
pub const RECENT_KEPT: usize = 6;
pub const RECENT_SHOWN: usize = 3;

/// Move `id` to the front of `recent` (no duplicates, bounded).
pub fn touch_recent(recent: &mut Vec<String>, id: &str) {
    recent.retain(|r| r != id);
    recent.insert(0, id.to_owned());
    recent.truncate(RECENT_KEPT);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(s: &LayerStack) -> Vec<LayerKind> {
        s.layers().iter().map(|l| l.config.kind()).collect()
    }

    fn proto(id: &str) -> Protocol {
        nf_feedback::protocol(id).unwrap_or_else(|| panic!("no protocol {id}"))
    }

    fn guarded() -> Protocol {
        nf_feedback::builtin().into_iter().find(|p| p.guard.is_some() && !p.guard_only).unwrap()
    }

    #[test]
    fn stack_stays_sorted_whatever_the_add_order() {
        let mut s = LayerStack::default();
        for k in [LayerKind::Guardrail, LayerKind::Feedback, LayerKind::Guardrail, LayerKind::Background, LayerKind::Feedback] {
            s.add(LayerConfig::default_of(k)).unwrap();
        }
        use LayerKind::{Background as B, Feedback as F, Guardrail as G};
        assert_eq!(kinds(&s), [B, F, F, G, G]);
        // insertion order inside a section is kept (ids ascend per kind)
        let fb: Vec<u32> = s.of_kind(F).map(|l| l.id).collect();
        assert!(fb[0] < fb[1]);
    }

    #[test]
    fn add_remove_and_limits() {
        let mut s = LayerStack::default();
        let a = s.add(LayerConfig::default_of(LayerKind::Feedback)).unwrap();
        let b = s.add(LayerConfig::default_of(LayerKind::Feedback)).unwrap();
        assert_ne!(a, b);
        assert!(s.remove(a).is_ok());
        assert!(s.remove(a).is_err(), "already gone");
        let c = s.add(LayerConfig::default_of(LayerKind::Feedback)).unwrap();
        assert!(c > b, "ids are never reused");
        for _ in 0..MAX_PER_KIND {
            let _ = s.add(LayerConfig::default_of(LayerKind::Guardrail));
        }
        assert_eq!(s.count(LayerKind::Guardrail), MAX_PER_KIND);
        assert!(s.add(LayerConfig::default_of(LayerKind::Guardrail)).unwrap_err().contains("at most"));
    }

    #[test]
    fn seeding_follows_the_protocol_lanes() {
        let a = AudioSettings::default();
        let plain = LayerStack::seed(&proto("alertOpen"), &a, true);
        assert_eq!(plain.count(LayerKind::Guardrail), 0, "no guard lane, no guardrail section");
        assert_eq!(plain.count(LayerKind::Feedback), 1);
        assert_eq!(plain.seeded_from, "alertOpen");
        let g = guarded();
        assert_eq!(LayerStack::seed(&g, &a, true).count(LayerKind::Guardrail), 1);
        assert_eq!(LayerStack::seed(&g, &a, false).count(LayerKind::Guardrail), 0, "guard switched off");
        let no_bg = AudioSettings { background: Background::None, ..a };
        assert_eq!(LayerStack::seed(&g, &no_bg, true).count(LayerKind::Background), 0);
        let sleep = nf_feedback::builtin().into_iter().find(|p| p.guard_only).unwrap();
        assert_eq!(LayerStack::seed(&sleep, &a, true).count(LayerKind::Feedback), 0, "guard-only has no reward lane");
    }

    #[test]
    fn patches_check_kind_and_range() {
        let bg = LayerConfig::default_of(LayerKind::Background);
        let p = LayerPatch { output: Some(RewardOutput::Rain), ..Default::default() };
        assert!(p.apply(bg).unwrap_err().contains("output"));
        let none = LayerPatch { sound: Some(Background::None), ..Default::default() };
        assert!(none.apply(bg).is_err());
        let loud = LayerPatch { volume: Some(1.5), ..Default::default() };
        assert!(loud.apply(bg).is_err());
        let ok = LayerPatch { sound: Some(Background::Rain), volume: Some(0.2), ..Default::default() };
        assert_eq!(ok.apply(bg).unwrap(), LayerConfig::Background { sound: Background::Rain, volume: 0.2 });
    }

    #[test]
    fn first_layer_drives_the_engine_slots() {
        let g = guarded();
        let caps = Caps::of(&g);
        let mut audio = AudioSettings::default();
        let mut guard = false;
        let mut s = LayerStack::seed(&g, &audio, guard);
        let first = s.primary(LayerKind::Feedback).unwrap().id;
        s.configure(first, &LayerPatch { output: Some(RewardOutput::Rain), ..Default::default() }).unwrap();
        let second =
            s.add(LayerConfig::Feedback { output: RewardOutput::Binaural, binaural: BinauralPreset::DeepSleep, volume: 0.3 }).unwrap();
        push(&s, &mut audio, &mut guard, caps);
        assert_eq!((audio.reward, audio.feedback), (RewardOutput::Rain, 1.0), "the second layer does not leak into the slot");
        s.remove(first).unwrap();
        push(&s, &mut audio, &mut guard, caps);
        assert_eq!((audio.reward, audio.binaural), (RewardOutput::Binaural, BinauralPreset::DeepSleep));
        s.remove(second).unwrap();
        push(&s, &mut audio, &mut guard, caps);
        assert_eq!(audio.reward, RewardOutput::None);
        s.add(LayerConfig::default_of(LayerKind::Guardrail)).unwrap();
        push(&s, &mut audio, &mut guard, caps);
        assert!(guard, "a guardrail layer switches the guard on");
    }

    #[test]
    fn engine_changes_pull_into_the_stack_and_round_trip() {
        let g = guarded();
        let caps = Caps::of(&g);
        let mut audio = AudioSettings::default();
        let mut s = LayerStack::seed(&g, &audio, false);
        audio.background = Background::None;
        audio.guard = GuardSound::Alarm;
        pull(&mut s, &audio, true, caps);
        assert_eq!(s.count(LayerKind::Background), 0);
        assert_eq!(
            s.primary(LayerKind::Guardrail).map(|l| l.config),
            Some(LayerConfig::Guardrail { sound: GuardSound::Alarm, volume: 1.0 })
        );
        let (mut a2, mut g2) = (audio, true);
        push(&s, &mut a2, &mut g2, caps);
        assert_eq!((a2, g2), (audio, true), "push after pull changes nothing");
        pull(&mut s, &audio, false, caps);
        assert_eq!(s.count(LayerKind::Guardrail), 0);
    }

    #[test]
    fn recents_are_newest_first_unique_and_bounded() {
        let mut r = Vec::new();
        for id in ["a", "b", "c", "a", "d", "e", "f", "g"] {
            touch_recent(&mut r, id);
        }
        assert_eq!(r, ["g", "f", "e", "d", "a", "c"]);
        assert_eq!(r.len(), RECENT_KEPT);
        touch_recent(&mut r, "c");
        assert_eq!(r[0], "c");
        assert_eq!(r.iter().filter(|x| *x == "c").count(), 1);
    }
}
