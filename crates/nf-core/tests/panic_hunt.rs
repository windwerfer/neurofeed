#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! `panic_hunt` (AGENTS.md "Never crash"): every command and query in the
//! catalog is called with adversarial params in several session states.
//!
//! Two properties, for every call:
//! 1. it never panics (a bad param is an `Err`, never a crash);
//! 2. a call that fails leaves the session state unchanged.
//!
//! Deterministic: hostile values are enumerated, not random. Params are
//! built per command from its JSON Schema (`input_schema`) and its catalog
//! example (`examples()`): each property in turn gets every hostile value,
//! then every enum value, then all properties at once.

use nf_core::{examples, input_schema, Request, Session, SPECS};
use serde_json::{json, Map, Value};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::OnceLock;

/// Values no well-behaved client sends.
fn hostile() -> Vec<Value> {
    vec![
        Value::Null,
        json!(true),
        json!(0),
        json!(-1),
        json!(1),
        json!(i64::MIN),
        json!(i64::MAX),
        json!(u64::MAX),
        json!(1e308),
        json!(-1e308),
        json!(5e-324),
        json!(0.5),
        json!(-0.0),
        json!(""),
        json!(" "),
        json!("x".repeat(10_000)),
        json!("../../../../etc/passwd"),
        json!("\u{0}\u{202e}🧠"),
        json!([]),
        json!(vec!["AF7"; 2_000]),
        json!([null, -1, "", {}]),
        json!({}),
        json!({ "a": { "b": { "c": [1, 2, 3] } } }),
    ]
}

/// Session states the hunt runs in.
#[derive(Debug, Clone, Copy)]
enum Fixture {
    Fresh,
    Connected,
    Recording,
    Training,
}

fn ok(s: &mut Session, id: &str, p: Value) {
    s.call(id, p).unwrap_or_else(|e| panic!("fixture step {id}: {e}"));
}

fn build(f: Fixture) -> Session {
    let mut s = Session::new();
    if matches!(f, Fixture::Fresh) {
        return s;
    }
    ok(&mut s, "device.connect", json!({ "id": "sim:muse_s" }));
    ok(&mut s, "clock.advance", json!({ "seconds": 3.0 }));
    match f {
        Fixture::Recording => ok(&mut s, "recording.start", json!({})),
        Fixture::Training => {
            ok(&mut s, "feedback.start", json!({ "minutes": 5 }));
            ok(&mut s, "calibration.start", json!({ "anyway": true }));
            ok(&mut s, "clock.advance", json!({ "seconds": 12.0 }));
            ok(&mut s, "calibration.skip", json!({}));
        }
        _ => {}
    }
    s
}

/// The catalog example's params (without the `cmd` tag), if any.
fn example_params(id: &str) -> Map<String, Value> {
    let ex = examples().into_iter().find(|e| e.id() == id);
    let v = match ex {
        Some(Request::Command(c)) => serde_json::to_value(c).unwrap_or(Value::Null),
        Some(Request::Query(q)) => serde_json::to_value(q).unwrap_or(Value::Null),
        None => Value::Null,
    };
    let mut m = match v {
        Value::Object(m) => m,
        _ => Map::new(),
    };
    m.remove("cmd");
    m
}

/// Enum values a property's schema lists (`enum` or `oneOf` of `const`s).
fn enum_values(prop: &Value) -> Vec<Value> {
    let mut out: Vec<Value> = prop.get("enum").and_then(Value::as_array).cloned().unwrap_or_default();
    for key in ["oneOf", "anyOf"] {
        for alt in prop.get(key).and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default() {
            if let Some(c) = alt.get("const") {
                out.push(c.clone());
            }
            out.extend(enum_values(alt));
        }
    }
    out
}

/// Every param object to try for `id` (built once per test binary).
fn cases(id: &str) -> &'static [Value] {
    static ALL: OnceLock<Vec<(&'static str, Vec<Value>)>> = OnceLock::new();
    let all = ALL.get_or_init(|| SPECS.iter().map(|s| (s.id, build_cases(s.id))).collect());
    all.iter().find(|(i, _)| *i == id).map_or(&[], |(_, c)| c.as_slice())
}

fn build_cases(id: &str) -> Vec<Value> {
    let schema = input_schema(id).unwrap_or_else(|| panic!("{id} has no schema"));
    let props: Map<String, Value> = schema.get("properties").and_then(Value::as_object).cloned().unwrap_or_default();
    let base = example_params(id);
    let mut out = vec![Value::Null, json!({}), json!([]), json!("x"), json!({ "zz_unknown": 1 }), Value::Object(base.clone())];
    for (key, prop) in &props {
        let with = |v: Value| {
            let mut m = base.clone();
            m.insert(key.clone(), v);
            Value::Object(m)
        };
        out.extend(hostile().into_iter().map(with));
        out.extend(enum_values(prop).into_iter().map(with));
        let mut without = base.clone();
        without.remove(key);
        out.push(Value::Object(without));
    }
    for v in hostile() {
        out.push(Value::Object(props.keys().map(|k| (k.clone(), v.clone())).collect()));
    }
    out
}

/// One hunt finding.
struct Finding {
    fixture: Fixture,
    id: String,
    params: String,
    what: String,
}

fn short(v: &Value) -> String {
    let s = v.to_string();
    if s.len() > 160 {
        format!("{}…", &s[..s.char_indices().nth(160).map_or(s.len(), |(i, _)| i)])
    } else {
        s
    }
}

/// What makes a fixture that fixture: device, recording, feedback phase.
fn shape(s: &Session) -> String {
    let st = s.state();
    format!("{:?}|{}|{:?}", st.device.as_ref().map(|d| &d.id), st.recording.as_ref().is_some_and(|r| r.active), st.feedback.phase)
}

/// Bring `s` back to fixture `f` with cheap commands (resume, reuse the
/// stored baseline, restart the recording); rebuild only if that fails.
fn restore(f: Fixture, s: &mut Session, want: &str) {
    let mut try_call = |id: &str, p: Value| drop(s.call(id, p));
    if !matches!(f, Fixture::Fresh) {
        try_call("sim.fault", json!({ "bad_pads": [], "dropout": false }));
        try_call("feedback.resume", json!({}));
    }
    if matches!(f, Fixture::Training) {
        try_call("feedback.start", json!({ "minutes": 5 }));
        try_call("calibration.reuse", json!({}));
    }
    if matches!(f, Fixture::Recording | Fixture::Training) {
        try_call("recording.start", json!({}));
    }
    if shape(s) != want {
        *s = build(f);
    }
}

/// Run every case of `id` on `s` (a session in fixture `f`); returns findings.
fn hunt(f: Fixture, s: &mut Session, id: &str) -> Vec<Finding> {
    let mut found = Vec::new();
    let want = shape(s);
    for params in cases(id) {
        let before = format!("{:?}", s.state());
        let r = catch_unwind(AssertUnwindSafe(|| s.call(id, params.clone())));
        let finding = |what: String| Finding { fixture: f, id: id.to_owned(), params: short(params), what };
        match r {
            Err(p) => {
                let msg = p.downcast_ref::<String>().cloned().or_else(|| p.downcast_ref::<&str>().map(|m| (*m).to_owned()));
                found.push(finding(format!("PANIC: {}", msg.unwrap_or_default())));
                *s = build(f); // never keep a session that unwound mid-call
            }
            Ok(Err(e)) => {
                if before != format!("{:?}", s.state()) {
                    found.push(finding(format!("failed ({e}) but changed state")));
                }
            }
            // A success that left the fixture (disconnect, stop, ...) is put back.
            Ok(Ok(_)) if shape(s) != want => restore(f, s, &want),
            Ok(Ok(_)) => {}
        }
    }
    found
}

fn run_fixture(f: Fixture) {
    static QUIET: OnceLock<()> = OnceLock::new();
    QUIET.get_or_init(|| std::panic::set_hook(Box::new(|_| {}))); // findings are reported below
    let mut found = Vec::new();
    let mut calls = 0usize;
    let mut s = build(f);
    for spec in SPECS {
        calls += cases(spec.id).len();
        found.extend(hunt(f, &mut s, spec.id));
    }
    let report: Vec<String> = found.iter().map(|x| format!("[{:?}] {} {} -> {}", x.fixture, x.id, x.params, x.what)).collect();
    assert!(report.is_empty(), "{} finding(s) in {calls} calls:\n{}", report.len(), report.join("\n"));
    assert!(calls > SPECS.len() * 20, "the hunt actually ran ({calls} calls)");
}

#[test]
fn panic_hunt_fresh_session() {
    run_fixture(Fixture::Fresh);
}

#[test]
fn panic_hunt_connected() {
    run_fixture(Fixture::Connected);
}

#[test]
fn panic_hunt_recording() {
    run_fixture(Fixture::Recording);
}

#[test]
fn panic_hunt_training() {
    run_fixture(Fixture::Training);
}

#[test]
fn hunt_covers_every_catalog_entry() {
    for spec in SPECS {
        assert!(cases(spec.id).len() >= 6, "{} has cases", spec.id);
    }
}
