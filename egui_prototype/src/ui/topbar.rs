//! Top bar: menu toggle, device status, pause.

use super::theme;
use crate::state::{Action, AppState};

pub fn show(ctx: &egui::Context, state: &AppState, actions: &mut Vec<Action>) {
    egui::TopBottomPanel::top("topbar")
        .exact_height(theme::TOPBAR_HEIGHT)
        .show(ctx, |ui| {
            ui.horizontal_centered(|ui| {
                if ui.button("☰").on_hover_text("Toggle sidebar").clicked() {
                    actions.push(Action::ToggleSidebar);
                }
                ui.strong("NeuroFeed");
                ui.separator();
                let dot = if state.paused {
                    egui::Color32::GRAY
                } else {
                    egui::Color32::from_rgb(0x66, 0xBB, 0x6A)
                };
                let (r, _) = ui.allocate_exact_size(egui::vec2(10.0, 10.0), egui::Sense::hover());
                ui.painter().circle_filled(r.center(), 4.5, dot);
                ui.label(&state.device.name);
                ui.weak(format!("{} ch", state.device.channels.len()));
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let label = if state.paused { "▶ Resume" } else { "⏸ Pause" };
                    if ui.button(label).clicked() {
                        actions.push(Action::TogglePause);
                    }
                    ui.weak(state.view.label());
                });
            });
        });
}
