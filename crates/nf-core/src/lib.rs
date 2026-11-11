//! # nf-core (L2)
//!
//! The NeuroFeed application core: a [`Session`] that owns all state, takes
//! every user/agent action as a serde [`Command`] (or read-only [`Query`]),
//! and advances time only through [`Session::tick`]. The egui app and the MCP
//! server are thin shells over it. No UI toolkit, no async runtime, no
//! threads or filesystem: compiles to wasm32.
#![forbid(unsafe_code)]

/// App version shown in the UI, sessions and MCP: `NEUROFEED_VERSION` at build time
/// (set by `scripts/version.sh` / the release workflows from the git tag), else Cargo.toml.
pub const APP_VERSION: &str = match option_env!("NEUROFEED_VERSION") {
    Some(v) => v,
    None => env!("CARGO_PKG_VERSION"),
};

pub mod ai;
pub mod analysis;
pub mod artifacts;
pub mod audio;
pub mod autoconnect;
mod command;
pub mod faults;
pub mod feedback;
pub mod import;
pub mod monitor;
pub mod nerd;
pub mod optical;
pub mod optics;
pub mod protocols;
pub mod rawtrace;
mod recording;
pub mod recovery;
pub mod replay;
pub mod report;
mod session;
pub mod settings;
pub mod side;
pub mod signal;
pub mod spectrum;
mod state;
pub mod streaming;
pub mod trust;

pub use command::{examples, find, input_schema, Command, CommandSpec, EnabledFn, Query, Request, SPECS};
pub use monitor::{MonitorId, Viewport, ViewportMode};
/// DSP primitives for views that render core buffers (pure functions).
pub use nf_audio;
pub use nf_dsp as dsp;
pub use nf_feedback;
pub use nf_feedback::StabilityConfig;
pub use nf_format::feedback_flags;
pub use nf_import;
pub use nf_store::SessionMeta;
pub use nf_types::{
    AiModel, AiModelState, Band, BandSnapshot, DeviceInfo, DeviceKind, DeviceProvider, DeviceSource, EegPacket, LinkState, PpgPacket,
};
pub use recording::{civil_utc, ExportFormat, RecordingInfo};
pub use session::{Event, Session, MAX_NOTES, SHUTDOWN_TIMEOUT_S};
pub use signal::{mains_name, MainsMode, Signal};
pub use state::{AppState, BandHistory, BandScale, View};

#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum CoreError {
    #[error("unknown command `{0}`")]
    UnknownCommand(String),
    #[error("invalid arguments: {0}")]
    InvalidArgs(String),
    #[error("device: {0}")]
    Device(String),
    #[error("`{id}` is disabled: {reason}")]
    Disabled { id: String, reason: String },
    #[error("{0}")]
    BadRequest(String),
}

pub type Reply = serde_json::Value;
