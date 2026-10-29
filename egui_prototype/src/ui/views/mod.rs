//! One module per functional view; everything else is a placeholder.

mod bands;
mod placeholder;

use crate::state::{Action, AppState, View};

pub fn show(ui: &mut egui::Ui, state: &AppState, actions: &mut Vec<Action>) {
    match state.view {
        View::Bands => bands::show(ui, state, actions),
        other => placeholder::show(ui, other),
    }
}
