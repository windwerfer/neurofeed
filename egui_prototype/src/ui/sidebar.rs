//! Left navigation rail.

use super::theme;
use crate::state::{Action, AppState, View};

pub fn show(ctx: &egui::Context, state: &AppState, actions: &mut Vec<Action>) {
    egui::SidePanel::left("sidebar")
        .exact_width(theme::SIDEBAR_WIDTH)
        .resizable(false)
        .show(ctx, |ui| {
            ui.add_space(6.0);
            for view in View::ALL {
                // Settings sits at the bottom in the Flutter app; keep a gap.
                if view == View::Settings {
                    ui.separator();
                }
                let selected = state.view == view;
                let button = egui::SelectableLabel::new(selected, view.label());
                if ui.add_sized([ui.available_width(), 28.0], button).clicked() {
                    actions.push(Action::SelectView(view));
                }
            }
        });
}
