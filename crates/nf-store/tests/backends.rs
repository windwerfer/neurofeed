#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
//! Both backends satisfy the same contract.

use nf_store::{MemoryStore, SessionMeta, Store, StoredSession};

fn session(name: &str, body: &[u8]) -> StoredSession {
    StoredSession {
        meta: SessionMeta {
            id: 0,
            started_unix_ms: Some(1.7e12),
            duration_s: 61.5,
            device_id: "sim:muse_s".into(),
            device_name: name.into(),
            protocol: Some("restAwake".into()),
            summary: Some(serde_json::json!({ "success": 0.4 })),
            eeg_samples: 1000,
            ppg_samples: 200,
            feedback_seconds: 60,
            bytes: body.len() as u64,
            import: Some(serde_json::json!({ "source_format": "edf" })),
            notes: String::new(),
            context: Some(serde_json::json!({ "app_version": "t" })),
        },
        device_json: "{}".into(),
        body: body.to_vec(),
    }
}

fn contract(s: &mut dyn Store) {
    assert!(s.list().unwrap().is_empty());
    let a = s.insert(session("a", &[1, 2, 3])).unwrap();
    let b = s.insert(session("b", &[4; 10])).unwrap();
    assert!(b > a);
    let list = s.list().unwrap();
    assert_eq!(list.iter().map(|m| m.device_name.as_str()).collect::<Vec<_>>(), ["b", "a"]);
    assert_eq!(list[0].bytes, 10);
    let got = s.get(a).unwrap().unwrap();
    assert_eq!(
        (got.meta.id, got.body.as_slice(), got.meta.summary.clone()),
        (a, &[1u8, 2, 3][..], Some(serde_json::json!({ "success": 0.4 })))
    );
    assert_eq!(got.meta, {
        let mut m = session("a", &[1, 2, 3]).meta;
        m.id = a;
        m
    });
    assert!(s.set_notes(a, "calm").unwrap());
    assert!(!s.set_notes(999, "x").unwrap());
    assert_eq!(s.get(a).unwrap().unwrap().meta.notes, "calm");
    assert_eq!(s.get(a).unwrap().unwrap().meta.context, Some(serde_json::json!({ "app_version": "t" })));
    assert!(s.delete(a).unwrap());
    assert!(!s.delete(a).unwrap());
    assert!(s.get(a).unwrap().is_none());
    assert_eq!(s.list().unwrap().len(), 1);
    assert_eq!(s.get_doc("k").unwrap(), None);
    s.put_doc("k", Some("[1]")).unwrap();
    s.put_doc("k", Some("[2]")).unwrap();
    assert_eq!(s.get_doc("k").unwrap().as_deref(), Some("[2]"));
    s.put_doc("k", None).unwrap();
    assert_eq!(s.get_doc("k").unwrap(), None);
}

#[test]
fn memory_store_contract() {
    contract(&mut MemoryStore::default());
}

#[cfg(feature = "sqlite")]
#[test]
fn sqlite_store_contract_and_persistence() {
    contract(&mut nf_store::SqliteStore::in_memory().unwrap());
    let dir = std::env::temp_dir().join(format!("nf-store-{}", std::process::id()));
    let path = dir.join("h.sqlite");
    let mut first = nf_store::SqliteStore::open(&path).unwrap();
    let id = first.insert(session("p", &[9])).unwrap();
    first.put_doc("protocols", Some("[]")).unwrap();
    drop(first);
    let again = nf_store::SqliteStore::open(&path).unwrap();
    assert_eq!(again.get(id).unwrap().unwrap().body, [9]);
    assert_eq!(again.get_doc("protocols").unwrap().as_deref(), Some("[]"));
    std::fs::remove_dir_all(dir).ok();
}

#[cfg(feature = "sqlite")]
#[test]
fn sqlite_v1_database_is_migrated() {
    let dir = std::env::temp_dir().join(format!("nf-store-v1-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("old.sqlite");
    let old = "CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, started_unix_ms REAL, duration_s REAL NOT NULL, \
        device_id TEXT NOT NULL, device_name TEXT NOT NULL, protocol TEXT, summary_json TEXT, eeg_samples INTEGER NOT NULL, \
        ppg_samples INTEGER NOT NULL, feedback_seconds INTEGER NOT NULL, device_json TEXT NOT NULL, body BLOB NOT NULL); \
        INSERT INTO sessions VALUES (NULL, NULL, 1.0, 'd', 'Old', NULL, NULL, 0, 0, 0, '{}', x'01'); PRAGMA user_version = 1;";
    rusqlite_exec(&path, old);
    let mut s = nf_store::SqliteStore::open(&path).unwrap();
    assert_eq!(s.list().unwrap()[0].import, None);
    let id = s.insert(session("new", &[2])).unwrap();
    assert_eq!(s.get(id).unwrap().unwrap().meta.import, Some(serde_json::json!({ "source_format": "edf" })));
    std::fs::remove_dir_all(dir).ok();
}

#[cfg(feature = "sqlite")]
fn rusqlite_exec(path: &std::path::Path, sql: &str) {
    nf_store::sqlite_exec_for_tests(path, sql).unwrap();
}

#[test]
fn merge_loaded_keeps_ids_and_renumbers_local_rows() {
    use nf_store::{MemoryStore, SessionMeta, Store, StoredSession};
    let row = |id| StoredSession {
        meta: SessionMeta {
            id,
            started_unix_ms: None,
            duration_s: 1.0,
            device_id: "d".into(),
            device_name: "D".into(),
            protocol: None,
            summary: None,
            eeg_samples: 0,
            ppg_samples: 0,
            feedback_seconds: 0,
            bytes: 0,
            import: None,
            notes: String::new(),
            context: None,
        },
        device_json: "{}".into(),
        body: vec![id as u8],
    };
    let mut m = MemoryStore::default();
    assert_eq!(m.insert(row(0)).ok(), Some(1));
    let renumbered = m.merge_loaded(vec![row(4), row(7)]);
    assert_eq!(renumbered, vec![8]);
    let ids: Vec<u64> = m.list().unwrap_or_default().iter().map(|s| s.id).collect();
    assert_eq!(ids, vec![8, 7, 4]);
    assert_eq!(m.insert(row(0)).ok(), Some(9));
}
