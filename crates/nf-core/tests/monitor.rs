#![allow(clippy::panic, clippy::unwrap_used)]
//! Monitor viewport commands end to end (headless session, simulator).
use nf_core::{BandScale, MonitorId, Session};
use nf_store::Store;
use serde_json::json;

fn session_with_data(seconds: f64) -> Session {
    let mut s = Session::new();
    s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
    s.call("clock.advance", json!({ "seconds": seconds })).unwrap();
    s
}

#[test]
fn zoom_pan_follow_through_commands() {
    let mut s = session_with_data(40.0);
    let g = s.call("monitor.get", json!({})).unwrap();
    assert_eq!(g["monitors"]["bands"]["mode"], "follow");
    assert_eq!(g["monitors"]["bands"]["window_s"], 30.0);
    // Zoom in at the centre: inspect, window halves, centre time kept.
    let before = s.call("monitor.get", json!({})).unwrap();
    let (a, b) = (before["monitors"]["bands"]["start_s"].as_f64().unwrap(), before["monitors"]["bands"]["end_s"].as_f64().unwrap());
    s.call("monitor.zoom", json!({ "monitor": "bands", "factor": 2.0, "focal": 0.5 })).unwrap();
    let g = s.call("monitor.get", json!({})).unwrap();
    let m = &g["monitors"]["bands"];
    assert_eq!(m["mode"], "inspect");
    assert_eq!(m["window_s"], 15.0);
    let mid = (m["start_s"].as_f64().unwrap() + m["end_s"].as_f64().unwrap()) / 2.0;
    assert!((mid - (a + b) / 2.0).abs() < 1e-6, "{mid} vs {}", (a + b) / 2.0);
    // Pan earlier, clamp at the oldest data.
    s.call("monitor.pan", json!({ "monitor": "bands", "seconds": -1000.0 })).unwrap();
    let g = s.call("monitor.get", json!({})).unwrap();
    let oldest = s.state().bands.oldest().unwrap().time;
    assert!((g["monitors"]["bands"]["start_s"].as_f64().unwrap() - oldest).abs() < 1e-6);
    s.call("monitor.viewport", json!({ "monitor": "bands", "mode": "follow" })).unwrap();
    assert!(s.state().monitors.viewport(MonitorId::Bands).following());
}

#[test]
fn bad_params_are_rejected_and_change_nothing() {
    let mut s = session_with_data(5.0);
    assert!(s.call("monitor.zoom", json!({ "monitor": "bands", "factor": 0.0 })).is_err());
    assert!(s.call("monitor.zoom", json!({ "monitor": "bands", "factor": -2.0 })).is_err());
    assert!(s.call("monitor.zoom", json!({ "monitor": "nope", "factor": 2.0 })).is_err());
    assert!(s.call("monitor.pan", json!({ "monitor": "bands", "seconds": 1, "x": 1 })).is_err());
    assert!(s.state().monitors.viewport(MonitorId::Bands).following());
}

#[test]
fn disconnect_returns_to_follow() {
    let mut s = session_with_data(10.0);
    s.call("monitor.pan", json!({ "monitor": "bands", "seconds": -2.0 })).unwrap();
    assert!(!s.state().monitors.viewport(MonitorId::Bands).following());
    s.call("device.disconnect", json!({})).unwrap();
    assert!(s.state().monitors.viewport(MonitorId::Bands).following());
}

#[test]
fn window_hidden_bands_and_scale_persist() {
    let mut s = Session::new();
    s.call("monitor.viewport", json!({ "monitor": "bands", "window_s": 120.0 })).unwrap();
    s.call("monitor.display", json!({ "hidden_bands": ["gamma"], "electrodes": ["AF7"] })).unwrap();
    s.call("scale.set", json!({ "scale": "relative" })).unwrap();
    let doc = s.store().get_doc(nf_core::settings::DOC_KEY).unwrap().unwrap();
    let mut store = nf_store::MemoryStore::default();
    store.put_doc(nf_core::settings::DOC_KEY, Some(&doc)).unwrap();
    let s2 = Session::new().with_store(Box::new(store));
    let st = s2.state();
    assert_eq!(st.monitors.viewport(MonitorId::Bands).window_s, 120.0);
    assert!(st.monitors.viewport(MonitorId::Bands).following());
    assert_eq!(st.monitors.bands.hidden_bands, vec![nf_core::Band::Gamma]);
    // Electrodes depend on the device and are not persisted.
    assert!(st.monitors.bands.electrodes.is_empty());
    assert_eq!(st.band_scale, BandScale::Relative);
}

#[test]
fn raw_display_commands_and_dynamic_channels() {
    for (id, n) in [("sim:muse", 4usize), ("sim:crown", 8)] {
        let mut s = Session::new();
        s.call("device.connect", json!({ "id": id })).unwrap();
        s.call("clock.advance", json!({ "seconds": 12.0 })).unwrap();
        let dev = s.state().device.clone().unwrap();
        assert_eq!(dev.channels.len(), n);
        let raw = &s.state().monitors.raw;
        assert_eq!(raw.selected(&dev.channels).len(), n, "all channels by default");
        // Raw viewport spans the 10 s signal ring and ends at its newest sample.
        let g = s.call("monitor.get", json!({})).unwrap();
        let m = &g["monitors"]["raw_eeg"];
        assert_eq!(m["window_s"], 8.0);
        let newest = s.live_signal().and_then(|(_, sig)| sig.time).unwrap();
        assert!((m["end_s"].as_f64().unwrap() - newest).abs() < 1e-9);
        // Pan clamps inside the ring; Follow returns.
        s.call("monitor.pan", json!({ "monitor": "raw_eeg", "seconds": -100.0 })).unwrap();
        let g = s.call("monitor.get", json!({})).unwrap();
        assert!((g["monitors"]["raw_eeg"]["start_s"].as_f64().unwrap() - (newest - nf_core::signal::BUFFER_S).max(0.0)).abs() < 1e-6);
        s.call("monitor.zoom", json!({ "monitor": "raw_eeg", "factor": 100.0 })).unwrap();
        assert_eq!(s.call("monitor.get", json!({})).unwrap()["monitors"]["raw_eeg"]["window_s"], 1.0, "min window");
        s.call("monitor.viewport", json!({ "monitor": "raw_eeg", "mode": "follow" })).unwrap();
        // Electrodes by name; unknown names fall back to all.
        let pick = vec![dev.channels[0].clone(), dev.channels[n - 1].clone()];
        s.call("monitor.raw", json!({ "electrodes": pick })).unwrap();
        assert_eq!(s.state().monitors.raw.selected(&dev.channels), vec![0, n - 1]);
        s.call("monitor.raw", json!({ "electrodes": ["NOPE"] })).unwrap();
        assert_eq!(s.state().monitors.raw.selected(&dev.channels).len(), n);
    }
}

#[test]
fn raw_mode_and_scale_validate_and_persist() {
    let mut s = Session::new();
    let g = s.call("monitor.get", json!({})).unwrap();
    assert_eq!((g["raw"]["mode"].as_str(), g["raw"]["scale"].as_str()), (Some("sweep"), Some("auto")));
    s.call("monitor.raw", json!({ "mode": "scroll", "scale": "100" })).unwrap();
    assert!(s.call("monitor.raw", json!({ "scale": "75" })).is_err());
    assert!(s.call("monitor.raw", json!({ "mode": "wipe" })).is_err());
    let g = s.call("monitor.get", json!({})).unwrap();
    assert_eq!((g["raw"]["mode"].as_str(), g["raw"]["scale"].as_str()), (Some("scroll"), Some("100")));
    // Round trip through the persisted settings document.
    let doc = nf_core::settings::Persisted::of(s.state());
    let back: nf_core::settings::Persisted = serde_json::from_str(&serde_json::to_string(&doc).unwrap()).unwrap();
    let mut st = nf_core::AppState::default();
    back.restore(&mut st);
    assert_eq!(st.monitors.raw.mode, nf_core::monitor::RawMode::Scroll);
    assert_eq!(st.monitors.raw.scale, nf_core::monitor::RawScale::Uv100);
    assert!(st.monitors.raw.electrodes.is_empty(), "electrodes are session-only");
    // An old settings doc without the raw fields loads with defaults.
    let old: nf_core::settings::Persisted = serde_json::from_str("{}").unwrap();
    assert_eq!(old.raw_mode, nf_core::monitor::RawMode::Sweep);
}

#[test]
fn raw_inspect_can_pan_back_through_the_ring() {
    let mut s = Session::new();
    s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
    s.call("clock.advance", json!({ "seconds": 70.0 })).unwrap();
    s.call("monitor.viewport", json!({ "monitor": "raw_eeg", "mode": "inspect" })).unwrap();
    let end0 = s.call("monitor.get", json!({})).unwrap()["monitors"]["raw_eeg"]["end_s"].as_f64().unwrap();
    for _ in 0..30 {
        s.call("monitor.pan", json!({ "monitor": "raw_eeg", "seconds": -1.0 })).unwrap();
    }
    let end = s.call("monitor.get", json!({})).unwrap()["monitors"]["raw_eeg"]["end_s"].as_f64().unwrap();
    assert!((end0 - end - 30.0).abs() < 1e-6, "panned {} s of 30", end0 - end);
}

#[test]
fn raw_inspect_stays_frozen_while_live_data_arrives() {
    let mut s = Session::new();
    s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
    s.call("clock.advance", json!({ "seconds": 70.0 })).unwrap();
    s.call("monitor.pan", json!({ "monitor": "raw_eeg", "seconds": -20.0 })).unwrap();
    let get = |s: &mut Session| s.call("monitor.get", json!({})).unwrap()["monitors"]["raw_eeg"]["end_s"].as_f64().unwrap();
    let end = get(&mut s);
    s.call("clock.advance", json!({ "seconds": 5.0 })).unwrap();
    assert!((get(&mut s) - end).abs() < 1e-9, "frozen while new samples arrive");
    // Once the ring evicts the window's start, the next pan clamps to the oldest data.
    s.call("clock.advance", json!({ "seconds": 40.0 })).unwrap();
    s.call("monitor.pan", json!({ "monitor": "raw_eeg", "seconds": 0.0 })).unwrap();
    let newest = s.live_signal().and_then(|(_, g)| g.time).unwrap();
    let start = s.call("monitor.get", json!({})).unwrap()["monitors"]["raw_eeg"]["start_s"].as_f64().unwrap();
    assert!((start - (newest - nf_core::signal::BUFFER_S)).abs() < 1e-6, "history boundary");
}
