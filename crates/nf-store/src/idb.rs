//! IndexedDB backend (browser). Sync [`Store`] over an async API: an
//! in-memory cache answers every call. On open the persisted rows load
//! asynchronously; `take_changed` merges them (renumbering sessions saved in
//! the meantime) and from then on every write is mirrored to IndexedDB.
//! DB `neurofeed`, object store `sessions`, key = id, value =
//! `{ meta: <json>, device: <json>, body: Uint8Array }`.
//! Named documents (small JSON) live in `localStorage` under `neurofeed.doc.<key>`
//! so they are readable synchronously at startup.

use std::cell::RefCell;
use std::sync::{Arc, Mutex};

use js_sys::{Array, Object, Reflect, Uint8Array};
use wasm_bindgen::{closure::Closure, JsCast, JsValue};
use web_sys::{IdbDatabase, IdbOpenDbRequest, IdbRequest, IdbTransactionMode};

use crate::{MemoryStore, Result, SessionMeta, Store, StoreError, StoredSession};

const DB: &str = "neurofeed";
const OS: &str = "sessions";

thread_local! {
    // wasm is single-threaded; the JS handle is !Send so it lives here.
    static HANDLE: RefCell<Option<IdbDatabase>> = const { RefCell::new(None) };
}

#[derive(Default)]
struct Shared {
    open: bool,
    loaded: Vec<StoredSession>,
    changed: bool,
    error: Option<String>,
}

enum Op {
    Put(StoredSession),
    Delete(u64),
}

/// Browser-persistent store.
pub struct IdbStore {
    cache: MemoryStore,
    /// The persisted rows were merged in; before that, writes stay local.
    merged: bool,
    shared: Arc<Mutex<Shared>>,
}

fn lock(s: &Mutex<Shared>) -> std::sync::MutexGuard<'_, Shared> {
    s.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn err(v: JsValue) -> String {
    v.as_string().unwrap_or_else(|| format!("{v:?}"))
}

fn to_js(s: &StoredSession) -> std::result::Result<JsValue, String> {
    let o = Object::new();
    let meta = serde_json::to_string(&s.meta).map_err(|e| e.to_string())?;
    Reflect::set(&o, &"meta".into(), &meta.into()).map_err(err)?;
    Reflect::set(&o, &"device".into(), &s.device_json.clone().into()).map_err(err)?;
    Reflect::set(&o, &"body".into(), &Uint8Array::from(s.body.as_slice()).into()).map_err(err)?;
    Ok(o.into())
}

fn from_js(v: &JsValue) -> Option<StoredSession> {
    let meta: SessionMeta = serde_json::from_str(&Reflect::get(v, &"meta".into()).ok()?.as_string()?).ok()?;
    let device_json = Reflect::get(v, &"device".into()).ok()?.as_string()?;
    let body = Reflect::get(v, &"body".into()).ok()?.dyn_into::<Uint8Array>().ok()?.to_vec();
    Some(StoredSession { meta, device_json, body })
}

fn apply(db: &IdbDatabase, op: &Op) -> std::result::Result<(), String> {
    let tx = db.transaction_with_str_and_mode(OS, IdbTransactionMode::Readwrite).map_err(err)?;
    let os = tx.object_store(OS).map_err(err)?;
    match op {
        Op::Put(s) => os.put_with_key(&to_js(s)?, &JsValue::from_f64(s.meta.id as f64)).map(|_| ()),
        Op::Delete(id) => os.delete(&JsValue::from_f64(*id as f64)).map(|_| ()),
    }
    .map_err(err)
}

fn local_storage() -> Result<web_sys::Storage> {
    web_sys::window().and_then(|w| w.local_storage().ok().flatten()).ok_or_else(|| StoreError("localStorage unavailable".into()))
}

impl IdbStore {
    /// Opens (or creates) the database; rows appear after the async load.
    pub fn open() -> Result<Self> {
        let shared = Arc::new(Mutex::new(Shared::default()));
        let factory =
            web_sys::window().and_then(|w| w.indexed_db().ok().flatten()).ok_or_else(|| StoreError("IndexedDB unavailable".into()))?;
        let req: IdbOpenDbRequest = factory.open_with_u32(DB, 1).map_err(|e| StoreError(err(e)))?;
        let upgrade = Closure::<dyn FnMut(web_sys::Event)>::new(move |e: web_sys::Event| {
            let db = e
                .target()
                .and_then(|t| t.dyn_into::<IdbRequest>().ok())
                .and_then(|r| r.result().ok())
                .and_then(|r| r.dyn_into::<IdbDatabase>().ok());
            if let Some(db) = db {
                if !db.object_store_names().contains(OS) {
                    let _ = db.create_object_store(OS);
                }
            }
        });
        req.set_onupgradeneeded(Some(upgrade.as_ref().unchecked_ref()));
        upgrade.forget();
        let sh = shared.clone();
        let ok = Closure::<dyn FnMut(web_sys::Event)>::new(move |e: web_sys::Event| {
            let Some(db) = e
                .target()
                .and_then(|t| t.dyn_into::<IdbRequest>().ok())
                .and_then(|r| r.result().ok())
                .and_then(|r| r.dyn_into::<IdbDatabase>().ok())
            else {
                return;
            };
            let all = db.transaction_with_str(OS).and_then(|tx| tx.object_store(OS)).and_then(|os| os.get_all());
            match all {
                Ok(r) => {
                    let sh2 = sh.clone();
                    let r2 = r.clone();
                    let done = Closure::<dyn FnMut()>::new(move || {
                        let rows: Vec<StoredSession> =
                            r2.result().ok().map(|a| Array::from(&a).iter().filter_map(|v| from_js(&v)).collect()).unwrap_or_default();
                        let mut s = lock(&sh2);
                        s.loaded = rows;
                        s.changed = true;
                    });
                    r.set_onsuccess(Some(done.as_ref().unchecked_ref()));
                    done.forget();
                }
                Err(e) => lock(&sh).error = Some(err(e)),
            }
            lock(&sh).open = true;
            HANDLE.with(|h| *h.borrow_mut() = Some(db));
        });
        req.set_onsuccess(Some(ok.as_ref().unchecked_ref()));
        ok.forget();
        let sh = shared.clone();
        let fail = Closure::<dyn FnMut()>::new(move || lock(&sh).error = Some("IndexedDB open failed".into()));
        req.set_onerror(Some(fail.as_ref().unchecked_ref()));
        fail.forget();
        Ok(Self { cache: MemoryStore::default(), merged: false, shared })
    }

    fn write(&self, op: Op) {
        if !self.merged {
            return;
        }
        let mut s = lock(&self.shared);
        let r = HANDLE.with(|h| h.borrow().as_ref().map(|db| apply(db, &op)));
        if let Some(Err(e)) = r {
            s.error = Some(e);
        }
    }

    /// Last background error, if any.
    pub fn last_error(&self) -> Option<String> {
        lock(&self.shared).error.clone()
    }
}

impl Store for IdbStore {
    fn insert(&mut self, s: StoredSession) -> Result<u64> {
        let id = self.cache.insert(s)?;
        if let Some(row) = self.cache.get(id)? {
            self.write(Op::Put(row));
        }
        Ok(id)
    }
    fn list(&self) -> Result<Vec<SessionMeta>> {
        self.cache.list()
    }
    fn get(&self, id: u64) -> Result<Option<StoredSession>> {
        self.cache.get(id)
    }
    fn delete(&mut self, id: u64) -> Result<bool> {
        let had = self.cache.delete(id)?;
        if had {
            self.write(Op::Delete(id));
        }
        Ok(had)
    }
    fn set_notes(&mut self, id: u64, notes: &str) -> Result<bool> {
        let had = self.cache.set_notes(id, notes)?;
        if let Some(row) = self.cache.get(id)?.filter(|_| had) {
            self.write(Op::Put(row));
        }
        Ok(had)
    }
    fn location(&self) -> String {
        match self.last_error() {
            Some(e) => format!("indexeddb (error: {e})"),
            None => "indexeddb".into(),
        }
    }
    fn get_doc(&self, key: &str) -> Result<Option<String>> {
        let ls = local_storage()?;
        ls.get_item(&format!("neurofeed.doc.{key}")).map_err(|e| StoreError(err(e)))
    }
    fn put_doc(&mut self, key: &str, value: Option<&str>) -> Result<()> {
        let ls = local_storage()?;
        let k = format!("neurofeed.doc.{key}");
        match value {
            Some(v) => ls.set_item(&k, v),
            None => ls.remove_item(&k),
        }
        .map_err(|e| StoreError(err(e)))
    }
    fn take_changed(&mut self) -> bool {
        let mut s = lock(&self.shared);
        if !s.changed {
            return false;
        }
        s.changed = false;
        // Merge the loaded rows under anything inserted before the load.
        let fresh: Vec<StoredSession> = std::mem::take(&mut s.loaded);
        drop(s);
        self.merged = true;
        for id in self.cache.merge_loaded(fresh) {
            if let Ok(Some(row)) = self.cache.get(id) {
                self.write(Op::Put(row));
            }
        }
        true
    }
}
