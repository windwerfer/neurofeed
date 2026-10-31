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
        ui.label("No device connected. Use Connect device in the top bar.");
    }
    live
}

/// Lay out one card per channel and call `draw(painter, plot_rect, channel)`.
pub fn cards(ui: &mut egui::Ui, names: &[String], draw: impl FnMut(&Painter, Rect, usize)) {
    let _ = cards_resp(ui, names, draw);
}

/// [`cards`] that also returns the union of the card responses (drag sense).
pub fn cards_resp(ui: &mut egui::Ui, names: &[String], mut draw: impl FnMut(&Painter, Rect, usize)) -> Option<egui::Response> {
    let mut all: Option<egui::Response> = None;
    let n = names.len().max(1);
    let avail = ui.available_size();
    let cols = if avail.x > 900.0 && n > 2 { 2 } else { 1 };
    let rows = n.div_ceil(cols);
    let gap = 10.0;
    let cell =
        Vec2::new((avail.x - gap * (cols as f32 - 1.0)) / cols as f32, ((avail.y - gap * (rows as f32 - 1.0)) / rows as f32).max(90.0));
    egui::Grid::new(ui.next_auto_id()).spacing([gap, gap]).show(ui, |ui| {
        for (ch, name) in names.iter().enumerate() {
            let (rect, resp) = ui.allocate_exact_size(cell, Sense::drag());
            all = Some(match all.take() {
                Some(a) => a.union(resp),
                None => resp,
            });
            let p = ui.painter_at(rect);
            let v = ui.visuals();
            p.rect_filled(rect, 6.0, v.extreme_bg_color);
            p.text(rect.left_top() + Vec2::new(8.0, 6.0), Align2::LEFT_TOP, name, FontId::proportional(14.0), v.strong_text_color());
            let plot = Rect::from_min_max(rect.left_top() + Vec2::new(44.0, 26.0), rect.right_bottom() - Vec2::new(10.0, 20.0));
            p.rect_stroke(plot, 0.0, Stroke::new(1.0_f32, v.faint_bg_color), egui::StrokeKind::Inside);
            draw(&p, plot, ch);
            if (ch + 1) % cols == 0 {
                ui.end_row();
            }
        }
    });
    all
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

/// Follow/Inspect viewport (legacy `viewport_controller.dart`): a window
/// length chip row, Follow (stick to now) or Inspect (frozen at an anchor;
/// drag a plot to pan). Kept in egui temp memory per view.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Viewport {
    pub window_s: f64,
    /// `None` = follow; `Some(t)` = window ends at session time `t`.
    pub anchor: Option<f64>,
}

impl Viewport {
    /// Seconds between the window end and now (0 when following).
    pub fn back_s(&self, now: f64, max_back: f64) -> f64 {
        self.anchor.map_or(0.0, |a| (now - a).clamp(0.0, max_back.max(0.0)))
    }
    /// Pan by `dx_frac` of the window (drag right = older), entering Inspect.
    pub fn pan(&mut self, now: f64, dx_frac: f64, max_back: f64) {
        let back = (self.back_s(now, max_back) + dx_frac * self.window_s).clamp(0.0, max_back.max(0.0));
        self.anchor = Some(now - back);
    }
}

/// The chip row; returns the viewport to draw this frame.
pub fn viewport(ui: &mut egui::Ui, key: &str, options: &[f64], now: f64) -> Viewport {
    let id = egui::Id::unique(("nf_viewport", key));
    let mut vp = ui.data(|d| d.get_temp::<Viewport>(id)).unwrap_or(Viewport { window_s: options[options.len() / 2], anchor: None });
    ui.horizontal(|ui| {
        ui.weak("window");
        for &o in options {
            if ui.selectable_label((vp.window_s - o).abs() < 1e-9, format!("{o:.0} s")).clicked() {
                vp.window_s = o;
            }
        }
        ui.separator();
        if ui.selectable_label(vp.anchor.is_none(), "▶ Follow").clicked() {
            vp.anchor = None;
        }
        if ui.selectable_label(vp.anchor.is_some(), "⏸ Inspect").clicked() && vp.anchor.is_none() {
            vp.anchor = Some(now);
        }
        if vp.anchor.is_some() {
            ui.weak(format!("{:.1} s ago · drag to pan", (now - vp.anchor.unwrap_or(now)).max(0.0)));
        } else {
            ui.weak("drag a plot to inspect");
        }
    });
    ui.data_mut(|d| d.insert_temp(id, vp));
    vp
}

/// Apply a drag on `resp` (plot area) to the stored viewport.
pub fn drag(ui: &egui::Ui, key: &str, resp: &egui::Response, now: f64, max_back: f64) {
    let dx = resp.drag_delta().x;
    if dx == 0.0 || resp.rect.width() <= 0.0 {
        return;
    }
    let id = egui::Id::unique(("nf_viewport", key));
    if let Some(mut vp) = ui.data(|d| d.get_temp::<Viewport>(id)) {
        vp.pan(now, f64::from(dx / resp.rect.width()), max_back);
        ui.data_mut(|d| d.insert_temp(id, vp));
    }
}
