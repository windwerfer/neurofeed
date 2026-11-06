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
