//! Shared monitor chrome and plot input, used by every live graph screen
//! (regular and compact alike; immersive phone landscape hides the chrome).
//!
//! - [`toolbar`]: the single toolbar row (Follow | Inspect, window, extras),
//!   horizontally scrollable when it overflows.
//! - [`interact`]: plot gestures → `monitor.*` commands: drag pans (enters
//!   Inspect), pinch or Ctrl/Cmd+wheel zooms around the pointer, the wheel
//!   pans, double-click returns to Follow.
//! - [`time_grid`]: elapsed `m:ss` ticks with vertical grid lines.
//!
//! The viewport state machine lives in `nf_core::monitor`; this module only
//! turns input into commands and draws.

use super::layout::{self, Layout, TOUCH};
use super::theme;
use egui::{Align2, FontId, Pos2, Rect, Response, Ui};
use nf_core::monitor::{self as m, MonitorId, Viewport, ViewportMode};
use nf_core::{AppState, Command};

/// Smallest zoom step sent as a command (ignore jitter).
const ZOOM_EPS: f32 = 1e-3;
/// Wheel points that pan one full window.
const WHEEL_PER_WINDOW: f32 = 600.0;

/// Chrome is hidden (phone landscape).
pub fn immersive(ui: &Ui) -> bool {
    layout::current(ui.ctx()) == Layout::Immersive
}

/// Short window label: `30s`, `2m`, `1m30s`.
pub fn window_label(s: f64) -> String {
    let s = if s.is_finite() { s.max(0.0) } else { 0.0 };
    if s < 60.0 {
        if (s - s.round()).abs() < 0.05 {
            format!("{s:.0}s")
        } else {
            format!("{s:.1}s")
        }
    } else {
        let whole = s.round() as u64;
        match whole % 60 {
            0 => format!("{}m", whole / 60),
            r => format!("{}m{r:02}s", whole / 60),
        }
    }
}

/// The monitor toolbar: one row, scrolls sideways when it does not fit.
/// `extras` adds the screen's own controls after the window menu.
pub fn toolbar(ui: &mut Ui, state: &AppState, id: MonitorId, out: &mut Vec<Command>, extras: impl FnOnce(&mut Ui, &mut Vec<Command>)) {
    if immersive(ui) {
        return;
    }
    let h = if layout::current(ui.ctx()).is_compact() { TOUCH } else { theme::MONITOR_TOOLBAR };
    let vp = state.monitors.viewport(id);
    let row = egui::vec2(ui.available_width(), h);
    ui.allocate_ui_with_layout(row, egui::Layout::left_to_right(egui::Align::Center), |ui| {
        egui::ScrollArea::horizontal()
            .id_salt(("nf_monitor_toolbar", id.name()))
            .scroll_bar_visibility(egui::scroll_area::ScrollBarVisibility::AlwaysHidden)
            .show(ui, |ui| {
                ui.set_height(h);
                ui.horizontal_centered(|ui| {
                    follow_inspect(ui, id, vp, out);
                    ui.add_space(8.0);
                    window_menu(ui, id, vp, out);
                    ui.add_space(8.0);
                    extras(ui, out);
                });
            });
    });
    ui.separator();
}

fn follow_inspect(ui: &mut Ui, id: MonitorId, vp: Viewport, out: &mut Vec<Command>) {
    ui.spacing_mut().item_spacing.x = 0.0;
    if ui.selectable_label(vp.following(), t!("monitor-follow")).on_hover_text(t!("monitor-follow-hint")).clicked() && !vp.following() {
        out.push(Command::MonitorViewport { monitor: id, window_s: None, mode: Some(ViewportMode::Follow), end_s: None });
    }
    if ui.selectable_label(!vp.following(), t!("monitor-inspect")).on_hover_text(t!("monitor-inspect-hint")).clicked() && vp.following() {
        let end_s = presented_end(ui, id, vp);
        out.push(Command::MonitorViewport { monitor: id, window_s: None, mode: Some(ViewportMode::Inspect), end_s });
    }
}

fn window_menu(ui: &mut Ui, id: MonitorId, vp: Viewport, out: &mut Vec<Command>) {
    let spec = id.spec();
    let preset = spec.presets.iter().any(|p| (p - vp.window_s).abs() < 1e-6);
    let text = if preset { window_label(vp.window_s) } else { t!("monitor-custom", s = window_label(vp.window_s)) };
    egui::ComboBox::from_id_salt(("nf_window", id.name()))
        .selected_text(text)
        .width(64.0)
        .show_ui(ui, |ui| {
            for &p in spec.presets {
                if ui.selectable_label((p - vp.window_s).abs() < 1e-6, window_label(p)).clicked() {
                    out.push(Command::MonitorViewport { monitor: id, window_s: Some(p), mode: None, end_s: None });
                }
            }
        })
        .response
        .on_hover_text(t!("monitor-window-hint"));
}

fn follow_id(id: MonitorId) -> egui::Id {
    egui::Id::unique(("nf_follow_clock", id.name()))
}

/// The live stream is advancing (connected, streaming, not paused).
pub fn live(state: &AppState) -> bool {
    !state.paused && matches!(state.link, Some(nf_core::LinkState::Streaming))
}

/// Visible `(start, end)` as drawn. Follow while live: the right edge glides
/// with presentation time ([`m::FollowClock`], ~1 s behind the newest
/// snapshot) and the next frame is requested. Otherwise the core range.
pub fn presented_range(ui: &Ui, state: &AppState, id: MonitorId, vp: Viewport, span: m::Span) -> (f64, f64) {
    presented_range_lead(ui, state, id, vp, span, m::FOLLOW_LEAD_S)
}

/// [`presented_range`] with the Follow lead (seconds behind the newest data).
pub fn presented_range_lead(ui: &Ui, state: &AppState, id: MonitorId, vp: Viewport, span: m::Span, lead_s: f64) -> (f64, f64) {
    let ctx = ui.ctx();
    if !vp.following() || !live(state) {
        ctx.data_mut(|d| d.remove::<m::FollowClock>(follow_id(id)));
        return vp.range(span);
    }
    let now = ui.input(|i| i.time);
    let mut clock = ctx.data_mut(|d| d.get_temp::<m::FollowClock>(follow_id(id))).unwrap_or_default();
    let end = clock.end(span.newest_s, now, lead_s);
    ctx.data_mut(|d| d.insert_temp(follow_id(id), clock));
    ctx.data_mut(|d| d.insert_temp(follow_id(id).with("end"), end));
    ctx.request_repaint(); // vsync-paced, only while live + Follow
    (end - vp.window_s, end)
}

/// The glide's current right edge, when Follow is gliding.
fn presented_end(ui: &Ui, id: MonitorId, vp: Viewport) -> Option<f64> {
    if !vp.following() {
        return None;
    }
    ui.ctx().data(|d| d.get_temp::<m::FollowClock>(follow_id(id)).and(d.get_temp::<f64>(follow_id(id).with("end"))))
}

/// Leaving Follow freezes where the user sees the graph, not 1 s later.
fn freeze_at_presented(ui: &Ui, id: MonitorId, vp: Viewport, out: &mut Vec<Command>) {
    if let Some(end) = presented_end(ui, id, vp) {
        out.push(Command::MonitorViewport { monitor: id, window_s: None, mode: Some(ViewportMode::Inspect), end_s: Some(end) });
    }
}

/// Map plot input on `resp` (covering `plot`) to viewport commands.
pub fn interact(ui: &Ui, resp: &Response, plot: Rect, id: MonitorId, vp: Viewport, out: &mut Vec<Command>) {
    interact_with(ui, resp, plot, id, vp, out, false);
}

/// [`interact`] for plots inside a vertical scroll list (`in_list`, Raw
/// EEG's stacked panes): the plain vertical wheel and vertical drags scroll
/// the list instead of panning; sideways wheel / drag still pan.
pub fn interact_with(ui: &Ui, resp: &Response, plot: Rect, id: MonitorId, vp: Viewport, out: &mut Vec<Command>, in_list: bool) {
    if plot.width() <= 1.0 {
        return;
    }
    let w = f64::from(plot.width());
    let (zoom, touch_center, scroll) = ui.input(|i| (i.zoom_delta(), i.multi_touch().map(|t| t.center_pos), i.smooth_scroll_delta()));
    let over = resp.contains_pointer() || touch_center.is_some_and(|c| plot.contains(c));
    if over && (zoom - 1.0).abs() > ZOOM_EPS {
        let at = touch_center.or_else(|| resp.hover_pos()).unwrap_or(plot.right_center());
        let focal = f64::from((at.x - plot.left()) / plot.width()).clamp(0.0, 1.0);
        if focal < 0.999 {
            freeze_at_presented(ui, id, vp, out);
        }
        out.push(Command::MonitorZoom { monitor: id, factor: f64::from(zoom), focal: Some(focal) });
        return;
    }
    if resp.double_clicked() && !vp.following() {
        out.push(Command::MonitorViewport { monitor: id, window_s: None, mode: Some(ViewportMode::Follow), end_s: None });
        return;
    }
    let drag = resp.drag_delta();
    if in_list && drag.y.abs() > drag.x.abs() {
        ui.scroll_with_delta(egui::vec2(0.0, drag.y));
        return;
    }
    let dx = drag.x;
    if touch_center.is_none() && dx != 0.0 {
        freeze_at_presented(ui, id, vp, out);
        out.push(Command::MonitorPan { monitor: id, seconds: -f64::from(dx) / w * vp.window_s });
        return;
    }
    // Wheel: sideways always pans; vertical pans once inspecting.
    let wheel = if vp.following() || in_list { scroll.x } else { scroll.x + scroll.y };
    if resp.contains_pointer() && wheel.abs() > 0.5 {
        freeze_at_presented(ui, id, vp, out);
        out.push(Command::MonitorPan { monitor: id, seconds: -f64::from(wheel / WHEEL_PER_WINDOW) * vp.window_s });
    }
}

/// Electrode chips (at least one stays on); `apply` turns the chosen names
/// (empty = all) into the screen's command. Names come from the device.
pub fn electrode_chips(
    ui: &mut Ui,
    channels: &[String],
    selected: &[usize],
    hint: &str,
    out: &mut Vec<Command>,
    apply: impl Fn(Vec<String>) -> Command,
) {
    ui.spacing_mut().item_spacing.x = 2.0;
    for (i, name) in channels.iter().enumerate() {
        let on = selected.contains(&i);
        if ui.selectable_label(on, name).on_hover_text(hint).clicked() {
            let mut next: Vec<usize> = selected.iter().copied().filter(|&c| c != i).collect();
            if !on {
                next.push(i);
            }
            if next.is_empty() {
                continue;
            }
            let names = if next.len() == channels.len() {
                Vec::new()
            } else {
                channels.iter().enumerate().filter(|(c, _)| next.contains(c)).map(|(_, n)| n.clone()).collect()
            };
            out.push(apply(names));
        }
    }
    ui.spacing_mut().item_spacing.x = 8.0;
}

/// `start–end` while inspecting.
pub fn inspect_label(ui: &mut Ui, vp: Viewport, span: m::Span) {
    if !vp.following() {
        let (a, b) = vp.range(span);
        ui.weak(format!("{}–{}", m::mmss(a), m::mmss(b)));
        ui.add_space(8.0);
    }
}

/// x of session time `t` inside `plot` for the visible `(start, end)`.
pub fn x_of(plot: Rect, (start, end): (f64, f64), t: f64) -> f32 {
    let span = (end - start).max(1e-9);
    plot.left() + (((t - start) / span) as f32) * plot.width()
}

/// Vertical grid lines and `m:ss` labels below `plot` for `(start, end)`.
pub fn time_grid(p: &egui::Painter, plot: Rect, range: (f64, f64), v: &egui::Visuals) {
    let (start, end) = range;
    let target = ((plot.width() / 110.0).floor() as usize).clamp(2, 10);
    let step = m::tick_step_s(end - start, target);
    let mut t = (start / step).ceil() * step;
    let mut n = 0;
    while t <= end && n < 64 {
        let x = x_of(plot, range, t);
        p.line_segment([Pos2::new(x, plot.top()), Pos2::new(x, plot.bottom())], theme::grid(v));
        p.text(Pos2::new(x, plot.bottom() + 3.0), Align2::CENTER_TOP, m::mmss(t), FontId::proportional(10.0), theme::axis_text(v));
        t += step;
        n += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn window_labels() {
        assert_eq!(window_label(30.0), "30s");
        assert_eq!(window_label(120.0), "2m");
        assert_eq!(window_label(90.0), "1m30s");
        assert_eq!(window_label(7.5), "7.5s");
        assert_eq!(window_label(f64::NAN), "0s");
    }

    #[test]
    fn x_mapping() {
        let r = Rect::from_min_max(Pos2::new(10.0, 0.0), Pos2::new(110.0, 10.0));
        assert_eq!(x_of(r, (0.0, 10.0), 5.0), 60.0);
        assert_eq!(x_of(r, (0.0, 0.0), 0.0), 10.0);
    }
}
