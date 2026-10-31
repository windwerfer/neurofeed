#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! Artifact detection end to end through MCP `command_run`.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use serde_json::{json, Value};

fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_or_else(|e| panic!("{id}: {e}"))
}
fn adv(s: &NfMcp, secs: f64) {
    run(s, "clock.advance", json!({ "seconds": secs }));
}
/// Artifacts seen over `n` feedback seconds.
fn seen(s: &NfMcp, n: u32) -> Vec<Value> {
    (0..n)
        .map(|_| {
            adv(s, 1.0);
            run(s, "artifact.status", Value::Null)["status"].clone()
        })
        .collect()
}
fn kinds(v: &[Value]) -> Vec<String> {
    v.iter().map(|x| x["artifact"].as_str().unwrap_or("-").to_owned()).collect()
}

#[test]
fn motion_blink_clench_are_detected_and_clean_signal_is_not() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    run(&s, "protocol.set", json!({ "id": "restAwake" }));
    run(&s, "feedback.start", json!({ "minutes": 4 }));
    adv(&s, 8.0);
    let clean = seen(&s, 20);
    assert!(kinds(&clean).iter().all(|k| k == "-"), "clean: {:?} {clean:?}", kinds(&clean));
    assert!(clean[5]["movement_score"].as_f64().unwrap() < 0.01);
    for (fault, want) in [("motion", "movement"), ("blink", "blink"), ("clench", "jaw")] {
        run(&s, "sim.fault", json!({ fault: true }));
        let got = kinds(&seen(&s, 8));
        // Blinks come every 2 s; movement and clench every second.
        let every = if fault == "blink" { 2 } else { 1 };
        assert!(
            got[2..].iter().all(|k| k == want || k == "-") && got[2..].iter().filter(|k| *k == want).count() >= 6 / every,
            "{fault}: {got:?}"
        );
        run(&s, "sim.fault", json!({}));
        adv(&s, 3.0);
        let after = seen(&s, 10);
        assert!(kinds(&after[3..]).iter().all(|k| k == "-"), "after {fault}: {:?}", kinds(&after));
    }
}

fn phase(s: &NfMcp) -> String {
    run(s, "feedback.status", Value::Null)["phase"]["phase"].as_str().unwrap_or_default().to_owned()
}

#[test]
fn artifact_seconds_are_dirty_never_counted_and_flagged_in_the_recording() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    run(&s, "protocol.set", json!({ "id": "restAwake" }));
    run(&s, "feedback.start", json!({ "minutes": 4 }));
    adv(&s, 5.0);
    run(&s, "calibration.start", Value::Null);
    for _ in 0..80 {
        if phase(&s) == "playing" {
            break;
        }
        adv(&s, 1.0);
    }
    assert_eq!(phase(&s), "playing");
    adv(&s, 5.0);
    run(&s, "sim.fault", json!({ "motion": true }));
    adv(&s, 6.0);
    let last = run(&s, "feedback.result.get", json!({ "last": 4 }));
    for r in last.as_array().unwrap() {
        assert_eq!(r["record"]["dirty"], "movement", "{r}");
        assert_eq!(r["counted"], false);
        assert!(r["reason"].as_str().unwrap().contains("movement"), "{r}");
    }
    run(&s, "sim.fault", json!({}));
    adv(&s, 4.0);
    let last = run(&s, "feedback.result.get", json!({ "last": 1 }));
    assert!(last[0]["record"]["dirty"].is_null(), "{last}");
    run(&s, "recording.stop", Value::Null);
    let rec = &run(&s, "recording.status", Value::Null)["recording"];
    assert!(rec["feedback_seconds"].as_u64().unwrap() >= 15, "{rec}");
}
