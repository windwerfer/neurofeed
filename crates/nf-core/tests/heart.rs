//! HR+SpO2 monitor: summaries, means, raw PPG detail, linked viewports.
#![allow(clippy::panic, clippy::unwrap_used)]

use nf_core::Session;
use nf_store::Store;
use serde_json::{json, Value};

fn live(dev: &str, seconds: f64) -> Session {
    let mut s = Session::new();
    s.call("device.connect", json!({ "id": dev })).unwrap();
    if seconds > 0.0 {
        s.call("clock.advance", json!({ "seconds": seconds })).unwrap();
    }
    s
}

fn heart(s: &mut Session) -> Value {
    s.call("heart.get", json!({})).unwrap()
}

fn reload(s: &Session) -> Session {
    let doc = s.store().get_doc(nf_core::settings::DOC_KEY).unwrap().unwrap();
    let mut store = nf_store::MemoryStore::default();
    store.put_doc(nf_core::settings::DOC_KEY, Some(&doc)).unwrap();
    Session::new().with_store(Box::new(store))
}

#[test]
fn unsupported_devices_report_no_metrics() {
    for dev in ["sim:crown", "sim:athena"] {
        let mut s = live(dev, 5.0);
        for q in ["heart.get", "hr.get", "spo2.get", "ppg.get"] {
            assert!(s.call(q, json!({})).is_err(), "{dev} {q}");
        }
    }
    let mut none = Session::new();
    assert!(none.call("heart.get", json!({})).is_err());
}

#[test]
fn means_hour_then_recording_reset_restart_and_device_switch() {
    let mut s = live("sim:muse", 40.0);
    let h = heart(&mut s);
    assert_eq!(h["simulated"], true, "simulator is labelled");
    assert_eq!(h["means"]["scope"], "hour");
    let hour_n = h["means"]["hr"]["count"].as_u64().unwrap();
    assert!((30..=40).contains(&hour_n), "{hour_n}");
    // Queries never add counts (no stale repeats).
    for _ in 0..20 {
        heart(&mut s);
    }
    assert_eq!(heart(&mut s)["means"]["hr"]["count"].as_u64().unwrap(), hour_n);
    s.call("recording.start", json!({})).unwrap();
    let h = heart(&mut s);
    assert_eq!(h["means"]["scope"], "recording");
    assert_eq!(h["means"]["hr"]["count"], 0, "no prior data in the recording mean");
    s.call("clock.advance", json!({ "seconds": 20.0 })).unwrap();
    let n = heart(&mut s)["means"]["hr"]["count"].as_u64().unwrap();
    assert!((18..=21).contains(&n), "one per second: {n}");
    // Pause freezes the view only: the recording mean keeps counting.
    s.call("stream.pause", json!({})).unwrap();
    s.call("clock.advance", json!({ "seconds": 10.0 })).unwrap();
    let h = heart(&mut s);
    let n2 = h["means"]["hr"]["count"].as_u64().unwrap();
    assert!(n2 >= n + 9, "{n} -> {n2}");
    assert!(h["view_time"].as_f64().unwrap() < h["time"].as_f64().unwrap() - 9.0, "view frozen: {h}");
    s.call("stream.resume", json!({})).unwrap();
    s.call("recording.stop", json!({})).unwrap();
    let h = heart(&mut s);
    assert_eq!(h["means"]["scope"], "hour");
    assert!(h["means"]["hr"]["count"].as_u64().unwrap() >= hour_n + n2);
    s.call("recording.start", json!({})).unwrap();
    assert_eq!(heart(&mut s)["means"]["hr"]["count"], 0, "restart resets");
    s.call("recording.stop", json!({})).unwrap();
    // Another device: nothing carries over.
    s.call("device.connect", json!({ "id": "sim:muse2" })).unwrap();
    let h = heart(&mut s);
    assert_eq!(h["means"]["hr"]["count"], 0);
    assert_eq!(h["summary"]["hr_count"], 0);
    assert!(h["hr"].is_null());
}

#[test]
fn raw_detail_is_native_rate_bounded_and_sliced() {
    let mut s = live("sim:muse", 330.0);
    let h = heart(&mut s);
    assert_eq!(h["ppg_rate_hz"], 64.0);
    assert_eq!(h["ppg_channels"], json!(["ambient", "infrared", "red"]));
    let d = &h["detail"];
    let bytes = d["bytes"].as_u64().unwrap();
    assert!((230_400..230_600).contains(&bytes), "3 × 300 s × 64 Hz × 4 B: {bytes}");
    let span = d["newest_s"].as_f64().unwrap() - d["oldest_s"].as_f64().unwrap();
    assert!((span - 300.0).abs() < 0.1, "{span}");
    // Bounded slices only.
    assert!(s.call("ppg.get", json!({ "seconds": 61.0 })).is_err());
    let p = s.call("ppg.get", json!({ "seconds": 10.0, "end_s": 200.0 })).unwrap();
    assert_eq!(p["unit"], "counts");
    for c in p["channels"].as_array().unwrap() {
        let n = c["samples"].as_array().unwrap().len();
        assert!((639..=641).contains(&n), "{n}");
        let t0 = c["segments"][0]["t0"].as_f64().unwrap();
        assert!((190.0..190.02).contains(&t0), "{t0}");
    }
    // Older than the 5 min detail: nothing (the 1 h summary still has it).
    let p = s.call("ppg.get", json!({ "seconds": 10.0, "end_s": 15.0 })).unwrap();
    assert!(p["channels"][1]["samples"].as_array().unwrap().is_empty());
    let hr = s.call("hr.get", json!({})).unwrap();
    assert!(hr["history"][0][0].as_f64().unwrap() < 10.0, "summary keeps the hour");
}

#[test]
fn cursor_readout_nearest_within_a_second() {
    let mut s = live("sim:muse", 30.0);
    let c = s.call("heart.get", json!({ "time_s": 20.0 })).unwrap()["cursor"].clone();
    let t = c["hr"]["time"].as_f64().unwrap();
    assert!((t - 20.0).abs() <= 1.0, "{c}");
    assert!(c["spo2"]["value"].as_f64().is_some(), "{c}");
    let c = s.call("heart.get", json!({ "time_s": 1.0 })).unwrap()["cursor"].clone();
    assert!(c["hr"].is_null(), "before the first estimate: {c}");
    assert!(s.call("heart.get", json!({ "time_s": f64::NAN })).is_err() || s.call("heart.get", json!({ "time_s": "x" })).is_err());
}

fn vp(s: &mut Session, id: &str) -> Value {
    s.call("monitor.get", json!({})).unwrap()["monitors"][id].clone()
}

#[test]
fn detail_selection_is_linked_and_clamped_to_the_raw_detail() {
    let mut s = live("sim:muse", 400.0);
    s.call("monitor.viewport", json!({ "monitor": "heart_overview", "window_s": 60.0 })).unwrap();
    // Panning the waveform keeps it inside the timeline.
    s.call("monitor.pan", json!({ "monitor": "heart_detail", "seconds": -150.0 })).unwrap();
    let (d, o) = (vp(&mut s, "heart_detail"), vp(&mut s, "heart_overview"));
    assert_eq!(d["mode"], "inspect");
    assert!(
        o["start_s"].as_f64().unwrap() <= d["start_s"].as_f64().unwrap() && o["end_s"].as_f64().unwrap() >= d["end_s"].as_f64().unwrap(),
        "{o} {d}"
    );
    // Cannot go before the 5 min raw detail.
    s.call("monitor.pan", json!({ "monitor": "heart_detail", "seconds": -1.0e6 })).unwrap();
    let d = vp(&mut s, "heart_detail");
    assert!(d["start_s"].as_f64().unwrap() >= 99.0, "{d}");
    // Zoom clamps (2..60 s).
    s.call("monitor.zoom", json!({ "monitor": "heart_detail", "factor": 100.0 })).unwrap();
    assert_eq!(vp(&mut s, "heart_detail")["window_s"], 2.0);
    s.call("monitor.zoom", json!({ "monitor": "heart_detail", "factor": 0.001 })).unwrap();
    assert_eq!(vp(&mut s, "heart_detail")["window_s"], 60.0);
    // The timeline can show the whole hour.
    s.call("monitor.viewport", json!({ "monitor": "heart_overview", "window_s": 3600.0 })).unwrap();
    assert_eq!(vp(&mut s, "heart_overview")["window_s"], 3600.0);
    // Detail Follow also re-engages the timeline's Follow.
    s.call("monitor.pan", json!({ "monitor": "heart_overview", "seconds": -100.0 })).unwrap();
    s.call("monitor.viewport", json!({ "monitor": "heart_detail", "mode": "follow" })).unwrap();
    assert_eq!(vp(&mut s, "heart_overview")["mode"], "follow");
    // Bookmarks work on the waveform window (session-local).
    let id = s.call("monitor.bookmark_add", json!({ "monitor": "heart_detail" })).unwrap()["id"].clone();
    s.call("monitor.bookmark_go", json!({ "monitor": "heart_detail", "id": id })).unwrap();
    assert_eq!(vp(&mut s, "heart_detail")["mode"], "inspect");
    // The global overview toggle is not the waveform toggle.
    assert!(s.call("monitor.overview", json!({ "monitor": "heart_detail", "on": false })).is_err());
}

#[test]
fn waveform_toggle_defaults_on_and_persists() {
    let mut s = Session::new();
    assert_eq!(s.call("monitor.get", json!({})).unwrap()["heart"]["waveform"], true);
    s.call("monitor.heart", json!({ "waveform": false })).unwrap();
    let mut r = reload(&s);
    assert_eq!(r.call("monitor.get", json!({})).unwrap()["heart"]["waveform"], false);
    r.call("monitor.heart", json!({ "waveform": true })).unwrap();
    assert!(reload(&r).state().monitors.heart.waveform);
}
