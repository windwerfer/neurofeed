//! Compact layout: bottom navigation bar (primary views + "More").

use super::layout::{PRIMARY, TOUCH};
use nf_core::{AppState, Command, View};

pub fn show(root: &mut egui::Ui, state: &AppState, out: &mut Vec<Command>) {
    egui::Panel::bottom("bottombar").exact_size(TOUCH + 8.0).show(root, |ui| {
        let n = PRIMARY.len() + 1;
        let w = (ui.available_width() - ui.spacing().item_spacing.x * (n as f32 - 1.0)) / n as f32;
        ui.horizontal_centered(|ui| {
            for view in PRIMARY {
                let b = egui::Button::selectable(state.view == view, view.label());
                if ui.add_sized([w, TOUCH], b).clicked() {
                    out.push(Command::ViewSet { view });
                }
            }
            let other = !PRIMARY.contains(&state.view);
            let text = if other { format!("☰ {}", state.view.label()) } else { "☰ More".to_owned() };
            let r = ui.add_sized([w, TOUCH], egui::Button::selectable(other, text));
            egui::Popup::menu(&r).show(|ui| {
                for view in View::ALL.into_iter().filter(|v| !PRIMARY.contains(v)) {
                    if ui.add_sized([180.0, TOUCH], egui::Button::selectable(state.view == view, view.label())).clicked() {
                        out.push(Command::ViewSet { view });
                    }
                }
            });
        });
    });
}
