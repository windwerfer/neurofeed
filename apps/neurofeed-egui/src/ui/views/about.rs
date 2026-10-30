//! About: version, what NeuroFeed is (and is not), and third-party notices.

use egui::RichText;

const NOTICES: &str = include_str!("../../../../../THIRD_PARTY_NOTICES.md");

pub(super) fn card(ui: &mut egui::Ui) {
    ui.label(format!("NeuroFeed {} · Rust / egui build", env!("CARGO_PKG_VERSION")));
    ui.weak("Open-source EEG neurofeedback for Muse and similar headbands. Not a medical device: it does not diagnose or treat anything.");
    ui.horizontal(|ui| {
        ui.hyperlink_to("Source code", "https://github.com/windwerfer/neurofeed");
        ui.weak("· Apache-2.0 license");
    });
    egui::CollapsingHeader::new("Third-party notices").show(ui, |ui| {
        egui::ScrollArea::vertical().max_height(320.0).show(ui, |ui| {
            ui.add(egui::Label::new(RichText::new(NOTICES).monospace().size(11.0)).wrap());
        });
    });
}
