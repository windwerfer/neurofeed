//! Legacy output rules (ported from the Dart audio controllers).

/// Rain stage tables: index 0 = heavy (stage 1) … 4 = calm (stage 5).
pub const RAIN_VOLUMES: [f64; 5] = [1.0, 0.7, 0.45, 0.2, 0.04];
pub const RAIN_CUTOFFS: [f64; 5] = [9000.0, 5500.0, 3000.0, 1500.0, 900.0];
/// Percentile bounds; pct >= 80 is the calmest stage.
pub const RAIN_BOUNDS: [f64; 4] = [20.0, 40.0, 60.0, 80.0];
/// Deadband (percentile points) before a stage change is accepted.
pub const RAIN_HYSTERESIS: f64 = 3.0;
/// Moderate rain until the first real percentile arrives.
pub const RAIN_INITIAL_STAGE: usize = 2;
pub const RAIN_SLEW_S: f64 = 0.5;
pub const RAIN_MUFFLE_CUTOFF: f64 = 900.0;
pub const RAIN_MUFFLE_VOLUME: f64 = 0.04;
/// Binaural volume factor while muffled.
pub const BINAURAL_MUFFLE: f64 = 0.05;
pub const MUSIC_SLEW_S: f64 = 1.2;
/// Volume slew of every modulated voice.
pub const VOLUME_SLEW_S: f64 = 0.5;

/// Stage index 0..=4 for a percentile (no hysteresis).
pub fn rain_stage_for(pct: f64) -> usize {
    RAIN_BOUNDS.iter().filter(|b| pct >= **b).count()
}

/// Next stage from `current` with [`RAIN_HYSTERESIS`] around the bounds.
pub fn rain_stage(current: usize, pct: f64) -> usize {
    let pct = if pct.is_finite() { pct.clamp(0.0, 100.0) } else { 50.0 };
    let current = current.min(4);
    let target = rain_stage_for(pct);
    if target > current && pct < RAIN_BOUNDS[current] + RAIN_HYSTERESIS {
        return current;
    }
    if target < current && pct > RAIN_BOUNDS[target] - RAIN_HYSTERESIS {
        return current;
    }
    target
}

/// Binaural swell volume (before the channel volume).
pub fn binaural_volume(pct: f64, muffle: bool) -> f64 {
    let pct = if pct.is_finite() { pct.clamp(0.0, 100.0) } else { 0.0 };
    pct / 100.0 * if muffle { BINAURAL_MUFFLE } else { 1.0 }
}

/// Music low-pass cutoff for a percentile.
pub fn music_cutoff(pct: f64, min_hz: f64, max_hz: f64, invert: bool) -> f64 {
    let pct = if pct.is_finite() { pct.clamp(0.0, 100.0) } else { 50.0 };
    let norm = if invert { 100.0 - pct } else { pct };
    min_hz + norm / 100.0 * (max_hz - min_hz)
}

/// Alarm gain after `elapsed_s` of continuous warning.
pub fn alarm_ramp(elapsed_s: f64) -> f64 {
    0.12 + 0.88 * (elapsed_s / 60.0).clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rain_stage_matches_legacy_table() {
        assert_eq!([0.0, 19.9, 20.0, 59.0, 80.0, 100.0].map(rain_stage_for), [0, 0, 1, 2, 4, 4]);
        // Up from stage 2 needs 60 + 3.
        assert_eq!(rain_stage(2, 61.0), 2);
        assert_eq!(rain_stage(2, 63.0), 3);
        // Down from 2 to 1 needs < 40 - 3.
        assert_eq!(rain_stage(2, 38.0), 2);
        assert_eq!(rain_stage(2, 36.0), 1);
        // Big jumps go straight through.
        assert_eq!(rain_stage(0, 95.0), 4);
        assert_eq!(rain_stage(4, 5.0), 0);
        assert_eq!(rain_stage(2, f64::NAN), 2);
    }

    #[test]
    fn swell_filter_and_ramp() {
        assert!((binaural_volume(50.0, false) - 0.5).abs() < 1e-12);
        assert!((binaural_volume(100.0, true) - 0.05).abs() < 1e-12);
        assert_eq!(music_cutoff(0.0, 200.0, 8000.0, false), 200.0);
        assert_eq!(music_cutoff(100.0, 200.0, 8000.0, true), 200.0);
        assert_eq!(music_cutoff(50.0, 200.0, 8000.0, false), 4100.0);
        assert!((alarm_ramp(0.0) - 0.12).abs() < 1e-12);
        assert_eq!(alarm_ramp(120.0), 1.0);
    }
}
