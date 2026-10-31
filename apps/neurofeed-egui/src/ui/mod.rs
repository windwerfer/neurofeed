//! egui rendering. Views read the `Session` (state + typed signal
//! accessors) and push `Command`s; they never mutate state directly.

pub(crate) mod device_dialog;
mod onboarding;
mod quality;
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
    /// Never show the first-run tour (demo / screenshot runs).
    pub no_tour: bool,
    /// Set by the UI: move the history database into this folder.
    pub move_store: Option<String>,
    /// Result of the last move (shown in Settings → Storage).
    pub store_note: Option<String>,
}

/// Draw one frame and return the commands the user triggered.
pub fn show(root: &mut egui::Ui, session: &Session, error: Option<&str>) -> Vec<Command> {
    show_with(root, session, error, &mut Shell::default())
}

/// [`show`] with shell settings (bridge toggle).
pub fn show_with(root: &mut egui::Ui, session: &Session, error: Option<&str>, shell: &mut Shell) -> Vec<Command> {
    let ctx = &root.ctx().clone();
    let state = session.state();
    let mut out = Vec::new();
    ctx.data_mut(|d| d.insert_temp(egui::Id::unique(views::MARKS_ID), state.settings.gesture_markers));
    topbar::show(root, session, error, &mut out);
    if state.sidebar_open {
        sidebar::show(root, state, &mut out);
    }
    egui::CentralPanel::default().show(root, |ui| {
        recovery(ui, session, &mut out);
        views::show(ui, session, &mut out, shell);
    });
    device_dialog::show(ctx, session, &mut out);
    if !state.settings.onboarded && !shell.no_tour {
        onboarding::show(ctx, &mut out);
    }
    out
}

/// Banner for a recording interrupted by a crash.
fn recovery(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let Some(p) = &session.state().recovery else { return };
    egui::Frame::group(ui.style()).fill(egui::Color32::from_rgb(0x5D, 0x40, 0x37)).show(ui, |ui| {
        ui.horizontal_wrapped(|ui| {
            let s = p.duration_s.max(0.0) as u64;
            ui.label(
                egui::RichText::new(format!(
                    "⚠ NeuroFeed closed during a recording ({}, {}:{:02} saved). Recover it to History?",
                    p.device_name,
                    s / 60,
                    s % 60
                ))
                .color(egui::Color32::WHITE),
            );
            if ui.button("Recover").clicked() {
                out.push(Command::RecoveryRestore);
            }
            if ui.button("Discard").clicked() {
                out.push(Command::RecoveryDiscard);
            }
        });
    });
    ui.add_space(6.0);
}
