//! egui rendering. Views read the `Session` (state + typed signal
//! accessors) and push `Command`s; they never mutate state directly.

pub(crate) mod device_dialog;
pub mod layout;
pub(crate) mod monitor;
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

/// Translated navigation label of a view.
pub fn view_label(view: nf_core::View) -> String {
    use nf_core::View as V;
    match view {
        V::Feedback => t!("view-feedback"),
        V::History => t!("view-history"),
        V::Bands => t!("view-bands"),
        V::RawEeg => t!("view-raw-eeg"),
        V::Histogram => t!("view-histogram"),
        V::Spectrogram => t!("view-spectrogram"),
        V::Psd => t!("view-psd"),
        V::HeartRate => t!("view-heart-rate"),
        V::Movement => t!("view-movement"),
        V::Streaming => t!("view-streaming"),
        V::Settings => t!("view-settings"),
    }
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
    crate::i18n::set(state.settings.language);
    let size = root.available_size();
    let width = size.x;
    let lay = layout::for_view(layout::pick(state.settings.layout, size, layout::phone(size)), state.view);
    layout::store(ctx, lay);
    if lay.is_compact() {
        layout::touch_style(root);
    }
    if lay == layout::Layout::Immersive {
        // Phone landscape on a monitor: the graph only (safe area via the root ui).
        egui::CentralPanel::default()
            .frame(egui::Frame::central_panel(root.style()).inner_margin(0.0))
            .show(root, |ui| views::show(ui, session, &mut out, shell));
    } else {
        topbar::show(root, session, error, lay, &mut out);
        if !lay.is_compact() && state.sidebar_open {
            sidebar::show(root, state, width < layout::NARROW_SIDEBAR_WIDTH, &mut out);
        }
        egui::CentralPanel::default().show(root, |ui| {
            recovery(ui, session, &mut out);
            views::show(ui, session, &mut out, shell);
        });
        if lay.is_compact() {
            sidebar::drawer(ctx, state, &mut out);
        }
    }
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
                egui::RichText::new(t!(
                    "mod-closed-during-recording",
                    device = p.device_name.as_str(),
                    duration = format!("{}:{:02}", s / 60, s % 60)
                ))
                .color(egui::Color32::WHITE),
            );
            if ui.button(t!("mod-recover")).clicked() {
                out.push(Command::RecoveryRestore);
            }
            if ui.button(t!("mod-discard")).clicked() {
                out.push(Command::RecoveryDiscard);
            }
        });
    });
    ui.add_space(6.0);
}
