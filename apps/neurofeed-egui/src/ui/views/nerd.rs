//! Nerd sheet: a side window with the reward (and guard) calibration piles
//! as histograms and the numbers behind each decision. Hover a row for what
//! it means.

use egui::{Align2, Color32, FontId, RichText, Sense, Stroke, Vec2};
use nf_core::nerd::{Histogram, Nerd, Section};

const BAR: Color32 = Color32::from_rgb(0x4D, 0xB6, 0xAC);
const THR: Color32 = Color32::from_rgb(0xFF, 0xB7, 0x4D);
const LIVE: Color32 = Color32::from_rgb(0x66, 0xBB, 0x6A);

pub(super) fn window(ctx: &egui::Context, open: &mut bool, n: &Nerd) {
    egui::Window::new("Nerd sheet").open(open).default_width(380.0).resizable(false).anchor(Align2::RIGHT_BOTTOM, [-16.0, -16.0]).show(
        ctx,
        |ui| {
            if !n.ready {
                ui.weak(t!("nerd-collecting-the-numbers-appear-after"));
                return;
            }
            if let Some(s) = &n.reward {
                section(ui, s, "nerd_reward");
            }
            if let Some(s) = &n.guard {
                ui.add_space(10.0);
                section(ui, s, "nerd_guard");
            }
            ui.add_space(6.0);
            ui.horizontal(|ui| {
                legend(ui, THR, "threshold");
                legend(ui, LIVE, "live");
            });
        },
    );
}

fn legend(ui: &mut egui::Ui, c: Color32, name: &str) {
    ui.label(RichText::new("■").color(c));
    ui.weak(name);
}

fn section(ui: &mut egui::Ui, s: &Section, id: &str) {
    ui.label(RichText::new(&s.pile.title).strong());
    histogram(ui, &s.pile.hist, s.pile.threshold, s.pile.live);
    egui::Grid::new(id).num_columns(2).striped(true).spacing([18.0, 3.0]).show(ui, |ui| {
        for r in &s.rows {
            ui.label(&r.label).on_hover_text(r.info);
            ui.label(RichText::new(&r.value).monospace()).on_hover_text(r.info);
            ui.end_row();
        }
    });
}

fn histogram(ui: &mut egui::Ui, h: &Histogram, thr: Option<f64>, live: Option<f64>) {
    let (rect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width().max(300.0), 90.0), Sense::hover());
    let p = ui.painter_at(rect);
    p.rect_filled(rect, 4.0, ui.visuals().extreme_bg_color);
    let plot = rect.shrink2(Vec2::new(6.0, 14.0));
    let max = h.counts.iter().copied().max().unwrap_or(0).max(1) as f32;
    let w = plot.width() / h.counts.len().max(1) as f32;
    for (i, c) in h.counts.iter().enumerate() {
        let x0 = plot.left() + i as f32 * w;
        let top = plot.bottom() - *c as f32 / max * plot.height();
        p.rect_filled(
            egui::Rect::from_min_max(egui::pos2(x0 + 1.0, top), egui::pos2(x0 + w - 1.0, plot.bottom())),
            1.0,
            BAR.gamma_multiply(0.8),
        );
    }
    let x = |v: f64| plot.left() + ((v - h.min) / (h.max - h.min)) as f32 * plot.width();
    for (v, c) in [(thr, THR), (live, LIVE)] {
        if let Some(v) = v.filter(|v| v.is_finite()) {
            let xx = x(v);
            p.line_segment([egui::pos2(xx, plot.top() - 6.0), egui::pos2(xx, plot.bottom())], Stroke::new(2.0_f32, c));
        }
    }
    let f = FontId::monospace(10.0);
    let weak = ui.visuals().weak_text_color();
    p.text(rect.left_bottom() + Vec2::new(4.0, -2.0), Align2::LEFT_BOTTOM, format!("{:.3}", h.min), f.clone(), weak);
    p.text(rect.right_bottom() + Vec2::new(-4.0, -2.0), Align2::RIGHT_BOTTOM, format!("{:.3}", h.max), f, weak);
}
