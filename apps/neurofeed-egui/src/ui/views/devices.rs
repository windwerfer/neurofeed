//! Devices: scan (Muse BLE, Crown OSC on desktop), list, connect, link state.

use nf_core::{Command, LinkState, Session};

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    ui.scope(|ui| {
        ui.horizontal(|ui| {
            let scan = session.enabled("device.scan");
            let r = ui.add_enabled(scan.is_ok(), egui::Button::new("Scan"));
            let r = match &scan {
                Err(why) => r.on_disabled_hover_text(why),
                Ok(()) => r.on_hover_text("8 s Bluetooth (Muse) + LAN OSC (Crown, UDP 9000) discovery"),
            };
            if r.clicked() {
                out.push(Command::DeviceScan { seconds: None });
            }
            let scanning = session.scanning();
            if !scanning.is_empty() {
                ui.spinner();
                ui.weak(format!("scanning {}", scanning.join(", ")));
                ui.ctx().request_repaint_after(std::time::Duration::from_millis(250));
            }
        });
        for e in session.provider_errors() {
            ui.colored_label(ui.visuals().error_fg_color, e);
        }
        egui::Grid::new("devices").num_columns(3).striped(true).show(ui, |ui| {
            for d in session.device_list() {
                let current = state.device.as_ref().is_some_and(|c| c.id == d.id);
                ui.label(&d.name);
                ui.weak(format!("{} · {} ch{}", d.id, d.channels.len(), if d.has_ppg() { " · PPG" } else { "" }));
                if current {
                    let s = match &state.link {
                        Some(LinkState::Connecting) => "connecting…".to_owned(),
                        Some(LinkState::Lost { reason }) => format!("lost: {reason}"),
                        _ => "connected".to_owned(),
                    };
                    ui.horizontal(|ui| {
                        ui.strong(s);
                        if ui.small_button("Disconnect").clicked() {
                            out.push(Command::DeviceDisconnect);
                        }
                    });
                } else if ui.button("Connect").clicked() {
                    out.push(Command::DeviceConnect { id: d.id.clone() });
                }
                ui.end_row();
            }
        });
    });
}
