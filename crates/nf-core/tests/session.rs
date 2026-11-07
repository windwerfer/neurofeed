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
    // First snapshot needs a full 1 s window, then 4 Hz.
    assert!((4..=6).contains(&s.state().bands.len()), "{}", s.state().bands.len());
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

/// A provider that can scan and counts watch / stop.
struct Scanner {
    watches: std::sync::Arc<std::sync::atomic::AtomicUsize>,
    stops: std::sync::Arc<std::sync::atomic::AtomicUsize>,
    on: std::sync::Arc<std::sync::atomic::AtomicBool>,
}

impl nf_core::DeviceProvider for Scanner {
    fn scheme(&self) -> &'static str {
        "fake"
    }
    fn list(&self) -> Vec<nf_core::DeviceInfo> {
        Vec::new()
    }
    fn open(&mut self, id: &str) -> Result<Box<dyn nf_core::DeviceSource>, String> {
        Err(format!("no {id}"))
    }
    fn can_scan(&self) -> bool {
        true
    }
    fn watch(&mut self) -> Result<(), String> {
        self.watches.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        self.on.store(true, std::sync::atomic::Ordering::Relaxed);
        Ok(())
    }
    fn stop_scan(&mut self) {
        self.stops.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        self.on.store(false, std::sync::atomic::Ordering::Relaxed);
    }
    fn scanning(&self) -> bool {
        self.on.load(std::sync::atomic::Ordering::Relaxed)
    }
}

#[test]
fn device_dialog_opens_closes_and_auto_scans() {
    let mut s = Session::new();
    // Simulators only: opening works, nothing to scan.
    let r = s.call("device.dialog", json!({ "open": true })).unwrap_or_default();
    assert_eq!(r["scanning"], json!([]));
    assert!(s.state().device_dialog);
    s.call("device.dialog", json!({ "open": false })).unwrap_or_default();
    assert!(!s.state().device_dialog);
    let watches = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let stops = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let on = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    s.register_provider(Box::new(Scanner { watches: watches.clone(), stops: stops.clone(), on: on.clone() }));
    let r = s.call("device.dialog", json!({ "open": true })).unwrap_or_default();
    assert_eq!(r["scanning"], json!(["fake"]));
    assert_eq!(watches.load(std::sync::atomic::Ordering::Relaxed), 1, "opening starts one watch");
    assert!(on.load(std::sync::atomic::Ordering::Relaxed));
    assert_eq!(s.call("device.status", json!({})).unwrap_or_default()["dialog_open"], json!(true));
    s.call("device.dialog", json!({ "open": false })).unwrap_or_default();
    assert_eq!(stops.load(std::sync::atomic::Ordering::Relaxed), 1, "closing stops the watch");
    assert!(!on.load(std::sync::atomic::Ordering::Relaxed));
    assert!(!s.state().device_dialog);
}

#[test]
fn battery_and_streaming_in_device_status() {
    let mut s = Session::new();
    s.call("device.connect", json!({ "id": "sim:muse" })).unwrap_or_default();
    s.call("clock.advance", json!({ "seconds": 1.0 })).unwrap_or_default();
    let st = s.call("device.status", json!({})).unwrap_or_default();
    assert_eq!(st["battery"], json!(87.0));
    assert_eq!(st["streaming"], json!(null), "no transport registered");
    let list = s.call("device.list", json!({})).unwrap_or_default();
    assert!(list.as_array().is_some_and(|l| l.iter().all(|d| d["rssi"].is_i64())), "simulators carry an RSSI");
    s.call("device.disconnect", json!(null)).unwrap_or_default();
    assert_eq!(s.call("device.status", json!({})).unwrap_or_default()["battery"], json!(null));
}

#[test]
fn stream_running_needs_enabled_and_transport() {
    let mut st = nf_core::streaming::StreamState::default();
    assert_eq!(st.running(), None);
    st.settings.enabled = true;
    assert_eq!(st.running(), None, "no transport");
    st.transport = true;
    assert_eq!(st.running(), Some("OSC"));
    st.settings.protocol = nf_core::streaming::StreamProtocol::Lsl;
    assert_eq!(st.running(), None);
    st.lsl_transport = true;
    assert_eq!(st.running(), Some("LSL"));
}
