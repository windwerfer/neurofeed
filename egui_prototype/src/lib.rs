//! NeuroFeed egui prototype.
//!
//! Layering (lower layers never import higher ones):
//! - `data`  – EEG domain types and data sources (no egui).
//! - `state` – application state and actions (no egui).
//! - `ui`    – egui rendering; reads state, emits actions.
//! - `app`   – eframe glue that wires the three together.

pub mod app;
pub mod data;
pub mod state;
pub mod ui;

pub use app::NeuroFeedApp;
