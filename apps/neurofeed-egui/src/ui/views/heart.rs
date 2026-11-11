//! HR+SpO2 view.
//!
//! - **Top (~70 %)**: dual-axis timeline of the 1 Hz estimates — SpO2 in
//!   blue on the left axis (%), HR in red on the right axis (bpm). Only
//!   reliable estimates are drawn; seconds without one are gaps. Thin
//!   horizontal lines mark the means (this recording so far, else the
//!   retained hour). Hover / tap shows a cursor with both readings at that
//!   time (nearest within ±1 s, nothing carried over gaps). It is the
//!   pulse waveform's overview: the faint shade is the waveform window
//!   (drag = move it, edges = resize, tap = jump, long press = bookmark),
//!   reusing the shared overview widget.
//! - **Bottom (~30 %, optional, saved)**: "Pulse waveform (PPG)", the raw
//!   optical samples at the device rate (sensor counts, auto-scaled per
//!   channel; not bpm, not a medical measurement). Only the last 5 min of
//!   raw samples are kept; older parts of the timeline are shaded.

use crate::ui::{monitor, overview, theme};
use egui::{Align2, Color32, FontId, Pos2, Rect, Sense, Stroke, Ui};
use nf_core::monitor::{MonitorId, Span};
use nf_core::optics::{Estimate, Optics, Series, GAP_S};
use nf_core::rawtrace as rt;
use nf_core::{AppState, Command, Session};

pub const HR_COLOR: Color32 = Color32::from_rgb(0xEF, 0x53, 0x50);
pub const SPO2_COLOR: Color32 = Color32::from_rgb(0x4F, 0xC3, 0xF7);
/// Optical channel colours (raw waveform): infrared, red, ambient.
const IR_COLOR: Color32 = Color32::from_rgb(0xFF, 0xB7, 0x4D);
const RED_COLOR: Color32 = Color32::from_rgb(0xF0, 0x62, 0x92);
const AMBIENT_COLOR: Color32 = Color32::from_rgb(0x90, 0x90, 0x90);
/// Plot gutters for the two value axes.
const AXIS_W: f32 = 44.0;
/// Follow lead of the timeline: estimates come every ~1 s (0.94–1.14 s,
/// packet-quantised), so 2 s keeps the newest one past the right edge.
const TIMELINE_LEAD_S: f64 = 2.0;
/// Data drawn past the right edge so Follow slides it in.
const OFFSCREEN_S: f64 = 3.0;

pub fn show(ui: &mut Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    let Some(o) = session.optics() else {
        let text = match &state.device {
            None => t!("heart-no-device-connected"),
            Some(d) if d.has_optics() && !d.has_ppg() => t!("heart-athena-classic-only"),
            Some(_) => t!("heart-no-ppg-on-this-device"),
        };
        ui.add_space(8.0);
        ui.label(text);
        return;
    };
    let wave_on = state.monitors.heart.waveform;
    let simulated = state.device.as_ref().is_some_and(|d| d.simulated);
    let tb = if wave_on { MonitorId::HeartDetail } else { MonitorId::HeartOverview };
    monitor::toolbar(ui, state, tb, out, |ui, out| {
        if ui.selectable_label(wave_on, t!("heart-waveform-toggle")).on_hover_text(t!("heart-waveform-toggle-hint")).clicked() {
            out.push(Command::MonitorHeart { waveform: Some(!wave_on) });
        }
        if simulated {
            ui.add_space(8.0);
            ui.weak(t!("heart-simulated")).on_hover_text(t!("heart-simulated-hint"));
        }
    });
    if o.time.is_none() {
        ui.add_space(8.0);
        ui.label(t!("heart-no-optical-data"));
        return;
    }
    let avail = ui.available_rect_before_wrap();
    let compact = crate::ui::layout::current(ui.ctx()).is_compact();
    let bottom_h = if wave_on && avail.height() > 160.0 { (avail.height() * 0.3).max(if compact { 90.0 } else { 80.0 }) } else { 0.0 };
    let top = Rect::from_min_max(avail.min, Pos2::new(avail.right(), avail.bottom() - bottom_h));
    let span_top = session.monitor_span_of(MonitorId::HeartOverview);
    let span_detail = session.monitor_span_of(MonitorId::HeartDetail);
    let (plot, range, resp) = if bottom_h > 0.0 {
        let dvp = state.monitors.viewport(MonitorId::HeartDetail);
        let map = sweep_map(ui, state, dvp, span_detail);
        // The shade is the pass shown below: the sweep's last window, or the
        // frozen pass incl. its not-yet-filled future part.
        let detail_range = match map {
            rt::Mapping::Sweep { now, window } => (now - window, now),
            rt::Mapping::Scroll { start, end } => (start, end),
        };
        let host = overview::Host {
            id: MonitorId::HeartDetail,
            range: detail_range,
            detail_oldest: span_detail.oldest_s,
            no_detail: t!("heart-no-raw-older"),
        };
        let mut draw = |ui: &Ui, p: &egui::Painter, plot: Rect, range: (f64, f64)| timeline(ui, p, o, plot, range);
        let content = overview::Content {
            span: span_top,
            margin: (AXIS_W, AXIS_W),
            draw: &mut draw,
            accent: Some(Color32::from_gray(200)),
            lead_s: TIMELINE_LEAD_S,
        };
        let Some(d) = overview::show_in(ui, state, &host, top, content, out) else { return };
        let bottom = Rect::from_min_max(Pos2::new(avail.left(), top.bottom()), avail.max);
        waveform(ui, state, o, bottom, map, out);
        (d.plot, d.range, d.resp)
    } else {
        let resp = ui.allocate_rect(top, Sense::click_and_drag());
        let plot = Rect::from_min_max(top.left_top() + egui::vec2(AXIS_W, 14.0), top.right_bottom() - egui::vec2(AXIS_W, 18.0));
        let vp = state.monitors.viewport(MonitorId::HeartOverview);
        monitor::interact(ui, &resp, plot, MonitorId::HeartOverview, vp, out);
        let range = monitor::presented_range_lead(ui, state, MonitorId::HeartOverview, vp, span_top, TIMELINE_LEAD_S);
        let p = ui.painter_at(top);
        timeline(ui, &p, o, plot, range);
        (plot, range, resp)
    };
    cursor(ui, o, plot, range, &resp);
}

/// A value axis `(lo, hi)` with its tick step.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Axis {
    pub lo: f64,
    pub hi: f64,
    pub step: f64,
}

/// HR axis (bpm): the visible reliable values ± 5, on 10 bpm steps, at
/// least 30 bpm tall, inside 30..230. Default 50..110 without data.
pub fn hr_axis(vals: impl Iterator<Item = f64>) -> Axis {
    let (mn, mx) = vals.fold((f64::MAX, f64::MIN), |(a, b), v| (a.min(v), b.max(v)));
    let (mut lo, mut hi) = if mn <= mx { (((mn - 5.0) / 10.0).floor() * 10.0, ((mx + 5.0) / 10.0).ceil() * 10.0) } else { (50.0, 110.0) };
    if hi - lo < 30.0 {
        let mid = ((lo + hi) / 20.0).round() * 10.0;
        (lo, hi) = (mid - 20.0, mid + 20.0);
    }
    let (lo, hi) = (lo.max(30.0), hi.min(230.0));
    Axis { lo, hi, step: if hi - lo > 80.0 { 20.0 } else { 10.0 } }
}

/// SpO2 axis (%): top is 100 %, bottom the visible minimum − 2 on whole
/// steps, at least 10 % tall (90..100 by default), never below 50 %.
pub fn spo2_axis(vals: impl Iterator<Item = f64>) -> Axis {
    let mn = vals.fold(f64::MAX, f64::min);
    let lo = if mn < f64::MAX { (mn - 2.0).floor().min(90.0) } else { 90.0 };
    let lo = lo.max(50.0);
    let lo = if 100.0 - lo > 20.0 { (lo / 5.0).floor() * 5.0 } else { lo };
    Axis {
        lo,
        hi: 100.0,
        step: if 100.0 - lo > 20.0 {
            10.0
        } else if 100.0 - lo > 10.0 {
            5.0
        } else {
            2.0
        },
    }
}

/// Screen y of value `v` on axis `a` in `plot`.
pub fn y_of(plot: Rect, a: Axis, v: f64) -> f32 {
    let f = ((v - a.lo) / (a.hi - a.lo).max(1e-9)) as f32;
    plot.bottom() - f * plot.height()
}

/// Value at screen y (inverse of [`y_of`]; tests).
#[cfg(test)]
pub fn v_of(plot: Rect, a: Axis, y: f32) -> f64 {
    a.lo + f64::from((plot.bottom() - y) / plot.height().max(1e-6)) * (a.hi - a.lo)
}

/// Reliable estimates of `s` in `[t0, t1]` (plus [`OFFSCREEN_S`]) as
/// polylines broken at gaps (> [`GAP_S`] apart) and unreliable seconds.
pub fn runs(o: &Optics, s: Series, (t0, t1): (f64, f64)) -> Vec<Vec<Estimate>> {
    let h = o.series(s);
    let from = h.partition_point(|e| e.time < t0 - GAP_S);
    let mut out: Vec<Vec<Estimate>> = Vec::new();
    let mut prev: Option<f64> = None;
    for e in h.range(from..).take_while(|e| e.time <= t1 + OFFSCREEN_S) {
        if !e.reliable(s) {
            prev = None;
            continue;
        }
        if prev.is_none_or(|p| e.time - p > GAP_S) {
            out.push(Vec::new());
        }
        if let Some(r) = out.last_mut() {
            r.push(*e);
        }
        prev = Some(e.time);
    }
    out
}

fn axes(o: &Optics, range: (f64, f64)) -> (Axis, Axis) {
    let vis = |s: Series| {
        runs(o, s, range).into_iter().flatten().filter(|e| e.time >= range.0 && e.time <= range.1).map(|e| e.value).collect::<Vec<_>>()
    };
    let mut hr = vis(Series::Hr);
    let mut sp = vis(Series::Spo2);
    // Keep the means on screen.
    hr.extend(o.mean(Series::Hr).value());
    sp.extend(o.mean(Series::Spo2).value());
    (hr_axis(hr.into_iter()), spo2_axis(sp.into_iter()))
}

fn ticks(a: Axis) -> impl Iterator<Item = f64> {
    let first = (a.lo / a.step).ceil() * a.step;
    (0..64).map(move |k| first + f64::from(k) * a.step).take_while(move |v| *v <= a.hi + 1e-9)
}

/// The dual-axis timeline into `plot` for `range`.
fn timeline(ui: &Ui, p: &egui::Painter, o: &Optics, plot: Rect, range: (f64, f64)) {
    let v = ui.visuals();
    let (hr_a, sp_a) = axes(o, range);
    monitor::time_grid(p, plot, range, v);
    let small = FontId::proportional(10.0);
    for t in ticks(hr_a) {
        let y = y_of(plot, hr_a, t);
        p.line_segment([Pos2::new(plot.left(), y), Pos2::new(plot.right(), y)], theme::grid(v));
        p.text(Pos2::new(plot.right() + 4.0, y), Align2::LEFT_CENTER, format!("{t:.0}"), small.clone(), HR_COLOR);
    }
    for t in ticks(sp_a) {
        p.text(Pos2::new(plot.left() - 4.0, y_of(plot, sp_a, t)), Align2::RIGHT_CENTER, format!("{t:.0}"), small.clone(), SPO2_COLOR);
    }
    p.text(Pos2::new(plot.left() - 4.0, plot.top() - 2.0), Align2::RIGHT_BOTTOM, "SpO2 %", small.clone(), SPO2_COLOR);
    p.text(Pos2::new(plot.right() + 4.0, plot.top() - 2.0), Align2::LEFT_BOTTOM, "HR bpm", small.clone(), HR_COLOR);
    // No summary before its oldest estimate (or outside the hour).
    let oldest = o.hr.front().map(|e| e.time).into_iter().chain(o.spo2.front().map(|e| e.time)).reduce(f64::min).unwrap_or(range.1);
    if oldest > range.0 {
        let x = monitor::x_of(plot, range, oldest).clamp(plot.left(), plot.right());
        p.rect_filled(Rect::from_x_y_ranges(plot.left()..=x, plot.y_range()), 0.0, theme::GAP_SHADE);
    }
    let clip = p.with_clip_rect(plot.expand(1.0));
    for (s, a, c) in [(Series::Spo2, sp_a, SPO2_COLOR), (Series::Hr, hr_a, HR_COLOR)] {
        for run in runs(o, s, range) {
            let pts: Vec<Pos2> = run.iter().map(|e| Pos2::new(monitor::x_of(plot, range, e.time), y_of(plot, a, e.value))).collect();
            if pts.len() == 1 {
                clip.circle_filled(pts[0], 1.8, c);
            } else {
                clip.add(egui::Shape::line(pts, Stroke::new(1.6, c)));
            }
        }
    }
    // Means: thin lines in the series colours, small labels on the left.
    let scope = if o.run().is_some() { t!("heart-mean-recording") } else { t!("heart-mean-hour") };
    let mut label_y: Vec<f32> = Vec::new();
    for (s, a, c, name, fmt) in [(Series::Hr, hr_a, HR_COLOR, "HR", 0usize), (Series::Spo2, sp_a, SPO2_COLOR, "SpO2", 1)] {
        let Some(m) = o.mean(s).value() else { continue };
        let y = y_of(plot, a, m).clamp(plot.top(), plot.bottom());
        // Grid-fine (a hair thicker), in the series colour, subdued.
        let grid = theme::grid(v);
        clip.line_segment([Pos2::new(plot.left(), y), Pos2::new(plot.right(), y)], Stroke::new(grid.width + 0.2, c.gamma_multiply(0.45)));
        // Labels never overlap each other.
        let mut ly = y - 2.0;
        if label_y.iter().any(|o| (o - ly).abs() < 12.0) {
            ly = y + 13.0;
        }
        label_y.push(ly);
        let text = format!("{name} Ø {m:.fmt$} · {scope}");
        p.text(Pos2::new(plot.left() + 4.0, ly), Align2::LEFT_BOTTOM, text, small.clone(), c);
    }
    p.text(
        plot.left_bottom() + egui::vec2(4.0, -3.0),
        Align2::LEFT_BOTTOM,
        t!("heart-spo2-uncalibrated"),
        small.clone(),
        theme::axis_text(v),
    );
    // Big current values (top-right) when there is room.
    if plot.height() > 150.0 && plot.width() > 320.0 {
        let big = FontId::proportional(if plot.height() > 260.0 { 26.0 } else { 20.0 });
        let hr = o.current_of(Series::Hr).map_or("--".to_owned(), |e| format!("{:.0}", e.value));
        let sp = o.current_of(Series::Spo2).map_or("--".to_owned(), |e| format!("{:.0}", e.value));
        let r = p.text(plot.right_top() + egui::vec2(-8.0, 6.0), Align2::RIGHT_TOP, format!("{hr} bpm"), big.clone(), HR_COLOR);
        p.text(Pos2::new(r.left() - 16.0, r.top()), Align2::RIGHT_TOP, format!("{sp} %"), big, SPO2_COLOR);
    }
}

fn cursor_id() -> egui::Id {
    egui::Id::unique("nf-heart-cursor")
}

/// Cursor time: hover (mouse), or the last tap (touch) until the next.
fn cursor(ui: &Ui, o: &Optics, plot: Rect, range: (f64, f64), resp: &egui::Response) {
    let t_at = |x: f32| range.0 + f64::from((x - plot.left()) / plot.width().max(1.0)) * (range.1 - range.0);
    if resp.clicked() {
        if let Some(q) = resp.interact_pointer_pos().filter(|q| plot.contains(*q)) {
            ui.ctx().data_mut(|d| d.insert_temp(cursor_id(), t_at(q.x)));
        }
    }
    let t = resp.hover_pos().filter(|q| plot.contains(*q)).map(|q| t_at(q.x)).or_else(|| ui.ctx().data(|d| d.get_temp::<f64>(cursor_id())));
    let Some(t) = t.filter(|t| *t >= range.0 && *t <= range.1) else { return };
    let p = ui.painter_at(plot.expand(2.0));
    let x = monitor::x_of(plot, range, t);
    p.line_segment(
        [Pos2::new(x, plot.top()), Pos2::new(x, plot.bottom())],
        Stroke::new(1.0, ui.visuals().strong_text_color().gamma_multiply(0.6)),
    );
    let text = readout(o, t);
    let font = FontId::proportional(11.0);
    let left = x > plot.center().x;
    let pos = Pos2::new(if left { x - 6.0 } else { x + 6.0 }, plot.top() + 4.0);
    let galley = p.layout_no_wrap(text, font, ui.visuals().strong_text_color());
    let r = Align2([if left { egui::Align::Max } else { egui::Align::Min }, egui::Align::Min]).anchor_size(pos, galley.size()).expand(3.0);
    p.rect_filled(r, 3.0, ui.visuals().extreme_bg_color.gamma_multiply(0.9));
    p.galley(r.min + egui::vec2(3.0, 3.0), galley, Color32::WHITE);
}

/// `m:ss  HR 72 bpm  SpO2 97 %` at `t` (nearest reliable within ±1 s).
pub fn readout(o: &Optics, t: f64) -> String {
    let hr = o.at(Series::Hr, t).map_or("--".to_owned(), |e| format!("{:.0}", e.value));
    let sp = o.at(Series::Spo2, t).map_or("--".to_owned(), |e| format!("{:.1}", e.value));
    format!("{}   HR {hr} bpm   SpO2 {sp} %", nf_core::monitor::mmss(t))
}

/// The pulse waveform detail: raw optical channels in an oscilloscope
/// sweep while following (same geometry, wrap split, cursor and freeze as
/// Raw EEG via `nf_core::rawtrace`), a time-ordered window in Inspect.
/// Each channel is auto-scaled over its visible samples; only the visible
/// samples are read.
fn waveform(ui: &mut Ui, state: &AppState, o: &Optics, rect: Rect, map: rt::Mapping, out: &mut Vec<Command>) {
    let id = MonitorId::HeartDetail;
    let resp = ui.allocate_rect(rect, Sense::click_and_drag());
    // Narrow (phone portrait): short title, legend on its own row.
    let narrow = rect.width() < 700.0;
    let top_pad = if narrow { 30.0 } else { 16.0 };
    let plot = Rect::from_min_max(rect.left_top() + egui::vec2(AXIS_W, top_pad), rect.right_bottom() - egui::vec2(AXIS_W, 18.0));
    let vp = state.monitors.viewport(id);
    // Leaving the sweep (button, drag, wheel, zoom) freezes on its pass.
    monitor::set_freeze_end(ui.ctx(), id, map.freeze_end());
    monitor::interact(ui, &resp, plot, id, vp, out);
    let p = ui.painter_at(rect);
    let v = ui.visuals().clone();
    p.line_segment([rect.left_top(), rect.right_top()], theme::grid(&v));
    p.text(
        rect.left_top() + egui::vec2(AXIS_W, 2.0),
        Align2::LEFT_TOP,
        if narrow { t!("heart-waveform-title-short") } else { t!("heart-waveform-title") },
        FontId::proportional(11.0),
        v.strong_text_color(),
    );
    super::raw::time_grid(&p, plot, map, &v, true);
    let x_px = |x: f32| plot.left() + x * plot.width();
    // Older than the 5 min raw detail (Inspect only; a sweep shows now).
    if let (Some(oldest), rt::Mapping::Scroll { start, end }) = (o.wave_span().map(|w| w.0), map) {
        if oldest > start {
            let x = x_px((((oldest - start) / (end - start).max(1e-9)) as f32).clamp(0.0, 1.0));
            let r = Rect::from_x_y_ranges(plot.left()..=x, plot.y_range());
            p.rect_filled(r, 0.0, theme::GAP_SHADE);
            if r.width() > 140.0 {
                p.text(r.center(), Align2::CENTER_CENTER, t!("heart-no-raw-older"), FontId::proportional(10.0), theme::axis_text(&v));
            }
        }
    }
    let names = state.device.as_ref().map(|d| d.ppg_channels.clone()).unwrap_or_default();
    let clip = p.with_clip_rect(plot.expand(1.0));
    let mut legend = Vec::new();
    for (ch, w) in o.waves.iter().enumerate() {
        let name = names.get(ch).map_or("?", String::as_str);
        let c = match name {
            "infrared" => IR_COLOR,
            "red" => RED_COLOR,
            _ => AMBIENT_COLOR,
        };
        let tr = channel_trace(w, o.rate, map, plot.width().max(1.0) as usize);
        let Some((lo, hi)) = value_range(&tr) else { continue };
        let pad = ((hi - lo) * 0.08).max(1.0);
        let (ylo, yhi) = (lo - pad, hi + pad);
        let y_px = |val: f32| plot.bottom() - (val - ylo) / (yhi - ylo) * plot.height();
        for run in &tr.runs {
            let pts: Vec<Pos2> = run.iter().map(|q| Pos2::new(x_px(q[0]), y_px(q[1]))).collect();
            clip.add(egui::Shape::line(pts, Stroke::new(if c == AMBIENT_COLOR { 0.8 } else { 1.3 }, c)));
        }
        legend.push((name.to_owned(), c, lo, hi));
    }
    if let Some(cx) = map.cursor() {
        let x = x_px(cx as f32);
        p.line_segment([Pos2::new(x, plot.top()), Pos2::new(x, plot.bottom())], Stroke::new(1.2, theme::sweep_cursor(&v)));
    }
    if legend.is_empty() {
        p.text(plot.center(), Align2::CENTER_CENTER, t!("heart-no-raw-here"), FontId::proportional(11.0), theme::axis_text(&v));
    }
    // Legend with each channel's visible raw range (counts).
    let mut x = rect.right() - 6.0;
    for (name, c, lo, hi) in legend.iter().rev() {
        let pos = Pos2::new(x, rect.top() + if narrow { 15.0 } else { 2.0 });
        let r = p.text(pos, Align2::RIGHT_TOP, format!("{name} {lo:.0}–{hi:.0}"), FontId::proportional(10.0), *c);
        x = r.left() - 10.0;
    }
    p.text(
        Pos2::new(plot.left() - 4.0, plot.center().y),
        Align2::RIGHT_CENTER,
        t!("heart-counts"),
        FontId::proportional(10.0),
        theme::axis_text(&v),
    );
}

/// The waveform's geometry this frame: Raw EEG's sweep (Follow) or a
/// time-ordered window (Inspect), with Raw's Follow lead.
pub fn sweep_map(ui: &Ui, state: &AppState, vp: nf_core::monitor::Viewport, span: Span) -> rt::Mapping {
    let range = monitor::presented_range_lead(ui, state, MonitorId::HeartDetail, vp, span, rt::RAW_FOLLOW_LEAD_S);
    super::raw::mapping(nf_core::monitor::RawMode::Sweep, vp, range)
}

/// One optical channel under `map`: only the visible window is visited.
pub fn channel_trace(w: &nf_core::optics::Wave, rate: f64, map: rt::Mapping, columns: usize) -> rt::Trace {
    let (lo, hi) = map.visible();
    let mut samples = Vec::new();
    w.visit(lo, hi, |s| samples.push(s));
    rt::trace_samples(samples.into_iter(), rate, map, columns)
}

/// Min and max value of a trace (counts).
fn value_range(tr: &rt::Trace) -> Option<(f32, f32)> {
    let (lo, hi) = tr.runs.iter().flatten().fold((f32::MAX, f32::MIN), |(a, b), q| (a.min(q[1]), b.max(q[1])));
    (lo <= hi).then_some((lo, hi))
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::panic)]
    use super::*;
    use serde_json::json;

    /// Full-app frames (root UI incl. layout/safe area); returns the last
    /// frame's texts and the rightmost x of any polyline inside `clip` tags.
    struct Frame {
        texts: Vec<String>,
        shapes: Vec<egui::epaint::ClippedShape>,
    }

    fn run(s: &mut Session, size: egui::Vec2, frames: &[Vec<egui::Event>]) -> (Frame, Vec<Command>) {
        let ctx = egui::Context::default();
        let mut all = Vec::new();
        let mut last = None;
        for (i, ev) in frames.iter().enumerate() {
            let input = egui::RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, size)),
                time: Some(i as f64 / 60.0),
                events: ev.clone(),
                ..Default::default()
            };
            let mut cmds = Vec::new();
            let mut o = ctx.run_ui(input, |u| cmds = crate::ui::show(u, s, None));
            o.textures_delta.clear();
            for c in cmds {
                s.execute(c.clone()).ok();
                all.push(c);
            }
            last = Some(o.shapes);
        }
        let shapes = last.unwrap_or_default();
        let texts = shapes
            .iter()
            .filter_map(|c| if let egui::Shape::Text(t) = &c.shape { Some(t.galley.text().to_owned()) } else { None })
            .collect();
        (Frame { texts, shapes }, all)
    }

    fn session(layout: &str, dev: &str, secs: f64) -> Session {
        let mut s = Session::new();
        s.call("settings.set", json!({ "onboarded": true, "layout": layout })).unwrap();
        s.call("device.connect", json!({ "id": dev })).unwrap();
        s.call("view.set", json!({ "view": "heart_rate" })).unwrap();
        s.call("clock.advance", json!({ "seconds": secs })).unwrap();
        s
    }

    fn idle(n: usize) -> Vec<Vec<egui::Event>> {
        vec![Vec::new(); n]
    }

    fn has(f: &Frame, needle: &str) -> bool {
        f.texts.iter().any(|t| t.contains(needle))
    }

    #[test]
    fn dual_axes_map_both_ways_and_stay_truthful() {
        let plot = Rect::from_min_max(Pos2::new(0.0, 100.0), Pos2::new(100.0, 300.0));
        let hr = hr_axis([58.0, 75.0].into_iter());
        assert_eq!((hr.lo, hr.hi), (50.0, 80.0));
        assert_eq!(y_of(plot, hr, 50.0), 300.0);
        assert_eq!(y_of(plot, hr, 80.0), 100.0);
        assert!((v_of(plot, hr, y_of(plot, hr, 63.3)) - 63.3).abs() < 1e-3);
        let sp = spo2_axis([96.5].into_iter());
        assert_eq!((sp.lo, sp.hi), (90.0, 100.0));
        assert!((v_of(plot, sp, 200.0) - 95.0).abs() < 1e-9);
        // Wide data: wider, still bounded and 100 % on top.
        let sp = spo2_axis([71.0].into_iter());
        assert_eq!((sp.lo, sp.hi), (65.0, 100.0));
        let hr = hr_axis([40.0, 190.0].into_iter());
        assert_eq!((hr.lo, hr.hi, hr.step), (30.0, 200.0, 20.0));
        let none = hr_axis(std::iter::empty());
        assert_eq!((none.lo, none.hi), (50.0, 110.0));
    }

    #[test]
    fn readout_names_both_values_and_dashes_for_missing() {
        let _lang = crate::i18n::lang_lock();
        let s = session("regular", "sim:muse", 30.0);
        let o = s.optics().unwrap();
        let r = readout(o, 20.0);
        assert!(r.starts_with("0:20") && r.contains("bpm") && !r.contains("HR --"), "{r}");
        assert!(readout(o, 1.0).contains("HR -- bpm"), "{}", readout(o, 1.0));
    }

    /// Sweep at `now` (window `w`) and the Inspect window it freezes to.
    fn maps(now: f64, w: f64) -> (rt::Mapping, rt::Mapping) {
        let sweep = rt::Mapping::Sweep { now, window: w };
        let e = sweep.freeze_end().unwrap();
        (sweep, rt::Mapping::Scroll { start: e - w, end: e })
    }

    fn pts_left_of(tr: &rt::Trace, cx: f64) -> Vec<[f32; 2]> {
        tr.runs.iter().flatten().copied().filter(|q| f64::from(q[0]) <= cx).collect()
    }

    #[test]
    fn sweep_freeze_keeps_every_x_and_clears_right_of_the_cursor() {
        let s = session("regular", "sim:muse", 125.0);
        let o = s.optics().unwrap();
        let w = 10.0;
        // Cursor near the start, the middle and the end of a pass.
        for now in [110.4, 115.0, 119.7] {
            let (sweep, frozen) = maps(now, w);
            let cx = sweep.cursor().unwrap();
            for wave in &o.waves {
                let a = channel_trace(wave, o.rate, sweep, 800);
                let b = channel_trace(wave, o.rate, frozen, 800);
                let (l1, l2) = (pts_left_of(&a, cx), pts_left_of(&b, cx));
                assert!(!l1.is_empty());
                // Same samples at the same x left of the cursor (the
                // frozen view may also show samples newer than `now`).
                let n = l1.len().min(l2.len());
                assert!(n + 3 >= l1.len(), "{now}: {} vs {}", l1.len(), l2.len());
                for (p, q) in l1.iter().zip(&l2).take(n.saturating_sub(2)) {
                    assert!((p[0] - q[0]).abs() < 1e-5 && p[1] == q[1], "{now}: {p:?} {q:?}");
                }
                // Right of the newest sample: nothing (the old pass is gone).
                let newest = wave.newest().unwrap();
                let nx = frozen.x(newest).0 as f32;
                assert!(b.runs.iter().flatten().all(|q| q[0] <= nx + 1e-4), "{now}: cleared right");
                // The sweep itself shows the previous pass right of the cursor.
                if cx < 0.9 {
                    assert!(a.runs.iter().flatten().any(|q| f64::from(q[0]) > cx + 0.05), "{now}");
                }
            }
        }
    }

    #[test]
    fn frozen_pass_fills_right_with_new_real_data_without_moving() {
        let mut s = session("regular", "sim:muse", 112.0);
        let w = 10.0;
        let (sweep, frozen) = maps(s.optics().unwrap().time.unwrap(), w);
        let before = channel_trace(&s.optics().unwrap().waves[1], 64.0, frozen, 800);
        s.call("clock.advance", json!({ "seconds": 3.0 })).unwrap();
        let after = channel_trace(&s.optics().unwrap().waves[1], 64.0, frozen, 800);
        let cx = sweep.cursor().unwrap();
        let max_x = |t: &rt::Trace| t.runs.iter().flatten().map(|q| q[0]).fold(0.0f32, f32::max);
        assert!(max_x(&after) > max_x(&before) + 0.25, "refills: {} -> {}", max_x(&before), max_x(&after));
        let (l1, l2) = (pts_left_of(&before, cx - 0.01), pts_left_of(&after, cx - 0.01));
        assert_eq!(l1, l2, "left part unchanged");
    }

    #[test]
    fn all_optical_channels_share_the_sweep_phase() {
        let s = session("regular", "sim:muse", 60.0);
        let o = s.optics().unwrap();
        let map = rt::Mapping::Sweep { now: 55.3, window: 10.0 };
        let firsts: Vec<f32> = o.waves.iter().map(|w| channel_trace(w, o.rate, map, 100_000).runs[0][0][0]).collect();
        assert!(firsts.windows(2).all(|p| (p[0] - p[1]).abs() < 1e-6), "{firsts:?}");
        // Window-only reads: 10 s of 64 Hz, not the 5 min.
        let n = o.waves[1].visit(45.3, 55.3, |_| {});
        assert!(n <= 10 * 64 + 4, "{n}");
    }

    #[test]
    fn inspect_button_freezes_on_the_pass_and_the_shade_follows_it() {
        let _lang = crate::i18n::lang_lock();
        let mut s = session("regular", "sim:muse", 112.0);
        let ctx = egui::Context::default();
        let mut inspect = None;
        for i in 0..3 {
            let input = egui::RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, egui::vec2(1100.0, 700.0))),
                time: Some(f64::from(i) / 60.0),
                ..Default::default()
            };
            let mut o = ctx.run_ui(input, |u| {
                crate::ui::show(u, &s, None);
            });
            o.textures_delta.clear();
            for c in &o.shapes {
                if let egui::Shape::Text(t) = &c.shape {
                    if t.galley.text() == "Inspect" {
                        inspect = Some(t.visual_bounding_rect().center());
                    }
                }
            }
        }
        let p = inspect.unwrap();
        let btn = |pressed| egui::Event::PointerButton {
            pos: p,
            button: egui::PointerButton::Primary,
            pressed,
            modifiers: egui::Modifiers::NONE,
        };
        let mut cmds = Vec::new();
        for (i, ev) in [vec![egui::Event::PointerMoved(p), btn(true)], vec![btn(false)], vec![]].into_iter().enumerate() {
            let input = egui::RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, egui::vec2(1100.0, 700.0))),
                time: Some(0.1 + i as f64 / 60.0),
                events: ev,
                ..Default::default()
            };
            let mut out = Vec::new();
            ctx.run_ui(input, |u| out = crate::ui::show(u, &s, None)).textures_delta.clear();
            for c in out {
                s.execute(c.clone()).unwrap();
                cmds.push(c);
            }
        }
        let vp = s.state().monitors.viewport(MonitorId::HeartDetail);
        let end = vp.end_s.unwrap_or_else(|| panic!("inspect: {cmds:?}"));
        assert!((end / vp.window_s - (end / vp.window_s).round()).abs() < 1e-9, "frozen on a pass end: {end}");
        assert!(end > s.optics().unwrap().time.unwrap(), "incl. its future part");
        let h = s.call("heart.get", json!({})).unwrap();
        assert_eq!(h["pulse"]["end_s"], end, "clamp keeps the pass");
        // The timeline's shade is that pass.
        for i in 0..2 {
            let input = egui::RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, egui::vec2(1100.0, 700.0))),
                time: Some(1.0 + f64::from(i) / 60.0),
                ..Default::default()
            };
            ctx.run_ui(input, |u| {
                crate::ui::show(u, &s, None);
            })
            .textures_delta
            .clear();
        }
        let shade = ctx.data(|d| d.get_temp::<Rect>(overview::shade_id(MonitorId::HeartOverview))).unwrap();
        assert!(shade.width() > 2.0);
        // A pan afterwards moves by exactly the pan (no extra shift).
        s.call("monitor.pan", json!({ "monitor": "heart_detail", "seconds": -2.5 })).unwrap();
        assert_eq!(s.state().monitors.viewport(MonitorId::HeartDetail).end_s, Some(end - 2.5));
        // Follow again: a sweep, no frozen end.
        s.call("monitor.viewport", json!({ "monitor": "heart_detail", "mode": "follow" })).unwrap();
        assert!(s.state().monitors.viewport(MonitorId::HeartDetail).following());
    }

    #[test]
    fn desktop_shows_timeline_waveform_means_and_scales() {
        let _lang = crate::i18n::lang_lock();
        let mut s = session("regular", "sim:muse", 120.0);
        let (f, _) = run(&mut s, egui::vec2(1100.0, 700.0), &idle(3));
        for needle in ["SpO2 %", "HR bpm", "HR Ø", "SpO2 Ø", "Pulse waveform (PPG)", "infrared", "red", "simulated optics", "bpm"] {
            assert!(has(&f, needle), "{needle}: {:?}", f.texts);
        }
        // Mean lines: grid-fine, subdued series colours.
        let means: Vec<f32> = f
            .shapes
            .iter()
            .filter_map(|c| match &c.shape {
                egui::Shape::LineSegment { stroke, .. }
                    if stroke.color == HR_COLOR.gamma_multiply(0.45) || stroke.color == SPO2_COLOR.gamma_multiply(0.45) =>
                {
                    Some(stroke.width)
                }
                _ => None,
            })
            .collect();
        assert_eq!(means.len(), 2, "two mean lines");
        assert!(means.iter().all(|w| *w <= crate::ui::theme::grid(&egui::Visuals::dark()).width + 0.25), "{means:?}");
        // Waveform hidden: timeline + means remain, no waveform.
        s.call("monitor.heart", json!({ "waveform": false })).unwrap();
        let (f, _) = run(&mut s, egui::vec2(1100.0, 700.0), &idle(3));
        assert!(!has(&f, "Pulse waveform (PPG)"));
        assert!(has(&f, "HR Ø") && has(&f, "SpO2 %"));
    }

    #[test]
    fn phone_landscape_is_graph_only_and_keeps_the_waveform() {
        let _lang = crate::i18n::lang_lock();
        let mut s = session("compact", "sim:muse", 60.0);
        let (f, _) = run(&mut s, egui::vec2(850.0, 400.0), &idle(3));
        assert!(has(&f, "Pulse waveform (PPG)") && has(&f, "HR bpm") && has(&f, "SpO2 %"), "{:?}", f.texts);
        assert!(!has(&f, "Follow"), "no chrome in landscape: {:?}", f.texts);
        // Portrait: chrome with the waveform toggle.
        let (f, _) = run(&mut s, egui::vec2(400.0, 850.0), &idle(3));
        assert!(has(&f, "Pulse waveform") && has(&f, "Follow"), "{:?}", f.texts);
    }

    #[test]
    fn unsupported_device_shows_a_message_no_numbers() {
        let _lang = crate::i18n::lang_lock();
        let mut s = session("regular", "sim:crown", 10.0);
        let (f, _) = run(&mut s, egui::vec2(1100.0, 700.0), &idle(2));
        assert!(has(&f, "No PPG on this device"), "{:?}", f.texts);
        assert!(!has(&f, "bpm"));
    }

    /// Rightmost x of the polylines in `color` and the clip right edge.
    fn right_edge(f: &Frame, color: Color32) -> Option<(f32, f32)> {
        f.shapes
            .iter()
            .filter_map(|c| match &c.shape {
                egui::Shape::Path(p) if p.stroke.color == egui::epaint::ColorMode::Solid(color) && p.points.len() > 1 => {
                    Some((p.points.iter().map(|q| q.x).fold(f32::MIN, f32::max), c.clip_rect.right()))
                }
                _ => None,
            })
            .reduce(|a, b| if a.0 > b.0 { a } else { b })
    }

    #[test]
    fn follow_draws_real_data_past_the_right_edge() {
        let _lang = crate::i18n::lang_lock();
        let mut s = session("regular", "sim:muse", 120.0);
        let (f, _) = run(&mut s, egui::vec2(1100.0, 700.0), &idle(4));
        let (x, clip) = right_edge(&f, HR_COLOR).expect("HR line");
        assert!(x > clip, "HR enters from off-screen: {x} vs {clip}");
        // The waveform sweeps (cursor moves, no scrolling to the edge):
        // its trace stays inside the plot.
        let (x, clip) = right_edge(&f, IR_COLOR).expect("IR trace");
        assert!(x <= clip, "{x} vs {clip}");
    }

    #[test]
    fn dragging_the_selection_moves_the_waveform_window() {
        let _lang = crate::i18n::lang_lock();
        let mut s = session("regular", "sim:muse", 200.0);
        s.call("monitor.viewport", json!({ "monitor": "heart_detail", "window_s": 30.0 })).unwrap();
        let (_, _) = run(&mut s, egui::vec2(1100.0, 700.0), &idle(2));
        // Re-run to read the shade rect from a fresh context.
        let ctx_shade = {
            let ctx = egui::Context::default();
            for i in 0..2 {
                let input = egui::RawInput {
                    screen_rect: Some(Rect::from_min_size(Pos2::ZERO, egui::vec2(1100.0, 700.0))),
                    time: Some(f64::from(i) / 60.0),
                    ..Default::default()
                };
                ctx.run_ui(input, |u| {
                    crate::ui::show(u, &s, None);
                })
                .textures_delta
                .clear();
            }
            ctx.data(|d| d.get_temp::<Rect>(overview::shade_id(MonitorId::HeartOverview))).unwrap()
        };
        let p = ctx_shade.center();
        let btn = |pos, pressed| egui::Event::PointerButton {
            pos,
            button: egui::PointerButton::Primary,
            pressed,
            modifiers: egui::Modifiers::NONE,
        };
        let frames = vec![
            vec![],
            vec![],
            vec![egui::Event::PointerMoved(p), btn(p, true)],
            vec![egui::Event::PointerMoved(p + egui::vec2(-40.0, 0.0))],
            vec![egui::Event::PointerMoved(p + egui::vec2(-80.0, 0.0))],
            vec![btn(p + egui::vec2(-80.0, 0.0), false)],
        ];
        let before = s.state().monitors.viewport(MonitorId::HeartDetail);
        let (_, cmds) = run(&mut s, egui::vec2(1100.0, 700.0), &frames);
        let after = s.state().monitors.viewport(MonitorId::HeartDetail);
        assert!(before.following() && !after.following(), "{cmds:?}");
        assert!(
            cmds.iter().any(|c| matches!(c, Command::MonitorPan { monitor: MonitorId::HeartDetail, seconds } if *seconds < 0.0)),
            "{cmds:?}"
        );
    }

    #[test]
    fn toggle_click_sends_the_waveform_command() {
        let _lang = crate::i18n::lang_lock();
        let mut s = session("regular", "sim:muse", 30.0);
        let ctx = egui::Context::default();
        let mut toggle = None;
        for i in 0..2 {
            let input = egui::RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, egui::vec2(1100.0, 700.0))),
                time: Some(f64::from(i) / 60.0),
                ..Default::default()
            };
            let mut o = ctx.run_ui(input, |u| {
                crate::ui::show(u, &s, None);
            });
            o.textures_delta.clear();
            for c in &o.shapes {
                if let egui::Shape::Text(t) = &c.shape {
                    if t.galley.text() == "Pulse waveform" {
                        toggle = Some(t.visual_bounding_rect().center());
                    }
                }
            }
        }
        let p = toggle.expect("toggle label");
        let btn = |pressed| egui::Event::PointerButton {
            pos: p,
            button: egui::PointerButton::Primary,
            pressed,
            modifiers: egui::Modifiers::NONE,
        };
        let (_, cmds) =
            run(&mut s, egui::vec2(1100.0, 700.0), &[vec![], vec![egui::Event::PointerMoved(p), btn(true)], vec![btn(false)], vec![]]);
        assert!(cmds.iter().any(|c| matches!(c, Command::MonitorHeart { waveform: Some(false) })), "{cmds:?}");
        assert!(!s.state().monitors.heart.waveform);
    }
}
