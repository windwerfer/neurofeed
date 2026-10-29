//! egui rendering. Views read `&AppState` and push `Command`s; they never
//! mutate state directly.

mod sidebar;
pub mod theme;
mod topbar;
mod views;

use nf_core::{AppState, Command};

/// Draw one frame and return the commands the user triggered.
pub fn show(ctx: &egui::Context, state: &AppState, error: Option<&str>) -> Vec<Command> {
    let mut out = Vec::new();
    topbar::show(ctx, state, error, &mut out);
    if state.sidebar_open {
        sidebar::show(ctx, state, &mut out);
    }
    egui::CentralPanel::default().show(ctx, |ui| views::show(ui, state, &mut out));
    out
}
