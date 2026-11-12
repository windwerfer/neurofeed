#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! Settings persistence and session notes through the generic command path.

use nf_core::{Request, Session};
use nf_store::{MemoryStore, Store};
use serde_json::{json, Value};

fn run(s: &mut Session, id: &str, p: Value) -> Result<Value, String> {
    s.run(Request::parse(id, p).map_err(|e| e.to_string())?).map_err(|e| e.to_string())
}

#[test]
fn settings_survive_a_restart_and_a_rolled_back_batch() {
    let mut s = Session::new().with_store(Box::new(MemoryStore::default()));
    run(&mut s, "settings.set", json!({ "subject": "p07", "appearance": "light" })).unwrap();
    run(&mut s, "audio.set", json!({ "master_volume": 0.3 })).unwrap();
    let bad = s.batch(&[("settings.set".into(), json!({ "subject": "x" })), ("settings.set".into(), json!({ "subject": "a/b" }))]);
    assert!(bad.is_err());
    assert_eq!(run(&mut s, "settings.get", Value::Null).unwrap()["user"]["subject"], "p07");
    let doc = s.store().get_doc("settings").unwrap().unwrap();
    let mut store = MemoryStore::default();
    store.put_doc("settings", Some(&doc)).unwrap();
    let s2 = Session::new().with_store(Box::new(store));
    assert_eq!(s2.state().settings.subject, "p07");
    assert!((s2.state().audio.master - 0.3).abs() < 1e-9);
}

/// Appearance defaults to `system`; an explicit `settings.set` (dark, light or
/// system) survives a restart, while an old doc with the former `dark` default
/// and no choice flag comes back as `system`.
#[test]
fn appearance_defaults_to_system_and_a_choice_persists() {
    let mut s = Session::new().with_store(Box::new(MemoryStore::default()));
    let user = |s: &mut Session| run(s, "settings.get", Value::Null).unwrap()["user"].clone();
    assert_eq!(user(&mut s)["appearance"], "system");
    assert_eq!(user(&mut s)["appearance_chosen"], false);
    run(&mut s, "settings.set", json!({ "appearance": "dark" })).unwrap();
    assert_eq!((user(&mut s)["appearance"].clone(), user(&mut s)["appearance_chosen"].clone()), (json!("dark"), json!(true)));
    let doc = s.store().get_doc("settings").unwrap().unwrap();
    let mut store = MemoryStore::default();
    store.put_doc("settings", Some(&doc)).unwrap();
    let s2 = Session::new().with_store(Box::new(store));
    assert_eq!(s2.state().settings.appearance, nf_core::settings::Appearance::Dark);

    let mut old = MemoryStore::default();
    old.put_doc("settings", Some(r#"{"user":{"appearance":"dark","subject":"p07"}}"#)).unwrap();
    let s3 = Session::new().with_store(Box::new(old));
    assert_eq!((s3.state().settings.appearance, s3.state().settings.subject.as_str()), (nf_core::settings::Appearance::System, "p07"));
    assert!(run(&mut s, "settings.set", json!({ "appearance": "sepia" })).is_err());
}

#[test]
fn notes_are_validated_saved_and_rolled_back() {
    let mut s = Session::new();
    run(&mut s, "device.connect", json!({ "id": "sim:muse_s" })).unwrap();
    run(&mut s, "recording.start", Value::Null).unwrap();
    run(&mut s, "clock.advance", json!({ "seconds": 2.0 })).unwrap();
    run(&mut s, "recording.stop", Value::Null).unwrap();
    let id = s.state().history[0].id;
    assert!(s.state().history[0].context.is_some(), "context snapshot kept");
    run(&mut s, "history.notes", json!({ "id": id, "notes": "sleepy after lunch" })).unwrap();
    assert_eq!(s.state().history[0].notes, "sleepy after lunch");
    assert!(run(&mut s, "history.notes", json!({ "id": 999, "notes": "" })).is_err());
    assert!(run(&mut s, "history.notes", json!({ "id": id, "notes": "x".repeat(4001) })).is_err());
    let bad = s.batch(&[("history.notes".into(), json!({ "id": id, "notes": "changed" })), ("history.delete".into(), json!({ "id": id }))]);
    assert!(bad.is_err());
    assert_eq!(s.store().list().unwrap()[0].notes, "sleepy after lunch", "store restored");
}

#[test]
fn streaming_protocol_and_destination_survive_a_restart_but_start_off() {
    let mut s = Session::new().with_store(Box::new(MemoryStore::default()));
    run(&mut s, "streaming.set", json!({ "protocol": "lsl", "port": 9100, "separate_groups": true })).unwrap();
    let doc = s.store().get_doc("settings").unwrap().unwrap();
    let mut store = MemoryStore::default();
    store.put_doc("settings", Some(&doc)).unwrap();
    let s2 = Session::new().with_store(Box::new(store));
    let st = &s2.state().streaming.settings;
    assert_eq!((st.protocol, st.port, st.separate_groups, st.enabled), (nf_core::streaming::StreamProtocol::Lsl, 9100, true, false));
}
