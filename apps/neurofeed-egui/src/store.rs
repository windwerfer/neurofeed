//! History backend for the shell: SQLite on desktop (`NF_DB` or the user
//! data dir), IndexedDB on the web (memory if unavailable).

use nf_store::Store;

#[cfg(not(target_arch = "wasm32"))]
fn default_path() -> Option<std::path::PathBuf> {
    use std::path::PathBuf;
    if let Some(p) = std::env::var_os("NF_DB") {
        return Some(PathBuf::from(p));
    }
    let dir = data_dir()?;
    // Settings → Storage → Move leaves a pointer to the new file here.
    if let Some(p) = std::fs::read_to_string(dir.join(POINTER)).ok().map(|s| PathBuf::from(s.trim())).filter(|p| p.exists()) {
        return Some(p);
    }
    Some(dir.join(FILE))
}

#[cfg(not(target_arch = "wasm32"))]
const FILE: &str = "history.sqlite";
#[cfg(not(target_arch = "wasm32"))]
const POINTER: &str = "history.location";

#[cfg(not(target_arch = "wasm32"))]
fn data_dir() -> Option<std::path::PathBuf> {
    use std::path::PathBuf;
    let env = |k| std::env::var_os(k).map(PathBuf::from);
    let dir = if cfg!(windows) {
        env("APPDATA")?.join("NeuroFeed")
    } else if cfg!(target_os = "macos") {
        env("HOME")?.join("Library/Application Support/NeuroFeed")
    } else {
        env("XDG_DATA_HOME").or_else(|| env("HOME").map(|h| h.join(".local/share")))?.join("neurofeed")
    };
    Some(dir)
}

/// Settings → Storage → Move: copy the database into `dir`, verify it,
/// switch the session to it, remember it, then delete the old file.
#[cfg(not(target_arch = "wasm32"))]
pub fn move_to(session: &mut nf_core::Session, dir: &std::path::Path) -> Result<String, String> {
    if std::env::var_os("NF_DB").is_some() {
        return Err("NF_DB is set, so the location is fixed; unset it to move the folder".into());
    }
    let old = std::path::PathBuf::from(&session.state().history_location);
    if !old.is_file() {
        return Err("history is not in a file, nothing to move".into());
    }
    let new = dir.join(FILE);
    if new == old {
        return Err("that is the current folder".into());
    }
    session.copy_store_to(&new).map_err(|e| e.to_string())?;
    let store = nf_store::SqliteStore::open(&new).map_err(|e| e.to_string())?;
    let n = store.list().map_err(|e| e.to_string())?.len();
    if n != session.state().history.len() {
        let _ = std::fs::remove_file(&new);
        return Err(format!("copy check failed ({n} of {} sessions); nothing changed", session.state().history.len()));
    }
    let home = data_dir().ok_or("no data folder")?;
    std::fs::create_dir_all(&home)
        .and_then(|()| std::fs::write(home.join(POINTER), new.display().to_string()))
        .map_err(|e| e.to_string())?;
    session.replace_store(Box::new(store));
    for ext in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{ext}", old.display()));
    }
    Ok(crate::t!("store-moved-sessions", n = n, dir = new.display().to_string()))
}

pub fn open() -> Box<dyn Store> {
    #[cfg(not(target_arch = "wasm32"))]
    if let Some(p) = default_path() {
        match nf_store::SqliteStore::open(&p) {
            Ok(s) => return Box::new(s),
            Err(e) => log::warn!("history at {}: {e}; using memory", p.display()),
        }
    }
    #[cfg(target_arch = "wasm32")]
    match nf_store::IdbStore::open() {
        Ok(s) => return Box::new(s),
        Err(e) => log::warn!("history: {e}; using memory"),
    }
    Box::new(nf_store::MemoryStore::default())
}
