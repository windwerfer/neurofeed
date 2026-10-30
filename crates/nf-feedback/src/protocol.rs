//! Built-in protocol catalog (from the legacy `assets/protocols.json`).
//! The AI sleep guard (`ai.a_vig`) is not ported yet. Protocols with a guard
//! offer the band-math drowsiness guard (`band.delta`, p75 of calibration)
//! as an opt-in instead; Sleep Guard itself needs the model (the legacy spec
//! has no band.delta fallback for it) and stays unavailable.

use crate::{Config, Feature, StabilityConfig};
use serde::Serialize;

/// Which eyes state the calibration and training expect.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Eyes {
    Open,
    Closed,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct Protocol {
    pub id: &'static str,
    pub title: &'static str,
    /// One line for the protocol card.
    pub summary: &'static str,
    pub eyes: Eyes,
    pub feature: Feature,
    /// `Some` = reward steadiness (stability downtrain).
    pub stability: Option<StabilityConfig>,
    pub default_minutes: u32,
    pub experimental: bool,
    /// `Some(reason)` = shown but cannot be started.
    pub unavailable: Option<&'static str>,
    /// Drowsiness guard lane (`None` = protocol has no guard).
    pub guard: Option<GuardSpec>,
}

/// Guard lane of a protocol.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct GuardSpec {
    /// Mute (and withhold) reward while the warning is active.
    pub muffle_reward: bool,
}

/// Warning threshold percentile of the calibration delta (legacy p75).
pub const GUARD_PERCENTILE: u8 = 75;

const fn guard(muffle_reward: bool) -> Option<GuardSpec> {
    Some(GuardSpec { muffle_reward })
}

impl Protocol {
    /// Engine config for this protocol at `percentile`.
    pub fn config(&self, percentile: u8) -> Config {
        Config { feature: self.feature, percentile, stability: self.stability, ..Config::default() }
    }

    /// Engine config with the band-math guard switched on (if the protocol has one).
    pub fn config_with_guard(&self, percentile: u8) -> Config {
        let guard = self.guard.map(|g| crate::GuardConfig { percentile: GUARD_PERCENTILE, muffle: g.muffle_reward });
        Config { guard, ..self.config(percentile) }
    }
}

const fn p(id: &'static str, title: &'static str, summary: &'static str, eyes: Eyes, feature: Feature) -> Protocol {
    Protocol {
        id,
        title,
        summary,
        eyes,
        feature,
        stability: None,
        default_minutes: 10,
        experimental: false,
        unavailable: None,
        guard: None,
    }
}

/// Default protocol.
pub const DEFAULT_PROTOCOL: &str = "restAwake";

pub const PROTOCOLS: &[Protocol] = &[
    Protocol {
        guard: guard(true),
        ..p("restAwake", "Rest Awake", "Rewards alpha over theta (ATR) with eyes closed.", Eyes::Closed, Feature::Atr)
    },
    Protocol {
        guard: guard(false),
        ..p("openMonitor", "Open Monitor", "Rewards relative alpha with eyes closed.", Eyes::Closed, Feature::Alpha)
    },
    p("alertOpen", "Alert, Eyes Open", "Rewards beta over theta (BTR) with eyes open.", Eyes::Open, Feature::Btr),
    Protocol {
        guard: guard(false),
        ..p("alertClosed", "Alert, Eyes Closed", "Rewards beta over theta (BTR) with eyes closed.", Eyes::Closed, Feature::Btr)
    },
    Protocol {
        stability: Some(StabilityConfig { window: StabilityConfig::DEFAULT_WINDOW, difficulty: StabilityConfig::DEFAULT_DIFFICULTY }),
        experimental: true,
        guard: guard(true),
        ..p(
            "bandStability",
            "Band Stability",
            "Experimental: rewards steadier alpha than in your calibration.",
            Eyes::Closed,
            Feature::Alpha,
        )
    },
    Protocol {
        unavailable: Some("needs the sleep model (coming later)"),
        guard: guard(false),
        ..p("sleepGuard", "Sleep Guard", "No reward; warns when you drift towards sleep.", Eyes::Closed, Feature::Atr)
    },
];

pub fn protocol(id: &str) -> Option<&'static Protocol> {
    PROTOCOLS.iter().find(|p| p.id == id)
}

#[cfg(test)]
mod stability_defaults {
    #![allow(clippy::unwrap_used)]
    use super::*;

    /// Legacy Dart `StabilityConfig`: window 10 s, difficulty 0.10.
    #[test]
    fn band_stability_uses_legacy_defaults() {
        let s = protocol("bandStability").unwrap().stability.unwrap();
        assert_eq!((s.window, s.difficulty), (10, 0.10));
        assert_eq!(StabilityConfig::default(), s);
    }

    /// Legacy protocols.json guard lanes: muffleReward for restAwake and
    /// bandStability only; alertOpen has no guard.
    #[test]
    fn guard_lanes_match_legacy() {
        let m = |id: &str| protocol(id).unwrap().guard.map(|g| g.muffle_reward);
        assert_eq!(
            ["restAwake", "openMonitor", "alertOpen", "alertClosed", "bandStability"].map(m),
            [Some(true), Some(false), None, Some(false), Some(true)]
        );
        let c = protocol("restAwake").unwrap().config_with_guard(60);
        assert_eq!(c.guard, Some(crate::GuardConfig { percentile: 75, muffle: true }));
        assert_eq!(protocol("alertOpen").unwrap().config_with_guard(60).guard, None);
    }
}
