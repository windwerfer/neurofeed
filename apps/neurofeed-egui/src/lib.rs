//! NeuroFeed egui shell (desktop + web). Thin: all state lives in
//! `nf_core::Session`; the UI reads `AppState` and emits `Command`s.

pub mod app;
pub mod audio;
#[cfg(not(target_arch = "wasm32"))]
pub mod bridge;
pub mod platform;
pub mod store;
pub mod ui;

pub use app::NeuroFeedApp;
