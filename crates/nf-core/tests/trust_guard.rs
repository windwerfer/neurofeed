//! Guard chart rows: stored decision-scale value and warn line, legacy fallback.
#![allow(clippy::unwrap_used)]
use nf_core::trust::{rows_from_records, LEGACY_WARN_LINE};
use nf_format::{trust_bits as tb, Record};

fn pair(ts: f64, bits: u16) -> [Record; 2] {
    [
        Record::Feedback { ts, value: 1.0, threshold: 1.0, flags: 0 },
        Record::Trust { ts, native: 0.5, pct: 50.0, thr_pct: 60.0, bits: bits | tb::PRODUCED },
    ]
}

#[test]
fn stored_guard_line_and_value_are_read() {
    let mut recs = pair(1.0, tb::HAS_GUARD | tb::WARN).to_vec();
    recs.push(Record::Guard { ts: 1.0, value: 82.0, line: 50.0 });
    let rows = rows_from_records(&recs);
    assert_eq!((rows[0].guard_plot, rows[0].guard_line, rows[0].warn), (Some(82.0), Some(50.0), Some(true)));
}

#[test]
fn old_guarded_sessions_fall_back_to_75() {
    let mut recs = pair(1.0, tb::HAS_GUARD).to_vec();
    recs.extend(pair(2.0, 0));
    let rows = rows_from_records(&recs);
    assert_eq!((rows[0].guard_line, rows[0].guard_plot), (Some(LEGACY_WARN_LINE), None));
    assert_eq!(rows[1].guard_line, None, "no guard, no line");
}
