//! Left navigation rail.

use super::theme;
use nf_core::{AppState, Command, View};

pub fn show(ctx: &egui::Context, state: &AppState, out: &mut Vec<Command>) {
    egui::SidePanel::left("sidebar").exact_width(theme::SIDEBAR_WIDTH).resizable(false).show(ctx, |ui| {
        ui.add_space(6.0);
        for view in View::ALL {
            if view == View::Settings {
                ui.separator();
            }
            let button = egui::SelectableLabel::new(state.view == view, view.label());
            if ui.add_sized([ui.available_width(), 28.0], button).clicked() {
                out.push(Command::ViewSet { view });
            }
        }
    });
}
