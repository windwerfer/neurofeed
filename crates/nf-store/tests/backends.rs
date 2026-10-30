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
    assert!(s.delete(a).unwrap());
    assert!(!s.delete(a).unwrap());
    assert!(s.get(a).unwrap().is_none());
    assert_eq!(s.list().unwrap().len(), 1);
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
    let id = nf_store::SqliteStore::open(&path).unwrap().insert(session("p", &[9])).unwrap();
    let again = nf_store::SqliteStore::open(&path).unwrap();
    assert_eq!(again.get(id).unwrap().unwrap().body, [9]);
    std::fs::remove_dir_all(dir).ok();
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
