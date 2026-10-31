//! Settings → Devices: scanning and connecting live in the Device dialog
//! (top bar); this card only opens it.

use nf_core::{Command, Session};

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    ui.horizontal(|ui| {
        match &state.device {
            Some(d) => ui.label(format!("Connected: {}", crate::ui::device_dialog::label(d))),
            None => ui.weak("No device connected."),
        };
        if ui.button("Device…").on_hover_text("Scan, connect, switch or disconnect").clicked() {
            out.push(Command::DeviceDialog { open: true });
        }
    });
}
