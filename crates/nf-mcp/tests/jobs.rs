#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! Long jobs through MCP with a manual clock: `job.start` wraps import /
//! export / AI install / AI load, `job.status` reports progress and the
//! result (the wrapped command's reply), `job.cancel` stops a job and
//! changes nothing. Also the native `ThreadRunner`.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp, ThreadRunner};
use nf_types::{AiModel, AiModelState, AiRuntime, AiScore, AiSource, AiWindow};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_or_else(|e| panic!("{id}: {e}"))
}
fn fails(s: &NfMcp, id: &str, params: Value) -> String {
    s.call("command_run", json!({ "id": id, "params": params })).expect_err(id).to_string()
}
fn adv(s: &NfMcp, secs: f64) {
    run(s, "clock.advance", json!({ "seconds": secs }));
}
fn start(s: &NfMcp, command: &str, params: Value) -> u64 {
    let j = run(s, "job.start", json!({ "command": command, "params": params }));
    assert_eq!(j["state"], "running", "{j}");
    assert_eq!(j["command"], command);
    j["id"].as_u64().unwrap()
}
fn status(s: &NfMcp, id: u64) -> Value {
    run(s, "job.status", json!({ "id": id }))
}
fn history_len(s: &NfMcp) -> usize {
    run(s, "history.list", Value::Null)["sessions"].as_array().unwrap().len()
}
fn events(s: &NfMcp) -> Vec<Value> {
    run(s, "events.drain", Value::Null).as_array().unwrap().clone()
}

/// Steps the clock until the job settles; returns (status, progress seen).
fn wait(s: &NfMcp, id: u64) -> (Value, Vec<f64>) {
    let mut seen = Vec::new();
    for _ in 0..2000 {
        let st = status(s, id);
        if st["job"]["state"] != "running" {
            return (st, seen);
        }
        seen.push(st["job"]["progress"].as_f64().unwrap_or(-1.0));
        adv(s, 0.1);
    }
    panic!("job {id} never finished");
}

/// 3 minutes of simulated Muse S (a raw body larger than one base64 step).
fn recorded() -> NfMcp {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    run(&s, "recording.start", json!({ "wall_clock_unix_ms": 1_709_294_400_000.0 }));
    adv(&s, 180.0);
    run(&s, "recording.stop", Value::Null);
    run(&s, "device.disconnect", Value::Null);
    events(&s);
    s
}

#[test]
fn import_job_reports_progress_and_matches_the_sync_import() {
    let s = recorded();
    let edf = run(&s, "recording.export", json!({ "format": "edf" }))["base64"].as_str().unwrap().to_owned();
    let before = history_len(&s);
    let params = json!({ "file_name": "r.edf", "data_base64": edf });
    let id = start(&s, "history.import", params.clone());
    assert_eq!(history_len(&s), before, "nothing saved before the job finishes");

    let (st, seen) = wait(&s, id);
    assert_eq!(st["job"]["state"], "done", "{st}");
    assert_eq!(st["job"]["progress"], 1.0);
    assert!(seen.len() > 3, "several steps: {seen:?}");
    assert!(seen.windows(2).all(|w| w[0] <= w[1]), "monotonic: {seen:?}");
    assert!(seen.iter().any(|p| *p > 0.0 && *p < 1.0), "{seen:?}");
    let job_id = st["result"]["id"].as_u64().unwrap();
    assert_eq!(history_len(&s), before + 1);

    let ev = events(&s);
    let kinds: Vec<&str> = ev.iter().filter_map(|e| e["event"].as_str()).filter(|k| k.starts_with("job_")).collect();
    assert_eq!(kinds.first(), Some(&"job_started"));
    assert_eq!(kinds.last(), Some(&"job_finished"));
    assert!(kinds.contains(&"job_progress"), "{kinds:?}");
    assert!(ev.iter().any(|e| e["event"] == "session_saved" && e["id"] == job_id));

    // Same session as the one-shot import (same records, same bands).
    let sync = run(&s, "history.import", params);
    assert_eq!(st["result"]["summary"], sync["summary"]);
    let export = |id: &Value| run(&s, "history.export", json!({ "id": id, "format": "nfed6" }))["base64"].clone();
    assert_eq!(export(&st["result"]["id"]), export(&sync["id"]));
}

#[test]
fn cancelled_import_saves_nothing() {
    let s = recorded();
    let edf = run(&s, "recording.export", json!({ "format": "edf" }))["base64"].as_str().unwrap().to_owned();
    let before = history_len(&s);
    let rev = run(&s, "app.status", Value::Null)["revision"].clone();
    let id = start(&s, "history.import", json!({ "file_name": "r.edf", "data_base64": edf }));
    adv(&s, 0.3);
    let p = status(&s, id)["job"]["progress"].as_f64().unwrap();
    assert!(p > 0.0 && p < 1.0, "mid-way: {p}");

    let c = run(&s, "job.cancel", json!({ "id": id }));
    assert_eq!(c["state"], "cancelled");
    adv(&s, 30.0);
    let st = status(&s, id);
    assert_eq!(st["job"]["state"], "cancelled", "{st}");
    assert!(st["result"].is_null());
    assert_eq!(history_len(&s), before, "nothing saved");
    assert!(fails(&s, "job.cancel", json!({ "id": id })).contains("already finished (cancelled)"));
    let ev = events(&s);
    assert!(ev.iter().any(|e| e["event"] == "job_finished" && e["state"] == "cancelled"));
    assert!(!ev.iter().any(|e| e["event"] == "session_saved"));
    // job.start and job.cancel are the only revisions.
    assert_eq!(run(&s, "app.status", Value::Null)["revision"], rev.as_u64().unwrap() + 2);
}

#[test]
fn export_jobs_equal_the_sync_exports() {
    let s = recorded();
    for format in ["raw_body", "nfed6", "edf"] {
        let sync = run(&s, "recording.export", json!({ "format": format }));
        if format == "raw_body" {
            assert!(sync["bytes"].as_u64().unwrap() > 3 << 18, "body spans several base64 steps");
        }
        let id = start(&s, "recording.export", json!({ "format": format }));
        let (st, _) = wait(&s, id);
        assert_eq!(st["job"]["state"], "done", "{format}: {st}");
        assert_eq!(st["result"], sync, "{format}");
    }
    // A saved session (the sync import puts one in history).
    let edf = run(&s, "recording.export", json!({ "format": "edf" }))["base64"].clone();
    let saved = run(&s, "history.import", json!({ "file_name": "r.edf", "data_base64": edf }))["id"].clone();
    for format in ["edf", "pdf"] {
        let p = json!({ "id": saved, "format": format });
        let id = start(&s, "history.export", p.clone());
        let (st, _) = wait(&s, id);
        assert_eq!(st["result"], run(&s, "history.export", p), "{format}");
    }
    let all = run(&s, "job.status", Value::Null)["jobs"].as_array().unwrap().clone();
    assert_eq!(all.len(), 5);
    assert!(all.iter().all(|j| j["state"] == "done" && j.get("result").is_none()), "the list has no results");
}

#[test]
fn refusals_explain_and_change_nothing() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    let rev = run(&s, "app.status", Value::Null)["revision"].clone();
    let job = |command: &str, params: Value| fails(&s, "job.start", json!({ "command": command, "params": params }));
    assert!(job("view.set", json!({ "view": "bands" })).contains("cannot run as a job"));
    assert!(job("no.such", Value::Null).contains("cannot run as a job"));
    assert!(job("recording.export", json!({ "format": "edf" })).contains("nothing recorded"), "disabled inner command");
    assert!(job("history.export", json!({ "id": "one", "format": "edf" })).contains("invalid"), "bad inner params");
    assert!(job("history.import", json!({ "file_name": "x.edf", "data_base64": "!!" })).contains("not base64"));
    assert!(job("ai.install", Value::Null).contains("desktop app only"), "no AI runtime");
    assert!(fails(&s, "job.status", json!({ "id": 9 })).contains("no job 9"));
    assert!(fails(&s, "job.cancel", json!({ "id": 9 })).contains("no job 9"));
    let b = s
        .call("command_batch", json!({ "steps": [{ "id": "view.set", "params": { "view": "bands" } }, { "id": "job.start", "params": { "command": "history.export", "params": { "id": 1, "format": "edf" } } }] }))
        .expect_err("batch")
        .to_string();
    assert!(b.contains("cannot be rolled back"), "{b}");
    assert_eq!(run(&s, "job.status", Value::Null)["jobs"], json!([]));
    assert_eq!(run(&s, "app.status", Value::Null)["revision"], rev);
}

#[test]
fn at_most_four_jobs_run_at_once() {
    let s = recorded();
    let ids: Vec<u64> = (0..4).map(|_| start(&s, "recording.export", json!({ "format": "raw_body" }))).collect();
    assert!(fails(&s, "job.start", json!({ "command": "recording.export", "params": { "format": "edf" } })).contains("4 jobs are running"));
    run(&s, "job.cancel", json!({ "id": ids[0] }));
    start(&s, "recording.export", json!({ "format": "edf" }));
}

/// Install progress comes from `progress`; `finish` completes it.
#[derive(Default)]
struct SlowAi {
    states: HashMap<AiModel, AiModelState>,
    progress: Arc<Mutex<Option<f64>>>,
    finish: Arc<Mutex<bool>>,
}

impl AiRuntime for SlowAi {
    fn state(&self, m: AiModel) -> AiModelState {
        match self.states.get(&m) {
            Some(AiModelState::Installing { .. }) if *self.finish.lock().unwrap() => AiModelState::Installed,
            Some(AiModelState::Installing { .. }) => AiModelState::Installing { progress: *self.progress.lock().unwrap() },
            Some(s) => s.clone(),
            None => AiModelState::Missing,
        }
    }
    fn folder(&self, m: AiModel) -> Option<String> {
        Some(format!("/models/{}", m.id()))
    }
    fn install(&mut self, m: AiModel, _: AiSource) -> Result<(), String> {
        *self.finish.lock().unwrap() = false;
        self.states.insert(m, AiModelState::Installing { progress: None });
        Ok(())
    }
    fn cancel_install(&mut self, m: AiModel) -> Result<(), String> {
        self.states.insert(m, AiModelState::Missing);
        Ok(())
    }
    fn remove(&mut self, m: AiModel) -> Result<(), String> {
        self.states.insert(m, AiModelState::Missing);
        Ok(())
    }
    fn load(&mut self, m: AiModel) -> Result<(), String> {
        self.states.insert(m, AiModelState::Ready { description: "slow".into() });
        Ok(())
    }
    fn unload(&mut self) {
        for s in self.states.values_mut() {
            if matches!(s, AiModelState::Ready { .. }) {
                *s = AiModelState::Installed;
            }
        }
    }
    fn submit(&mut self, _: AiWindow) -> bool {
        false
    }
    fn poll(&mut self) -> Vec<AiScore> {
        Vec::new()
    }
}

fn model_state(s: &NfMcp) -> Value {
    run(s, "ai.status", Value::Null)["models"][0]["state"].clone()
}

#[test]
fn ai_install_job_follows_the_runtime_and_cancels() {
    let ai = SlowAi::default();
    let (progress, finish) = (ai.progress.clone(), ai.finish.clone());
    let mut session = Session::new();
    session.set_ai_runtime(Box::new(ai));
    let s = NfMcp::new(session, ClockMode::Manual);
    run(&s, "ai.set", json!({ "auto_load": false }));

    let id = start(&s, "ai.install", json!({ "model": "cbramod_a_vig" }));
    assert!(fails(&s, "job.start", json!({ "command": "ai.load", "params": {} })).contains("is running"), "one AI job at a time");
    *progress.lock().unwrap() = Some(0.4);
    adv(&s, 0.1);
    assert_eq!(status(&s, id)["job"]["progress"], 0.4);
    *finish.lock().unwrap() = true;
    let (st, _) = wait(&s, id);
    assert_eq!(st["job"]["state"], "done", "{st}");
    assert_eq!(st["result"]["models"][0]["state"], "installed", "result = ai.status");

    let id = start(&s, "ai.load", json!({}));
    assert!(status(&s, id)["job"]["progress"].is_null(), "a load has no progress");
    let (st, _) = wait(&s, id);
    assert_eq!(st["job"]["state"], "done", "{st}");
    assert_eq!(model_state(&s), "ready");

    run(&s, "ai.remove", json!({ "model": "cbramod_a_vig", "confirm": true }));
    let id = start(&s, "ai.install", json!({}));
    assert_eq!(run(&s, "job.cancel", json!({ "id": id }))["state"], "cancelled");
    adv(&s, 1.0);
    assert_eq!(model_state(&s), "missing");
    assert_eq!(status(&s, id)["job"]["state"], "cancelled");
}

#[test]
fn thread_runner_runs_jobs_beside_the_session() {
    let s = recorded();
    let sync = run(&s, "recording.export", json!({ "format": "edf" }));
    let s = {
        // Same recording, now with the runner: rebuild through an import.
        let mut session = Session::new();
        session.set_job_runner(Box::new(ThreadRunner));
        let t = NfMcp::new(session, ClockMode::Manual);
        let id = start(&t, "history.import", json!({ "file_name": "r.edf", "data_base64": sync["base64"] }));
        // The thread runs on its own; ticks only collect the outcome.
        let mut done = Value::Null;
        for _ in 0..5000 {
            done = status(&t, id);
            if done["job"]["state"] != "running" {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(2));
            adv(&t, 0.1);
        }
        assert_eq!(done["job"]["state"], "done", "{done}");
        assert_eq!(history_len(&t), 1);
        t
    };
    // Cancelled on the thread: the result is discarded even if the work ends.
    let saved = run(&s, "history.list", Value::Null)["sessions"][0]["id"].clone();
    let id = start(&s, "history.export", json!({ "id": saved, "format": "edf" }));
    run(&s, "job.cancel", json!({ "id": id }));
    std::thread::sleep(std::time::Duration::from_millis(50));
    adv(&s, 1.0);
    let st = status(&s, id);
    assert_eq!(st["job"]["state"], "cancelled");
    assert!(st["result"].is_null());
}
