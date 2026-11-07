//! Spectrogram monitor (Flutter `spectrogram_view.dart`): one heatmap of the
//! selected, analysis-eligible electrodes averaged in **linear power** per
//! column (`nf_core::spectrum::spectrogram_average`), 0–60 Hz, 300 s of
//! spectral history (columns every 0.25 s on the source clock; a dropout
//! leaves missing columns, never filled), plasma colour map with a colour
//! bar, dB range Auto or locked, shared Follow / Inspect, window presets,
//! pinch / Ctrl+wheel zoom, drag pan and the overview (on by default).
//!
//! Rendering: only the visible columns are averaged and uploaded as one
//! small texture (≤ 1 201 × 61 texels), rebuilt when a new column arrives or
//! the selection / window / range changes, never per frame.

use crate::ui::{monitor, overview, theme};
use egui::{Align2, Color32, ColorImage, FontId, Pos2, Rect, Sense, Stroke, TextureOptions, Ui};
use nf_core::monitor::{MonitorId, Span};
use nf_core::signal::SPEC_HOP_S;
use nf_core::spectrum::SpecAverage;
use nf_core::{Command, Session};

/// Display range (Flutter: 0–60 Hz).
pub const MAX_HZ: f64 = 60.0;
const BAR_W: f32 = 12.0;
const RIGHT_GUTTER: f32 = 46.0;

/// Flutter `spectrogram_pane.dart` plasma stops.
const PLASMA: [(f32, [u8; 3]); 5] = [
    (0.0, [0x0D, 0x08, 0x87]),
    (0.25, [0x7E, 0x03, 0xA8]),
    (0.5, [0xCC, 0x47, 0x78]),
    (0.75, [0xF8, 0x95, 0x40]),
    (1.0, [0xF0, 0xF9, 0x21]),
];

/// Plasma colour at `u` in 0..=1 (clamped; NaN = darkest).
pub fn plasma(u: f32) -> Color32 {
    let u = if u.is_finite() { u.clamp(0.0, 1.0) } else { 0.0 };
    let i = PLASMA.iter().position(|(s, _)| *s >= u).unwrap_or(4).max(1);
    let ((a, ca), (b, cb)) = (PLASMA[i - 1], PLASMA[i]);
    let f = ((u - a) / (b - a).max(1e-6)).clamp(0.0, 1.0);
    let mix = |k: usize| (f32::from(ca[k]) + (f32::from(cb[k]) - f32::from(ca[k])) * f).round() as u8;
    Color32::from_rgb(mix(0), mix(1), mix(2))
}

/// Auto dB range: min..max of the visible bins from 1 Hz, outward to 5 dB,
/// at least 20 dB wide.
pub fn auto_range(a: &SpecAverage) -> (f32, f32) {
    let first = (1.0 / a.df.max(1e-9)).ceil() as usize;
    let vals = a.cols.iter().flat_map(|c| c.iter().skip(first)).copied().filter(|v| v.is_finite());
    let (lo, hi) = vals.fold((f32::MAX, f32::MIN), |(l, h), v| (l.min(v), h.max(v)));
    if lo > hi {
        return (-20.0, 25.0);
    }
    let (lo, mut hi) = ((lo / 5.0).floor() * 5.0, (hi / 5.0).ceil() * 5.0);
    if hi - lo < 20.0 {
        hi = lo + 20.0;
    }
    (lo, hi)
}

/// Columns come on a 0.25 s grid in source time that starts at the first
/// window (`phase` = its offset, ± packet jitter); column `t` sits in slot
/// `round((t - phase) / hop)`, so jitter never merges two columns.
pub fn phase(first: f64) -> f64 {
    first.rem_euclid(SPEC_HOP_S)
}

/// Visible slot range.
pub fn slots((start, end): (f64, f64), phase: f64) -> (i64, i64) {
    (((start - phase) / SPEC_HOP_S).floor() as i64, ((end - phase) / SPEC_HOP_S).ceil() as i64)
}

fn slot(t: f64, phase: f64) -> i64 {
    ((t - phase) / SPEC_HOP_S).round() as i64
}

/// Cache key: channels, visible slots, locked range (0.1 dB), newest column
/// slot and column count (a new column, device change or re-include
/// rebuilds; nothing else does).
type Key = (Vec<usize>, i64, i64, Option<(i32, i32)>, i64, usize);

#[derive(Clone)]
struct Cached {
    key: Key,
    avg: SpecAverage,
    db: (f32, f32),
    tex: Option<egui::TextureHandle>,
}

fn cached(ui: &Ui, sig: &nf_core::signal::Signal, chans: &[usize], (s0, s1): (i64, i64), ph: f64, lock: Option<(f32, f32)>) -> Cached {
    let id = egui::Id::unique("nf-spectrogram-cache");
    let newest = sig.spec_times.back().map_or(-1, |t| slot(*t, ph));
    let key = (chans.to_vec(), s0, s1, lock.map(|(a, b)| ((a * 10.0) as i32, (b * 10.0) as i32)), newest, sig.spec_times.len());
    if let Some(c) = ui.data(|d| d.get_temp::<Cached>(id)).filter(|c| c.key == key) {
        return c;
    }
    let avg = nf_core::spectrum::spectrogram_average(
        sig,
        chans,
        ph + (s0 as f64 - 0.5) * SPEC_HOP_S,
        ph + (s1 as f64 + 0.5) * SPEC_HOP_S,
        MAX_HZ,
    );
    let db = lock.unwrap_or_else(|| auto_range(&avg));
    let tex = image(&avg, s0, s1, ph, db).map(|img| ui.ctx().load_texture("nf-spectrogram", img, TextureOptions::NEAREST));
    let c = Cached { key, avg, db, tex };
    ui.data_mut(|d| d.insert_temp(id, c.clone()));
    c
}

/// Slots `s0..=s1` × bins (top row = highest bin); missing columns transparent.
fn image(a: &SpecAverage, s0: i64, s1: i64, ph: f64, (lo, hi): (f32, f32)) -> Option<ColorImage> {
    let w = usize::try_from(s1 - s0 + 1).ok().filter(|w| *w > 0 && *w <= 4096)?;
    let h = a.bins;
    if h == 0 {
        return None;
    }
    let mut px = vec![Color32::TRANSPARENT; w * h];
    for (t, col) in a.times.iter().zip(&a.cols) {
        let Ok(x) = usize::try_from(slot(*t, ph) - s0) else { continue };
        if x >= w || col.is_empty() {
            continue;
        }
        for (k, v) in col.iter().take(h).enumerate() {
            px[(h - 1 - k) * w + x] = plasma((v - lo) / (hi - lo).max(1e-6));
        }
    }
    Some(ColorImage::new([w, h], px))
}

pub fn show(ui: &mut Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    let id = MonitorId::Spectrogram;
    let vp = state.monitors.viewport(id);
    let live = session.live_signal();
    let channels: Vec<String> = live.map(|(d, _)| d.channels.clone()).unwrap_or_default();
    let span = live.and_then(|(_, s)| Some(Span::new(*s.spec_times.front()?, *s.spec_times.back()?)));
    let disp = &state.monitors.spectrogram;
    let lock_now = ui.data(|d| d.get_temp::<(f32, f32)>(egui::Id::unique("nf-spectrogram-shown")));
    monitor::toolbar(ui, state, id, out, |ui, out| {
        if let Some(span) = span {
            monitor::inspect_label(ui, vp, span);
        }
        mag_menu(ui, disp.db_lock, lock_now, out);
        ui.add_space(8.0);
        let sel = disp.selected(&channels);
        monitor::channel_selector(ui, &channels, &sel, &state.analysis, true, out, |names| Command::MonitorSpectrogram {
            electrodes: Some(names),
            db_min: None,
            db_max: None,
            auto: None,
        });
        ui.add_space(8.0);
        overview::toggle(ui, state, id, out);
    });
    let (Some((dev, sig)), Some(span)) = (live, span) else {
        ui.label(if live.is_none() { t!("spectrogram-no-device-connected-use-connect") } else { t!("raw-waiting-for-data") });
        return;
    };
    let range = monitor::presented_range(ui, state, id, vp, span);
    let chans = state.analysis.eligible_of(&dev.channels, &disp.selected(&dev.channels));
    let full = ui.available_rect_before_wrap();
    let ov_h = overview::height(ui, state, id, full.height());
    let rect = Rect::from_min_max(full.min, Pos2::new(full.right(), full.bottom() - ov_h));
    let resp = ui.allocate_rect(rect, Sense::click_and_drag());
    let plot = Rect::from_min_max(rect.left_top() + egui::vec2(40.0, 16.0), rect.right_bottom() - egui::vec2(RIGHT_GUTTER, 18.0));
    monitor::interact(ui, &resp, plot, id, vp, out);
    draw(ui, sig, &chans, plot, range, disp.db_lock, &resp);
    if ov_h > 0.0 {
        let host = overview::Host { id, range, detail_oldest: span.oldest_s, no_detail: t!("overview-no-spectral") };
        overview::show(ui, state, &chans, &host, ov_h, out);
    }
}

fn y_of(plot: Rect, hz: f64) -> f32 {
    plot.bottom() - ((hz / MAX_HZ) as f32) * plot.height()
}

fn draw(
    ui: &Ui,
    sig: &nf_core::signal::Signal,
    chans: &[usize],
    plot: Rect,
    range: (f64, f64),
    lock: Option<(f32, f32)>,
    resp: &egui::Response,
) {
    let v = ui.visuals().clone();
    let p = ui.painter_at(plot.expand2(egui::vec2(40.0, 18.0)).with_max_x(plot.right() + RIGHT_GUTTER));
    p.rect_filled(plot, 0.0, Color32::BLACK);
    for hz in [0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0] {
        let y = y_of(plot, hz);
        p.line_segment([Pos2::new(plot.left() - 4.0, y), Pos2::new(plot.left(), y)], theme::grid(&v));
        p.text(Pos2::new(plot.left() - 6.0, y), Align2::RIGHT_CENTER, format!("{hz:.0}"), FontId::proportional(10.0), theme::axis_text(&v));
    }
    p.text(Pos2::new(plot.left() - 36.0, plot.top() - 14.0), Align2::LEFT_TOP, "Hz", FontId::proportional(10.0), theme::axis_text(&v));
    monitor::time_grid(&p.with_clip_rect(plot.expand2(egui::vec2(30.0, 18.0))), plot, range, &v);
    if chans.is_empty() {
        monitor::no_eligible(ui, plot);
        return;
    }
    let ph = phase(sig.spec_times.front().copied().unwrap_or(0.0));
    let (s0, s1) = slots(range, ph);
    let c = cached(ui, sig, chans, (s0, s1), ph, lock);
    ui.data_mut(|d| d.insert_temp(egui::Id::unique("nf-spectrogram-shown"), c.db));
    if let Some(tex) = &c.tex {
        let df = c.avg.df;
        let x0 = monitor::x_of(plot, range, ph + (s0 as f64 - 0.5) * SPEC_HOP_S);
        let x1 = monitor::x_of(plot, range, ph + (s1 as f64 + 0.5) * SPEC_HOP_S);
        let top = y_of(plot, (c.avg.bins as f64 - 0.5) * df);
        let bottom = y_of(plot, -0.5 * df);
        let img = Rect::from_min_max(Pos2::new(x0, top), Pos2::new(x1, bottom));
        p.with_clip_rect(plot).image(tex.id(), img, Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)), Color32::WHITE);
    }
    colour_bar(&p, plot, c.db, lock.is_some(), &v);
    if c.avg.times.is_empty() {
        p.text(plot.center(), Align2::CENTER_CENTER, t!("spectrogram-no-columns"), FontId::proportional(14.0), Color32::LIGHT_GRAY);
    }
    readout(ui, &p, plot, range, &c, resp);
}

fn colour_bar(p: &egui::Painter, plot: Rect, (lo, hi): (f32, f32), locked: bool, v: &egui::Visuals) {
    let bar = Rect::from_min_max(Pos2::new(plot.right() + 6.0, plot.top()), Pos2::new(plot.right() + 6.0 + BAR_W, plot.bottom()));
    let n = 48;
    for i in 0..n {
        let u0 = i as f32 / n as f32;
        let r = Rect::from_x_y_ranges(
            bar.x_range(),
            (bar.bottom() - bar.height() * (u0 + 1.0 / n as f32))..=(bar.bottom() - bar.height() * u0),
        );
        p.rect_filled(r, 0.0, plasma(u0 + 0.5 / n as f32));
    }
    p.rect_stroke(bar, 0.0, theme::grid(v), egui::StrokeKind::Outside);
    for (u, val) in [(0.0, lo), (0.5, (lo + hi) / 2.0), (1.0, hi)] {
        let y = bar.bottom() - bar.height() * u;
        p.text(Pos2::new(bar.right() + 3.0, y), Align2::LEFT_CENTER, format!("{val:.0}"), FontId::proportional(10.0), theme::axis_text(v));
    }
    let unit = if locked { t!("spectrogram-db-locked") } else { "dB".to_owned() };
    p.text(Pos2::new(bar.left(), plot.top() - 3.0), Align2::LEFT_BOTTOM, unit, FontId::proportional(10.0), theme::axis_text(v));
}

/// Hover / tap: `m:ss · f Hz · x dB` of the column under the pointer.
fn readout(ui: &Ui, p: &egui::Painter, plot: Rect, range: (f64, f64), c: &Cached, resp: &egui::Response) {
    let Some(q) = resp.hover_pos().or_else(|| resp.interact_pointer_pos()).filter(|q| plot.contains(*q)) else { return };
    let t = range.0 + f64::from((q.x - plot.left()) / plot.width().max(1.0)) * (range.1 - range.0);
    let hz = f64::from((plot.bottom() - q.y) / plot.height().max(1.0)) * MAX_HZ;
    let i = c.avg.times.partition_point(|&x| x < t - SPEC_HOP_S / 2.0);
    let Some((ct, col)) = c.avg.times.get(i).zip(c.avg.cols.get(i)).filter(|(ct, _)| (*ct - t).abs() <= SPEC_HOP_S) else { return };
    let k = (hz / c.avg.df.max(1e-9)).round() as usize;
    let Some(db) = col.get(k) else { return };
    let text =
        t!("spectrogram-readout", t = nf_core::monitor::mmss(*ct), hz = format!("{:.0}", k as f64 * c.avg.df), db = format!("{db:.1}"));
    let v = ui.visuals();
    p.line_segment([Pos2::new(q.x, plot.top()), Pos2::new(q.x, plot.bottom())], Stroke::new(1.0, Color32::from_white_alpha(120)));
    let al = if q.x > plot.center().x { Align2::RIGHT_TOP } else { Align2::LEFT_TOP };
    let dx = if q.x > plot.center().x { -6.0 } else { 6.0 };
    let pos = Pos2::new(q.x + dx, plot.top() + 6.0);
    let g = p.layout_no_wrap(text, FontId::proportional(11.0), v.strong_text_color());
    let r = al.anchor_size(pos, g.size()).expand(3.0);
    p.rect_filled(r, 3.0, theme::overlay_bg(v));
    p.galley(r.min + egui::vec2(3.0, 3.0), g, v.strong_text_color());
}

fn mag_menu(ui: &mut Ui, lock: Option<(f32, f32)>, shown: Option<(f32, f32)>, out: &mut Vec<Command>) {
    let text = match lock {
        Some((a, b)) => t!("spectrogram-mag-locked", lo = format!("{a:.0}"), hi = format!("{b:.0}")),
        None => t!("spectrogram-mag-auto"),
    };
    ui.menu_button(text, |ui| {
        if ui.selectable_label(lock.is_none(), t!("spectrogram-auto")).clicked() {
            out.push(Command::MonitorSpectrogram { electrodes: None, db_min: None, db_max: None, auto: Some(true) });
        }
        if let Some((a, b)) = shown.filter(|_| lock.is_none()) {
            if ui.button(t!("spectrogram-lock-current", lo = format!("{a:.0}"), hi = format!("{b:.0}"))).clicked() {
                out.push(Command::MonitorSpectrogram { electrodes: None, db_min: Some(a), db_max: Some(b), auto: None });
            }
        }
        ui.separator();
        let (mut a, mut b) = lock.or(shown).unwrap_or((-20.0, 25.0));
        let ch_a = ui.add(egui::Slider::new(&mut a, -60.0..=60.0).step_by(5.0).text(t!("spectrogram-db-min"))).changed();
        let ch_b = ui.add(egui::Slider::new(&mut b, -60.0..=60.0).step_by(5.0).text(t!("spectrogram-db-max"))).changed();
        if (ch_a || ch_b) && nf_core::monitor::db_range_ok(a, b) {
            out.push(Command::MonitorSpectrogram { electrodes: None, db_min: Some(a), db_max: Some(b), auto: None });
        }
    })
    .response
    .on_hover_text(t!("spectrogram-mag-hint"));
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use nf_core::Session;
    use serde_json::json;

    fn show_v(u: &mut egui::Ui, s: &Session) {
        super::show(u, s, &mut Vec::new());
    }

    #[test]
    fn plasma_ends_and_clamps() {
        assert_eq!(plasma(0.0), Color32::from_rgb(0x0D, 0x08, 0x87));
        assert_eq!(plasma(1.0), Color32::from_rgb(0xF0, 0xF9, 0x21));
        assert_eq!(plasma(2.0), plasma(1.0));
        assert_eq!(plasma(f32::NAN), plasma(0.0));
        assert_eq!(plasma(0.5), Color32::from_rgb(0xCC, 0x47, 0x78));
    }

    #[test]
    fn slots_cover_the_window() {
        assert_eq!(slots((10.0, 40.0), 0.0), (40, 160));
        assert_eq!(slots((10.1, 40.1), 0.0), (40, 161));
        // Columns at 0.12 + k·0.25 with ±0.05 s jitter keep distinct slots.
        let ph = phase(0.12);
        let t: Vec<i64> = [10.12, 10.42, 10.57, 10.90].iter().map(|&t| slot(t, ph)).collect();
        assert_eq!(t, vec![40, 41, 42, 43]);
    }

    #[test]
    fn image_places_columns_by_time_and_leaves_gaps() {
        let a = SpecAverage { df: 1.0, bins: 2, times: vec![10.0, 10.75], cols: vec![vec![0.0, 10.0], Vec::new()] };
        let img = image(&a, 40, 43, 0.0, (0.0, 10.0)).unwrap();
        assert_eq!(img.size, [4, 2]);
        // Bottom row = 0 Hz, top = 1 Hz; slot 40 filled, 41..43 empty.
        assert_eq!(img.pixels[4], plasma(0.0));
        assert_eq!(img.pixels[0], plasma(1.0));
        assert_eq!(img.pixels[1], Color32::TRANSPARENT);
        assert_eq!(img.pixels[7], Color32::TRANSPARENT);
    }

    #[test]
    fn auto_range_is_wide_enough_and_skips_dc() {
        let a = SpecAverage { df: 1.0, bins: 3, times: vec![0.0], cols: vec![vec![90.0, 1.0, 3.0]] };
        assert_eq!(auto_range(&a), (0.0, 20.0));
        assert_eq!(auto_range(&SpecAverage::default()), (-20.0, 25.0));
    }

    #[test]
    fn excluded_selection_shows_no_eligible_and_axes_are_truthful() {
        let _lang = crate::i18n::lang_lock();
        let mut s = Session::new();
        s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
        s.call("clock.advance", json!({ "seconds": 5.0 })).unwrap();
        let none = t!("channels-none-eligible");
        let t = crate::ui::views::histogram::tests::texts(&s, show_v);
        assert!(!t.contains(&none));
        assert!(t.iter().any(|x| x == "60") && t.iter().any(|x| x == "Hz") && t.iter().any(|x| x == "dB"), "{t:?}");
        s.call("monitor.spectrogram", json!({ "electrodes": ["AF7"] })).unwrap();
        s.call("analysis.exclude", json!({ "channel": "AF7", "confirm": true })).unwrap();
        assert!(crate::ui::views::histogram::tests::texts(&s, show_v).contains(&none));
    }
}
