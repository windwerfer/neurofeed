#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! A full simulated feedback session driven only through MCP `command_run`.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use serde_json::{json, Value};

fn server() -> NfMcp {
    NfMcp::new(Session::new(), ClockMode::Manual)
}
fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_or_else(|e| panic!("{id}: {e}"))
}
fn fails(s: &NfMcp, id: &str, params: Value) -> String {
    s.call("command_run", json!({ "id": id, "params": params })).expect_err(id).to_string()
}
fn adv(s: &NfMcp, secs: f64) {
    run(s, "clock.advance", json!({ "seconds": secs }));
}
fn status(s: &NfMcp) -> Value {
    run(s, "feedback.status", Value::Null)
}
fn phase(s: &NfMcp) -> String {
    let p = &status(s)["phase"];
    match p["reason"].as_str() {
        Some(r) => format!("paused:{r}"),
        None => p["phase"].as_str().unwrap_or_default().to_owned(),
    }
}
/// Advance 1 s at a time until `want`; returns seconds waited.
fn until(s: &NfMcp, want: &str, max: u32) -> u32 {
    for i in 0..=max {
        if phase(s) == want {
            return i;
        }
        adv(s, 1.0);
    }
    panic!("never reached {want}; now {}", phase(s));
}
fn fault(s: &NfMcp, pads: &[&str], dropout: bool) {
    run(s, "sim.fault", json!({ "bad_pads": pads, "dropout": dropout }));
}

#[test]
fn full_session_calibration_adaptation_pauses_reconnect_summary() {
    let s = server();
    start_and_fit_check(&s);
    extended_calibration(&s);
    training_adapts(&s);
    pauses_and_dropouts(&s);
    reuse_baseline(&s);
}

fn start_and_fit_check(s: &NfMcp) {
    let s = s.clone();
    assert!(fails(&s, "feedback.start", Value::Null).contains("no device"));
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    adv(&s, 3.0);
    let protos = run(&s, "protocol.list", Value::Null);
    assert!(protos.as_array().unwrap().iter().any(|p| p["protocol"]["guard_only"] == true), "Sleep Guard listed");
    run(&s, "protocol.set", json!({ "id": "restAwake" }));
    assert!(fails(&s, "feedback.pause", Value::Null).contains("not training"));

    run(&s, "feedback.start", json!({ "minutes": 4 }));
    assert_eq!(phase(&s), "fit_check");
    assert!(fails(&s, "protocol.set", json!({ "id": "alertOpen" })).contains("locked"));
    assert!(fails(&s, "calibration.reuse", Value::Null).contains("no stored baseline"));
    // Fit check: target pads (AF7/AF8) green for 3 s.
    fault(&s, &["AF8"], false);
    adv(&s, 4.0);
    assert!(fails(&s, "calibration.start", Value::Null).contains("AF8"));
    fault(&s, &[], false);
    adv(&s, 4.0);
    assert_eq!(status(&s)["fit"]["ready"], true);
}

fn extended_calibration(s: &NfMcp) {
    let s = s.clone();
    // Calibration with 20 s of bad signal: extends to the 60 s cap.
    run(&s, "calibration.start", Value::Null);
    adv(&s, 5.0);
    fault(&s, &["AF7"], false);
    adv(&s, 20.0);
    let c = &status(&s)["calibration"];
    assert!(c["waiting"].as_str().unwrap().contains("AF7"), "{c}");
    assert!(fails(&s, "calibration.skip", Value::Null).contains("good seconds") || c["valid_s"].as_u64().unwrap() >= 10);
    fault(&s, &[], false);
    let waited = until(&s, "playing", 60);
    let b = &status(&s)["last_baseline"];
    assert_eq!(b["wall_s"], 60, "{b}");
    assert!(b["valid_s"].as_u64().unwrap() < 45, "{b}");
    assert!(waited > 25, "extended past 45 s ({waited})");
}

fn training_adapts(s: &NfMcp) {
    let s = s.clone();
    // Training with adaptation (75 s window, every 30 s).
    adv(&s, 120.0);
    let res = run(&s, "feedback.result.get", Value::Null);
    let played: Vec<&Value> = res.as_array().unwrap().iter().filter(|r| r["second"].is_u64()).collect();
    assert!(played.len() >= 119);
    assert!(played.iter().any(|r| r["record"]["adapt"].is_object()), "adapted");
    assert!(played.iter().any(|r| r["in_target"] == true));
    let thr0 = status(&s)["threshold"].as_f64().unwrap();
    let t = run(&s, "threshold.set", json!({ "percentile": 70 }));
    assert!(t["threshold"].as_f64().unwrap() > thr0);
}

fn pauses_and_dropouts(s: &NfMcp) {
    let s = s.clone();
    // Bad signal on both target pads for 10 s auto-pauses; recovers by itself.
    fault(&s, &["AF7", "AF8"], false);
    let w = until(&s, "paused:bad_signal", 15);
    assert!((10..=13).contains(&w), "{w}");
    assert!(fails(&s, "feedback.resume", Value::Null).contains("resumes by itself"));
    let last = run(&s, "feedback.result.get", json!({ "last": 1 }));
    assert!(last[0]["reason"].as_str().unwrap().contains("AF7"));
    fault(&s, &[], false);
    until(&s, "playing", 5);

    // User pause/resume.
    run(&s, "feedback.pause", Value::Null);
    let p0 = status(&s)["played_s"].clone();
    adv(&s, 5.0);
    assert_eq!(status(&s)["played_s"], p0, "paused time does not count");
    run(&s, "feedback.resume", Value::Null);

    // Short dropout: paused, then resumes when the same device is back.
    fault(&s, &[], true);
    until(&s, "paused:disconnected", 4);
    adv(&s, 4.0);
    assert_eq!(status(&s)["reconnect_prompt"], false, "no prompt before 15 s");
    fault(&s, &[], false);
    until(&s, "playing", 3);
    long_dropout_never_ends(&s);
    // Only the user ends it: Disconnect needs end_session=true.
    let err = fails(&s, "device.disconnect", json!({}));
    assert!(err.contains("end_session=true"), "{err}");
    assert_eq!(phase(&s), "playing", "a refused disconnect changes nothing");
    run(&s, "device.disconnect", json!({ "end_session": true }));
    assert_eq!(phase(&s), "ended");
    let sum = &status(&s)["summary"];
    assert_eq!(sum["ended_by"], "device disconnected by the user");
    assert!(sum["adapt_steps"].as_u64().unwrap() >= 1, "{sum}");
    assert!(sum["pauses"].as_u64().unwrap() >= 3, "{sum}");
    assert!(sum["success"].as_f64().is_some());
}

/// A link loss of any length pauses (silent) and never ends the session;
/// after 15 s the user is asked; a different device may not join.
fn long_dropout_never_ends(s: &NfMcp) {
    let s = s.clone();
    fault(&s, &[], true);
    until(&s, "paused:disconnected", 4);
    adv(&s, 16.0);
    let st = status(&s);
    assert_eq!(st["reconnect_prompt"], true, "{st}");
    assert!(st["link_lost_s"].as_f64().unwrap() >= 15.0, "{st}");
    let ev = run(&s, "events.drain", Value::Null);
    assert!(ev.as_array().unwrap().iter().any(|e| e["event"] == "reconnect_prompt"), "{ev}");
    assert!(ev.as_array().unwrap().iter().any(|e| e["event"] == "chime"), "training chimed before the dropout");
    let cue = &run(&s, "audio.status", Value::Null)["cue"];
    assert_eq!((cue["background_on"].as_bool(), cue["reward_on"].as_bool()), (Some(false), Some(false)), "{cue}");
    let err = fails(&s, "device.connect", json!({ "id": "sim:crown" }));
    assert!(err.contains("end the session"), "{err}");
    run(&s, "feedback.keep_waiting", Value::Null);
    assert_eq!(status(&s)["reconnect_prompt"], false);
    adv(&s, 120.0);
    assert_eq!(phase(&s), "paused:disconnected", "never auto-ends");
    assert_eq!(status(&s)["reconnect_prompt"], false, "keep waiting holds until the link is back");
    fault(&s, &[], false);
    until(&s, "playing", 3);
    assert_eq!(status(&s)["link_lost_s"], Value::Null);
}

fn reuse_baseline(s: &NfMcp) {
    let s = s.clone();
    // Next session reuses the stored baseline; stop builds a summary.
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    adv(&s, 2.0);
    run(&s, "feedback.start", json!({ "minutes": 1 }));
    run(&s, "calibration.reuse", Value::Null);
    assert_eq!(phase(&s), "playing");
    adv(&s, 10.0);
    run(&s, "feedback.stop", Value::Null);
    assert_eq!(status(&s)["summary"]["ended_by"], "stopped");
}

#[test]
fn clean_calibration_takes_45_seconds_and_session_completes() {
    let s = server();
    run(&s, "device.connect", json!({ "id": "sim:muse2" }));
    adv(&s, 2.0);
    run(&s, "feedback.start", json!({ "minutes": 1 }));
    run(&s, "calibration.start", json!({ "anyway": true }));
    let w = until(&s, "playing", 60);
    assert!((45..=47).contains(&w), "{w}");
    assert_eq!(status(&s)["last_baseline"]["valid_s"], 45);
    adv(&s, 61.0);
    assert_eq!(phase(&s), "ended");
    assert_eq!(status(&s)["summary"]["ended_by"], "completed");
    assert_eq!(status(&s)["summary"]["played_s"], 60);
}

#[test]
fn start_anyway_finishes_calibration_early_and_rollback_restores_phase() {
    let s = server();
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    adv(&s, 2.0);
    run(&s, "feedback.start", Value::Null);
    run(&s, "calibration.start", json!({ "anyway": true }));
    adv(&s, 5.0);
    assert!(fails(&s, "calibration.skip", Value::Null).contains("needs 10"));
    adv(&s, 10.0);
    // Atomic batch: the failing second step rolls back the skip.
    let err = s.call(
        "command_batch",
        json!({ "steps": [
        { "id": "calibration.skip" }, { "id": "threshold.set", "params": { "percentile": 0 } } ] }),
    );
    assert!(err.is_err());
    assert_eq!(phase(&s), "calibrating");
    run(&s, "calibration.skip", Value::Null);
    assert_eq!(phase(&s), "playing");
}
fn b64decode(s: &str) -> Vec<u8> {
    let val = |c: u8| match c {
        b'A'..=b'Z' => c - b'A',
        b'a'..=b'z' => c - b'a' + 26,
        b'0'..=b'9' => c - b'0' + 52,
        b'+' => 62,
        _ => 63,
    };
    let mut out = Vec::new();
    for chunk in s.as_bytes().chunks(4) {
        let pad = chunk.iter().filter(|&&c| c == b'=').count();
        let n = chunk.iter().fold(0u32, |n, &c| (n << 6) | u32::from(if c == b'=' { 0 } else { val(c) }));
        out.extend_from_slice(&n.to_be_bytes()[1..4 - pad]);
    }
    out
}

#[test]
fn recording_carries_feedback_seconds_and_ppg_at_the_end() {
    use nf_format::{feedback_flags as f, Record};
    let s = server();
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    adv(&s, 2.0);
    run(&s, "recording.start", Value::Null);
    run(&s, "feedback.start", json!({ "minutes": 1 }));
    run(&s, "calibration.start", json!({ "anyway": true }));
    adv(&s, 80.0);
    run(&s, "recording.stop", Value::Null);
    let st = run(&s, "recording.status", Value::Null)["recording"].clone();
    assert!(st["ppg_samples"].as_u64().unwrap() > 0);
    let fb_n = st["feedback_seconds"].as_u64().unwrap();
    assert!(fb_n >= 75, "{st}");
    let b64 = run(&s, "recording.export", json!({ "format": "raw_body" }));
    let body = b64decode(b64["base64"].as_str().unwrap());
    let recs = nf_format::parse_body(&body).unwrap();
    let first = recs.iter().position(|r| matches!(r, Record::Feedback { .. })).unwrap();
    let tail = &recs[first..];
    assert!(tail.iter().all(|r| matches!(r, Record::Feedback { .. } | Record::Trust { .. })), "feedback appended at the end");
    assert_eq!(tail.iter().filter(|r| matches!(r, Record::Feedback { .. })).count() as u64, fb_n);
    assert_eq!(tail.iter().filter(|r| matches!(r, Record::Trust { .. })).count() as u64, fb_n, "one trust record per second");
    assert!(recs.iter().any(|r| matches!(r, Record::Ppg { .. })));
    let flags: Vec<u16> = recs[first..].iter().map(|r| if let Record::Feedback { flags, .. } = r { *flags } else { 0 }).collect();
    assert!(flags.iter().any(|x| x & f::CALIBRATING != 0));
    assert!(flags.iter().any(|x| x & f::COUNTED != 0));
}

#[test]
fn calibration_waits_silently_through_a_long_dropout() {
    let s = server();
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    adv(&s, 3.0);
    run(&s, "feedback.start", json!({ "minutes": 1 }));
    run(&s, "calibration.start", json!({ "anyway": true }));
    adv(&s, 5.0);
    assert_eq!(phase(&s), "calibrating");
    fault(&s, &[], true);
    adv(&s, 3.0); // data counts as gone after 1.5 s
    let before = status(&s)["calibration"]["wall_s"].clone();
    adv(&s, 40.0);
    let st = status(&s);
    assert_eq!(phase(&s), "calibrating", "not cancelled: {st}");
    assert_eq!(st["reconnect_prompt"], true);
    assert_eq!(st["calibration"]["wall_s"], before, "calibration time stops while the device is gone");
    assert_eq!(run(&s, "audio.status", Value::Null)["cue"]["background_on"], false);
    fault(&s, &[], false);
    adv(&s, 3.0);
    assert_eq!(status(&s)["reconnect_prompt"], false);
    assert_eq!(run(&s, "audio.status", Value::Null)["cue"]["background_on"], true);
    assert_eq!(phase(&s), "calibrating");
}

/// `sim.configure` on a running simulator reopens it in place: the
/// feedback session and its recording go on (feedback-disconnect rule 4).
#[test]
fn sim_configure_keeps_the_session_and_its_recording() {
    let s = server();
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    adv(&s, 2.0);
    run(&s, "feedback.start", json!({ "minutes": 5 }));
    run(&s, "calibration.start", json!({ "anyway": true }));
    until(&s, "playing", 60);
    let before = run(&s, "recording.status", Value::Null)["recording"]["eeg_samples"].as_u64().unwrap();
    run(&s, "sim.configure", json!({ "alpha_uv": 30.0 }));
    adv(&s, 5.0);
    let rec = run(&s, "recording.status", Value::Null)["recording"].clone();
    assert_eq!(rec["active"], true, "recording survives sim.configure: {rec}");
    assert!(rec["eeg_samples"].as_u64().unwrap() > before, "{rec}");
    assert_eq!(phase(&s), "playing");
}

fn nfed6_annotations(s: &NfMcp) -> Vec<Value> {
    let b64 = run(s, "recording.export", json!({ "format": "nfed6" }));
    let c = nf_format::decode_container(&b64decode(b64["base64"].as_str().unwrap())).unwrap();
    let meta: Value = serde_json::from_slice(&c.metadata_json).unwrap();
    meta["annotations"].as_array().cloned().unwrap_or_default()
}

/// A dropout during a recording is one `disconnect` annotation from the
/// last data to the first data back (seconds from the recording start).
#[test]
fn recording_annotates_a_dropout_as_disconnect() {
    let s = server();
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    adv(&s, 2.0);
    run(&s, "recording.start", Value::Null);
    adv(&s, 10.0);
    fault(&s, &[], true);
    adv(&s, 12.0);
    fault(&s, &[], false);
    adv(&s, 5.0);
    run(&s, "recording.stop", Value::Null);
    let a = nfed6_annotations(&s);
    assert_eq!(a.len(), 1, "{a:?}");
    assert_eq!(a[0]["type"], "disconnect");
    let (onset, dur) = (a[0]["onset"].as_f64().unwrap(), a[0]["duration"].as_f64().unwrap());
    assert!((onset - 10.0).abs() <= 0.2, "onset at the last data: {onset}");
    assert!((dur - 12.0).abs() <= 0.2, "duration up to the data coming back: {dur}");
    let id = run(&s, "recording.status", Value::Null)["recording"]["saved_id"].as_u64().unwrap();
    let saved = run(&s, "history.get", json!({ "id": id }));
    assert_eq!(saved["meta"]["annotations"].as_array().map(Vec::len), Some(1), "stored with the session: {saved}");
}

/// Stopping while the device is still gone closes the span at the end.
#[test]
fn disconnect_still_open_at_stop_ends_with_the_recording() {
    let s = server();
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    adv(&s, 2.0);
    run(&s, "recording.start", Value::Null);
    adv(&s, 4.0);
    fault(&s, &[], true);
    adv(&s, 6.0);
    run(&s, "recording.stop", Value::Null);
    let a = nfed6_annotations(&s);
    assert_eq!(a.len(), 1, "{a:?}");
    let end = a[0]["onset"].as_f64().unwrap() + a[0]["duration"].as_f64().unwrap();
    assert!((end - 10.0).abs() <= 0.2, "closed at the recording end: {a:?}");
}
