//! Bands monitor (legacy `bands_view.dart`): one full-bleed time series of
//! band power averaged over the chosen electrodes, a floating band legend
//! that hides/shows lines, and the shared monitor toolbar (Follow/Inspect,
//! window, dB | %, electrodes). Pinch / Ctrl+wheel zoom, drag pans.
//! Values: `nf_core::monitor::band_values` (linear averaging; relative =
//! share of the visible bands). Per-electrode bars stay behind `…`.

use crate::ui::monitor;
use crate::ui::theme;
use egui::{Align2, FontId, Pos2, Rect, RichText, Sense, Stroke, Vec2};
use nf_core::monitor::{band_values, MonitorId, Span};
use nf_core::{AppState, Band, BandScale, BandSnapshot, Command, DeviceInfo};
use std::cell::Cell;

thread_local! {
    /// View-local chrome (legacy had it too): per-electrode bars instead of the graph.
    static BARS: Cell<bool> = const { Cell::new(false) };
}

/// Snapshots come at 10 Hz; a longer silence is a gap.
const GAP_S: f64 = 0.5;
/// dB axis when there is nothing to fit.
const DB_DEFAULT: (f32, f32) = (-10.0, 30.0);

pub fn show(ui: &mut egui::Ui, state: &AppState, out: &mut Vec<Command>) {
    let Some(device) = &state.device else {
        monitor::toolbar(ui, state, MonitorId::Bands, out, |_, _| {});
        ui.label(t!("bands-no-device-connected-use-connect"));
        return;
    };
    let mut bars = BARS.with(Cell::get);
    let span = span(state);
    monitor::toolbar(ui, state, MonitorId::Bands, out, |ui, out| {
        if let Some(span) = span {
            inspect_label(ui, state, span);
        }
        scale_toggle(ui, state, out);
        ui.add_space(8.0);
        electrode_chips(ui, state, device, out);
        ui.add_space(8.0);
        crate::ui::overview::toggle(ui, state, MonitorId::Bands, out);
        ui.add_space(4.0);
        ui.menu_button("…", |ui| {
            ui.checkbox(&mut bars, t!("bands-bars-per-electrode"));
        });
    });
    BARS.with(|b| b.set(bars));
    let (Some(span), Some(latest)) = (span, state.bands.latest()) else {
        ui.label(t!("bands-waiting-for-data"));
        return;
    };
    if bars {
        bars_grid(ui, state, device, latest);
    } else {
        over_time(ui, state, device, span, out);
    }
}

fn span(state: &AppState) -> Option<Span> {
    Some(Span::new(state.bands.oldest()?.time, state.bands.latest()?.time))
}

fn relative(state: &AppState) -> bool {
    state.band_scale == BandScale::Relative
}

fn visible(state: &AppState) -> [bool; 5] {
    Band::ALL.map(|b| state.monitors.bands.visible(b))
}

fn inspect_label(ui: &mut egui::Ui, state: &AppState, span: Span) {
    monitor::inspect_label(ui, state.monitors.viewport(MonitorId::Bands), span);
}

fn scale_toggle(ui: &mut egui::Ui, state: &AppState, out: &mut Vec<Command>) {
    ui.spacing_mut().item_spacing.x = 0.0;
    for (scale, label, hint) in [
        (BandScale::Absolute, t!("bands-scale-db"), t!("bands-scale-db-hint")),
        (BandScale::Relative, t!("bands-scale-relative"), t!("bands-scale-relative-hint")),
    ] {
        if ui.selectable_label(state.band_scale == scale, label).on_hover_text(hint).clicked() && state.band_scale != scale {
            out.push(Command::ScaleSet { scale });
        }
    }
    ui.spacing_mut().item_spacing.x = 8.0;
}

/// Electrodes in the average (at least one stays on). Names come from the device.
fn electrode_chips(ui: &mut egui::Ui, state: &AppState, device: &DeviceInfo, out: &mut Vec<Command>) {
    let sel = state.monitors.bands.selected(&device.channels);
    monitor::channel_selector(ui, &device.channels, &sel, &state.analysis, true, out, |names| Command::MonitorDisplay {
        electrodes: Some(names),
        hidden_bands: None,
    });
}

/// One decimated point: x on screen and the five band values.
type Pt = (f32, [Option<f32>; 5], bool);

fn over_time(ui: &mut egui::Ui, state: &AppState, device: &DeviceInfo, span: Span, out: &mut Vec<Command>) {
    let ov_h = crate::ui::overview::height(ui, state, MonitorId::Bands, ui.available_height());
    let (rect, resp) =
        ui.allocate_exact_size((ui.available_size() - Vec2::new(0.0, ov_h)).max(Vec2::new(160.0, 120.0)), Sense::click_and_drag());
    let plot = Rect::from_min_max(rect.left_top() + Vec2::new(40.0, 16.0), rect.right_bottom() - Vec2::new(8.0, 18.0));
    let vp = state.monitors.viewport(MonitorId::Bands);
    monitor::interact(ui, &resp, plot, MonitorId::Bands, vp, out);
    let range = monitor::presented_range(ui, state, MonitorId::Bands, vp, span);
    // Display choice ∩ analysis-eligible; empty = a message, never all.
    let chans = state.analysis.eligible_of(&device.channels, &state.monitors.bands.selected(&device.channels));
    if ov_h > 0.0 {
        // Bands has full detail over its whole history: nothing shaded.
        let host = crate::ui::overview::Host { id: MonitorId::Bands, range, detail_oldest: span.oldest_s, no_detail: String::new() };
        crate::ui::overview::show(ui, state, &chans, &host, ov_h, out);
    }
    if chans.is_empty() {
        monitor::no_eligible(ui, plot);
        return;
    }
    let pts = series(state, &chans, plot, range);
    let (y0, y1) = y_range(relative(state), &pts);
    let v = ui.visuals().clone();
    let p = ui.painter_at(rect);
    y_axis(&p, plot, (y0, y1), relative(state), &v);
    monitor::time_grid(&p, plot, range, &v);
    let lines = ui.painter_at(plot.expand(2.0));
    for band in Band::ALL.into_iter().filter(|b| state.monitors.bands.visible(*b)) {
        draw_band(&lines, plot, &pts, band, (y0, y1));
    }
    legend(ui, state, plot, out);
}

/// The Bands mini strip (PSD context strip): grid, axis and band lines of
/// `chans` (already eligibility-filtered) over `range`. Reads only the
/// snapshots in range (binary search), decimated per pixel column.
pub fn strip(p: &egui::Painter, state: &AppState, chans: &[usize], plot: Rect, range: (f64, f64)) {
    let pts = series(state, chans, plot, range);
    let rel = relative(state);
    let (y0, y1) = y_range(rel, &pts);
    let v = p.ctx().global_style().visuals.clone();
    y_axis(p, plot, (y0, y1), rel, &v);
    monitor::time_grid(p, plot, range, &v);
    let lines = p.with_clip_rect(plot.expand(2.0));
    for band in Band::ALL.into_iter().filter(|b| state.monitors.bands.visible(*b)) {
        draw_band(&lines, plot, &pts, band, (y0, y1));
    }
}

/// Points in the visible range, at most ~one per pixel column (mean).
fn series(state: &AppState, chans: &[usize], plot: Rect, range: (f64, f64)) -> Vec<Pt> {
    let (vis, rel) = (visible(state), relative(state));
    let raw: Vec<(f64, [Option<f32>; 5])> =
        state.bands.range(range.0 - GAP_S, range.1).map(|s: &BandSnapshot| (s.time, band_values(s, chans, vis, rel))).collect();
    let per_px = (raw.len() as f32 / plot.width().max(1.0)).ceil().max(1.0) as usize;
    let mut out = Vec::with_capacity(raw.len() / per_px + 1);
    let mut prev_t = f64::NEG_INFINITY;
    for chunk in raw.chunks(per_px) {
        let (Some(first), Some(last)) = (chunk.first(), chunk.last()) else { continue };
        let gap = first.0 - prev_t > GAP_S * per_px as f64;
        prev_t = last.0;
        let t = (first.0 + last.0) / 2.0;
        let mut v = [None; 5];
        for (b, slot) in v.iter_mut().enumerate() {
            let vals: Vec<f32> = chunk.iter().filter_map(|c| c.1.get(b).copied().flatten()).collect();
            if !vals.is_empty() {
                *slot = Some(vals.iter().sum::<f32>() / vals.len() as f32);
            }
        }
        out.push((monitor::x_of(plot, range, t), v, gap));
    }
    out
}

/// Fixed 0..100 % or a dB range fitted to the data in 10 dB steps.
fn y_range(relative: bool, pts: &[Pt]) -> (f32, f32) {
    if relative {
        return (0.0, 100.0);
    }
    let vals = pts.iter().flat_map(|p| p.1.iter().flatten().copied()).filter(|v| v.is_finite());
    let (lo, hi) = vals.fold((f32::MAX, f32::MIN), |(a, b), v| (a.min(v), b.max(v)));
    if lo > hi {
        return DB_DEFAULT;
    }
    let (mut lo, mut hi) = ((lo / 10.0).floor() * 10.0, (hi / 10.0).ceil() * 10.0);
    if hi - lo < 20.0 {
        lo -= 10.0;
        hi = lo + 30.0;
    }
    (lo, hi)
}

fn y_to(plot: Rect, (y0, y1): (f32, f32), y: f32) -> f32 {
    plot.bottom() - ((y - y0) / (y1 - y0).max(1e-6)).clamp(0.0, 1.0) * plot.height()
}

fn y_axis(p: &egui::Painter, plot: Rect, yr: (f32, f32), relative: bool, v: &egui::Visuals) {
    let step = if relative {
        25.0
    } else if yr.1 - yr.0 > 60.0 {
        20.0
    } else {
        10.0
    };
    let mut y = yr.0;
    while y <= yr.1 + 1e-3 {
        let sy = y_to(plot, yr, y);
        p.line_segment([Pos2::new(plot.left(), sy), Pos2::new(plot.right(), sy)], theme::grid(v));
        p.text(Pos2::new(plot.left() - 6.0, sy), Align2::RIGHT_CENTER, format!("{y:.0}"), FontId::proportional(10.0), theme::axis_text(v));
        y += step;
    }
    let unit = if relative { "%" } else { "dB" };
    p.text(Pos2::new(plot.left() + 4.0, plot.top() - 14.0), Align2::LEFT_TOP, unit, FontId::proportional(10.0), theme::axis_text(v));
}

fn draw_band(p: &egui::Painter, plot: Rect, pts: &[Pt], band: Band, yr: (f32, f32)) {
    let color = theme::band_color(band);
    let mut run: Vec<Pos2> = Vec::new();
    let flush = |run: &mut Vec<Pos2>| {
        if run.len() > 1 {
            p.add(egui::Shape::line(std::mem::take(run), Stroke::new(1.6, color)));
        }
        run.clear();
    };
    for (x, vals, gap) in pts {
        let Some(v) = vals.get(band.index()).copied().flatten() else {
            flush(&mut run);
            continue;
        };
        if *gap {
            flush(&mut run);
        }
        let pt = Pos2::new(*x, y_to(plot, yr, v));
        if v < yr.0 || v > yr.1 {
            p.circle_filled(pt, 1.6, theme::CLIPPED);
        }
        run.push(pt);
    }
    flush(&mut run);
}

/// Floating band legend inside the plot's top-right corner; tap hides/shows.
fn legend(ui: &mut egui::Ui, state: &AppState, plot: Rect, out: &mut Vec<Command>) {
    let row = if crate::ui::layout::current(ui.ctx()).is_compact() { 24.0 } else { 20.0 };
    let size = Vec2::new(72.0, row * 5.0 + 8.0);
    let r = Rect::from_min_size(Pos2::new(plot.right() - size.x - 6.0, plot.top() + 6.0), size);
    if r.left() < plot.left() || r.bottom() > plot.bottom() {
        return;
    }
    let hidden = &state.monitors.bands.hidden_bands;
    ui.scope_builder(egui::UiBuilder::new().max_rect(r), |ui| {
        egui::Frame::popup(ui.style()).inner_margin(4.0).show(ui, |ui| {
            ui.spacing_mut().item_spacing.y = 0.0;
            for band in Band::ALL {
                let on = !hidden.contains(&band);
                let col = if on { theme::band_color(band) } else { ui.visuals().weak_text_color().gamma_multiply(0.6) };
                let mut text = RichText::new(band.name()).color(col);
                if !on {
                    text = text.strikethrough();
                }
                let b = egui::Button::new(text).frame(false).min_size(Vec2::new(64.0, row));
                if ui.add(b).on_hover_text(t!("bands-show-hide-this-band")).clicked() {
                    let mut next: Vec<Band> = hidden.iter().copied().filter(|h| *h != band).collect();
                    if on {
                        next.push(band);
                    }
                    out.push(Command::MonitorDisplay { electrodes: None, hidden_bands: Some(next) });
                }
            }
        });
    });
}

/// Per-electrode bars (behind `…`); same value math per single electrode.
fn bars_grid(ui: &mut egui::Ui, state: &AppState, device: &DeviceInfo, snap: &BandSnapshot) {
    let n = device.channels.len().max(1);
    let avail = ui.available_size();
    let cols = if avail.x > 700.0 { n.min(4) } else { n.min(2) };
    let rows = n.div_ceil(cols);
    let gap = 12.0;
    let cell =
        Vec2::new((avail.x - gap * (cols as f32 - 1.0)) / cols as f32, ((avail.y - gap * (rows as f32 - 1.0)) / rows as f32).max(120.0));
    let (vis, rel) = (visible(state), relative(state));
    egui::ScrollArea::vertical().show(ui, |ui| {
        egui::Grid::new("bands_grid").spacing([gap, gap]).show(ui, |ui| {
            for (ch, name) in device.channels.iter().enumerate() {
                channel_card(ui, cell, name, band_values(snap, &[ch], vis, rel), rel);
                if (ch + 1) % cols == 0 {
                    ui.end_row();
                }
            }
        });
    });
}

fn channel_card(ui: &mut egui::Ui, size: Vec2, name: &str, vals: [Option<f32>; 5], relative: bool) {
    let (rect, _) = ui.allocate_exact_size(size, Sense::hover());
    let p = ui.painter_at(rect);
    let v = ui.visuals();
    p.rect_filled(rect, 6.0, v.extreme_bg_color);
    p.text(rect.left_top() + Vec2::new(10.0, 8.0), Align2::LEFT_TOP, name, FontId::proportional(16.0), v.strong_text_color());
    let plot = Rect::from_min_max(rect.left_top() + Vec2::new(10.0, 34.0), rect.right_bottom() - Vec2::new(10.0, 26.0));
    let slot = plot.width() / 5.0;
    p.line_segment([plot.left_bottom(), plot.right_bottom()], Stroke::new(1.0, v.weak_text_color()));
    let yr = if relative { (0.0, 100.0) } else { DB_DEFAULT };
    for band in Band::ALL {
        let Some(val) = vals.get(band.index()).copied().flatten() else { continue };
        let frac = ((val - yr.0) / (yr.1 - yr.0)).clamp(0.0, 1.0);
        let x0 = plot.left() + slot * band.index() as f32 + slot * 0.15;
        let x1 = x0 + slot * 0.7;
        let top = plot.bottom() - (plot.height() - 16.0).max(0.0) * frac;
        p.rect_filled(Rect::from_min_max(Pos2::new(x0, top), Pos2::new(x1, plot.bottom())), 3.0, theme::band_color(band));
        let text = if relative { format!("{val:.0}%") } else { format!("{val:.1}") };
        p.text(Pos2::new((x0 + x1) / 2.0, top - 2.0), Align2::CENTER_BOTTOM, text, FontId::monospace(11.0), v.text_color());
        let initial: String = band.name().chars().take(1).collect();
        p.text(
            Pos2::new((x0 + x1) / 2.0, plot.bottom() + 4.0),
            Align2::CENTER_TOP,
            initial,
            FontId::proportional(12.0),
            v.weak_text_color(),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn db_range_fits_in_10_db_steps() {
        let pts: Vec<Pt> = vec![(0.0, [Some(-3.0), Some(12.0), None, None, None], false)];
        assert_eq!(y_range(false, &pts), (-10.0, 20.0));
        assert_eq!(y_range(false, &[]), DB_DEFAULT);
        assert_eq!(y_range(true, &pts), (0.0, 100.0));
        let flat: Vec<Pt> = vec![(0.0, [Some(5.0); 5], false)];
        let (lo, hi) = y_range(false, &flat);
        assert!(hi - lo >= 20.0 && lo <= 5.0 && hi >= 5.0);
    }
}
