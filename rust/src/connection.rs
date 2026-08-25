use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use muse_rs::prelude::*;
use tokio::sync::mpsc;

use crate::api::muse::MuseEventDto;
use crate::api::simulator::DeviceSimulator;
use crate::frb_generated::StreamSink;

/// Handle type for Muse, Crown, and simulated connections
pub enum ConnectionHandle {
    Muse(MuseHandle),
    Crown, // Placeholder - Phase D will implement proper Crown handle
    Simulator(Arc<DeviceSimulator>),
}

impl ConnectionHandle {
    pub async fn disconnect(&self) {
        match self {
            ConnectionHandle::Muse(h) => {
                let _ = h.disconnect().await;
            }
            ConnectionHandle::Crown => {
                // Phase D: implement proper Crown disconnect
                log::warn!("[crown] disconnect called but not yet implemented");
            }
            ConnectionHandle::Simulator(s) => {
                s.stop().await;
            }
        }
    }
}

/// A live connection kept on the Rust side (Dart never sees the
/// non-serializable handles).
pub struct ActiveConnection {
    pub handle: ConnectionHandle,
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
    pub events: Option<mpsc::Receiver<MuseEventDto>>,
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
