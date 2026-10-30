//! Device list / connect (filled in with nf-device providers).

use egui::RichText;
use nf_core::{Command, Session};

pub fn show(ui: &mut egui::Ui, session: &Session, _out: &mut Vec<Command>) {
    ui.group(|ui| {
        ui.label(RichText::new("Devices").strong().size(17.0));
        ui.weak(session.state().device.as_ref().map_or("not connected".to_owned(), |d| format!("connected: {}", d.name)));
    });
}
