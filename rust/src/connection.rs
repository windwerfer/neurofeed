use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use muse_rs::prelude::*;
use tokio::sync::mpsc;

use crate::api::muse::MuseEventDto;
use crate::frb_generated::StreamSink;

/// A live Muse connection kept on the Rust side (Dart never sees the
/// non-serializable `MuseHandle`/`Peripheral`).
pub struct ActiveConnection {
    pub handle: MuseHandle,
    pub name: String,
    pub id: String,
    pub firmware: String,
}

#[derive(Default)]
pub struct ManagerState {
    /// All devices discovered in the most recent scan, keyed by BLE id.
    pub devices: HashMap<String, MuseDevice>,
    /// The currently active connection, if any.
    pub active: Option<ActiveConnection>,
    /// The Dart-side event sink, set when `subscribe_events` is called.
    pub sink: Option<StreamSink<MuseEventDto>>,
    /// The receiver end of the active connection's event channel, if any.
    pub events: Option<mpsc::Receiver<MuseEvent>>,
    /// Whether the event-forwarding task is already running.
    pub forwarder_running: bool,
    /// Monotonically increasing counter, bumped on each new connection.
    /// The event forwarder uses this to avoid clearing state that belongs
    /// to a newer connection when its own receiver ends.
    pub connection_epoch: u64,
}

#[derive(Default)]
pub struct AppState {
    pub inner: Mutex<ManagerState>,
}

static STATE: OnceLock<AppState> = OnceLock::new();

pub fn state() -> &'static AppState {
    STATE.get_or_init(AppState::default)
}
