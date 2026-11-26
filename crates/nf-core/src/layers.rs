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
//!
//! Volumes: the **group** volume (master, background, feedback, guardrail,
//! intro, end bell) lives in `AudioSettings` and is the main control. A
//! layer's own `volume` (0..=1, default 1) is relative inside its group and is
//! only shown when the group has several layers ([`LayerStack::shows_volume`]).
//! The engine does not apply the per-layer volume yet.

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

/// Music source and filter of one layer (used when its sound is Music).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct MusicSettings {
    /// Folder with .ogg/.mp3/.flac/.wav; `None` = not chosen.
    pub folder: Option<String>,
    /// Low-pass range, Hz, mapped from score 0..100.
    pub min_hz: f64,
    pub max_hz: f64,
    /// High scores close the filter instead of opening it.
    pub invert: bool,
    /// Play the tracks in random order.
    pub shuffle: bool,
}

impl MusicSettings {
    /// Cutoff slider bounds, Hz.
    pub const CUTOFF_MIN_HZ: f64 = 200.0;
    pub const CUTOFF_MAX_HZ: f64 = 8000.0;
    /// Longest folder path accepted.
    pub const MAX_FOLDER_LEN: usize = 1024;

    /// Collapsed sub-line: "<folder> • low-pass 200–8000 Hz".
    pub fn summary(&self) -> String {
        let name = self.folder.as_deref().map(folder_name).filter(|n| !n.is_empty()).unwrap_or("no folder");
        let inv = if self.invert { " (inverted)" } else { "" };
        format!("{name} • low-pass {:.0}–{:.0} Hz{inv}", self.min_hz, self.max_hz)
    }
}

impl Default for MusicSettings {
    fn default() -> Self {
        let d = AudioSettings::default();
        Self { folder: None, min_hz: d.music_min_hz, max_hz: d.music_max_hz, invert: d.music_invert, shuffle: false }
    }
}

/// Last path component (either separator), for display.
fn folder_name(path: &str) -> &str {
    path.trim_end_matches(['/', '\\']).rsplit(['/', '\\']).next().unwrap_or(path)
}

/// Per-kind settings of one layer. `volume` is 0..=1, relative inside the group.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum LayerConfig {
    Background { sound: Background, volume: f64, music: MusicSettings },
    Feedback { output: RewardOutput, binaural: BinauralPreset, volume: f64, music: MusicSettings },
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
            LayerKind::Background => Self::Background { sound: d.background, volume: 1.0, music: MusicSettings::default() },
            LayerKind::Feedback => Self::Feedback { output: d.reward, binaural: d.binaural, volume: 1.0, music: MusicSettings::default() },
            LayerKind::Guardrail => Self::Guardrail { sound: d.guard, volume: 1.0 },
        }
    }

    /// The music settings, when the layer's sound is Music.
    pub fn music(&self) -> Option<&MusicSettings> {
        match self {
            Self::Background { sound: Background::Music, music, .. } | Self::Feedback { output: RewardOutput::Music, music, .. } => {
                Some(music)
            }
            _ => None,
        }
    }

    pub fn volume(&self) -> f64 {
        match self {
            Self::Background { volume, .. } | Self::Feedback { volume, .. } | Self::Guardrail { volume, .. } => *volume,
        }
    }

    /// One-line summary for the tile subtitle.
    pub fn summary(&self) -> String {
        match self {
            Self::Background { sound: Background::Music, music, .. } | Self::Feedback { output: RewardOutput::Music, music, .. } => {
                music.summary()
            }
            Self::Background { sound, .. } => format!("{sound:?}"),
            Self::Feedback { output: RewardOutput::Binaural, binaural, .. } => format!("Binaural · {}", binaural.label()),
            Self::Feedback { output, .. } => format!("{output:?}"),
            Self::Guardrail { sound, .. } => format!("{sound:?}"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
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
    /// Background: drone | drone_loop | rain | binaural | music (remove the layer for none).
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
    /// All kinds, 0..=1: relative to the group volume (`volume.set`).
    #[serde(default)]
    pub volume: Option<f64>,
    /// Background / feedback: music folder; "" clears it.
    #[serde(default)]
    pub music_folder: Option<String>,
    /// Background / feedback: low-pass range, Hz (200..=8000, max at least 50 above min).
    #[serde(default)]
    pub music_min_hz: Option<f64>,
    #[serde(default)]
    pub music_max_hz: Option<f64>,
    /// Background / feedback: high scores close the filter.
    #[serde(default)]
    pub music_invert: Option<bool>,
    /// Background / feedback: shuffle the track order.
    #[serde(default)]
    pub music_shuffle: Option<bool>,
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
        set.iter().find(|(_, on, k)| *on && *k != kind).map(|(f, ..)| *f).or_else(|| self.foreign_music_field(kind))
    }

    fn foreign_music_field(&self, kind: LayerKind) -> Option<&'static str> {
        let set = [
            ("music_folder", self.music_folder.is_some()),
            ("music_min_hz", self.music_min_hz.is_some()),
            ("music_max_hz", self.music_max_hz.is_some()),
            ("music_invert", self.music_invert.is_some()),
            ("music_shuffle", self.music_shuffle.is_some()),
        ];
        set.iter().find(|(_, on)| *on && kind == LayerKind::Guardrail).map(|(f, _)| *f)
    }

    /// `music` with the music fields applied; errors leave nothing changed.
    fn apply_music(&self, m: &MusicSettings) -> Result<MusicSettings, String> {
        let mut m = m.clone();
        if let Some(f) = &self.music_folder {
            let f = f.trim();
            if f.len() > MusicSettings::MAX_FOLDER_LEN {
                return Err(format!("music_folder is longer than {} bytes", MusicSettings::MAX_FOLDER_LEN));
            }
            m.folder = Some(f.to_owned()).filter(|f| !f.is_empty());
        }
        m.min_hz = self.music_min_hz.unwrap_or(m.min_hz);
        m.max_hz = self.music_max_hz.unwrap_or(m.max_hz);
        let (lo, hi) = (MusicSettings::CUTOFF_MIN_HZ, MusicSettings::CUTOFF_MAX_HZ);
        if !(m.min_hz.is_finite() && m.max_hz.is_finite() && m.min_hz >= lo && m.max_hz <= hi && m.min_hz + 50.0 <= m.max_hz) {
            return Err(format!("cutoff range must be within {lo}..={hi} Hz with max at least 50 Hz above min"));
        }
        m.invert = self.music_invert.unwrap_or(m.invert);
        m.shuffle = self.music_shuffle.unwrap_or(m.shuffle);
        Ok(m)
    }

    /// `cfg` with the patch applied; nothing changes on error.
    pub fn apply(&self, cfg: &LayerConfig) -> Result<LayerConfig, String> {
        let kind = cfg.kind();
        let cfg = cfg.clone();
        if let Some(v) = self.volume.filter(|v| !(0.0..=1.0).contains(v)) {
            return Err(format!("volume must be in [0, 1], got {v}"));
        }
        if let Some(f) = self.foreign_field(kind) {
            return Err(wrong(f, kind));
        }
        let vol = self.volume;
        Ok(match cfg {
            LayerConfig::Background { sound, volume, music } => {
                let sound = self.sound.unwrap_or(sound);
                if sound == Background::None {
                    return Err("a background layer needs a sound; remove the layer for none".into());
                }
                LayerConfig::Background { sound, volume: vol.unwrap_or(volume), music: self.apply_music(&music)? }
            }
            LayerConfig::Feedback { output, binaural, volume, music } => LayerConfig::Feedback {
                output: self.output.unwrap_or(output),
                binaural: self.binaural.unwrap_or(binaural),
                volume: vol.unwrap_or(volume),
                music: self.apply_music(&music)?,
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
    pub fn seed(p: &Protocol, audio: &AudioSettings, guard: bool, music_dir: Option<&str>) -> Self {
        let mut s = Self { seeded_from: p.id.clone(), ..Self::default() };
        if audio.background != Background::None {
            s.insert(LayerConfig::Background { sound: audio.background, volume: 1.0, music: MusicSettings::default() });
        }
        if !p.guard_only {
            s.insert(LayerConfig::Feedback {
                output: audio.reward,
                binaural: audio.binaural,
                volume: 1.0,
                music: music_of(audio, music_dir),
            });
        }
        if p.guard.is_some() && guard {
            s.insert(LayerConfig::Guardrail { sound: audio.guard, volume: 1.0 });
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

    /// A layer's own volume slider is shown only when its group has several
    /// layers; with one layer the group slider is the control.
    pub fn shows_volume(&self, kind: LayerKind) -> bool {
        self.count(kind) > 1
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
        let (id, kind) = (self.next_id, config.kind());
        let at = self.layers.partition_point(|l| l.config.kind() <= kind);
        self.layers.insert(at, Layer { id, config });
        id
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
        layer.config = patch.apply(&layer.config)?;
        Ok(layer.clone())
    }

    fn remove_kind(&mut self, kind: LayerKind) {
        self.layers.retain(|l| l.config.kind() != kind);
    }

    /// Make `config` the first layer of its kind (insert when none), but keep
    /// that layer's own volume and the settings the engine slot does not carry.
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

/// Music settings the engine slot carries (the shuffle flag is layer-only).
fn music_of(audio: &AudioSettings, dir: Option<&str>) -> MusicSettings {
    MusicSettings {
        folder: dir.map(str::to_owned),
        min_hz: audio.music_min_hz,
        max_hz: audio.music_max_hz,
        invert: audio.music_invert,
        shuffle: false,
    }
}

/// Stack → engine slots (after a layer command): the first layer of a kind
/// drives its slot; no layer of a kind silences / disables it. Group volumes
/// are not touched (they belong to `AudioSettings`).
pub fn push(stack: &LayerStack, audio: &mut AudioSettings, guard: &mut bool, music_dir: &mut Option<String>, caps: Caps) {
    match stack.primary(LayerKind::Background).map(|l| &l.config) {
        Some(LayerConfig::Background { sound, .. }) => audio.background = *sound,
        _ => audio.background = Background::None,
    }
    match stack.primary(LayerKind::Feedback).map(|l| &l.config) {
        Some(LayerConfig::Feedback { output, binaural, music, .. }) => {
            (audio.reward, audio.binaural) = (*output, *binaural);
            (audio.music_min_hz, audio.music_max_hz, audio.music_invert) = (music.min_hz, music.max_hz, music.invert);
            music_dir.clone_from(&music.folder);
        }
        _ => audio.reward = RewardOutput::None,
    }
    match stack.primary(LayerKind::Guardrail).map(|l| &l.config) {
        Some(LayerConfig::Guardrail { sound, .. }) => {
            audio.guard = *sound;
            *guard = *guard || caps.guard;
        }
        _ if caps.guard => *guard = false,
        _ => {}
    }
    *audio = audio.sanitized();
}

/// Engine slots → stack (after `audio.set` / `guard.set`), so the old path and
/// the layers never disagree. Idempotent: `push` after `pull` changes nothing.
/// The first layer keeps its own volume and shuffle flag.
pub fn pull(stack: &mut LayerStack, audio: &AudioSettings, guard: bool, music_dir: Option<&str>, caps: Caps) {
    if audio.background == Background::None {
        stack.remove_kind(LayerKind::Background);
    } else {
        let mut cfg =
            stack.primary(LayerKind::Background).map_or_else(|| LayerConfig::default_of(LayerKind::Background), |l| l.config.clone());
        if let LayerConfig::Background { sound, .. } = &mut cfg {
            *sound = audio.background;
        }
        stack.set_primary(cfg);
    }
    if !caps.guard_only && (audio.reward != RewardOutput::None || stack.primary(LayerKind::Feedback).is_some()) {
        let mut cfg = stack.primary(LayerKind::Feedback).map_or_else(|| LayerConfig::default_of(LayerKind::Feedback), |l| l.config.clone());
        if let LayerConfig::Feedback { output, binaural, music, .. } = &mut cfg {
            (*output, *binaural) = (audio.reward, audio.binaural);
            let shuffle = music.shuffle;
            *music = MusicSettings { shuffle, ..music_of(audio, music_dir) };
        }
        stack.set_primary(cfg);
    }
    if caps.guard && !guard {
        stack.remove_kind(LayerKind::Guardrail);
    } else if caps.guard {
        let mut cfg =
            stack.primary(LayerKind::Guardrail).map_or_else(|| LayerConfig::default_of(LayerKind::Guardrail), |l| l.config.clone());
        if let LayerConfig::Guardrail { sound, .. } = &mut cfg {
            *sound = audio.guard;
        }
        stack.set_primary(cfg);
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
        let plain = LayerStack::seed(&proto("alertOpen"), &a, true, None);
        assert_eq!(plain.count(LayerKind::Guardrail), 0, "no guard lane, no guardrail section");
        assert_eq!(plain.count(LayerKind::Feedback), 1);
        assert_eq!(plain.seeded_from, "alertOpen");
        let g = guarded();
        assert_eq!(LayerStack::seed(&g, &a, true, None).count(LayerKind::Guardrail), 1);
        assert_eq!(LayerStack::seed(&g, &a, false, None).count(LayerKind::Guardrail), 0, "guard switched off");
        let no_bg = AudioSettings { background: Background::None, ..a };
        assert_eq!(LayerStack::seed(&g, &no_bg, true, None).count(LayerKind::Background), 0);
        let sleep = nf_feedback::builtin().into_iter().find(|p| p.guard_only).unwrap();
        assert_eq!(LayerStack::seed(&sleep, &a, true, None).count(LayerKind::Feedback), 0, "guard-only has no reward lane");
    }

    #[test]
    fn patches_check_kind_and_range() {
        let bg = LayerConfig::default_of(LayerKind::Background);
        let p = LayerPatch { output: Some(RewardOutput::Rain), ..Default::default() };
        assert!(p.apply(&bg).unwrap_err().contains("output"));
        let none = LayerPatch { sound: Some(Background::None), ..Default::default() };
        assert!(none.apply(&bg).is_err());
        let loud = LayerPatch { volume: Some(1.5), ..Default::default() };
        assert!(loud.apply(&bg).is_err());
        let ok = LayerPatch { sound: Some(Background::Rain), volume: Some(0.2), ..Default::default() };
        assert_eq!(
            ok.apply(&bg).unwrap(),
            LayerConfig::Background { sound: Background::Rain, volume: 0.2, music: MusicSettings::default() }
        );
    }

    #[test]
    fn first_layer_drives_the_engine_slots() {
        let g = guarded();
        let caps = Caps::of(&g);
        let mut audio = AudioSettings::default();
        let mut guard = false;
        let mut dir = None;
        let mut s = LayerStack::seed(&g, &audio, guard, None);
        let first = s.primary(LayerKind::Feedback).unwrap().id;
        s.configure(first, &LayerPatch { output: Some(RewardOutput::Rain), ..Default::default() }).unwrap();
        let second = s
            .add(LayerConfig::Feedback {
                output: RewardOutput::Binaural,
                binaural: BinauralPreset::DeepSleep,
                volume: 0.3,
                music: MusicSettings::default(),
            })
            .unwrap();
        push(&s, &mut audio, &mut guard, &mut dir, caps);
        assert_eq!((audio.reward, audio.feedback), (RewardOutput::Rain, 1.0), "the second layer does not leak into the slot");
        s.remove(first).unwrap();
        push(&s, &mut audio, &mut guard, &mut dir, caps);
        assert_eq!((audio.reward, audio.binaural), (RewardOutput::Binaural, BinauralPreset::DeepSleep));
        s.remove(second).unwrap();
        push(&s, &mut audio, &mut guard, &mut dir, caps);
        assert_eq!(audio.reward, RewardOutput::None);
        s.add(LayerConfig::default_of(LayerKind::Guardrail)).unwrap();
        push(&s, &mut audio, &mut guard, &mut dir, caps);
        assert!(guard, "a guardrail layer switches the guard on");
    }

    #[test]
    fn engine_changes_pull_into_the_stack_and_round_trip() {
        let g = guarded();
        let caps = Caps::of(&g);
        let mut audio = AudioSettings::default();
        let mut s = LayerStack::seed(&g, &audio, false, None);
        audio.background = Background::None;
        audio.guard = GuardSound::Alarm;
        pull(&mut s, &audio, true, None, caps);
        assert_eq!(s.count(LayerKind::Background), 0);
        assert_eq!(
            s.primary(LayerKind::Guardrail).map(|l| l.config.clone()),
            Some(LayerConfig::Guardrail { sound: GuardSound::Alarm, volume: 1.0 })
        );
        let (mut a2, mut g2) = (audio, true);
        push(&s, &mut a2, &mut g2, &mut None, caps);
        assert_eq!((a2, g2), (audio, true), "push after pull changes nothing");
        pull(&mut s, &audio, false, None, caps);
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

    fn music_patch() -> LayerPatch {
        LayerPatch { output: Some(RewardOutput::Music), ..Default::default() }
    }

    #[test]
    fn music_settings_default_patch_and_summary() {
        let fb = LayerConfig::default_of(LayerKind::Feedback);
        assert!(fb.music().is_none(), "no music settings unless the sound is Music");
        let p = LayerPatch {
            output: Some(RewardOutput::Music),
            music_folder: Some(" /home/u/Music/calm/ ".into()),
            music_min_hz: Some(300.0),
            music_max_hz: Some(4000.0),
            music_invert: Some(true),
            music_shuffle: Some(true),
            ..Default::default()
        };
        let cfg = p.apply(&fb).unwrap();
        let m = cfg.music().unwrap();
        assert_eq!(m.folder.as_deref(), Some("/home/u/Music/calm/"));
        assert!(m.invert && m.shuffle);
        assert_eq!(cfg.summary(), "calm • low-pass 300–4000 Hz (inverted)");
        let cleared = LayerPatch { music_folder: Some(String::new()), ..Default::default() }.apply(&cfg).unwrap();
        assert_eq!(cleared.music().unwrap().folder, None);
        assert_eq!(MusicSettings::default().summary(), "no folder • low-pass 200–8000 Hz");
        assert_eq!(folder_name("C:\\Music\\Jazz"), "Jazz");
    }

    #[test]
    fn music_patch_rejects_bad_ranges_and_foreign_kinds() {
        let fb = LayerConfig::default_of(LayerKind::Feedback);
        for (lo, hi) in [(100.0, 4000.0), (300.0, 9000.0), (3000.0, 3020.0), (f64::NAN, 4000.0), (5000.0, 400.0)] {
            let p = LayerPatch { music_min_hz: Some(lo), music_max_hz: Some(hi), ..Default::default() };
            assert!(p.apply(&fb).unwrap_err().contains("cutoff"), "{lo}..{hi}");
        }
        let long = LayerPatch { music_folder: Some("x".repeat(MusicSettings::MAX_FOLDER_LEN + 1)), ..Default::default() };
        assert!(long.apply(&fb).is_err());
        let guard = LayerConfig::default_of(LayerKind::Guardrail);
        let p = LayerPatch { music_shuffle: Some(true), ..Default::default() };
        assert!(p.apply(&guard).unwrap_err().contains("music_shuffle"));
        let bg = LayerPatch { sound: Some(Background::Music), music_invert: Some(true), ..Default::default() };
        assert!(
            bg.apply(&LayerConfig::default_of(LayerKind::Background)).unwrap().music().unwrap().invert,
            "background layers can be music"
        );
    }

    #[test]
    fn each_layer_keeps_its_own_music_settings() {
        let mut s = LayerStack::default();
        let a = s.add(LayerConfig::default_of(LayerKind::Feedback)).unwrap();
        let b = s.add(LayerConfig::default_of(LayerKind::Feedback)).unwrap();
        for (id, dir) in [(a, "/m/one"), (b, "/m/two")] {
            let p = LayerPatch { music_folder: Some(dir.into()), ..music_patch() };
            s.configure(id, &p).unwrap();
        }
        let folders: Vec<_> = s.layers().iter().map(|l| l.config.music().and_then(|m| m.folder.clone())).collect();
        assert_eq!(folders, [Some("/m/one".to_owned()), Some("/m/two".to_owned())]);
    }

    #[test]
    fn layer_volume_slider_shows_only_when_the_group_has_several_layers() {
        let mut s = LayerStack::default();
        assert!(!s.shows_volume(LayerKind::Feedback), "no layer");
        let a = s.add(LayerConfig::default_of(LayerKind::Feedback)).unwrap();
        s.add(LayerConfig::default_of(LayerKind::Background)).unwrap();
        assert!(!s.shows_volume(LayerKind::Feedback), "one layer: the group slider is the control");
        let b = s.add(LayerConfig::default_of(LayerKind::Feedback)).unwrap();
        assert!(s.shows_volume(LayerKind::Feedback));
        assert!(!s.shows_volume(LayerKind::Background), "groups are independent");
        s.remove(b).unwrap();
        assert!(!s.shows_volume(LayerKind::Feedback));
        assert!(s.get(a).is_some());
    }

    #[test]
    fn music_settings_map_onto_the_engine_slot_and_back() {
        let g = guarded();
        let caps = Caps::of(&g);
        let mut audio = AudioSettings::default();
        let (mut guard, mut dir) = (false, None);
        let mut s = LayerStack::seed(&g, &audio, guard, None);
        let id = s.primary(LayerKind::Feedback).unwrap().id;
        let p = LayerPatch {
            music_folder: Some("/m/x".into()),
            music_min_hz: Some(400.0),
            music_invert: Some(true),
            music_shuffle: Some(true),
            ..music_patch()
        };
        s.configure(id, &p).unwrap();
        push(&s, &mut audio, &mut guard, &mut dir, caps);
        assert_eq!((audio.reward, audio.music_min_hz, audio.music_invert), (RewardOutput::Music, 400.0, true));
        assert_eq!(dir.as_deref(), Some("/m/x"));
        audio.music_max_hz = 6000.0;
        pull(&mut s, &audio, guard, dir.as_deref(), caps);
        let m = s.get(id).unwrap().config.music().unwrap().clone();
        assert_eq!((m.max_hz, m.shuffle, m.folder.as_deref()), (6000.0, true, Some("/m/x")), "shuffle is layer-only and survives");
    }

    #[test]
    fn group_volumes_are_not_overwritten_by_layer_volumes() {
        let g = guarded();
        let caps = Caps::of(&g);
        let mut audio = AudioSettings { feedback: 0.3, ..AudioSettings::default() };
        let (mut guard, mut dir) = (true, None);
        let mut s = LayerStack::seed(&g, &audio, guard, None);
        let id = s.primary(LayerKind::Feedback).unwrap().id;
        s.configure(id, &LayerPatch { volume: Some(0.5), ..Default::default() }).unwrap();
        push(&s, &mut audio, &mut guard, &mut dir, caps);
        assert_eq!(audio.feedback, 0.3);
        pull(&mut s, &audio, guard, None, caps);
        assert_eq!(s.get(id).unwrap().config.volume(), 0.5);
    }
}
