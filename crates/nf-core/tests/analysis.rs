#![allow(clippy::unwrap_used, clippy::panic)]
//! Analysis channel exclusion: explicit confirm, session reset, remember by
//! device id + name, every derived endpoint honours it, raw keeps all.
use nf_core::Session;
use serde_json::{json, Value};

fn s(dev: &str) -> Session {
    let mut s = Session::new();
    s.call("device.connect", json!({ "id": dev })).unwrap();
    s.call("clock.advance", json!({ "seconds": 12.0 })).unwrap();
    s
}

fn excluded(s: &mut Session) -> Vec<String> {
    let a = s.call("analysis.get", json!({})).unwrap();
    a["channels"].as_array().unwrap().iter().filter(|c| c["excluded"] == true).map(|c| c["channel"].as_str().unwrap().to_owned()).collect()
}

#[test]
fn exclude_needs_confirm_and_unknown_channels_fail() {
    let mut s = s("sim:muse");
    let e = s.call("analysis.exclude", json!({ "channel": "AF7", "confirm": false })).unwrap_err().to_string();
    assert!(e.contains("confirm=true") && e.contains("derived graphs"), "{e}");
    assert!(excluded(&mut s).is_empty(), "cancel leaves it unchanged");
    assert!(s.call("analysis.exclude", json!({ "channel": "XX", "confirm": true })).is_err());
    s.call("analysis.exclude", json!({ "channel": "AF7", "confirm": true })).unwrap();
    assert_eq!(excluded(&mut s), vec!["AF7"]);
    let a = s.call("analysis.get", json!({})).unwrap();
    assert_eq!((a["excluded_count"].as_u64(), a["eligible_count"].as_u64()), (Some(1), Some(3)));
    // Re-include: immediate, no confirm.
    s.call("analysis.include", json!({ "channel": "AF7" })).unwrap();
    assert!(excluded(&mut s).is_empty());
}

#[test]
fn session_exclusions_reset_on_disconnect_and_switch() {
    let mut s = s("sim:muse");
    s.call("analysis.exclude", json!({ "channel": "TP9", "confirm": true })).unwrap();
    s.call("device.connect", json!({ "id": "sim:crown" })).unwrap();
    assert!(excluded(&mut s).is_empty(), "no leak to another device");
    s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
    assert!(excluded(&mut s).is_empty(), "session-only is gone after a switch");
    s.call("analysis.exclude", json!({ "channel": "TP9", "confirm": true })).unwrap();
    s.call("device.disconnect", json!({})).unwrap();
    s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
    assert!(excluded(&mut s).is_empty());
}

#[test]
fn remembered_exclusion_restores_visibly_and_include_forgets() {
    let mut s = s("sim:crown");
    s.call("analysis.exclude", json!({ "channel": "PO3", "confirm": true, "remember": true })).unwrap();
    s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
    assert!(excluded(&mut s).is_empty(), "remembered for the crown id only");
    s.call("device.connect", json!({ "id": "sim:crown" })).unwrap();
    assert_eq!(excluded(&mut s), vec!["PO3"]);
    let a = s.call("analysis.get", json!({})).unwrap();
    assert_eq!(a["restored"], json!(["PO3"]));
    assert!(a["channels"].as_array().unwrap().iter().any(|c| c["channel"] == "PO3" && c["remembered"] == true));
    s.call("analysis.ack_restored", json!({})).unwrap();
    assert_eq!(s.call("analysis.get", json!({})).unwrap()["restored"], json!([]));
    let r = s.call("analysis.include", json!({ "channel": "PO3" })).unwrap();
    assert_eq!(r["forgot_remembered"], true);
    s.call("device.disconnect", json!({})).unwrap();
    s.call("device.connect", json!({ "id": "sim:crown" })).unwrap();
    assert!(excluded(&mut s).is_empty(), "not silently re-excluded");
    // Persisted with the settings.
    let p = nf_core::settings::Persisted::of(s.state());
    assert!(p.excluded_channels.is_empty());
}

#[test]
fn derived_endpoints_honour_exclusion_raw_keeps_everything() {
    let mut s = s("sim:muse");
    s.call("analysis.exclude", json!({ "channel": "AF7", "confirm": true })).unwrap();
    s.call("clock.advance", json!({ "seconds": 2.0 })).unwrap();
    let f = s.call("features.get", json!({})).unwrap();
    assert!(!f["usable_pads"].to_string().contains("AF7"), "{f}");
    let b = s.call("bands.get", json!({})).unwrap();
    let af7 = b["channels"].as_array().unwrap().iter().find(|c| c["channel"] == "AF7").unwrap().clone();
    assert_eq!(af7, json!({ "channel": "AF7", "excluded": true }), "no values, no zeros");
    let h = s.call("histogram.get", json!({ "seconds": 2.0 })).unwrap();
    assert!(!h["channels"].to_string().contains("AF7"));
    assert!(s.call("spectrogram.get", json!({ "channel": "AF7" })).is_err());
    assert!(s.call("psd.get", json!({ "channel": "AF7" })).is_err());
    let p = s.call("psd.get", json!({})).unwrap();
    assert_eq!(p["channels"].as_array().unwrap().len(), 3);
    let st = s.call("signal.status", json!({})).unwrap();
    assert!(st["pads"].as_array().unwrap().iter().any(|p| p["channel"] == "AF7" && p["excluded"] == true));
    // Raw keeps all four.
    let r = s.call("raw.get", json!({ "seconds": 1.0 })).unwrap();
    assert_eq!(r["channels"].as_array().unwrap().len(), 4, "{}", r["channels"].as_array().unwrap().len());
    // Recording keeps every channel's samples.
    s.call("recording.start", json!({})).unwrap();
    s.call("clock.advance", json!({ "seconds": 2.0 })).unwrap();
    let rec = s.call("recording.status", json!({})).unwrap();
    let n = rec.to_string();
    assert!(n.contains("eeg_samples"), "{n}");
    let samples = rec.pointer("/eeg_samples").or_else(|| rec.pointer("/recording/eeg_samples")).and_then(Value::as_u64).unwrap();
    assert!(samples >= 4 * 256, "all channels recorded: {samples}");
}

#[test]
fn psd_average_uses_eligible_selection_and_never_falls_back() {
    let mut s = s("sim:muse");
    let all = s.call("psd.average", json!({ "window_s": 4.0 })).unwrap();
    assert_eq!(all["channels"].as_array().unwrap().len(), 4);
    assert_eq!(all["segments"], 28, "4 ch × 7 one-second segments");
    s.call("analysis.exclude", json!({ "channel": "AF7", "confirm": true })).unwrap();
    let only = s.call("psd.average", json!({ "window_s": 4.0, "electrodes": ["AF7"] })).unwrap();
    assert_eq!(only["unavailable"], "no eligible electrode selected");
    assert!(only.get("db").is_none());
    let two = s.call("psd.average", json!({ "window_s": 2.0, "electrodes": ["AF7", "AF8"] })).unwrap();
    assert_eq!(two["channels"], json!(["AF8"]));
    assert_eq!(two["excluded"], json!(["AF7"]));
    // Inspect: the requested window, not the newest one.
    let t = s.call("psd.average", json!({ "window_s": 2.0, "end_s": 6.0 })).unwrap();
    assert_eq!((t["start_s"].as_f64(), t["end_s"].as_f64()), (Some(4.0), Some(6.0)));
    s.call("monitor.viewport", json!({ "monitor": "psd", "mode": "inspect", "end_s": 8.0 })).unwrap();
    let v = s.call("psd.average", json!({})).unwrap();
    assert_eq!((v["start_s"].as_f64(), v["end_s"].as_f64()), (Some(4.0), Some(8.0)), "default window 4 s at the viewport");
}

#[test]
fn feedback_pauses_with_reason_when_all_target_pads_are_excluded() {
    let mut s = s("sim:muse");
    s.call("analysis.exclude", json!({ "channel": "AF7", "confirm": true })).unwrap();
    s.call("analysis.exclude", json!({ "channel": "AF8", "confirm": true })).unwrap();
    s.call("feedback.start", json!({})).unwrap();
    s.call("clock.advance", json!({ "seconds": 4.0 })).unwrap();
    let f = s.call("feedback.status", json!({})).unwrap().to_string();
    assert!(f.contains("excluded from analysis"), "{f}");
    assert!(!f.contains("\"good\":true"), "{f}");
}

#[test]
fn one_target_pad_excluded_feedback_uses_the_other_only() {
    let mut s = s("sim:muse");
    s.call("analysis.exclude", json!({ "channel": "AF7", "confirm": true })).unwrap();
    s.call("feedback.start", json!({})).unwrap();
    s.call("clock.advance", json!({ "seconds": 4.0 })).unwrap();
    let f = s.call("feedback.status", json!({})).unwrap();
    let pads = f.pointer("/fit/pads").or_else(|| f.pointer("/pads")).cloned().unwrap_or_default().to_string();
    assert!(pads.contains("AF8") && !pads.contains("AF7"), "{f}");
}

#[test]
fn quality_hint_appears_for_a_sustained_bad_pad_and_dismisses() {
    let mut s = s("sim:muse");
    s.call("sim.fault", json!({ "bad_pads": ["TP10"] })).unwrap();
    s.call("clock.advance", json!({ "seconds": 30.0 })).unwrap();
    assert_eq!(s.call("analysis.get", json!({})).unwrap()["hint"], Value::Null, "not before 60 s");
    s.call("clock.advance", json!({ "seconds": 40.0 })).unwrap();
    assert_eq!(s.call("analysis.get", json!({})).unwrap()["hint"], "TP10");
    assert!(excluded(&mut s).is_empty(), "a hint never excludes");
    s.call("analysis.hint_dismiss", json!({})).unwrap();
    s.call("clock.advance", json!({ "seconds": 120.0 })).unwrap();
    assert_eq!(s.call("analysis.get", json!({})).unwrap()["hint"], Value::Null, "no nagging");
}
