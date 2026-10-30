//! # nf-core (L2)
//!
//! The NeuroFeed application core: a [`Session`] that owns all state, takes
//! every user/agent action as a serde [`Command`] (or read-only [`Query`]),
//! and advances time only through [`Session::tick`]. The egui app and the MCP
//! server are thin shells over it. No UI toolkit, no async runtime, no
//! threads or filesystem: compiles to wasm32.
#![forbid(unsafe_code)]

pub mod artifacts;
pub mod audio;
mod command;
pub mod feedback;
pub mod import;
pub mod nerd;
pub mod optics;
pub mod protocols;
mod recording;
pub mod report;
mod session;
pub mod settings;
pub mod signal;
mod state;
pub mod streaming;
pub mod trust;

pub use command::{examples, find, input_schema, Command, CommandSpec, EnabledFn, Query, Request, SPECS};
/// DSP primitives for views that render core buffers (pure functions).
pub use nf_audio;
pub use nf_dsp as dsp;
pub use nf_feedback;
pub use nf_feedback::StabilityConfig;
pub use nf_format::feedback_flags;
pub use nf_import;
pub use nf_store::SessionMeta;
pub use nf_types::{Band, BandSnapshot, DeviceInfo, DeviceKind, DeviceProvider, DeviceSource, EegPacket, LinkState, PpgPacket};
pub use recording::{civil_utc, ExportFormat, RecordingInfo};
pub use session::{Event, Session, MAX_NOTES};
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
