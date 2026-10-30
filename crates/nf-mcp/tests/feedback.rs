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
fn full_session_calibration_adaptation_pauses_grace_summary() {
    let s = server();
    assert!(fails(&s, "feedback.start", Value::Null).contains("no device"));
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    adv(&s, 3.0);
    let protos = run(&s, "protocol.list", Value::Null);
    assert!(protos.as_array().unwrap().iter().any(|p| p["protocol"]["unavailable"].is_string()));
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

    // Short dropout: paused, then resumes inside the 10 s grace.
    fault(&s, &[], true);
    until(&s, "paused:disconnected", 4);
    adv(&s, 4.0);
    fault(&s, &[], false);
    until(&s, "playing", 3);
    // Long dropout: ends after the grace.
    fault(&s, &[], true);
    adv(&s, 14.0);
    assert_eq!(phase(&s), "ended");
    let sum = &status(&s)["summary"];
    assert_eq!(sum["ended_by"], "device disconnected");
    assert!(sum["adapt_steps"].as_u64().unwrap() >= 1, "{sum}");
    assert!(sum["pauses"].as_u64().unwrap() >= 3, "{sum}");
    assert!(sum["success"].as_f64().is_some());
    let ev = run(&s, "events.drain", Value::Null);
    assert!(ev.as_array().unwrap().iter().any(|e| e["event"] == "chime"));

    // Next session reuses the stored baseline; stop builds a summary.
    fault(&s, &[], false);
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
    assert!(recs[first..].iter().all(|r| matches!(r, Record::Feedback { .. })), "feedback appended at the end");
    assert_eq!((recs.len() - first) as u64, fb_n);
    assert!(recs.iter().any(|r| matches!(r, Record::Ppg { .. })));
    let flags: Vec<u16> = recs[first..].iter().map(|r| if let Record::Feedback { flags, .. } = r { *flags } else { 0 }).collect();
    assert!(flags.iter().any(|x| x & f::CALIBRATING != 0));
    assert!(flags.iter().any(|x| x & f::COUNTED != 0));
}
