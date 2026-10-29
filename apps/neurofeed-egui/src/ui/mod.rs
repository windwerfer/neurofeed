//! egui rendering. Views read the `Session` (state + typed signal
//! accessors) and push `Command`s; they never mutate state directly.

mod sidebar;
pub mod theme;
mod topbar;
mod views;

use nf_core::{Command, Session};

/// Draw one frame and return the commands the user triggered.
pub fn show(ctx: &egui::Context, session: &Session, error: Option<&str>) -> Vec<Command> {
    let state = session.state();
    let mut out = Vec::new();
    topbar::show(ctx, session, error, &mut out);
    if state.sidebar_open {
        sidebar::show(ctx, state, &mut out);
    }
    egui::CentralPanel::default().show(ctx, |ui| views::show(ui, session, &mut out));
    out
}
