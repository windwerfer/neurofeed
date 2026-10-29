//! Top bar: sidebar toggle, device picker/status, mains/quality, record, pause.

use super::theme;
use nf_core::{mains_name, Command, MainsMode, Session};

/// Devices offered in the picker (real providers will add theirs later).
const DEVICES: [(&str, &str); 3] =
    [("sim:muse_s", "Muse S (simulated)"), ("sim:athena", "Muse S Athena (simulated)"), ("sim:crown", "Crown (simulated)")];

pub fn show(ctx: &egui::Context, session: &Session, error: Option<&str>, out: &mut Vec<Command>) {
    let state = session.state();
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
                let rec = state.recording.as_ref().filter(|r| r.active);
                if let Some(r) = rec {
                    if ui.button(format!("⏹ Stop ({:.0} s)", r.duration)).clicked() {
                        out.push(Command::RecordingStop);
                    }
                } else if ui.add_enabled(state.device.is_some(), egui::Button::new("⏺ Record")).clicked() {
                    out.push(Command::RecordingStart { wall_clock_unix_ms: None });
                }
                if let Some((_, sig)) = session.live_signal() {
                    let notch = match sig.applied() {
                        nf_core::dsp::Mains::Unknown => "50+60".to_owned(),
                        m => mains_name(m).to_owned(),
                    };
                    let lock = if sig.locked() { " 🔒" } else { "" };
                    egui::ComboBox::from_id_salt("mains").selected_text(format!("notch {notch}{lock}")).show_ui(ui, |ui| {
                        for (mode, label) in
                            [(MainsMode::Auto, "auto"), (MainsMode::Hz50, "50 Hz"), (MainsMode::Hz60, "60 Hz"), (MainsMode::Off, "off")]
                        {
                            if ui.selectable_label(state.mains_mode == mode, label).clicked() {
                                out.push(Command::MainsSet { mode });
                            }
                        }
                    });
                    let good = (0..sig.quality.len()).filter(|&i| sig.usable(i)).count();
                    ui.weak(format!("pads {good}/{}", sig.quality.len()));
                }
            });
        });
    });
}
