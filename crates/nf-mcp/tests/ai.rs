#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! AI sleep guard through MCP `command_run` with a fake model runtime:
//! install / auto-load, live scores, Sleep Guard (staged calibration, AI
//! only, no reward), fixed vs percentile cut, persistence, web gating.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use nf_types::{AiModel, AiModelState, AiRuntime, AiScore, AiSource, AiWindow};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

/// Scores instantly: P(drowsy) = the shared value; embedding tilts with it.
#[derive(Default)]
struct FakeAi {
    states: HashMap<AiModel, AiModelState>,
    out: Vec<AiScore>,
    p: Arc<Mutex<f32>>,
}

impl AiRuntime for FakeAi {
    fn state(&self, m: AiModel) -> AiModelState {
        self.states.get(&m).cloned().unwrap_or(AiModelState::Missing)
    }
    fn folder(&self, m: AiModel) -> Option<String> {
        Some(format!("/models/{}", m.id()))
    }
    fn install(&mut self, m: AiModel, src: AiSource) -> Result<(), String> {
        match src {
            AiSource::Import { path } if path.ends_with(m.weights_file()) => {}
            AiSource::Download if m.download_url().is_some() => {}
            _ => return Err(format!("{} checksum mismatch", m.label())),
        }
        self.states.insert(m, AiModelState::Installed);
        Ok(())
    }
    fn remove(&mut self, m: AiModel) -> Result<(), String> {
        self.states.insert(m, AiModelState::Missing);
        Ok(())
    }
    fn load(&mut self, m: AiModel) -> Result<(), String> {
        self.unload();
        self.states.insert(m, AiModelState::Ready { description: "fake".into() });
        Ok(())
    }
    fn unload(&mut self) {
        for s in self.states.values_mut() {
            if matches!(s, AiModelState::Ready { .. }) {
                *s = AiModelState::Installed;
            }
        }
    }
    fn submit(&mut self, w: AiWindow) -> bool {
        assert_eq!(w.signal.len(), 4 * w.n_times);
        let p = *self.p.lock().unwrap();
        let heads = w.model.scorers().iter().map(|s| ((*s).to_owned(), p)).collect();
        self.out.push(AiScore { model: w.model, t: w.t, embedding: vec![1.0 - p, p, 0.5], heads, ms: 12.0 });
        true
    }
    fn poll(&mut self) -> Vec<AiScore> {
        std::mem::take(&mut self.out)
    }
}

fn server(p: &Arc<Mutex<f32>>, store: Option<nf_store::MemoryStore>) -> NfMcp {
    let mut s = Session::new();
    if let Some(st) = store {
        s = s.with_store(Box::new(st));
    }
    s.set_ai_runtime(Box::new(FakeAi { p: p.clone(), ..FakeAi::default() }));
    NfMcp::new(s, ClockMode::Manual)
}
fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_or_else(|e| panic!("{id}: {e}"))
}
fn fails(s: &NfMcp, id: &str, params: Value) -> String {
    s.call("command_run", json!({ "id": id, "params": params })).expect_err(id).to_string()
}
fn adv(s: &NfMcp, secs: f64) {
    for _ in 0..secs as u32 {
        run(s, "clock.advance", json!({ "seconds": 1.0 }));
    }
}

#[test]
fn without_a_runtime_ai_is_gated_with_a_reason() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    let st = run(&s, "ai.status", Value::Null);
    assert_eq!(st["runtime"], false);
    assert!(st["unavailable_reason"].as_str().unwrap().contains("desktop"));
    assert!(fails(&s, "ai.install", Value::Null).contains("desktop app only"));
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    run(&s, "protocol.set", json!({ "id": "sleepGuard" }));
    let e = fails(&s, "feedback.start", Value::Null);
    assert!(e.contains("Sleep Guard needs the AI model") && e.contains("no band-math fallback"), "{e}");
}

#[test]
fn install_autoload_score_and_remove() {
    let p = Arc::new(Mutex::new(0.2));
    let s = server(&p, None);
    assert!(fails(&s, "ai.install", json!({ "model": "reve_base" })).contains("checksum"), "gated: no download");
    let e = fails(&s, "ai.install", json!({ "path": "/tmp/wrong.bin" }));
    assert!(e.contains("checksum"), "{e}");
    let st = run(&s, "ai.install", json!({ "path": "/dl/pretrained_weights.pth" }));
    assert_eq!(st["models"][0]["state"], "installed");
    adv(&s, 1.0);
    let st = run(&s, "ai.status", Value::Null);
    assert_eq!(st["models"][0]["state"], "ready", "auto-loaded: {st}");
    assert_eq!(st["ready"], true);
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    adv(&s, 4.0);
    let live = &run(&s, "ai.status", Value::Null)["live"];
    assert!(live["windows"].as_u64().unwrap() >= 1, "{live}");
    assert!((live["value"].as_f64().unwrap() - 0.2).abs() < 1e-6);
    // Unload stays unloaded (no auto-load loop); remove needs confirm.
    run(&s, "ai.unload", Value::Null);
    adv(&s, 2.0);
    assert_eq!(run(&s, "ai.status", Value::Null)["models"][0]["state"], "installed");
    assert!(fails(&s, "ai.remove", json!({ "model": "cbramod_a_vig" })).contains("confirm"));
    let st = run(&s, "ai.remove", json!({ "model": "cbramod_a_vig", "confirm": true }));
    assert_eq!(st["models"][0]["state"], "missing");
    assert!(fails(&s, "ai.unload", Value::Null).contains("no model loaded"));
}

fn until_phase(s: &NfMcp, want: &str, max: u32) -> Vec<Value> {
    let mut seen = Vec::new();
    for _ in 0..max {
        let st = run(s, "feedback.status", Value::Null);
        if st["phase"]["phase"] == want {
            return seen;
        }
        seen.push(st);
        adv(s, 1.0);
    }
    panic!("never reached {want}");
}

#[test]
fn sleep_guard_runs_on_the_ai_and_warns() {
    let p = Arc::new(Mutex::new(0.2));
    let s = server(&p, None);
    run(&s, "ai.install", json!({ "path": "/dl/pretrained_weights.pth" }));
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    run(&s, "protocol.set", json!({ "id": "sleepGuard" }));
    adv(&s, 5.0);
    run(&s, "feedback.start", json!({ "minutes": 3 }));
    adv(&s, 4.0);
    run(&s, "calibration.start", Value::Null);
    let seen = until_phase(&s, "playing", 130);
    let stages: Vec<&str> = seen.iter().filter_map(|v| v["calibration"]["stage"].as_str()).collect();
    for want in ["artifacts", "eyes_open", "eyes_closed"] {
        assert!(stages.contains(&want), "stage {want} in {stages:?}");
    }
    let ai = run(&s, "ai.status", Value::Null);
    assert_eq!(ai["anchors"]["clear"], true, "V_clear from the eyes-open stage");
    let g = &run(&s, "audio.status", Value::Null)["guard"];
    assert_eq!(
        (g["scorer"].as_str(), g["threshold"].as_f64(), g["threshold_mode"].as_str()),
        (Some("ai.a_vig"), Some(0.5), Some("fixed")),
        "{g}"
    );
    adv(&s, 5.0);
    *p.lock().unwrap() = 0.9;
    adv(&s, 4.0);
    let res = run(&s, "feedback.result.get", Value::Null);
    let played: Vec<&Value> = res.as_array().unwrap().iter().filter(|r| r["second"].is_u64()).collect();
    assert!(played.iter().all(|r| r["in_target"] == false && r["chime"] == false), "never rewards");
    let last = played.last().unwrap();
    assert_eq!(last["record"]["warn"], true, "{last}");
    assert!(last["reason"].as_str().unwrap().contains("sleep guard"));
    // Mid-session switch to the percentile of the calibration (all 0.2).
    run(&s, "ai.set", json!({ "threshold_mode": "percentile" }));
    let g = &run(&s, "audio.status", Value::Null)["guard"];
    assert!((g["threshold"].as_f64().unwrap() - 0.2).abs() < 1e-6, "{g}");
    assert!(fails(&s, "ai.set", json!({ "scorer": "ai.wake_light" })).contains("locked"));
}

#[test]
fn rest_awake_uses_the_ai_guard_when_ready_and_band_math_stays_off() {
    let p = Arc::new(Mutex::new(0.9));
    let s = server(&p, None);
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    run(&s, "protocol.set", json!({ "id": "restAwake" }));
    let g = &run(&s, "audio.status", Value::Null)["guard"];
    assert_eq!((g["enabled"].as_bool(), g["scorer"].as_str()), (Some(false), Some("none")), "off without AI: {g}");
    run(&s, "ai.install", json!({ "path": "/dl/pretrained_weights.pth" }));
    adv(&s, 2.0);
    let g = &run(&s, "audio.status", Value::Null)["guard"];
    assert_eq!((g["enabled"].as_bool(), g["band_math"].as_bool(), g["scorer"].as_str()), (Some(true), Some(false), Some("ai.a_vig")));
}

#[test]
fn ai_settings_survive_a_restart() {
    use nf_store::Store;
    let mut s = Session::new().with_store(Box::new(nf_store::MemoryStore::default()));
    s.set_ai_runtime(Box::new(FakeAi::default()));
    let p = json!({ "model": "reve_base", "threshold_mode": "percentile", "fixed_threshold": 0.42, "auto_load": false });
    s.run(nf_core::Request::parse("ai.set", p).unwrap()).unwrap();
    let doc = s.store().get_doc("settings").unwrap().unwrap();
    let mut store = nf_store::MemoryStore::default();
    store.put_doc("settings", Some(&doc)).unwrap();
    let s2 = Session::new().with_store(Box::new(store));
    let a = &s2.state().ai.settings;
    assert_eq!((a.scorer.as_str(), a.fixed_threshold, a.auto_load), ("ai.a_vig_reve", 0.42, false));
}
