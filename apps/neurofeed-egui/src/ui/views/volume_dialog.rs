//! The speaker button and its Volume dialog on the session setup screen.
//! One slider per group (0–100 %); each release is one `volume.set`, so the
//! change applies at once and is remembered by the core. Whether the dialog
//! is open is view chrome.

use nf_core::audio::VolumePatch;
use nf_core::nf_audio::AudioSettings;
use nf_core::{Command, Session};

/// (label key, current value, patch builder) per group.
type Row = (&'static str, f64, fn(f64) -> VolumePatch);

fn rows(a: &AudioSettings) -> [Row; 6] {
    [
        ("volume-master", a.master, |v| VolumePatch { master: Some(v), ..Default::default() }),
        ("volume-background", a.background_volume, |v| VolumePatch { background: Some(v), ..Default::default() }),
        ("volume-feedback", a.feedback, |v| VolumePatch { feedback: Some(v), ..Default::default() }),
        ("volume-guardrail", a.guard_volume, |v| VolumePatch { guardrail: Some(v), ..Default::default() }),
        ("volume-intro", a.intro_volume, |v| VolumePatch { intro: Some(v), ..Default::default() }),
        ("volume-end-bell", a.end_bell_volume, |v| VolumePatch { end_bell: Some(v), ..Default::default() }),
    ]
}

pub(super) fn open_id() -> egui::Id {
    egui::Id::unique("volume_dialog_open")
}

/// The speaker icon; returns nothing, toggles the dialog.
pub(super) fn button(ui: &mut egui::Ui) {
    if ui.button("🔊").on_hover_text(t!("volume-title")).clicked() {
        ui.data_mut(|d| d.insert_temp(open_id(), true));
    }
}

/// The dialog window (call once per frame from the setup screen).
pub(super) fn window(ctx: &egui::Context, session: &Session, out: &mut Vec<Command>) {
    if !ctx.data(|d| d.get_temp::<bool>(open_id())).unwrap_or(false) {
        return;
    }
    let mut open = true;
    let mut done = false;
    egui::Window::new(t!("volume-title")).open(&mut open).collapsible(false).resizable(false).show(ctx, |ui| {
        ui.weak(t!("volume-help"));
        ui.add_space(6.0);
        for (key, cur, make) in rows(&session.state().audio) {
            slider(ui, key, cur, make, out);
        }
        ui.add_space(6.0);
        ui.horizontal(|ui| {
            if ui.button(t!("volume-reset")).clicked() {
                out.push(Command::VolumeSet(VolumePatch { reset: true, ..Default::default() }));
            }
            if ui.button(t!("volume-done")).clicked() {
                done = true;
            }
        });
    });
    if !open || done {
        ctx.data_mut(|d| d.remove::<bool>(open_id()));
    }
}

/// Percent slider: previews while dragging, commits on release.
fn slider(ui: &mut egui::Ui, key: &str, cur: f64, make: fn(f64) -> VolumePatch, out: &mut Vec<Command>) {
    let id = egui::Id::unique(("volume_slider", key));
    let mut pct = ui.data(|d| d.get_temp::<f64>(id)).unwrap_or(cur * 100.0);
    let r = ui.add(egui::Slider::new(&mut pct, 0.0..=100.0).integer().suffix(" %").text(crate::i18n::tr(key, &[])));
    if r.dragged() || r.has_focus() {
        ui.data_mut(|d| d.insert_temp(id, pct));
    } else {
        ui.data_mut(|d| d.remove::<f64>(id));
    }
    if r.drag_stopped() || (r.changed() && !r.dragged()) {
        out.push(Command::VolumeSet(make((pct / 100.0).clamp(0.0, 1.0))));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn there_is_exactly_one_slider_per_group_in_the_documented_order() {
        let a = AudioSettings::default();
        let keys: Vec<_> = rows(&a).iter().map(|r| r.0).collect();
        assert_eq!(keys, ["volume-master", "volume-background", "volume-feedback", "volume-guardrail", "volume-intro", "volume-end-bell"]);
        let mut hit = Vec::new();
        for (_, _, make) in rows(&a) {
            let p = make(0.25);
            hit.push([p.master, p.background, p.feedback, p.guardrail, p.intro, p.end_bell].iter().filter(|v| v.is_some()).count());
        }
        assert_eq!(hit, [1; 6], "each slider sets exactly its own group");
    }
}
