#![allow(clippy::panic)]
use nf_core::{Session, View};
use serde_json::json;

#[test]
fn connect_advance_and_read_bands() {
    let mut s = Session::new();
    s.call("device.connect", json!({ "id": "sim:muse" })).unwrap_or_default();
    s.call("clock.advance", json!({ "seconds": 2.0 })).unwrap_or_default();
    let bands = s.call("bands.get", json!({})).unwrap_or_default();
    assert_eq!(bands["channels"].as_array().map(Vec::len), Some(4));
    // First snapshot needs a full 1 s window, then 10 Hz.
    assert!((9..=11).contains(&s.state().bands.len()), "{}", s.state().bands.len());
}

#[test]
fn pause_freezes_data_and_tick_uses_deltas() {
    let mut s = Session::new();
    s.call("device.connect", json!({ "id": "sim:crown" })).unwrap_or_default();
    s.tick(100.0);
    s.tick(100.5);
    assert!((s.state().time - 0.5).abs() < 1e-9);
    s.call("stream.pause", json!(null)).unwrap_or_default();
    let n = s.state().bands.len();
    s.call("clock.advance", json!({ "seconds": 5 })).unwrap_or_default();
    assert_eq!(s.state().bands.len(), n);
}

#[test]
fn events_are_emitted_and_drained() {
    let mut s = Session::new();
    s.call("view.set", json!({ "view": "psd" })).unwrap_or_default();
    assert_eq!(s.state().view, View::Psd);
    let ev = s.drain_events();
    assert_eq!(ev.len(), 1);
    assert!(s.drain_events().is_empty());
}

#[test]
fn batch_is_atomic() {
    let mut s = Session::new();
    s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
    let rev = s.state().revision;
    // step 2 fails (resume while not paused is disabled) -> everything rolled back
    let steps = vec![
        ("view.set".to_owned(), json!({ "view": "psd" })),
        ("device.connect".to_owned(), json!({ "id": "sim:crown" })),
        ("stream.resume".to_owned(), json!({})),
    ];
    assert!(s.batch(&steps).is_err());
    assert_eq!(s.state().view, View::Bands);
    assert_eq!(s.state().device.as_ref().map(|d| d.id.as_str()), Some("sim:muse_s"));
    assert_eq!(s.state().revision, rev);
    // pre-validation: unknown id fails before anything runs
    assert!(s.batch(&[("view.set".into(), json!({ "view": "psd" })), ("nope".into(), json!({}))]).is_err());
    assert_eq!(s.state().view, View::Bands);
    // success path
    assert!(s.batch(&steps[..2]).is_ok());
    assert_eq!(s.state().view, View::Psd);
}

#[test]
fn disabled_commands_report_reason_and_change_nothing() {
    let mut s = Session::new();
    assert_eq!(s.enabled("stream.pause"), Err("no device connected".into()));
    let err = s.call("stream.pause", json!({})).unwrap_err().to_string();
    assert!(err.contains("disabled"), "{err}");
    assert_eq!(s.state().revision, 0);
    assert!(s.call("device.connect", json!({ "id": "ble:x" })).is_err());
    assert!(s.state().device.is_none());
}

#[test]
fn dropped_and_bad_samples_are_flagged_for_the_plots() {
    use nf_core::signal::{FLAG_BAD, FLAG_GAP, FLAG_OK};
    let mut s = Session::new();
    s.call("device.connect", json!({ "id": "sim:muse_s" })).unwrap_or_default();
    s.call("clock.advance", json!({ "seconds": 3.0 })).unwrap_or_default();
    s.call("sim.fault.add", json!({ "kind": "disconnect", "reconnect_after_s": 1.0 })).unwrap_or_default();
    s.call("sim.fault.add", json!({ "kind": "out_of_range", "value": "inf", "channels": ["AF8"], "duration_s": 2.0 })).unwrap_or_default();
    for _ in 0..30 {
        s.call("clock.advance", json!({ "seconds": 0.1 })).unwrap_or_default();
    }
    let Some((_, sig)) = s.live_signal() else { panic!("no signal") };
    let count = |ch: usize, f: u8| sig.last_flags(ch, 2560).iter().filter(|x| **x == f).count();
    let rate = sig.rate as usize;
    // ~1 s gap on every channel, ~1 s of bad AF8 after it, the rest ok.
    for ch in 0..4 {
        assert!((rate * 8 / 10..=rate * 12 / 10).contains(&count(ch, FLAG_GAP)), "ch {ch}: gap {}", count(ch, FLAG_GAP));
    }
    assert!(count(2, FLAG_BAD) > rate / 2, "AF8 bad {}", count(2, FLAG_BAD));
    assert_eq!(count(1, FLAG_BAD), 0);
    assert!(count(1, FLAG_OK) > rate * 3);
    assert!(sig.last(2, 2560, true).iter().all(|x| x.is_finite()));
}
