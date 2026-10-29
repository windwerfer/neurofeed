//! egui rendering. Views read `&AppState` and push `Action`s; they never
//! mutate state directly.

mod sidebar;
pub mod theme;
mod topbar;
mod views;

use crate::state::{Action, AppState};

/// Draw one frame and return the actions the user triggered.
pub fn show(ctx: &egui::Context, state: &AppState) -> Vec<Action> {
    let mut actions = Vec::new();
    topbar::show(ctx, state, &mut actions);
    if state.sidebar_open {
        sidebar::show(ctx, state, &mut actions);
    }
    egui::CentralPanel::default().show(ctx, |ui| {
        views::show(ui, state, &mut actions);
    });
    actions
}
