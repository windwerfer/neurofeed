//! NeuroFeed egui shell (desktop + web). Thin: all state lives in
//! `nf_core::Session`; the UI reads `AppState` and emits `Command`s.

pub mod app;
pub mod audio;
pub mod store;
pub mod ui;

pub use app::NeuroFeedApp;
