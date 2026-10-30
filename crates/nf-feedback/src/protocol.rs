//! Built-in protocol catalog (from the legacy `assets/protocols.json`).
//! The AI sleep guard (`ai.a_vig`) is not ported yet: protocols that only
//! make sense with it are listed as unavailable; the others run without it.

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
}

impl Protocol {
    /// Engine config for this protocol at `percentile`.
    pub fn config(&self, percentile: u8) -> Config {
        Config { feature: self.feature, percentile, stability: self.stability, ..Config::default() }
    }
}

const fn p(id: &'static str, title: &'static str, summary: &'static str, eyes: Eyes, feature: Feature) -> Protocol {
    Protocol { id, title, summary, eyes, feature, stability: None, default_minutes: 10, experimental: false, unavailable: None }
}

/// Default protocol.
pub const DEFAULT_PROTOCOL: &str = "restAwake";

pub const PROTOCOLS: &[Protocol] = &[
    p("restAwake", "Rest Awake", "Rewards alpha over theta (ATR) with eyes closed.", Eyes::Closed, Feature::Atr),
    p("openMonitor", "Open Monitor", "Rewards relative alpha with eyes closed.", Eyes::Closed, Feature::Alpha),
    p("alertOpen", "Alert, Eyes Open", "Rewards beta over theta (BTR) with eyes open.", Eyes::Open, Feature::Btr),
    p("alertClosed", "Alert, Eyes Closed", "Rewards beta over theta (BTR) with eyes closed.", Eyes::Closed, Feature::Btr),
    Protocol {
        stability: Some(StabilityConfig { window: StabilityConfig::DEFAULT_WINDOW, difficulty: StabilityConfig::DEFAULT_DIFFICULTY }),
        experimental: true,
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
}
