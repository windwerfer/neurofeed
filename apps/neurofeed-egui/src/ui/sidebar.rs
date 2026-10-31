//! Left navigation rail.

use super::theme;
use nf_core::{AppState, Command, View};

pub fn show(root: &mut egui::Ui, state: &AppState, out: &mut Vec<Command>) {
    egui::Panel::left("sidebar").exact_size(theme::SIDEBAR_WIDTH).resizable(false).show(root, |ui| {
        ui.add_space(6.0);
        for view in View::ALL {
            if view == View::Settings {
                ui.separator();
            }
            let button = egui::Button::selectable(state.view == view, view.label());
            if ui.add_sized([ui.available_width(), 28.0], button).clicked() {
                out.push(Command::ViewSet { view });
            }
        }
    });
}
