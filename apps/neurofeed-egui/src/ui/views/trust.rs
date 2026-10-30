//! Trust pane: what each feedback second really was. Shared by the live
//! training screen, the session summary and History.
//!
//! Layout (top to bottom): totals; plot (percentile vs threshold percentile,
//! or feature value vs threshold) with calibration shaded and gesture marks;
//! one strip cell per second (in zone, below, held back, dirty, paused); the
//! legend with the dirty breakdown. Hover shows the second's details.

use super::plot::{label, to_screen, trace};
use egui::{Align2, Color32, Rect, RichText, Sense, Stroke, Vec2};
use nf_core::trust::{Row, Trust};

pub const IN_ZONE: Color32 = Color32::from_rgb(0x66, 0xBB, 0x6A);
pub const BELOW: Color32 = Color32::from_rgb(0x2E, 0x6E, 0x68);
pub const HELD: Color32 = Color32::from_rgb(0xFF, 0xB7, 0x4D);
pub const DIRTY: Color32 = Color32::from_rgb(0xE5, 0x73, 0x73);
pub const IDLE: Color32 = Color32::from_rgb(0x55, 0x55, 0x55);
const LINE: Color32 = Color32::from_rgb(0x4D, 0xB6, 0xAC);
const THR: Color32 = Color32::from_rgb(0xFF, 0xB7, 0x4D);
const MARK: Color32 = Color32::from_rgb(0x90, 0xA4, 0xF0);

/// What the plot shows.
#[derive(Clone, Copy, PartialEq, Eq, Default)]
pub enum Plot {
    #[default]
    Percentile,
    Value,
}

fn pct(v: Option<f64>) -> String {
    v.map_or("--".into(), |x| format!("{x:.0} %"))
}

fn mmss(s: u32) -> String {
    format!("{}:{:02}", s / 60, s % 60)
}

/// Strip colour of a second.
pub fn cell(r: &Row) -> Color32 {
    if r.calibrating || r.paused {
        IDLE
    } else if !r.clean {
        DIRTY
    } else if !r.held_back.is_empty() {
        HELD
    } else if r.in_target {
        IN_ZONE
    } else {
        BELOW
    }
}

/// The headline numbers.
pub fn totals(ui: &mut egui::Ui, t: &Trust, big: bool) {
    let x = &t.totals;
    let size = if big { 26.0 } else { 18.0 };
    let clean = (x.training_s > 0).then(|| f64::from(x.clean_s) * 100.0 / f64::from(x.training_s));
    ui.horizontal_wrapped(|ui| {
        let mut stat = |label: &str, value: String, hint: &str| {
            ui.vertical(|ui| {
                ui.weak(label);
                ui.label(RichText::new(value).size(size).strong()).on_hover_text(hint);
            });
            ui.add_space(if big { 26.0 } else { 14.0 });
        };
        stat("In zone", pct(x.pct_in_zone), "share of clean training seconds above the threshold");
        stat("Clean", pct(clean), "training seconds without artifacts and with a verdict");
        stat("Held back", pct(x.pct_held_back), "above target but not rewarded (band ceiling, guard, no baseline)");
        if x.pct_warning.is_some() {
            stat("Guard warning", pct(x.pct_warning), "clean guarded seconds with the drowsiness warning on");
        }
        stat("Trained", mmss(x.training_s), "calibration and pauses excluded");
        stat("Rewards", x.reward_chimes.to_string(), "reward chimes");
    });
}

/// Totals, plot, strip and legend. `plot` is the caller's mode toggle.
pub fn pane(ui: &mut egui::Ui, t: &Trust, plot: &mut Plot, height: f32, big_totals: bool) {
    totals(ui, t, big_totals);
    ui.horizontal(|ui| {
        ui.selectable_value(plot, Plot::Percentile, "Percentile");
        ui.selectable_value(plot, Plot::Value, "Value");
    });
    if t.rows.is_empty() {
        ui.weak("No feedback seconds yet.");
        return;
    }
    let w = ui.available_width();
    let (rect, resp) = ui.allocate_exact_size(Vec2::new(w, height), Sense::hover());
    let (strip, _) = ui.allocate_exact_size(Vec2::new(w, 12.0), Sense::hover());
    let painter = ui.painter_at(rect.union(strip));
    let inner = rect.shrink2(Vec2::new(8.0, 14.0));
    let x = span(t);
    let y = draw_plot(&painter, ui, t, *plot, inner, x);
    draw_strip(&painter, t, strip, inner, x);
    if let Some(pos) = resp.hover_pos() {
        hover(ui, &painter, t, (inner, x, y), pos, *plot);
    }
    legend(ui, t);
}

fn span(t: &Trust) -> (f32, f32) {
    let t0 = t.rows.first().map_or(0.0, |r| r.t) as f32;
    let t1 = t.rows.last().map_or(1.0, |r| r.t) as f32 + 1.0;
    (t0, t1.max(t0 + 1.0))
}

fn series(t: &Trust, plot: Plot) -> (Vec<Option<f64>>, Vec<Option<f64>>) {
    match plot {
        Plot::Percentile => (t.rows.iter().map(|r| r.plot_pct).collect(), t.rows.iter().map(|r| r.thr_pct).collect()),
        Plot::Value => (t.rows.iter().map(|r| r.value).collect(), t.rows.iter().map(|r| r.threshold).collect()),
    }
}

fn y_range(t: &Trust, plot: Plot) -> (f32, f32) {
    if plot == Plot::Percentile {
        return (0.0, 100.0);
    }
    let (a, b) = series(t, plot);
    let (lo, hi) = a.iter().chain(&b).flatten().fold((f64::MAX, f64::MIN), |(l, h), v| (l.min(*v), h.max(*v)));
    if lo > hi {
        return (0.0, 1.0);
    }
    let pad = ((hi - lo) * 0.1).max(1e-3);
    ((lo - pad) as f32, (hi + pad) as f32)
}

/// Line segments, broken where the series has no value.
fn lines(p: &egui::Painter, t: &Trust, vals: &[Option<f64>], r: Rect, x: (f32, f32), y: (f32, f32), c: Color32) {
    let mut run = Vec::new();
    for (row, v) in t.rows.iter().zip(vals) {
        match v {
            Some(v) => run.push(to_screen(r, x, y, row.t as f32 + 0.5, *v as f32)),
            None => trace(p, std::mem::take(&mut run), c),
        }
    }
    trace(p, run, c);
}

fn draw_plot(p: &egui::Painter, ui: &egui::Ui, t: &Trust, plot: Plot, r: Rect, x: (f32, f32)) -> (f32, f32) {
    p.rect_stroke(r.expand2(Vec2::new(8.0, 14.0)), 6.0, Stroke::new(1.0_f32, ui.visuals().widgets.noninteractive.bg_stroke.color));
    let y = y_range(t, plot);
    if let Some(end) = t.rows.iter().filter(|r| r.calibrating).map(|r| r.t as f32 + 1.0).reduce(f32::max) {
        let shade = Rect::from_two_pos(to_screen(r, x, y, x.0, y.1), to_screen(r, x, y, end, y.0));
        p.rect_filled(shade, 0.0, ui.visuals().faint_bg_color);
        label(p, shade.center(), Align2::CENTER_CENTER, "calibration");
    }
    let (a, b) = series(t, plot);
    lines(p, t, &b, r, x, y, THR);
    lines(p, t, &a, r, x, y, LINE);
    for m in &t.marks {
        let top = to_screen(r, x, y, m.t as f32, y.1);
        p.line_segment([top, Pos2Ext::down(top, r.height())], Stroke::new(1.0_f32, MARK));
    }
    let what = if plot == Plot::Percentile {
        "percentile (dirty seconds hold the last clean value) · threshold"
    } else {
        "feature value · threshold"
    };
    label(p, r.left_top() + Vec2::new(0.0, -12.0), Align2::LEFT_TOP, what);
    label(p, r.right_bottom() + Vec2::new(0.0, 12.0), Align2::RIGHT_BOTTOM, format!("{:.0} s", x.1 - x.0));
    y
}

trait Pos2Ext {
    fn down(self, dy: f32) -> Self;
}
impl Pos2Ext for egui::Pos2 {
    fn down(self, dy: f32) -> Self {
        self + Vec2::new(0.0, dy)
    }
}

fn draw_strip(p: &egui::Painter, t: &Trust, strip: Rect, inner: Rect, x: (f32, f32)) {
    let lane = Rect::from_x_y_ranges(inner.x_range(), strip.y_range());
    for r in &t.rows {
        let a = to_screen(lane, x, (0.0, 1.0), r.t as f32, 1.0);
        let b = to_screen(lane, x, (0.0, 1.0), r.t as f32 + 1.0, 0.0);
        p.rect_filled(Rect::from_two_pos(a, b).shrink2(Vec2::new(0.0, 1.0)), 0.0, cell(r));
    }
}

/// Plot rect plus its x and y ranges.
type Axes = (Rect, (f32, f32), (f32, f32));

fn hover(ui: &egui::Ui, p: &egui::Painter, t: &Trust, (r, x, y): Axes, pos: egui::Pos2, plot: Plot) {
    let sec = x.0 + (pos.x - r.left()) / r.width() * (x.1 - x.0);
    let Some(row) = t.rows.iter().find(|row| (row.t as f32..row.t as f32 + 1.0).contains(&sec)) else { return };
    let top = to_screen(r, x, y, row.t as f32 + 0.5, y.1);
    p.line_segment([top, top.down(r.height() + 26.0)], Stroke::new(1.0_f32, Color32::GRAY));
    egui::show_tooltip_at_pointer(ui.ctx(), ui.layer_id(), egui::Id::new("trust_hover"), |ui| {
        ui.label(RichText::new(format!("{:.0} s", row.t)).strong());
        ui.label(describe(row));
        let fmt = |v: Option<f64>, d: usize| v.map_or("--".into(), |v| format!("{v:.d$}"));
        match plot {
            Plot::Percentile => ui.weak(format!("percentile {} · threshold {}", fmt(row.pct, 0), fmt(row.thr_pct, 0))),
            Plot::Value => ui.weak(format!("value {} · threshold {}", fmt(row.value, 3), fmt(row.threshold, 3))),
        };
    });
}

/// One line for a second: the strip category and its reason.
pub fn describe(r: &Row) -> String {
    let mut s = if r.calibrating {
        "calibrating".to_owned()
    } else if r.paused {
        "paused".to_owned()
    } else if !r.clean {
        format!("dirty: {}", r.dirty.unwrap_or("no verdict").replace('_', " "))
    } else if !r.held_back.is_empty() {
        format!("held back: {}", r.held_back.join(", ").replace('_', " "))
    } else if r.in_target {
        "in zone".to_owned()
    } else {
        "below threshold".to_owned()
    };
    if r.warn == Some(true) {
        s += " · drowsiness warning";
    }
    if r.reward_chime {
        s += " · reward";
    }
    s
}

fn legend(ui: &mut egui::Ui, t: &Trust) {
    ui.horizontal_wrapped(|ui| {
        for (c, name) in [(IN_ZONE, "in zone"), (BELOW, "below"), (HELD, "held back"), (DIRTY, "dirty"), (IDLE, "calibrating / paused")] {
            let (r, _) = ui.allocate_exact_size(Vec2::splat(10.0), Sense::hover());
            ui.painter().rect_filled(r, 2.0, c);
            ui.weak(name);
            ui.add_space(6.0);
        }
        if !t.marks.is_empty() {
            ui.label(RichText::new(format!("| {} gesture mark(s)", t.marks.len())).small().color(MARK));
        }
    });
    if !t.totals.dirty_s.is_empty() {
        let parts: Vec<String> = t.totals.dirty_s.iter().map(|(k, n)| format!("{} {n} s", k.replace('_', " "))).collect();
        ui.weak(format!("Dirty: {}", parts.join(" · ")));
    }
}
