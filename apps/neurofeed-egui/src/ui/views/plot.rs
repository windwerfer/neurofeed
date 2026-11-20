//! Small drawing helpers for the sparkline-style plots (History, Trust).

use egui::{Align2, Color32, FontId, Painter, Pos2, Rect, Stroke};

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
