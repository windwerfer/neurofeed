//! Spectrum plot (frequency on X): band-coloured background regions, dB
//! curve, alpha-peak marker and a tap/cursor hairline readout. Shared base
//! for the PSD now and the Histogram later (`docs/ui-port/monitors.md`).

use super::theme;
use egui::{Align2, FontId, Pos2, Rect, Sense, Stroke, Ui};
use nf_core::Band;

/// What to draw: dB per bin (`k·df` Hz) up to `max_hz`.
pub struct Curve<'a> {
    pub db: &'a [f32],
    pub df: f64,
    pub peak_hz: Option<f64>,
}

/// Frequency axis ticks (Flutter `psd_pane.dart`).
const TICKS: [f64; 8] = [0.0, 4.0, 8.0, 13.0, 30.0, 50.0, 60.0, 100.0];

pub fn x_of(plot: Rect, max_hz: f64, hz: f64) -> f32 {
    plot.left() + ((hz / max_hz).clamp(0.0, 1.0) as f32) * plot.width()
}

pub fn hz_at(plot: Rect, max_hz: f64, x: f32) -> f64 {
    f64::from(((x - plot.left()) / plot.width().max(1.0)).clamp(0.0, 1.0)) * max_hz
}

/// dB range fitted to the visible bins (from 1 Hz) in 10 dB steps.
pub fn y_range(db: &[f32], df: f64, max_hz: f64) -> (f32, f32) {
    let vals = db.iter().enumerate().filter(|(k, v)| *k as f64 * df >= 1.0 && *k as f64 * df <= max_hz && v.is_finite()).map(|(_, v)| *v);
    let (lo, hi) = vals.fold((f32::MAX, f32::MIN), |(a, b), v| (a.min(v), b.max(v)));
    if lo > hi {
        return (-20.0, 20.0);
    }
    let (lo, mut hi) = ((lo / 10.0).floor() * 10.0, (hi / 10.0).ceil() * 10.0);
    if hi - lo < 20.0 {
        hi = lo + 20.0;
    }
    (lo, hi)
}

/// Draw into `rect`; returns the hairline frequency if the user tapped or
/// moved the cursor (kept by the caller).
pub fn plot(ui: &mut Ui, rect: Rect, max_hz: f64, curve: Option<&Curve>, hairline: Option<f64>, empty: &str) -> Option<f64> {
    let resp = ui.allocate_rect(rect, Sense::click_and_drag());
    let plot = Rect::from_min_max(rect.left_top() + egui::vec2(40.0, 16.0), rect.right_bottom() - egui::vec2(8.0, 18.0));
    let v = ui.visuals().clone();
    let p = ui.painter_at(rect);
    for (band, (lo, hi)) in Band::ALL.into_iter().zip(nf_core::dsp::BANDS_HZ) {
        let r = Rect::from_x_y_ranges(x_of(plot, max_hz, lo)..=x_of(plot, max_hz, hi), plot.y_range());
        p.rect_filled(r, 0.0, theme::band_color(band).gamma_multiply(0.16));
    }
    for hz in TICKS.into_iter().filter(|h| *h <= max_hz) {
        let x = x_of(plot, max_hz, hz);
        p.line_segment([Pos2::new(x, plot.top()), Pos2::new(x, plot.bottom())], theme::grid(&v));
        p.text(Pos2::new(x, plot.bottom() + 2.0), Align2::CENTER_TOP, format!("{hz:.0}"), FontId::proportional(10.0), theme::axis_text(&v));
    }
    p.text(
        Pos2::new(plot.right() - 2.0, plot.bottom() - 2.0),
        Align2::RIGHT_BOTTOM,
        "Hz",
        FontId::proportional(10.0),
        theme::axis_text(&v),
    );
    let Some(c) = curve else {
        p.text(plot.center(), Align2::CENTER_CENTER, empty, FontId::proportional(14.0), v.weak_text_color());
        return None;
    };
    let (y0, y1) = y_range(c.db, c.df, max_hz);
    let y_to = |db: f32| plot.bottom() - ((db - y0) / (y1 - y0).max(1e-6)).clamp(0.0, 1.0) * plot.height();
    let step = if y1 - y0 > 60.0 { 20.0 } else { 10.0 };
    let mut y = y0;
    while y <= y1 + 1e-3 {
        let sy = y_to(y);
        p.line_segment([Pos2::new(plot.left(), sy), Pos2::new(plot.right(), sy)], theme::grid(&v));
        p.text(Pos2::new(plot.left() - 6.0, sy), Align2::RIGHT_CENTER, format!("{y:.0}"), FontId::proportional(10.0), theme::axis_text(&v));
        y += step;
    }
    p.text(
        Pos2::new(plot.left() - 36.0, plot.top() - 14.0),
        Align2::LEFT_TOP,
        t!("psd-unit"),
        FontId::proportional(10.0),
        theme::axis_text(&v),
    );
    let pts: Vec<Pos2> =
        c.db.iter()
            .enumerate()
            .map(|(k, d)| (k as f64 * c.df, *d))
            .filter(|(f, _)| *f <= max_hz)
            .map(|(f, d)| Pos2::new(x_of(plot, max_hz, f), y_to(d)))
            .collect();
    p.with_clip_rect(plot.expand(1.0)).add(egui::Shape::line(pts, Stroke::new(1.6, v.strong_text_color())));
    let at = |hz: f64| c.db.get((hz / c.df).round() as usize).copied();
    if let Some((hz, d)) = c.peak_hz.and_then(|h| at(h).map(|d| (h, d))) {
        let pos = Pos2::new(x_of(plot, max_hz, hz), y_to(d));
        let col = theme::band_color(Band::Alpha);
        p.circle_filled(pos, 3.0, col);
        p.text(pos + egui::vec2(0.0, -6.0), Align2::CENTER_BOTTOM, format!("{hz:.1} Hz"), FontId::proportional(11.0), col);
    }
    let picked = resp
        .interact_pointer_pos()
        .or_else(|| resp.hover_pos())
        .filter(|q| plot.expand(4.0).contains(*q))
        .map(|q| hz_at(plot, max_hz, q.x));
    let shown = picked.or(hairline);
    if let Some(hz) = shown {
        let k = (hz / c.df).round();
        let hz = k * c.df;
        if let Some(d) = at(hz) {
            let x = x_of(plot, max_hz, hz);
            p.line_segment([Pos2::new(x, plot.top()), Pos2::new(x, plot.bottom())], Stroke::new(1.0, theme::sweep_cursor(&v)));
            let text = t!("psd-readout", hz = format!("{hz:.1}"), db = format!("{d:.1}"));
            let anchor = if x > plot.center().x { Align2::RIGHT_TOP } else { Align2::LEFT_TOP };
            p.text(
                Pos2::new(x + if x > plot.center().x { -6.0 } else { 6.0 }, plot.top() + 2.0),
                anchor,
                text,
                FontId::monospace(11.0),
                v.strong_text_color(),
            );
        }
    }
    if resp.clicked() || resp.dragged() {
        return picked;
    }
    None
}
