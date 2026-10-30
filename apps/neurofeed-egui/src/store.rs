//! History backend for the shell: SQLite on desktop (`NF_DB` or the user
//! data dir), memory on the web (not persisted yet).

use nf_store::Store;

#[cfg(not(target_arch = "wasm32"))]
fn default_path() -> Option<std::path::PathBuf> {
    use std::path::PathBuf;
    if let Some(p) = std::env::var_os("NF_DB") {
        return Some(PathBuf::from(p));
    }
    let env = |k| std::env::var_os(k).map(PathBuf::from);
    let dir = if cfg!(windows) {
        env("APPDATA")?.join("NeuroFeed")
    } else if cfg!(target_os = "macos") {
        env("HOME")?.join("Library/Application Support/NeuroFeed")
    } else {
        env("XDG_DATA_HOME").or_else(|| env("HOME").map(|h| h.join(".local/share")))?.join("neurofeed")
    };
    Some(dir.join("history.sqlite"))
}

pub fn open() -> Box<dyn Store> {
    #[cfg(not(target_arch = "wasm32"))]
    if let Some(p) = default_path() {
        match nf_store::SqliteStore::open(&p) {
            Ok(s) => return Box::new(s),
            Err(e) => log::warn!("history at {}: {e}; using memory", p.display()),
        }
    }
    Box::new(nf_store::MemoryStore::default())
}
