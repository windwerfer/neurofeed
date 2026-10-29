//! One module per functional view; everything else is a placeholder.

mod bands;
mod placeholder;

use nf_core::{AppState, Command, View};

pub fn show(ui: &mut egui::Ui, state: &AppState, out: &mut Vec<Command>) {
    match state.view {
        View::Bands => bands::show(ui, state, out),
        other => placeholder::show(ui, other),
    }
}
