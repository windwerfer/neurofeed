//! Top bar: sidebar toggle, device picker/status, pause.

use super::theme;
use nf_core::{AppState, Command};

/// Devices offered in the picker (real providers will add theirs later).
const DEVICES: [(&str, &str); 2] = [("sim:muse", "Muse S (simulated)"), ("sim:crown", "Crown (simulated)")];

pub fn show(ctx: &egui::Context, state: &AppState, error: Option<&str>, out: &mut Vec<Command>) {
    egui::TopBottomPanel::top("topbar").exact_height(theme::TOPBAR_HEIGHT).show(ctx, |ui| {
        ui.horizontal_centered(|ui| {
            if ui.button("☰").on_hover_text("Toggle sidebar").clicked() {
                out.push(Command::SidebarSet { open: !state.sidebar_open });
            }
            ui.strong("NeuroFeed");
            ui.separator();
            let live = state.device.is_some() && !state.paused;
            let dot = if live { egui::Color32::from_rgb(0x66, 0xBB, 0x6A) } else { egui::Color32::GRAY };
            let (r, _) = ui.allocate_exact_size(egui::vec2(10.0, 10.0), egui::Sense::hover());
            ui.painter().circle_filled(r.center(), 4.5, dot);
            let current = state.device.as_ref().map_or("No device", |d| d.name.as_str());
            egui::ComboBox::from_id_salt("device").selected_text(current).show_ui(ui, |ui| {
                for (id, name) in DEVICES {
                    let selected = state.device.as_ref().is_some_and(|d| d.id == id);
                    if ui.selectable_label(selected, name).clicked() && !selected {
                        out.push(Command::DeviceConnect { id: id.into() });
                    }
                }
                if ui.selectable_label(state.device.is_none(), "Disconnect").clicked() {
                    out.push(Command::DeviceDisconnect);
                }
            });
            if let Some(d) = &state.device {
                ui.weak(format!("{} ch", d.channels.len()));
            }
            if let Some(e) = error {
                ui.colored_label(ui.visuals().error_fg_color, e);
            }
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                let label = if state.paused { "▶ Resume" } else { "⏸ Pause" };
                if ui.button(label).clicked() {
                    out.push(if state.paused { Command::StreamResume } else { Command::StreamPause });
                }
                ui.weak(format!("t = {:.0} s", state.time));
            });
        });
    });
}
