//! Top bar: sidebar toggle, device picker/status, mains/quality, record, pause.

use super::theme;
use nf_core::{mains_name, Command, MainsMode, Session};

pub fn show(ctx: &egui::Context, session: &Session, error: Option<&str>, out: &mut Vec<Command>) {
    let state = session.state();
    egui::TopBottomPanel::top("topbar").exact_height(theme::TOPBAR_HEIGHT).show(ctx, |ui| {
        ui.horizontal_centered(|ui| {
            if ui.button("☰").on_hover_text("Toggle sidebar").clicked() {
                out.push(Command::SidebarSet { open: !state.sidebar_open });
            }
            ui.strong("NeuroFeed");
            ui.separator();
            let dot = match (&state.device, &state.link) {
                (None, _) => egui::Color32::GRAY,
                (Some(_), Some(nf_core::LinkState::Connecting)) => egui::Color32::from_rgb(0xE6, 0xAA, 0x3C),
                (Some(_), Some(nf_core::LinkState::Lost { .. })) => egui::Color32::from_rgb(0xE5, 0x39, 0x35),
                _ if state.paused => egui::Color32::GRAY,
                _ => egui::Color32::from_rgb(0x66, 0xBB, 0x6A),
            };
            let (r, _) = ui.allocate_exact_size(egui::vec2(10.0, 10.0), egui::Sense::hover());
            ui.painter().circle_filled(r.center(), 4.5, dot);
            let current = state.device.as_ref().map_or("No device", |d| d.name.as_str());
            egui::ComboBox::from_id_salt("device").selected_text(current).show_ui(ui, |ui| {
                for d in session.device_list() {
                    let selected = state.device.as_ref().is_some_and(|c| c.id == d.id);
                    if ui.selectable_label(selected, &d.name).on_hover_text(&d.id).clicked() && !selected {
                        out.push(Command::DeviceConnect { id: d.id });
                    }
                }
                if session.enabled("device.scan").is_ok() {
                    let label = if session.scanning().is_empty() { "Scan for devices…" } else { "Scanning…" };
                    if ui.selectable_label(false, label).clicked() {
                        out.push(Command::DeviceScan { seconds: None });
                    }
                }
                if ui.selectable_label(state.device.is_none(), "Disconnect").clicked() {
                    out.push(Command::DeviceDisconnect);
                }
            });
            if let Some(d) = &state.device {
                ui.weak(format!("{} ch", d.channels.len()));
            }
            match &state.link {
                Some(nf_core::LinkState::Connecting) => {
                    ui.weak("connecting…");
                }
                Some(nf_core::LinkState::Lost { reason }) => {
                    ui.colored_label(ui.visuals().error_fg_color, reason);
                }
                _ => {}
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
