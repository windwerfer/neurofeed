//! Background reconnect to the last connected headset.
//! Contract: `.ai/contracts/device-autoconnect.md`.
//!
//! Pure bookkeeping on session time; [`crate::Session`] does the scanning and
//! connecting. Only the remembered device is ever connected automatically.

use schemars::JsonSchema;
use serde::Serialize;

/// Length of one background scan burst (seconds).
pub const BURST_S: f64 = 6.0;
/// Burst period while the device has been gone for less than [`SLOW_AFTER_S`].
pub const PERIOD_S: f64 = 30.0;
/// Burst period after that (battery: ~5 % radio duty instead of 20 %).
pub const SLOW_PERIOD_S: f64 = 120.0;
pub const SLOW_AFTER_S: f64 = 300.0;
/// Minimum gap between two automatic connect attempts.
pub const ATTEMPT_GAP_S: f64 = 20.0;
/// While the Device dialog is open, re-arm a provider whose watch stopped.
pub const DIALOG_REARM_S: f64 = 5.0;

#[derive(Debug, Clone, Default, PartialEq, Serialize, JsonSchema)]
pub struct AutoReconnect {
    /// Last real (non-simulated) device that streamed. Persisted.
    pub target: Option<String>,
    /// The user pressed Disconnect: no auto-reconnect until the user connects
    /// again or the app restarts. Not persisted.
    pub suspended: bool,
    /// Session time the background search started (`None` = not searching).
    pub searching_since: Option<f64>,
    /// Automatic connect attempts in this search.
    pub attempts: u32,
    #[serde(skip)]
    pub(crate) next_burst: f64,
    #[serde(skip)]
    pub(crate) next_attempt: f64,
    #[serde(skip)]
    pub(crate) next_rearm: f64,
}

impl AutoReconnect {
    /// Start (or keep) searching at `now`.
    pub(crate) fn search(&mut self, now: f64) {
        if self.searching_since.is_none() {
            self.searching_since = Some(now);
            self.attempts = 0;
            self.next_burst = now;
        }
    }

    /// The target is back (or there is nothing to look for).
    pub(crate) fn stop(&mut self) {
        self.searching_since = None;
        self.attempts = 0;
    }

    fn period(&self, now: f64) -> f64 {
        match self.searching_since {
            Some(t) if now - t >= SLOW_AFTER_S => SLOW_PERIOD_S,
            _ => PERIOD_S,
        }
    }

    /// A burst is due; schedules the next one.
    pub(crate) fn take_burst(&mut self, now: f64) -> bool {
        if now < self.next_burst {
            return false;
        }
        self.next_burst = now + self.period(now);
        true
    }

    /// Run the next burst at once (the dialog just closed and stopped scans).
    pub(crate) fn burst_now(&mut self) {
        self.next_burst = f64::NEG_INFINITY;
    }

    /// A connect attempt is allowed; counts it.
    pub(crate) fn take_attempt(&mut self, now: f64) -> bool {
        if now < self.next_attempt {
            return false;
        }
        self.next_attempt = now + ATTEMPT_GAP_S;
        self.attempts += 1;
        true
    }

    pub(crate) fn take_rearm(&mut self, now: f64) -> bool {
        if now < self.next_rearm {
            return false;
        }
        self.next_rearm = now + DIALOG_REARM_S;
        true
    }

    /// Seconds until the next burst while searching.
    pub fn next_scan_in(&self, now: f64) -> Option<f64> {
        self.searching_since.map(|_| (self.next_burst - now).max(0.0))
    }
}

/// Provider scheme of a device id (`muse:AA:BB` -> `muse`).
pub fn scheme(id: &str) -> &str {
    id.split_once(':').map_or(id, |(s, _)| s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bursts_follow_the_duty_cycle_and_slow_down() {
        let mut a = AutoReconnect::default();
        a.search(100.0);
        assert!(a.take_burst(100.0));
        assert!(!a.take_burst(100.0 + PERIOD_S - 0.1));
        assert!(a.take_burst(100.0 + PERIOD_S));
        let late = 100.0 + SLOW_AFTER_S;
        assert!(a.take_burst(late));
        assert!(!a.take_burst(late + PERIOD_S));
        assert!(a.take_burst(late + SLOW_PERIOD_S));
        a.burst_now();
        assert!(a.take_burst(late + SLOW_PERIOD_S + 1.0));
    }

    #[test]
    fn attempts_are_spaced_and_survive_a_restart_of_the_search() {
        let mut a = AutoReconnect::default();
        a.search(0.0);
        assert!(a.take_attempt(0.0));
        a.stop(); // link went to Connecting, then Lost again
        a.search(1.0);
        assert!(!a.take_attempt(1.0), "a failed connect must not retry at once");
        assert!(a.take_attempt(ATTEMPT_GAP_S));
        assert_eq!(a.attempts, 1);
    }

    #[test]
    fn scheme_of_ids() {
        assert_eq!(scheme("muse:AA:BB"), "muse");
        assert_eq!(scheme("crown:abc"), "crown");
        assert_eq!(scheme("plain"), "plain");
    }
}
