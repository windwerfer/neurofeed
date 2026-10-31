#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! Timed simulator faults (`sim.fault.add` / `sim.fault.clear`) and how the
//! engine flags them: link state, pad quality, artifact / trust flags.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use serde_json::{json, Value};

fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_or_else(|e| panic!("{id}: {e}"))
}
fn fails(s: &NfMcp, id: &str, params: Value) -> String {
    s.call("command_run", json!({ "id": id, "params": params })).expect_err(id).to_string()
}
fn adv(s: &NfMcp, secs: u32) {
    for _ in 0..secs {
        run(s, "clock.advance", json!({ "seconds": 1.0 }));
    }
}
fn sim() -> NfMcp {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    adv(&s, 6);
    s
}
fn pads(s: &NfMcp) -> Vec<(String, f64)> {
    let st = run(s, "signal.status", json!({}));
    st["pads"].as_array().unwrap().iter().map(|p| (p["channel"].as_str().unwrap().to_owned(), p["quality"].as_f64().unwrap())).collect()
}
fn faults(s: &NfMcp) -> Vec<Value> {
    run(s, "app.status", Value::Null)["faults"].as_array().cloned().unwrap_or_default()
}
fn link(s: &NfMcp) -> String {
    run(s, "device.status", Value::Null)["link"]["state"].as_str().unwrap_or_default().to_owned()
}

#[test]
fn disconnect_loses_the_link_and_reconnects_on_its_own() {
    let s = sim();
    assert_eq!(link(&s), "streaming");
    let r = run(&s, "sim.fault.add", json!({ "kind": "disconnect", "reconnect_after_s": 4.0 }));
    assert!(r["id"].as_u64().is_some());
    adv(&s, 2);
    assert_eq!(link(&s), "lost");
    assert_eq!(faults(&s).len(), 1);
    assert_eq!(faults(&s)[0]["kind"], "disconnect");
    adv(&s, 3);
    assert_eq!(link(&s), "streaming");
    assert!(faults(&s).is_empty());
}

#[test]
fn noise_spikes_glitch_and_out_of_range_ruin_only_the_chosen_pads() {
    for kind in [
        json!({ "kind": "noise", "clean_fraction": 0.0 }),
        json!({ "kind": "spikes" }),
        json!({ "kind": "glitch" }),
        json!({ "kind": "out_of_range", "value": "nan" }),
        json!({ "kind": "out_of_range", "value": "inf" }),
        json!({ "kind": "out_of_range", "value": "rail" }),
    ] {
        let s = sim();
        let mut p = kind.clone();
        p["channels"] = json!(["AF7"]);
        p["duration_s"] = json!(5.0);
        run(&s, "sim.fault.add", p);
        adv(&s, 3);
        let q = pads(&s);
        assert!(q.iter().all(|(_, v)| v.is_finite()), "{kind}: {q:?}");
        let af7 = q.iter().find(|(c, _)| c == "AF7").unwrap().1;
        assert!(af7 < 60.0, "{kind}: AF7 should be bad: {q:?}");
        assert!(q.iter().filter(|(c, _)| c != "AF7").all(|(_, v)| *v >= 60.0), "{kind}: others stay good: {q:?}");
        adv(&s, 8);
        assert!(faults(&s).is_empty(), "{kind}: expired");
        assert!(pads(&s).iter().all(|(_, v)| *v >= 60.0), "{kind}: recovers: {:?}", pads(&s));
    }
}

#[test]
fn clean_fraction_controls_how_much_noise_gets_through() {
    let bad_seconds = |clean: f64| {
        let s = sim();
        run(&s, "sim.fault.add", json!({ "kind": "noise", "clean_fraction": clean, "channels": ["TP9"] }));
        (0..40)
            .filter(|_| {
                adv(&s, 1);
                pads(&s).iter().find(|(c, _)| c == "TP9").unwrap().1 < 60.0
            })
            .count()
    };
    let (mostly_clean, mostly_bad) = (bad_seconds(0.9), bad_seconds(0.2));
    assert!(mostly_clean < 15 && mostly_bad > 25, "0.9 → {mostly_clean} bad s, 0.2 → {mostly_bad} bad s");
}

#[test]
fn movement_blink_clench_are_flagged_by_the_artifact_detector() {
    for (kind, want) in [("movement", "movement"), ("blink", "blink"), ("clench", "jaw")] {
        let s = sim();
        run(&s, "protocol.set", json!({ "id": "restAwake" }));
        run(&s, "feedback.start", json!({ "minutes": 4 }));
        adv(&s, 4);
        let id = run(&s, "sim.fault.add", json!({ "kind": kind, "duration_s": 6.0 }))["id"].clone();
        let seen: Vec<String> = (0..6)
            .map(|_| {
                adv(&s, 1);
                run(&s, "artifact.status", Value::Null)["status"]["artifact"].as_str().unwrap_or("-").to_owned()
            })
            .collect();
        assert!(seen.iter().filter(|k| *k == want).count() >= 2, "{kind}: {seen:?}");
        adv(&s, 1);
        assert!(fails(&s, "sim.fault.clear", json!({ "id": id })).contains("no fault"), "already expired");
    }
}

#[test]
fn trust_marks_faulted_training_seconds_as_not_counted() {
    let s = sim();
    run(&s, "protocol.set", json!({ "id": "restAwake" }));
    run(&s, "feedback.start", json!({ "minutes": 4 }));
    adv(&s, 5);
    run(&s, "calibration.start", Value::Null);
    for _ in 0..80 {
        if run(&s, "feedback.status", Value::Null)["phase"]["phase"] == "playing" {
            break;
        }
        adv(&s, 1);
    }
    adv(&s, 4);
    run(&s, "sim.fault.add", json!({ "kind": "spikes" }));
    adv(&s, 4);
    let last = run(&s, "feedback.result.get", json!({ "last": 2 }));
    for r in last.as_array().unwrap() {
        assert_eq!(r["counted"], false, "{r}");
        assert!(r["reason"].as_str().unwrap_or_default().contains("no good signal"), "{r}");
    }
    run(&s, "sim.fault.clear", json!({}));
    assert!(faults(&s).is_empty());
}

#[test]
fn bad_fault_params_are_rejected() {
    let s = sim();
    assert!(fails(&s, "sim.fault.add", json!({ "kind": "noise", "clean_fraction": 2.0 })).contains("clean_fraction"));
    assert!(fails(&s, "sim.fault.add", json!({ "kind": "blink", "channels": ["XX"] })).contains("unknown channel"));
    assert!(fails(&s, "sim.fault.add", json!({ "kind": "spikes", "duration_s": -1.0 })).contains("duration_s"));
    assert!(fails(&s, "sim.fault.add", json!({ "kind": "blink", "clean_fraction": 0.5 })).contains("does not apply"));
    assert!(s.call("command_run", json!({ "id": "sim.fault.add", "params": { "kind": "warp" } })).is_err());
}

#[test]
fn mid_stream_disconnect_zeroes_quality_and_pauses_band_snapshots() {
    let s = sim();
    run(&s, "sim.fault.add", json!({ "kind": "disconnect", "reconnect_after_s": 3.0 }));
    adv(&s, 2);
    assert!(pads(&s).iter().all(|(_, q)| *q == 0.0), "{:?}", pads(&s));
    adv(&s, 5);
    assert_eq!(link(&s), "streaming");
    assert!(pads(&s).iter().all(|(_, q)| *q >= 60.0), "recovers: {:?}", pads(&s));
}
