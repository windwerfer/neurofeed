//! The LSL clock: seconds of a monotonic clock that does not jump with wall
//! time. On Unix this is `CLOCK_MONOTONIC`, the same clock liblsl uses, so
//! timestamps from this crate and from liblsl apps on the same machine are
//! directly comparable. Elsewhere it counts from the first call.

/// Current LSL time in seconds.
#[must_use]
pub fn local_clock() -> f64 {
    imp::now()
}

#[cfg(unix)]
mod imp {
    pub fn now() -> f64 {
        let t = rustix::time::clock_gettime(rustix::time::ClockId::Monotonic);
        t.tv_sec as f64 + t.tv_nsec as f64 * 1e-9
    }
}

#[cfg(not(unix))]
mod imp {
    use std::sync::OnceLock;
    use std::time::Instant;
    static START: OnceLock<Instant> = OnceLock::new();
    pub fn now() -> f64 {
        START.get_or_init(Instant::now).elapsed().as_secs_f64()
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn monotonic() {
        let a = super::local_clock();
        let b = super::local_clock();
        assert!(b >= a && a > 0.0);
    }
}
