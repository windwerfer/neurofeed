use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use muse_rs::prelude::*;
use tokio::sync::mpsc;

use crate::api::muse::MuseEventDto;
use crate::api::neurosity_osc::CrownOscHandle;
use crate::api::simulator::DeviceSimulator;
use crate::frb_generated::StreamSink;

/// Handle type for Muse, Crown (OSC), and simulated connections
pub enum ConnectionHandle {
    Muse(MuseHandle),
    Crown(CrownOscHandle),
    Simulator(Arc<DeviceSimulator>),
}

impl ConnectionHandle {
    pub async fn disconnect(&self) {
        match self {
            ConnectionHandle::Muse(h) => {
                let _ = h.disconnect().await;
            }
            ConnectionHandle::Crown(h) => h.disconnect(),
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
    pub aux_channels: u32,
}

#[derive(Default)]
pub struct ManagerState {
    /// Muse devices discovered by BLE scans, keyed by BLE id.
    pub devices: HashMap<String, MuseDevice>,
    /// The currently active connection, if any.
    pub active: Option<ActiveConnection>,
    /// The Dart-side event sink, set when `subscribe_events` is called.
    pub sink: Option<StreamSink<MuseEventDto>>,
    /// The receiver end of the active connection's event channel, if any.
    pub events: Option<mpsc::Receiver<MuseEventDto>>,
    /// EEG electrodes at or above this index are dropped by the forwarder
    /// for the active connection (Muse without AUX: `Some(4)`).
    pub eeg_electrode_limit: Option<i32>,
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
