#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! Audio settings, the live cue and the band-math drowsiness guard via MCP.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use serde_json::{json, Value};

fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_or_else(|e| panic!("{id}: {e}"))
}
fn fails(s: &NfMcp, id: &str, params: Value) -> String {
    s.call("command_run", json!({ "id": id, "params": params })).expect_err(id).to_string()
}
fn adv(s: &NfMcp, secs: f64) {
    run(s, "clock.advance", json!({ "seconds": secs }));
}
fn audio(s: &NfMcp) -> Value {
    run(s, "audio.status", Value::Null)
}

#[test]
fn audio_settings_validate_and_reset() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    let a = audio(&s);
    assert_eq!(a["settings"]["reward"], "chime");
    assert_eq!(a["binaural_presets"].as_array().unwrap().len(), 5);
    assert_eq!(a["cue"]["reward_on"], false);
    let set = run(
        &s,
        "audio.set",
        json!({ "reward_output": "rain", "background": "binaural", "binaural_preset": "theta_calm", "music_min_hz": 9000 }),
    );
    assert_eq!((set["reward"].as_str(), set["background"].as_str()), (Some("rain"), Some("binaural")));
    assert_eq!(set["music_min_hz"], 8000.0);
    assert!(fails(&s, "audio.set", json!({ "master_volume": 1.5 })).contains("[0, 1]"));
    assert!(fails(&s, "audio.set", json!({ "reward_output": "kazoo" })).contains("kazoo"));
    assert!(fails(&s, "audio.set", json!({ "volume": 1 })).contains("volume"));
    assert_eq!(run(&s, "audio.set", json!({ "reset": true }))["reward"], "chime");
    let schema = s.call("command_describe", json!({ "id": "audio.set" })).unwrap();
    assert!(schema.to_string().contains("reward_output"), "{schema}");
}

#[test]
fn drowsy_guard_warns_mutes_reward_and_chimes() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    adv(&s, 3.0);
    run(&s, "protocol.set", json!({ "id": "alertOpen" }));
    assert!(fails(&s, "guard.set", json!({ "enabled": true })).contains("no guard"));
    run(&s, "protocol.set", json!({ "id": "restAwake", "minutes": 5 }));
    let g = run(&s, "guard.set", json!({ "enabled": true }));
    assert_eq!((g["enabled"].as_bool(), g["muffle_reward"].as_bool()), (Some(true), Some(true)));
    run(&s, "audio.set", json!({ "reward_output": "rain" }));
    run(&s, "feedback.start", Value::Null);
    assert!(fails(&s, "guard.set", json!({ "enabled": false })).contains("locked"));
    adv(&s, 5.0);
    run(&s, "calibration.start", Value::Null);
    adv(&s, 50.0);
    assert_eq!(audio(&s)["cue"]["background_on"], true);
    adv(&s, 20.0);
    let a = audio(&s);
    assert_eq!(a["phase"]["phase"], "playing");
    assert_eq!((a["cue"]["reward_on"].as_bool(), a["cue"]["warning"].as_bool()), (Some(true), Some(false)));
    assert!(a["cue"]["pct"].is_number() && a["guard"]["threshold"].is_number(), "{a}");
    run(&s, "events.drain", Value::Null);
    run(&s, "sim.fault", json!({ "drowsy": true }));
    adv(&s, 25.0);
    let a = audio(&s);
    assert_eq!((a["cue"]["warning"].as_bool(), a["cue"]["muffle"].as_bool()), (Some(true), Some(true)), "{a}");
    let ev = run(&s, "events.drain", Value::Null).to_string();
    assert_eq!(ev.matches("guard_chime").count(), 2, "20 s cooldown: {ev}");
    let last = run(&s, "feedback.result.get", json!({ "last": 1 })).to_string();
    assert!(last.contains("sleep guard") || last.contains("\"in_target\":false"), "{last}");
    run(&s, "sim.fault", json!({}));
    adv(&s, 10.0);
    assert_eq!(audio(&s)["cue"]["warning"], false);
}
