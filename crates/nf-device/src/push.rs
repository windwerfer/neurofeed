//! Provider fed from outside Rust: the Android BLE wrapper (JNI) announces
//! devices and, once the session opens one, pushes blocks into its [`Feed`].
//! Also the mock transport for tests.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use crate::{lock, DeviceInfo, DeviceProvider, DeviceSource, Feed, LiveSource};

#[derive(Default)]
struct Shared {
    devices: Vec<DeviceInfo>,
    /// Feeds of opened devices, by id, until the transport takes them.
    opened: HashMap<String, Feed>,
    /// Ids whose source was dropped (transport should disconnect).
    closed: Vec<String>,
    scan_requests: u32,
}

/// See module docs. Create with [`PushProvider::new`].
pub struct PushProvider {
    scheme: &'static str,
    shared: Arc<Mutex<Shared>>,
}

/// Transport side of a [`PushProvider`].
#[derive(Clone)]
pub struct PushHandle {
    shared: Arc<Mutex<Shared>>,
}

impl PushProvider {
    /// `scheme` is the id prefix, e.g. `android` for `android:AA:BB:...`.
    pub fn new(scheme: &'static str) -> (Self, PushHandle) {
        let shared = Arc::new(Mutex::new(Shared::default()));
        (Self { scheme, shared: shared.clone() }, PushHandle { shared })
    }
}

impl PushHandle {
    /// Add or update a discovered device (its id must use the scheme).
    pub fn announce(&self, info: DeviceInfo) {
        let mut s = lock(&self.shared);
        s.devices.retain(|d| d.id != info.id);
        s.devices.push(info);
    }
    pub fn forget(&self, id: &str) {
        lock(&self.shared).devices.retain(|d| d.id != id);
    }
    /// The feed of a device the session just opened (taken once).
    pub fn take_opened(&self, id: &str) -> Option<Feed> {
        lock(&self.shared).opened.remove(id)
    }
    /// Ids whose sources were dropped since the last call.
    pub fn take_closed(&self) -> Vec<String> {
        std::mem::take(&mut lock(&self.shared).closed)
    }
    /// Scan requests since the last call (the wrapper runs the BLE scan).
    pub fn take_scan_requests(&self) -> u32 {
        std::mem::take(&mut lock(&self.shared).scan_requests)
    }
}

impl DeviceProvider for PushProvider {
    fn scheme(&self) -> &'static str {
        self.scheme
    }
    fn list(&self) -> Vec<DeviceInfo> {
        lock(&self.shared).devices.clone()
    }
    fn open(&mut self, id: &str) -> Result<Box<dyn DeviceSource>, String> {
        let info =
            lock(&self.shared).devices.iter().find(|d| d.id == id).cloned().ok_or_else(|| format!("`{id}` not found; scan first"))?;
        let (src, feed) = LiveSource::new(info);
        let sh = self.shared.clone();
        let key = id.to_owned();
        lock(&self.shared).opened.insert(id.to_owned(), feed);
        Ok(Box::new(src.on_drop(move || lock(&sh).closed.push(key))))
    }
    fn can_scan(&self) -> bool {
        true
    }
    fn scan(&mut self, _seconds: f64) -> Result<(), String> {
        lock(&self.shared).scan_requests += 1;
        Ok(())
    }
}
