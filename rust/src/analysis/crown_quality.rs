//! Neurosity pad signal quality: Crown per-pad values averaged to 1 Hz with a
//! per-second fallback to the in-app score.

use crate::api::device_config::QualitySource;
use crate::api::features::SIGNAL_GOOD_THRESHOLD;

/// Crown pads (CP3, C3, F5, PO3, PO4, F6, C4, CP4).
pub const CROWN_PADS: usize = 8;

/// Neurosity SignalQuality V2 reports 0..1 per channel; >= 0.75 is adequate.
pub const CROWN_QUALITY_ADEQUATE: f64 = 0.75;

/// Map a Crown 0..1 pad value onto the app's 0–100 score so Crown "adequate"
/// (0.75) lands on [SIGNAL_GOOD_THRESHOLD]: piecewise linear 0→0, 0.75→80, 1→100.
pub fn crown_quality_to_score(q: f64) -> f64 {
    if q <= CROWN_QUALITY_ADEQUATE {
        q / CROWN_QUALITY_ADEQUATE * SIGNAL_GOOD_THRESHOLD
    } else {
        SIGNAL_GOOD_THRESHOLD
            + (q - CROWN_QUALITY_ADEQUATE) / (1.0 - CROWN_QUALITY_ADEQUATE)
                * (100.0 - SIGNAL_GOOD_THRESHOLD)
    }
}

/// Per-pad Crown quality messages within one second. Any value outside
/// 0..1 (unknown scale) makes the whole second unusable.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct CrownQualitySecond {
    sum: [f64; CROWN_PADS],
    count: u32,
    out_of_range: bool,
}

impl CrownQualitySecond {
    pub fn add(&mut self, values: &[f32; CROWN_PADS]) {
        if values.iter().any(|v| !(0.0..=1.0).contains(v)) {
            self.out_of_range = true;
            return;
        }
        for (sum, v) in self.sum.iter_mut().zip(values) {
            *sum += *v as f64;
        }
        self.count += 1;
    }

    /// Per-pad mean of the second, `None` when missing or out of range. Resets.
    pub fn take(&mut self) -> Option<[f64; CROWN_PADS]> {
        let second = std::mem::take(self);
        if second.count == 0 || second.out_of_range {
            return None;
        }
        Some(second.sum.map(|s| s / second.count as f64))
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ResolvedPadQuality {
    pub scores: [Option<f64>; CROWN_PADS],
    pub source: QualitySource,
    /// The 1 Hz Crown per-pad means (0..1) when [source] is Crown.
    pub crown: Option<[f64; CROWN_PADS]>,
}

/// Crown values win only with [QualitySource::Crown] and a complete, in-range
/// second; otherwise the in-app score is used.
pub fn resolve_pad_quality(
    source: QualitySource,
    crown: Option<[f64; CROWN_PADS]>,
    app: &[Option<f64>; CROWN_PADS],
) -> ResolvedPadQuality {
    match (source, crown) {
        (QualitySource::Crown, Some(crown)) => ResolvedPadQuality {
            scores: crown.map(|q| Some(crown_quality_to_score(q))),
            source: QualitySource::Crown,
            crown: Some(crown),
        },
        _ => ResolvedPadQuality {
            scores: *app,
            source: QualitySource::App,
            crown: None,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app_scores() -> [Option<f64>; CROWN_PADS] {
        [Some(90.0), Some(40.0), None, Some(85.0), Some(10.0), Some(99.0), Some(70.0), Some(81.0)]
    }

    #[test]
    fn score_mapping_puts_adequate_on_the_usable_threshold() {
        assert_eq!(crown_quality_to_score(0.0), 0.0);
        assert!((crown_quality_to_score(CROWN_QUALITY_ADEQUATE) - SIGNAL_GOOD_THRESHOLD).abs() < 1e-9);
        assert!((crown_quality_to_score(1.0) - 100.0).abs() < 1e-9);
        assert!(crown_quality_to_score(0.74) < SIGNAL_GOOD_THRESHOLD);
        assert!(crown_quality_to_score(0.76) > SIGNAL_GOOD_THRESHOLD);
    }

    #[test]
    fn second_averages_each_pad_and_resets() {
        let mut second = CrownQualitySecond::default();
        second.add(&[0.8, 0.2, 1.0, 0.0, 0.5, 0.9, 0.6, 0.7]);
        second.add(&[1.0, 0.4, 1.0, 0.0, 0.7, 0.9, 0.8, 0.7]);
        second.add(&[0.9, 0.3, 1.0, 0.0, 0.6, 0.9, 0.7, 0.7]);
        second.add(&[0.9, 0.3, 1.0, 0.0, 0.6, 0.9, 0.7, 0.7]);
        let mean = second.take().expect("complete second");
        let want = [0.9, 0.3, 1.0, 0.0, 0.6, 0.9, 0.7, 0.7];
        for (m, w) in mean.iter().zip(want) {
            assert!((m - w).abs() < 1e-6, "{m} vs {w}");
        }
        assert_eq!(second.take(), None);
    }

    #[test]
    fn empty_second_is_missing() {
        assert_eq!(CrownQualitySecond::default().take(), None);
    }

    #[test]
    fn out_of_range_or_nan_value_drops_the_whole_second() {
        let mut second = CrownQualitySecond::default();
        second.add(&[0.9; CROWN_PADS]);
        second.add(&[0.9, 0.9, 12.5, 0.9, 0.9, 0.9, 0.9, 0.9]);
        assert_eq!(second.take(), None);

        second.add(&[0.9, -0.1, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9]);
        assert_eq!(second.take(), None);

        second.add(&[0.9, 0.9, 0.9, f32::NAN, 0.9, 0.9, 0.9, 0.9]);
        assert_eq!(second.take(), None);

        second.add(&[0.9; CROWN_PADS]);
        assert!(second.take().is_some(), "next second starts clean");
    }

    #[test]
    fn crown_source_uses_complete_crown_second() {
        let crown = [0.9, 0.1, 0.75, 1.0, 0.0, 0.5, 0.8, 0.3];
        let r = resolve_pad_quality(QualitySource::Crown, Some(crown), &app_scores());
        assert_eq!(r.source, QualitySource::Crown);
        assert_eq!(r.crown, Some(crown));
        assert!(r.scores.iter().all(|s| s.is_some()));
        assert!(r.scores[0].unwrap() >= SIGNAL_GOOD_THRESHOLD);
        assert!(r.scores[1].unwrap() < SIGNAL_GOOD_THRESHOLD);
        assert!((r.scores[2].unwrap() - SIGNAL_GOOD_THRESHOLD).abs() < 1e-9);
    }

    #[test]
    fn crown_source_falls_back_to_app_for_a_missing_second() {
        let r = resolve_pad_quality(QualitySource::Crown, None, &app_scores());
        assert_eq!(r.source, QualitySource::App);
        assert_eq!(r.crown, None);
        assert_eq!(r.scores, app_scores());
    }

    #[test]
    fn app_source_ignores_crown_values() {
        let r = resolve_pad_quality(QualitySource::App, Some([1.0; CROWN_PADS]), &app_scores());
        assert_eq!(r.source, QualitySource::App);
        assert_eq!(r.crown, None);
        assert_eq!(r.scores, app_scores());
    }
}
