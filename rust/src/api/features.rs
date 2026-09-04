//! Feature registry + FFI (PR 2).
//!
//! JSON names IDs; this module owns per-(device, feature) producer electrodes,
//! availability, enable-set, and the pad-quality formula used to autodrop when
//! aggregating `band.*` features. `FeatureDto` is defined once here.

use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, OnceLock};

use flutter_rust_bridge::frb;

use crate::api::device_config::{DeviceConfig, DeviceKind};

pub(crate) const ID_ATR: &str = "band.atr";
pub(crate) const ID_TAR: &str = "band.tar";
pub(crate) const ID_BTR: &str = "band.btr";
pub(crate) const ID_ALPHA: &str = "band.alpha";
pub(crate) const ID_DELTA: &str = "band.delta";
pub(crate) const ID_DROWSINESS: &str = "ai.drowsiness";
pub(crate) const ID_FOCUS: &str = "device.focus";
pub(crate) const ID_CALM: &str = "device.calm";

/// Keep in sync with Dart `atrUsableSignalThreshold` / `signalGoodThreshold`
/// and the Dart copy of this formula in `connection_provider._maybeComputeSignalQuality`
/// until the Crown-run series deletes the Dart one.
pub(crate) const SIGNAL_GOOD_THRESHOLD: f64 = 80.0;

const EEG_RING_SAMPLES: usize = 256;
const MIN_QUALITY_SAMPLES: usize = 10;

#[frb(dart_metadata = ("freezed",))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeatureSource {
    Band,
    Ai,
    Device,
}

#[frb(dart_metadata = ("freezed",))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeatureLane {
    Reward,
    Guard,
}

#[frb(dart_metadata = ("freezed",))]
#[derive(Debug, Clone)]
pub struct FeatureInfo {
    pub id: String,
    pub source: FeatureSource,
    pub usable_for: Vec<FeatureLane>,
    pub default_electrodes: Vec<String>,
    pub native_rate_hz: f32,
    pub available: bool,
    pub unavailable_reason: Option<String>,
}

#[frb(dart_metadata = ("freezed",))]
#[derive(Debug, Clone)]
pub struct FeatureDto {
    pub id: String,
    pub timestamp: f64,
    pub value: f64,
}

struct Spec {
    id: &'static str,
    source: FeatureSource,
    usable_for: &'static [FeatureLane],
    muse_electrodes: &'static [&'static str],
    crown_electrodes: &'static [&'static str],
    native_rate_hz: f32,
    muse_available: bool,
    crown_available: bool,
    unavailable_muse: Option<&'static str>,
    unavailable_crown: Option<&'static str>,
}

const SPECS: &[Spec] = &[
    Spec {
        id: ID_ATR,
        source: FeatureSource::Band,
        usable_for: &[FeatureLane::Reward],
        muse_electrodes: &["AF7", "AF8"],
        crown_electrodes: &["PO3", "PO4"],
        native_rate_hz: 1.0,
        muse_available: true,
        crown_available: true,
        unavailable_muse: None,
        unavailable_crown: None,
    },
    Spec {
        id: ID_TAR,
        source: FeatureSource::Band,
        usable_for: &[FeatureLane::Reward],
        muse_electrodes: &["AF7", "AF8"],
        crown_electrodes: &["PO3", "PO4"],
        native_rate_hz: 1.0,
        muse_available: true,
        crown_available: true,
        unavailable_muse: None,
        unavailable_crown: None,
    },
    Spec {
        id: ID_BTR,
        source: FeatureSource::Band,
        usable_for: &[FeatureLane::Reward],
        muse_electrodes: &["AF7", "AF8"],
        crown_electrodes: &["PO3", "PO4"],
        native_rate_hz: 1.0,
        muse_available: true,
        crown_available: true,
        unavailable_muse: None,
        unavailable_crown: None,
    },
    Spec {
        id: ID_ALPHA,
        source: FeatureSource::Band,
        usable_for: &[FeatureLane::Reward],
        muse_electrodes: &["AF7", "AF8"],
        crown_electrodes: &["PO3", "PO4"],
        native_rate_hz: 1.0,
        muse_available: true,
        crown_available: true,
        unavailable_muse: None,
        unavailable_crown: None,
    },
    Spec {
        id: ID_DELTA,
        source: FeatureSource::Band,
        usable_for: &[FeatureLane::Guard],
        muse_electrodes: &["AF7", "AF8"],
        crown_electrodes: &["PO3", "PO4"],
        native_rate_hz: 1.0,
        muse_available: true,
        crown_available: true,
        unavailable_muse: None,
        unavailable_crown: None,
    },
    Spec {
        id: ID_DROWSINESS,
        source: FeatureSource::Ai,
        usable_for: &[FeatureLane::Guard],
        muse_electrodes: &["AF7", "AF8", "TP9", "TP10"],
        crown_electrodes: &[],
        native_rate_hz: 1.0,
        muse_available: true,
        crown_available: false,
        unavailable_muse: None,
        unavailable_crown: Some("ai.drowsiness is Muse-only"),
    },
    Spec {
        id: ID_FOCUS,
        source: FeatureSource::Device,
        usable_for: &[FeatureLane::Reward, FeatureLane::Guard],
        muse_electrodes: &[],
        crown_electrodes: &[],
        native_rate_hz: 4.0,
        muse_available: false,
        crown_available: true,
        unavailable_muse: Some("device.focus is Crown-native"),
        unavailable_crown: None,
    },
    Spec {
        id: ID_CALM,
        source: FeatureSource::Device,
        usable_for: &[FeatureLane::Reward, FeatureLane::Guard],
        muse_electrodes: &[],
        crown_electrodes: &[],
        native_rate_hz: 4.0,
        muse_available: false,
        crown_available: true,
        unavailable_muse: Some("device.calm is Crown-native"),
        unavailable_crown: None,
    },
];

#[frb(ignore)]
struct Registry {
    enabled: HashSet<String>,
    electrode_overrides: HashMap<String, Vec<String>>,
    active_kind: Option<DeviceKind>,
    /// Crown `/signalQuality` mapped 0–1 → 0–100. `None` until the first packet.
    crown_quality: [Option<f64>; 8],
}

impl Default for Registry {
    fn default() -> Self {
        Self {
            enabled: HashSet::new(),
            electrode_overrides: HashMap::new(),
            active_kind: None,
            crown_quality: [None; 8],
        }
    }
}

fn registry() -> &'static Mutex<Registry> {
    static REG: OnceLock<Mutex<Registry>> = OnceLock::new();
    REG.get_or_init(|| Mutex::new(Registry::default()))
}

fn spec_by_id(id: &str) -> Option<&'static Spec> {
    SPECS.iter().find(|s| s.id == id)
}

fn is_neurosity(kind: DeviceKind) -> bool {
    kind.is_neurosity()
}

fn default_electrode_names(spec: &Spec, kind: DeviceKind) -> Vec<String> {
    let names = if is_neurosity(kind) {
        spec.crown_electrodes
    } else {
        spec.muse_electrodes
    };
    names.iter().map(|s| (*s).to_string()).collect()
}

fn available_on(spec: &Spec, kind: DeviceKind) -> (bool, Option<String>) {
    if is_neurosity(kind) {
        (
            spec.crown_available,
            spec.unavailable_crown.map(|s| s.to_string()),
        )
    } else {
        (
            spec.muse_available,
            spec.unavailable_muse.map(|s| s.to_string()),
        )
    }
}

fn all_known_electrode_names() -> HashSet<String> {
    let mut names = HashSet::new();
    for n in DeviceConfig::muse().electrode_names {
        names.insert(n.to_ascii_lowercase());
    }
    for n in DeviceConfig::neurosity_crown().electrode_names {
        names.insert(n.to_ascii_lowercase());
    }
    names
}

/// Sync Rust; FRB 2.11.1 exposes a Dart `Future` (not `#[frb(sync)]`).
pub fn available_features(kind: DeviceKind) -> Vec<FeatureInfo> {
    SPECS
        .iter()
        .map(|spec| {
            let (available, reason) = available_on(spec, kind);
            FeatureInfo {
                id: spec.id.to_string(),
                source: spec.source,
                usable_for: spec.usable_for.to_vec(),
                default_electrodes: default_electrode_names(spec, kind),
                native_rate_hz: spec.native_rate_hz,
                available,
                unavailable_reason: if available { None } else { reason },
            }
        })
        .collect()
}

/// Replace-set. Unknown / unavailable-on-active-kind ids → Err.
/// Empty vec unsubscribes all subscribed features. No headset → store the set.
pub fn set_enabled_features(ids: Vec<String>) -> anyhow::Result<()> {
    let mut seen = HashSet::new();
    let mut unique = Vec::new();
    for id in ids {
        if !seen.insert(id.clone()) {
            continue;
        }
        unique.push(id);
    }

    let mut reg = registry().lock().unwrap_or_else(|e| e.into_inner());
    for id in &unique {
        let spec = spec_by_id(id).ok_or_else(|| anyhow::anyhow!("unknown feature id: {id}"))?;
        if let Some(kind) = reg.active_kind {
            let (ok, reason) = available_on(spec, kind);
            if !ok {
                anyhow::bail!(
                    "{}",
                    reason.unwrap_or_else(|| format!("{id} is unavailable on this device"))
                );
            }
        }
    }
    reg.enabled = unique.into_iter().collect();
    Ok(())
}

/// Optional override; names, not indices. Empty names reset to default.
pub fn set_feature_electrodes(id: String, names: Vec<String>) -> anyhow::Result<()> {
    let spec = spec_by_id(&id).ok_or_else(|| anyhow::anyhow!("unknown feature id: {id}"))?;
    if spec.source == FeatureSource::Device {
        anyhow::bail!("{id} has no montage");
    }

    let mut reg = registry().lock().unwrap_or_else(|e| e.into_inner());
    if matches!(reg.active_kind, Some(DeviceKind::Neurosity)) && spec.id == ID_DROWSINESS {
        anyhow::bail!("ai.drowsiness is Muse-only");
    }

    if names.is_empty() {
        reg.electrode_overrides.remove(&id);
        return Ok(());
    }

    if spec.source == FeatureSource::Device {
        anyhow::bail!("{id} has no montage");
    }

    let known = if let Some(kind) = reg.active_kind {
        DeviceConfig::for_kind(kind)
            .electrode_names
            .into_iter()
            .map(|n| n.to_ascii_lowercase())
            .collect::<HashSet<_>>()
    } else {
        all_known_electrode_names()
    };
    for name in &names {
        if !known.contains(&name.to_ascii_lowercase()) {
            anyhow::bail!("unknown electrode name: {name}");
        }
    }
    reg.electrode_overrides.insert(id, names);
    Ok(())
}

pub(crate) fn is_enabled(id: &str) -> bool {
    registry()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .enabled
        .contains(id)
}

pub(crate) fn enabled_ids() -> Vec<String> {
    registry()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .enabled
        .iter()
        .cloned()
        .collect()
}

pub(crate) fn set_active_kind(kind: DeviceKind) {
    let mut reg = registry().lock().unwrap_or_else(|e| e.into_inner());
    reg.active_kind = Some(kind);
    reg.crown_quality = [None; 8];
}

pub(crate) fn clear_active_kind() {
    let mut reg = registry().lock().unwrap_or_else(|e| e.into_inner());
    reg.active_kind = None;
    reg.crown_quality = [None; 8];
}

pub(crate) fn active_kind() -> Option<DeviceKind> {
    registry()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .active_kind
}

/// Store Crown `/signalQuality` (0–1) as 0–100 for band-feature autodrop.
pub(crate) fn set_crown_quality(channel: usize, q_0_1: f32) {
    if channel >= 8 {
        return;
    }
    let mut reg = registry().lock().unwrap_or_else(|e| e.into_inner());
    reg.crown_quality[channel] = Some((q_0_1 as f64).clamp(0.0, 1.0) * 100.0);
}

pub(crate) fn crown_quality(channel: usize) -> Option<f64> {
    if channel >= 8 {
        return None;
    }
    registry()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .crown_quality[channel]
}

pub(crate) fn resolved_electrode_names(kind: DeviceKind, id: &str) -> anyhow::Result<Vec<String>> {
    let spec = spec_by_id(id).ok_or_else(|| anyhow::anyhow!("unknown feature id: {id}"))?;
    let (ok, reason) = available_on(spec, kind);
    if !ok {
        anyhow::bail!(
            "{}",
            reason.unwrap_or_else(|| format!("{id} is unavailable on this device"))
        );
    }
    let reg = registry().lock().unwrap_or_else(|e| e.into_inner());
    if let Some(over) = reg.electrode_overrides.get(id) {
        return Ok(over.clone());
    }
    Ok(default_electrode_names(spec, kind))
}

pub(crate) fn resolved_electrode_indices(kind: DeviceKind, id: &str) -> anyhow::Result<Vec<usize>> {
    let names = resolved_electrode_names(kind, id)?;
    let config = DeviceConfig::for_kind(kind);
    let mut out = Vec::with_capacity(names.len());
    for name in names {
        let idx = config
            .electrode_index(&name)
            .ok_or_else(|| anyhow::anyhow!("unknown electrode name: {name}"))?;
        out.push(idx);
    }
    Ok(out)
}

/// Keep in sync with Dart `_maybeComputeSignalQuality` until the Crown-run
/// series deletes the Dart copy. `noise < 0` means "no Bands yet" (no penalty).
pub(crate) fn pad_quality_from_std_and_noise(std: f64, noise: f64) -> f64 {
    let mut score = if std < 1.0 || std > 100.0 {
        0.0
    } else if std < 15.0 {
        80.0 + (15.0 - std) / 15.0 * 20.0
    } else if std < 40.0 {
        50.0 + (40.0 - std) / 25.0 * 25.0
    } else {
        let s = 40.0 * (100.0 - std) / 60.0;
        if s < 0.0 {
            0.0
        } else {
            s
        }
    };
    if noise >= 0.0 {
        let penalty = ((noise - 0.2) / 0.3).clamp(0.0, 1.0);
        score *= 1.0 - 0.6 * penalty;
    }
    score
}

pub(crate) fn sample_std(samples: &[f64]) -> Option<f64> {
    let n = samples.len();
    if n < MIN_QUALITY_SAMPLES {
        return None;
    }
    let mean = samples.iter().sum::<f64>() / n as f64;
    let var = samples.iter().map(|s| (s - mean) * (s - mean)).sum::<f64>() / n as f64;
    Some(var.sqrt())
}

#[frb(ignore)]
#[derive(Clone, Copy, Default)]
pub(crate) struct ChannelBands {
    pub delta: f64,
    pub theta: f64,
    pub alpha: f64,
    pub beta: f64,
    pub gamma: f64,
    pub line_noise_ratio: f64,
}

fn relative(b: ChannelBands) -> Option<(f64, f64, f64, f64, f64)> {
    let total = b.delta + b.theta + b.alpha + b.beta + b.gamma;
    if total <= 0.0 {
        return None;
    }
    Some((
        b.delta / total,
        b.theta / total,
        b.alpha / total,
        b.beta / total,
        b.gamma / total,
    ))
}

/// Average usable pads and compute the native scalar. `None` = skip sample.
pub(crate) fn aggregate_band_feature(id: &str, pads: &[ChannelBands]) -> Option<f64> {
    if pads.is_empty() {
        return None;
    }
    if id == ID_DELTA {
        let sum: f64 = pads.iter().map(|p| p.delta).sum();
        return Some(sum / pads.len() as f64);
    }
    let mut n = 0u32;
    let mut t = 0.0;
    let mut a = 0.0;
    let mut b = 0.0;
    for p in pads {
        let Some(rel) = relative(*p) else {
            continue;
        };
        t += rel.1;
        a += rel.2;
        b += rel.3;
        n += 1;
    }
    if n == 0 {
        return None;
    }
    let inv = 1.0 / n as f64;
    t *= inv;
    a *= inv;
    b *= inv;
    let value = match id {
        ID_ATR => {
            if t <= 0.0 {
                return None;
            }
            a / t
        }
        ID_TAR => {
            if a <= 0.0 {
                return None;
            }
            t / a
        }
        ID_BTR => {
            if t <= 0.0 {
                return None;
            }
            b / t
        }
        ID_ALPHA => a,
        _ => return None,
    };
    if !value.is_finite() {
        return None;
    }
    Some(value)
}

/// 1 s EEG ring used by the Muse quality formula (256 samples @ 256 Hz).
#[frb(ignore)]
pub(crate) struct EegRing {
    samples: Vec<f64>,
}

impl Default for EegRing {
    fn default() -> Self {
        Self::new()
    }
}

impl EegRing {
    pub fn new() -> Self {
        Self {
            samples: Vec::with_capacity(EEG_RING_SAMPLES),
        }
    }

    pub fn extend(&mut self, batch: &[f64]) {
        self.samples.extend_from_slice(batch);
        if self.samples.len() > EEG_RING_SAMPLES {
            let drain = self.samples.len() - EEG_RING_SAMPLES;
            self.samples.drain(..drain);
        }
    }

    pub fn quality(&self, line_noise: f64) -> Option<f64> {
        let std = sample_std(&self.samples)?;
        Some(pad_quality_from_std_and_noise(std, line_noise))
    }
}

/// Pick usable pads and aggregate one enabled `band.*` feature.
///
/// Muse: quality from the 1 s EEG ring + line-noise penalty.
/// Crown: quality from `/signalQuality` × 100. Missing/short quality → skip pad.
pub(crate) fn collect_usable_pads(
    kind: DeviceKind,
    indices: &[usize],
    bands: &HashMap<i32, ChannelBands>,
    rings: &HashMap<i32, EegRing>,
) -> Vec<ChannelBands> {
    let neurosity = is_neurosity(kind);
    let mut picked = Vec::new();
    for &idx in indices {
        let el = idx as i32;
        let Some(ch) = bands.get(&el).copied() else {
            continue;
        };
        let q = if neurosity {
            crown_quality(idx)
        } else {
            let noise = ch.line_noise_ratio;
            rings.get(&el).and_then(|r| r.quality(noise))
        };
        let Some(q) = q else {
            continue;
        };
        if q >= SIGNAL_GOOD_THRESHOLD {
            picked.push(ch);
        }
    }
    picked
}

#[cfg(test)]
mod tests {
    use super::*;

    static TEST_LOCK: Mutex<()> = Mutex::new(());

    fn reset() -> std::sync::MutexGuard<'static, ()> {
        let lock = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let mut reg = registry().lock().unwrap();
        *reg = Registry::default();
        lock
    }

    #[test]
    fn crown_osc_indices_match_device_config_names() {
        let names = DeviceConfig::neurosity_crown().electrode_names;
        assert_eq!(
            names,
            vec!["CP3", "C3", "F5", "PO3", "PO4", "F6", "C4", "CP4"]
        );
        assert_eq!(names[3], "PO3");
        assert_eq!(names[4], "PO4");
        assert_eq!(
            DeviceConfig::neurosity_crown().target_electrodes,
            vec![3, 4]
        );
    }

    #[test]
    fn muse_atr_default_electrodes_are_af7_af8() {
        let _lock = reset();
        let idx = resolved_electrode_indices(DeviceKind::Muse, ID_ATR).unwrap();
        assert_eq!(idx, vec![1, 2]);
        let names = resolved_electrode_names(DeviceKind::Muse, ID_ATR).unwrap();
        assert_eq!(names, vec!["AF7", "AF8"]);
    }

    #[test]
    fn crown_atr_default_electrodes_are_po3_po4() {
        let _lock = reset();
        let idx = resolved_electrode_indices(DeviceKind::Neurosity, ID_ATR).unwrap();
        assert_eq!(idx, vec![3, 4]);
        let names = resolved_electrode_names(DeviceKind::Neurosity, ID_ATR).unwrap();
        assert_eq!(names, vec!["PO3", "PO4"]);
    }

    #[test]
    fn drowsiness_is_muse_only_focus_is_crown_only() {
        let muse = available_features(DeviceKind::Muse);
        let crown = available_features(DeviceKind::Neurosity);
        assert_eq!(muse.len(), 8);
        assert!(
            !crown
                .iter()
                .find(|f| f.id == ID_DROWSINESS)
                .unwrap()
                .available
        );
        assert!(crown.iter().find(|f| f.id == ID_FOCUS).unwrap().available);
        assert!(!muse.iter().find(|f| f.id == ID_FOCUS).unwrap().available);
    }

    #[test]
    fn set_enabled_rejects_unknown_and_unavailable() {
        let _lock = reset();
        assert!(set_enabled_features(vec!["bands".into()]).is_err());
        assert!(set_enabled_features(vec!["nope".into()]).is_err());
        assert!(set_enabled_features(vec![ID_DROWSINESS.into()]).is_ok());
        set_active_kind(DeviceKind::Neurosity);
        assert!(set_enabled_features(vec![ID_DROWSINESS.into()]).is_err());
        assert!(set_enabled_features(vec![ID_FOCUS.into()]).is_ok());
        set_active_kind(DeviceKind::Muse);
        assert!(set_enabled_features(vec![ID_FOCUS.into()]).is_err());
        assert!(set_enabled_features(vec![]).is_ok());
        assert!(!is_enabled(ID_FOCUS));
    }

    #[test]
    fn set_enabled_dedupes_and_replace_set() {
        let _lock = reset();
        set_enabled_features(vec![ID_ATR.into(), ID_ATR.into(), ID_DELTA.into()]).unwrap();
        let mut ids = enabled_ids();
        ids.sort();
        assert_eq!(ids, vec![ID_ATR, ID_DELTA]);
        set_enabled_features(vec![ID_ALPHA.into()]).unwrap();
        assert!(is_enabled(ID_ALPHA));
        assert!(!is_enabled(ID_ATR));
    }

    #[test]
    fn set_feature_electrodes_names_and_reset() {
        let _lock = reset();
        set_feature_electrodes(ID_ATR.into(), vec!["TP9".into(), "TP10".into()]).unwrap();
        assert_eq!(
            resolved_electrode_names(DeviceKind::Muse, ID_ATR).unwrap(),
            vec!["TP9", "TP10"]
        );
        set_feature_electrodes(ID_ATR.into(), vec![]).unwrap();
        assert_eq!(
            resolved_electrode_names(DeviceKind::Muse, ID_ATR).unwrap(),
            vec!["AF7", "AF8"]
        );
        assert!(set_feature_electrodes(ID_ATR.into(), vec!["nope".into()]).is_err());
        assert!(set_feature_electrodes(ID_FOCUS.into(), vec!["AF7".into()]).is_err());
        set_active_kind(DeviceKind::Neurosity);
        assert!(set_feature_electrodes(ID_DROWSINESS.into(), vec!["AF7".into()]).is_err());
    }

    #[test]
    fn quality_formula_matches_dart_branches() {
        assert_eq!(pad_quality_from_std_and_noise(0.5, -1.0), 0.0);
        assert_eq!(pad_quality_from_std_and_noise(101.0, -1.0), 0.0);
        let s15 = pad_quality_from_std_and_noise(10.0, -1.0);
        assert!((s15 - (80.0 + 5.0 / 15.0 * 20.0)).abs() < 1e-9);
        let s40 = pad_quality_from_std_and_noise(30.0, -1.0);
        assert!((s40 - (50.0 + 10.0 / 25.0 * 25.0)).abs() < 1e-9);
        let s60 = pad_quality_from_std_and_noise(70.0, -1.0);
        assert!((s60 - (40.0 * 30.0 / 60.0)).abs() < 1e-9);
        let with_noise = pad_quality_from_std_and_noise(10.0, 0.5);
        let penalty = ((0.5_f64 - 0.2) / 0.3).clamp(0.0, 1.0);
        assert!((with_noise - s15 * (1.0 - 0.6 * penalty)).abs() < 1e-9);
    }

    #[test]
    fn short_ring_skips_quality() {
        let mut ring = EegRing::new();
        ring.extend(&[1.0; 9]);
        assert!(ring.quality(-1.0).is_none());
        ring.extend(&[1.0; 1]);
        assert!(ring.quality(-1.0).is_some());
    }

    #[test]
    fn collect_usable_pads_skips_missing_and_bad() {
        let _lock = reset();
        let mut bands = HashMap::new();
        bands.insert(
            1,
            ChannelBands {
                delta: 1.0,
                theta: 1.0,
                alpha: 2.0,
                beta: 1.0,
                gamma: 1.0,
                line_noise_ratio: -1.0,
            },
        );
        bands.insert(
            2,
            ChannelBands {
                delta: 1.0,
                theta: 1.0,
                alpha: 2.0,
                beta: 1.0,
                gamma: 1.0,
                line_noise_ratio: -1.0,
            },
        );
        let mut rings = HashMap::new();
        let mut good = EegRing::new();
        let mut good_samples = vec![0.0; 128];
        good_samples.extend(std::iter::repeat(20.0).take(128));
        good.extend(&good_samples);
        let mut bad = EegRing::new();
        bad.extend(&[1.0; 256]);
        rings.insert(1, good);
        rings.insert(2, bad);
        let picked = collect_usable_pads(DeviceKind::Muse, &[1, 2], &bands, &rings);
        assert_eq!(picked.len(), 1);
        let empty = collect_usable_pads(DeviceKind::Muse, &[1, 2], &HashMap::new(), &rings);
        assert!(empty.is_empty());
        assert!(aggregate_band_feature(ID_ATR, &empty).is_none());
    }

    #[test]
    fn aggregate_atr_and_absolute_delta() {
        let pads = [ChannelBands {
            delta: 2.0,
            theta: 1.0,
            alpha: 2.0,
            beta: 1.0,
            gamma: 0.0,
            line_noise_ratio: 0.0,
        }];
        let atr = aggregate_band_feature(ID_ATR, &pads).unwrap();
        assert!((atr - 2.0).abs() < 1e-9);
        let delta = aggregate_band_feature(ID_DELTA, &pads).unwrap();
        assert!((delta - 2.0).abs() < 1e-9);
    }
}
