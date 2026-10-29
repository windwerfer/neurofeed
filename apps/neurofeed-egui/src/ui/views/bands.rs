//! Bands view: per-channel bar chart of delta/theta/alpha/beta/gamma power.

use crate::ui::theme;
use egui::{Align2, FontId, Rect, Sense, Stroke, Vec2};
use nf_core::{AppState, Band, BandScale, BandSnapshot, Command};

/// Display range for absolute log10 band power (µV²).
const ABS_MIN: f32 = -1.0;
const ABS_MAX: f32 = 3.0;

pub fn show(ui: &mut egui::Ui, state: &AppState, out: &mut Vec<Command>) {
    ui.horizontal(|ui| {
        ui.heading("Band powers");
        if state.device.as_ref().is_some_and(|d| d.simulated) {
            ui.weak("(simulated data)");
        }
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            for (scale, label) in [(BandScale::Relative, "Relative %"), (BandScale::Absolute, "Absolute (log)")] {
                if ui.selectable_label(state.band_scale == scale, label).clicked() {
                    out.push(Command::ScaleSet { scale });
                }
            }
        });
    });
    legend(ui);
    ui.separator();

    let Some(device) = &state.device else {
        ui.label("No device connected. Pick a simulator in the top bar.");
        return;
    };
    let Some(snapshot) = state.bands.latest() else {
        ui.label("Waiting for data…");
        return;
    };

    let n = device.channels.len().max(1);
    let avail = ui.available_size();
    let cols = if avail.x > 700.0 { n.min(4) } else { n.min(2) };
    let rows = n.div_ceil(cols);
    let gap = 12.0;
    let cell =
        Vec2::new((avail.x - gap * (cols as f32 - 1.0)) / cols as f32, ((avail.y - gap * (rows as f32 - 1.0)) / rows as f32).max(120.0));

    egui::Grid::new("bands_grid").spacing([gap, gap]).show(ui, |ui| {
        for (ch, name) in device.channels.iter().enumerate() {
            channel_card(ui, cell, name, ch, snapshot, state.band_scale);
            if (ch + 1) % cols == 0 {
                ui.end_row();
            }
        }
    });
}

fn legend(ui: &mut egui::Ui) {
    ui.horizontal_wrapped(|ui| {
        for band in Band::ALL {
            let (lo, hi) = band.range_hz();
            ui.colored_label(theme::band_color(band), "■");
            ui.label(format!("{} {lo:.0}–{hi:.0} Hz", band.name()));
            ui.add_space(8.0);
        }
    });
}

fn channel_card(ui: &mut egui::Ui, size: Vec2, name: &str, ch: usize, snapshot: &BandSnapshot, scale: BandScale) {
    let (rect, _) = ui.allocate_exact_size(size, Sense::hover());
    let painter = ui.painter_at(rect);
    let visuals = ui.visuals();
    painter.rect_filled(rect, 6.0, visuals.extreme_bg_color);
    painter.text(rect.left_top() + Vec2::new(10.0, 8.0), Align2::LEFT_TOP, name, FontId::proportional(16.0), visuals.strong_text_color());

    let plot = Rect::from_min_max(rect.left_top() + Vec2::new(10.0, 34.0), rect.right_bottom() - Vec2::new(10.0, 26.0));
    let slot = plot.width() / Band::ALL.len() as f32;
    let baseline = plot.bottom();
    painter.line_segment([plot.left_bottom(), plot.right_bottom()], Stroke::new(1.0_f32, visuals.weak_text_color()));

    for (i, band) in Band::ALL.iter().enumerate() {
        let (fraction, text) = match scale {
            BandScale::Absolute => {
                let v = snapshot.power(ch, *band).unwrap_or(ABS_MIN);
                (((v - ABS_MIN) / (ABS_MAX - ABS_MIN)).clamp(0.0, 1.0), format!("{v:.2}"))
            }
            BandScale::Relative => {
                let r = snapshot.relative(ch, *band).unwrap_or(0.0);
                (r.clamp(0.0, 1.0), format!("{:.0}%", r * 100.0))
            }
        };
        let x0 = plot.left() + slot * i as f32 + slot * 0.15;
        let x1 = x0 + slot * 0.7;
        let top = baseline - (plot.height() - 16.0).max(0.0) * fraction;
        painter.rect_filled(Rect::from_min_max(egui::pos2(x0, top), egui::pos2(x1, baseline)), 3.0, theme::band_color(*band));
        let cx = (x0 + x1) / 2.0;
        painter.text(egui::pos2(cx, top - 2.0), Align2::CENTER_BOTTOM, text, FontId::monospace(11.0), visuals.text_color());
        painter.text(
            egui::pos2(cx, baseline + 4.0),
            Align2::CENTER_TOP,
            &band.name()[..1],
            FontId::proportional(12.0),
            visuals.weak_text_color(),
        );
    }
}
