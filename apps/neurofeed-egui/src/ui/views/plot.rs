//! Shared drawing helpers: a grid of per-channel cards and an axis frame.

use egui::{Align2, Color32, FontId, Painter, Pos2, Rect, Sense, Stroke, Vec2};
use nf_core::{DeviceInfo, Session, Signal};

/// Heading plus the live signal, or a hint when nothing is connected.
pub fn header<'a>(ui: &mut egui::Ui, session: &'a Session, title: &str, note: &str) -> Option<(&'a DeviceInfo, &'a Signal)> {
    ui.horizontal(|ui| {
        ui.heading(title);
        ui.weak(note);
    });
    ui.separator();
    let live = session.live_signal();
    if live.is_none() {
        ui.label("No device connected. Pick a simulator in the top bar.");
    }
    live
}

/// Lay out one card per channel and call `draw(painter, plot_rect, channel)`.
pub fn cards(ui: &mut egui::Ui, names: &[String], mut draw: impl FnMut(&Painter, Rect, usize)) {
    let n = names.len().max(1);
    let avail = ui.available_size();
    let cols = if avail.x > 900.0 && n > 2 { 2 } else { 1 };
    let rows = n.div_ceil(cols);
    let gap = 10.0;
    let cell =
        Vec2::new((avail.x - gap * (cols as f32 - 1.0)) / cols as f32, ((avail.y - gap * (rows as f32 - 1.0)) / rows as f32).max(90.0));
    egui::Grid::new(ui.next_auto_id()).spacing([gap, gap]).show(ui, |ui| {
        for (ch, name) in names.iter().enumerate() {
            let (rect, _) = ui.allocate_exact_size(cell, Sense::hover());
            let p = ui.painter_at(rect);
            let v = ui.visuals();
            p.rect_filled(rect, 6.0, v.extreme_bg_color);
            p.text(rect.left_top() + Vec2::new(8.0, 6.0), Align2::LEFT_TOP, name, FontId::proportional(14.0), v.strong_text_color());
            let plot = Rect::from_min_max(rect.left_top() + Vec2::new(44.0, 26.0), rect.right_bottom() - Vec2::new(10.0, 20.0));
            p.rect_stroke(plot, 0.0, Stroke::new(1.0_f32, v.faint_bg_color));
            draw(&p, plot, ch);
            if (ch + 1) % cols == 0 {
                ui.end_row();
            }
        }
    });
}

/// Map `x in [x0, x1]`, `y in [y0, y1]` into `r` (y up).
pub fn to_screen(r: Rect, (x0, x1): (f32, f32), (y0, y1): (f32, f32), x: f32, y: f32) -> Pos2 {
    let fx = ((x - x0) / (x1 - x0)).clamp(0.0, 1.0);
    let fy = ((y - y0) / (y1 - y0)).clamp(0.0, 1.0);
    Pos2::new(r.left() + fx * r.width(), r.bottom() - fy * r.height())
}

/// Small axis label.
pub fn label(p: &Painter, pos: Pos2, align: Align2, text: impl ToString) {
    p.text(pos, align, text.to_string(), FontId::monospace(10.0), Color32::GRAY);
}

/// Line trace in the accent colour.
pub fn trace(p: &Painter, pts: Vec<Pos2>, color: Color32) {
    if pts.len() > 1 {
        p.add(egui::Shape::line(pts, Stroke::new(1.3_f32, color)));
    }
}
