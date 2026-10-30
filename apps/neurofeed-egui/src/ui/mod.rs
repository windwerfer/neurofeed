//! egui rendering. Views read the `Session` (state + typed signal
//! accessors) and push `Command`s; they never mutate state directly.

mod sidebar;
pub mod theme;
mod topbar;
mod views;

use nf_core::{Command, Session};

/// Shell-owned settings the UI shows but the core doesn't know about.
#[derive(Debug, Default, Clone)]
pub struct Shell {
    /// Agent bridge: `None` unsupported (web), `Some(None)` off,
    /// `Some(Some(addr))` listening.
    pub bridge: Option<Option<String>>,
    /// Set by the UI: turn the bridge on/off.
    pub set_bridge: Option<bool>,
}

/// Draw one frame and return the commands the user triggered.
pub fn show(ctx: &egui::Context, session: &Session, error: Option<&str>) -> Vec<Command> {
    show_with(ctx, session, error, &mut Shell::default())
}

/// [`show`] with shell settings (bridge toggle).
pub fn show_with(ctx: &egui::Context, session: &Session, error: Option<&str>, shell: &mut Shell) -> Vec<Command> {
    let state = session.state();
    let mut out = Vec::new();
    topbar::show(ctx, session, error, &mut out);
    if state.sidebar_open {
        sidebar::show(ctx, state, &mut out);
    }
    egui::CentralPanel::default().show(ctx, |ui| views::show(ui, session, &mut out, shell));
    out
}
