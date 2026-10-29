use nf_core::View;

pub fn show(ui: &mut egui::Ui, view: View) {
    ui.centered_and_justified(|ui| {
        ui.heading(format!("{}: Not implemented yet", view.label()));
    });
}
