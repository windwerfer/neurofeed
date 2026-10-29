//! HR+SpO2 view: current values, the infrared pulse wave and the trends.

use super::plot;
use egui::{Align2, Color32, FontId, Rect, Sense, Stroke};
use nf_core::optics::{Estimate, Optics};
use nf_core::Session;
use std::collections::VecDeque;

const WAVE_S: f64 = 6.0;
const HR_COLOR: Color32 = Color32::from_rgb(0xEF, 0x53, 0x50);
const SPO2_COLOR: Color32 = Color32::from_rgb(0x4F, 0xC3, 0xF7);

pub fn show(ui: &mut egui::Ui, session: &Session) {
    ui.horizontal(|ui| {
        ui.heading("HR + SpO2");
        ui.weak("PPG infrared/red, estimates every 1 s over the last 8 s");
    });
    ui.separator();
    let Some(o) = session.optics() else {
        ui.label(if session.state().device.is_some() { "This device has no PPG sensor." } else { "No device connected." });
        return;
    };
    let hr = Optics::current(&o.hr, o.time);
    let sp = Optics::current(&o.spo2, o.time);
    ui.horizontal(|ui| {
        big(ui, "Heart rate", hr.map(|e| format!("{:.0} bpm", e.value)), hr, HR_COLOR);
        ui.add_space(40.0);
        big(ui, "SpO2", sp.map(|e| format!("{:.1} %", e.value)), sp, SPO2_COLOR);
    });
    ui.add_space(8.0);
    let avail = ui.available_size();
    let h = (avail.y - 20.0) / 2.0;
    // Pulse wave (infrared, auto-scaled).
    let (rect, _) = ui.allocate_exact_size(egui::vec2(avail.x, h), Sense::hover());
    let p = ui.painter_at(rect);
    p.rect_filled(rect, 6.0, ui.visuals().extreme_bg_color);
    p.text(
        rect.left_top() + egui::vec2(8.0, 6.0),
        Align2::LEFT_TOP,
        "Pulse wave (infrared)",
        FontId::proportional(14.0),
        ui.visuals().strong_text_color(),
    );
    let r = Rect::from_min_max(rect.left_top() + egui::vec2(10.0, 26.0), rect.right_bottom() - egui::vec2(10.0, 10.0));
    if let Some(ir) = o.ir_index() {
        let s = o.last(ir, (WAVE_S * o.rate) as usize);
        let (lo, hi) = s.iter().fold((f32::MAX, f32::MIN), |(a, b), &x| (a.min(x), b.max(x)));
        if hi > lo {
            let n = (WAVE_S * o.rate) as f32;
            let off = n - s.len() as f32;
            let pts = s.iter().enumerate().map(|(i, &y)| plot::to_screen(r, (0.0, n), (lo, hi), off + i as f32, y)).collect();
            plot::trace(&p, pts, HR_COLOR);
        }
    }
    ui.add_space(10.0);
    let (rect, _) = ui.allocate_exact_size(egui::vec2(avail.x, h), Sense::hover());
    let p = ui.painter_at(rect);
    p.rect_filled(rect, 6.0, ui.visuals().extreme_bg_color);
    p.text(
        rect.left_top() + egui::vec2(8.0, 6.0),
        Align2::LEFT_TOP,
        "Trend (last 2 min)",
        FontId::proportional(14.0),
        ui.visuals().strong_text_color(),
    );
    let r = Rect::from_min_max(rect.left_top() + egui::vec2(44.0, 26.0), rect.right_bottom() - egui::vec2(44.0, 18.0));
    p.rect_stroke(r, 0.0, Stroke::new(1.0_f32, ui.visuals().faint_bg_color));
    let now = o.time.unwrap_or(0.0) as f32;
    trend(&p, r, &o.hr, now, (40.0, 140.0), HR_COLOR);
    trend(&p, r, &o.spo2, now, (85.0, 100.0), SPO2_COLOR);
    plot::label(&p, r.left_top(), Align2::RIGHT_TOP, "140 ");
    plot::label(&p, r.left_bottom(), Align2::RIGHT_BOTTOM, "40 ");
    plot::label(&p, r.right_top(), Align2::LEFT_TOP, " 100%");
    plot::label(&p, r.right_bottom(), Align2::LEFT_BOTTOM, " 85%");
    plot::label(&p, r.left_bottom(), Align2::LEFT_TOP, "-120 s");
    plot::label(&p, r.right_bottom(), Align2::RIGHT_TOP, "now");
}

fn big(ui: &mut egui::Ui, title: &str, text: Option<String>, e: Option<Estimate>, color: Color32) {
    ui.vertical(|ui| {
        ui.weak(title);
        ui.label(egui::RichText::new(text.unwrap_or_else(|| "--".into())).size(40.0).color(color).strong());
        ui.weak(e.map_or("waiting for pulse…".to_owned(), |e| format!("confidence {:.0} %", e.confidence * 100.0)));
    });
}

fn trend(p: &egui::Painter, r: Rect, h: &VecDeque<Estimate>, now: f32, range: (f32, f32), color: Color32) {
    let pts = h.iter().map(|e| plot::to_screen(r, (now - 120.0, now), range, e.time as f32, e.value as f32)).collect();
    plot::trace(p, pts, color);
}
