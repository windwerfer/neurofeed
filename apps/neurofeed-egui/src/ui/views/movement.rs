//! Movement (IMU): accelerometer x / y / z and the dynamic |a| − 1 g, one
//! pane per shown trace on the shared monitor chrome: Follow | Inspect and
//! window menu (core viewport `movement`, 15 s … 5 min), drag / pinch /
//! wheel input, the trace selector, the Y range (± g) and the optional
//! overview timeline (off by default). Traces use the shared min/max
//! decimation of `nf_core::rawtrace`; a dropout breaks the line and is
//! shaded. The side ring keeps 5 min (`nf_core::side::ACCEL_S`).

use super::raw::{pane_height, time_grid, RIGHT_GUTTER, X_GUTTER};
use crate::ui::layout::{self, Layout};
use crate::ui::{monitor, theme};
use egui::{Align2, FontId, Pos2, Rect, Sense, Stroke, Ui, Vec2};
use nf_core::monitor::{MonitorId, MoveRange, MoveTrace, Viewport};
use nf_core::rawtrace::{self as rt, Mapping};
use nf_core::side::Side;
use nf_core::{AppState, Command, Session};

/// Longer than this without a sample is a dropout (the IMU runs at ≥ 50 Hz).
pub(crate) const GAP_S: f64 = 0.25;

const MIN_PANE_REGULAR: f32 = 96.0;
const MIN_PANE_COMPACT: f32 = 84.0;
const MIN_PANE_IMMERSIVE: f32 = 64.0;

/// Dropouts inside `[t0, t1]` for samples at `times` (ascending): the
/// holes between samples, plus a trailing one from the newest sample up to
/// `t1` while data is not arriving.
pub(crate) fn gaps(times: impl Iterator<Item = f64>, t0: f64, t1: f64) -> Vec<(f64, f64)> {
    let mut out = Vec::new();
    let mut prev: Option<f64> = None;
    for t in times {
        if let Some(p) = prev.filter(|p| t - p > GAP_S) {
            out.push((p.max(t0), t.min(t1)));
        }
        prev = Some(t);
    }
    if let Some(p) = prev.filter(|p| t1 - p > GAP_S) {
        out.push((p.max(t0), t1));
    }
    out
}

/// Samples with time in `[t0, t1]` (binary search: bounded by the window,
/// not by the 5 min ring).
fn window(side: &Side, t0: f64, t1: f64) -> impl Iterator<Item = &(f64, [f32; 3])> {
    let from = side.accel.partition_point(|a| a.0 < t0);
    side.accel.range(from..).take_while(move |a| a.0 <= t1)
}

/// One trace as `Some((t, g))` samples with `None` at every dropout so the
/// line breaks there.
fn samples(side: &Side, trace: MoveTrace, t0: f64, t1: f64) -> impl Iterator<Item = Option<(f64, f32)>> + '_ {
    let mut prev: Option<f64> = None;
    window(side, t0, t1).flat_map(move |(t, a)| {
        let broke = prev.is_some_and(|p| t - p > GAP_S);
        prev = Some(*t);
        broke.then_some(None).into_iter().chain(std::iter::once(Some((*t, trace.value(*a)))))
    })
}

/// Everything one frame draws, copied from the state.
struct Frame<'a> {
    side: &'a Side,
    traces: Vec<MoveTrace>,
    range_g: f32,
    map: Mapping,
    gaps: Vec<(f64, f64)>,
}

pub fn show(ui: &mut Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    let id = MonitorId::Movement;
    let vp = state.monitors.viewport(id);
    let side = session.side().filter(|s| s.accel_rate.is_some());
    let span = side.map(|_| session.monitor_span_of(id));
    toolbar(ui, state, vp, span, out);
    let (Some(side), Some(span)) = (side, span) else {
        ui.label(if state.device.is_some() {
            t!("movement-this-device-sends-no-accelerometer")
        } else {
            t!("movement-no-device-connected-use-connect")
        });
        return;
    };
    if side.accel.is_empty() {
        ui.label(t!("movement-waiting"));
        return;
    }
    let range = monitor::presented_range_lead(ui, state, id, vp, span, rt::RAW_FOLLOW_LEAD_S);
    let frame = Frame {
        side,
        traces: state.monitors.movement.shown(),
        range_g: state.monitors.movement.range.half_g(),
        map: Mapping::Scroll { start: range.0, end: range.1 },
        gaps: gaps(window(side, range.0, range.1).map(|a| a.0), range.0, range.1),
    };
    let ov_h = crate::ui::overview::height(ui, state, id, ui.available_height());
    let main = egui::vec2(ui.available_width(), ui.available_height() - ov_h);
    ui.allocate_ui_with_layout(main, egui::Layout::top_down(egui::Align::Min), |ui| {
        ui.set_min_size(main);
        stack(ui, &frame, vp, out);
    });
    if ov_h > 0.0 {
        overview(ui, state, id, span, range, vp, ov_h, out);
    }
}

/// Bands history minimap; the shade is the movement window, detail only
/// inside the 5 min ring.
#[allow(clippy::too_many_arguments)]
fn overview(
    ui: &mut Ui,
    state: &AppState,
    id: MonitorId,
    span: nf_core::monitor::Span,
    range: (f64, f64),
    vp: Viewport,
    h: f32,
    out: &mut Vec<Command>,
) {
    let channels = state.device.as_ref().map(|d| d.channels.clone()).unwrap_or_default();
    let chans = state.analysis.eligible_of(&channels, &state.monitors.bands.selected(&channels));
    let host = crate::ui::overview::Host {
        id,
        range: (range.1 - vp.window_s, range.1),
        detail_oldest: span.oldest_s,
        no_detail: t!("overview-no-movement"),
    };
    crate::ui::overview::show(ui, state, &chans, &host, h, out);
}

fn toolbar(ui: &mut Ui, state: &AppState, vp: Viewport, span: Option<nf_core::monitor::Span>, out: &mut Vec<Command>) {
    let id = MonitorId::Movement;
    monitor::toolbar(ui, state, id, out, |ui, out| {
        if let Some(span) = span {
            monitor::inspect_label(ui, vp, span);
        }
        trace_selector(ui, state, out);
        ui.add_space(8.0);
        range_menu(ui, state.monitors.movement.range, out);
        ui.add_space(8.0);
        crate::ui::overview::toggle(ui, state, id, out);
    });
}

fn trace_selector(ui: &mut Ui, state: &AppState, out: &mut Vec<Command>) {
    let names: Vec<String> = MoveTrace::ALL.iter().map(|t| t.label().to_owned()).collect();
    let shown = state.monitors.movement.shown();
    let sel: Vec<usize> = MoveTrace::ALL.iter().enumerate().filter(|(_, t)| shown.contains(t)).map(|(i, _)| i).collect();
    // The names are never analysis channels, so no exclusion marks apply.
    let none = nf_core::analysis::Analysis::default();
    monitor::channel_selector(ui, &names, &sel, &none, false, out, |picked| Command::MonitorMovement {
        traces: Some(MoveTrace::ALL.into_iter().filter(|t| picked.iter().any(|n| n == t.label())).collect()),
        range_g: None,
    });
}

fn range_label(r: MoveRange) -> String {
    t!("movement-range-label", g = format!("{}", r.half_g()))
}

fn range_menu(ui: &mut Ui, cur: MoveRange, out: &mut Vec<Command>) {
    egui::ComboBox::from_id_salt("nf_movement_range")
        .selected_text(range_label(cur))
        .width(78.0)
        .show_ui(ui, |ui| {
            for r in MoveRange::ALL {
                if ui.selectable_label(cur == r, range_label(r)).clicked() && cur != r {
                    out.push(Command::MonitorMovement { traces: None, range_g: Some(r) });
                }
            }
        })
        .response
        .on_hover_text(format!("{}\n{}", t!("movement-range-hint"), t!("movement-axis-caption")));
}

fn min_pane(ui: &Ui) -> f32 {
    match layout::current(ui.ctx()) {
        Layout::Regular => MIN_PANE_REGULAR,
        Layout::Compact => MIN_PANE_COMPACT,
        Layout::Immersive => MIN_PANE_IMMERSIVE,
    }
}

fn stack(ui: &mut Ui, frame: &Frame<'_>, vp: Viewport, out: &mut Vec<Command>) {
    let (h, scrolls) = pane_height(ui.available_height(), frame.traces.len(), min_pane(ui));
    let width = ui.available_width();
    egui::ScrollArea::vertical().id_salt("nf_movement_panes").auto_shrink([false, false]).show(ui, |ui| {
        ui.spacing_mut().item_spacing.y = 0.0;
        for (i, trace) in frame.traces.iter().enumerate() {
            let last = i + 1 == frame.traces.len();
            let size = Vec2::new(width, h + if last { X_GUTTER } else { 0.0 });
            let (rect, resp) = ui.allocate_exact_size(size, Sense::click_and_drag());
            let plot = Rect::from_min_max(
                rect.left_top() + Vec2::new(4.0, 4.0),
                rect.right_bottom() - Vec2::new(RIGHT_GUTTER, if last { X_GUTTER + 2.0 } else { 4.0 }),
            );
            monitor::interact_with(ui, &resp, plot, MonitorId::Movement, vp, out, scrolls);
            if ui.is_rect_visible(rect) {
                draw_pane(ui, frame, *trace, plot, last);
            }
        }
    });
}

fn draw_pane(ui: &Ui, frame: &Frame<'_>, trace: MoveTrace, plot: Rect, last: bool) {
    let v = ui.visuals().clone();
    let p = ui.painter_at(plot.expand2(Vec2::new(RIGHT_GUTTER, X_GUTTER)));
    let x_px = |x: f32| plot.left() + x * plot.width();
    let Mapping::Scroll { start, end } = frame.map else { return };
    for &(g0, g1) in &frame.gaps {
        let fx = |t: f64| x_px((((t - start) / (end - start).max(1e-9)) as f32).clamp(0.0, 1.0));
        p.rect_filled(Rect::from_x_y_ranges(fx(g0)..=fx(g1), plot.y_range()), 0.0, theme::GAP_SHADE);
    }
    p.line_segment([plot.left_center(), plot.right_center()], theme::grid(&v));
    time_grid(&p, plot, frame.map, &v, last);
    let half = frame.range_g;
    let y_px = |g: f32| plot.center().y - (g / half).clamp(-1.0, 1.0) * plot.height() / 2.0;
    let rate = frame.side.accel_rate.unwrap_or(50.0);
    let pts = rt::trace_samples(samples(frame.side, trace, start, end), rate, frame.map, plot.width().max(1.0) as usize);
    let stroke = Stroke::new(1.3, theme::movement_trace(&v, trace));
    for run in &pts.runs {
        let line: Vec<Pos2> = run.iter().map(|q| Pos2::new(x_px(q[0]), y_px(q[1]))).collect();
        p.add(egui::Shape::line(line, stroke));
        for q in run.iter().filter(|q| q[1].abs() > half) {
            p.circle_filled(Pos2::new(x_px(q[0]), y_px(q[1])), 1.6, theme::CLIPPED);
        }
    }
    gutter(&p, &v, plot, half, trace);
}

fn gutter(p: &egui::Painter, v: &egui::Visuals, plot: Rect, half: f32, trace: MoveTrace) {
    let gx = plot.right() + 6.0;
    let font = FontId::proportional(10.0);
    p.text(Pos2::new(gx, plot.top()), Align2::LEFT_TOP, format!("{half}"), font.clone(), theme::axis_text(v));
    p.text(Pos2::new(gx, plot.center().y), Align2::LEFT_CENTER, "0 g", font.clone(), theme::axis_text(v));
    p.text(Pos2::new(gx, plot.bottom()), Align2::LEFT_BOTTOM, format!("-{half}"), font, theme::axis_text(v));
    p.text(
        Pos2::new(plot.right() - 4.0, plot.top() + 2.0),
        Align2::RIGHT_TOP,
        trace.label(),
        FontId::proportional(13.0),
        theme::movement_trace(v, trace),
    );
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::panic)]
    use super::*;
    use serde_json::json;

    #[test]
    fn gaps_find_holes_and_a_trailing_dropout() {
        // 50 Hz for 1 s, a 2 s hole, 50 Hz for 1 s, then nothing until t1 = 6.
        let times: Vec<f64> = (0..50).map(|i| f64::from(i) / 50.0).chain((0..50).map(|i| 3.0 + f64::from(i) / 50.0)).collect();
        let g = gaps(times.iter().copied(), 0.0, 6.0);
        assert_eq!(g.len(), 2, "{g:?}");
        assert!((g[0].0 - 0.98).abs() < 1e-9 && (g[0].1 - 3.0).abs() < 1e-9);
        assert!((g[1].0 - 3.98).abs() < 1e-9 && g[1].1 == 6.0);
        // Healthy data up to the right edge: no gap; no samples: none either.
        assert!(gaps((0..300).map(|i| f64::from(i) / 50.0), 0.0, 5.99).is_empty());
        assert!(gaps(std::iter::empty(), 0.0, 5.0).is_empty());
    }

    #[test]
    fn samples_break_the_line_at_a_dropout_and_stay_in_the_window() {
        let mut dev = Session::new();
        dev.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
        let info = dev.state().device.clone().unwrap();
        let mut side = Side::new(&nf_core::DeviceInfo { accel_rate_hz: Some(50.0), ..info });
        // 0.0 .. 0.18 and 5.0 .. 5.18 at 50 Hz: a 4.8 s hole between.
        for t0 in [0.0, 5.0] {
            (0..10).for_each(|i| side.accel.push_back((t0 + f64::from(i) / 50.0, [0.0, 0.0, 1.0])));
        }
        let all: Vec<_> = samples(&side, MoveTrace::Z, 0.0, 10.0).collect();
        assert_eq!(all.iter().filter(|s| s.is_none()).count(), 1);
        assert_eq!(all.len(), 21);
        let late: Vec<_> = samples(&side, MoveTrace::Z, 4.0, 10.0).flatten().collect();
        assert!(late.len() == 10 && late.iter().all(|(t, g)| *t >= 5.0 && *g == 1.0), "{late:?}");
        assert_eq!(samples(&side, MoveTrace::X, 20.0, 30.0).count(), 0);
    }

    fn render(layout: &str, size: Vec2, extra: &[(&str, serde_json::Value)]) -> Vec<String> {
        let _lang = crate::i18n::lang_lock();
        let mut s = Session::new();
        s.call("settings.set", json!({ "onboarded": true, "layout": layout })).unwrap();
        s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
        s.call("view.set", json!({ "view": "movement" })).unwrap();
        s.call("clock.advance", json!({ "seconds": 90.0 })).unwrap();
        for (id, p) in extra {
            s.call(id, p.clone()).unwrap();
        }
        let ctx = egui::Context::default();
        let mut shapes = Vec::new();
        for i in 0..3 {
            let input = egui::RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, size)),
                time: Some(f64::from(i) / 60.0),
                ..Default::default()
            };
            let mut o = ctx.run_ui(input, |u| {
                crate::ui::show(u, &s, None);
            });
            o.textures_delta.clear();
            shapes = o.shapes;
        }
        shapes.iter().filter_map(|c| if let egui::Shape::Text(t) = &c.shape { Some(t.galley.text().to_owned()) } else { None }).collect()
    }

    #[test]
    fn regular_draws_toolbar_four_panes_and_range_labels() {
        let texts = render("regular", Vec2::new(1200.0, 800.0), &[]);
        for want in ["Follow", "Inspect", "±1.5 g", "|a| − 1 g", "0 g", "1.5", "-1.5"] {
            assert!(texts.iter().any(|t| t == want || t.contains(want)), "{want} in {texts:?}");
        }
        assert!(texts.iter().any(|t| t == "x") && texts.iter().any(|t| t == "y") && texts.iter().any(|t| t == "z"));
        assert!(!texts.iter().any(|t| t == &t!("overview-toggle")) || texts.contains(&t!("overview-toggle")), "toggle present");
    }

    #[test]
    fn trace_choice_and_range_change_what_is_drawn() {
        let texts =
            render("regular", Vec2::new(1200.0, 800.0), &[("monitor.movement", json!({ "traces": ["magnitude"], "range_g": "6" }))]);
        assert!(texts.iter().any(|t| t == "-6"), "{texts:?}");
        // Pane titles are the only "x"/"y"/"z" texts that are not chips: with one trace shown none is a pane.
        assert_eq!(texts.iter().filter(|t| *t == "|a| − 1 g").count(), 2, "chip + pane title: {texts:?}");
    }

    #[test]
    fn compact_and_phone_landscape_render_and_landscape_has_no_chrome() {
        let compact = render("compact", Vec2::new(400.0, 850.0), &[]);
        assert!(compact.iter().any(|t| t == "0 g"));
        let land = render("compact", Vec2::new(860.0, 400.0), &[]);
        assert!(land.iter().any(|t| t == "0 g"));
        assert!(!land.iter().any(|t| t == "Follow"), "graph-only landscape: {land:?}");
    }

    #[test]
    fn overview_is_off_by_default_and_draws_when_toggled_on() {
        let off = render("regular", Vec2::new(1200.0, 800.0), &[]);
        let on = render("regular", Vec2::new(1200.0, 800.0), &[("monitor.overview", json!({ "monitor": "movement", "on": true }))]);
        let rows = |t: &[String]| t.iter().filter(|s| s.contains(':')).count();
        assert!(rows(&on) > rows(&off), "overview adds its own time axis: {} vs {}", rows(&on), rows(&off));
    }

    #[test]
    fn no_accelerometer_and_no_device_have_their_own_message() {
        let _lang = crate::i18n::lang_lock();
        let mut s = Session::new();
        s.call("settings.set", json!({ "onboarded": true, "layout": "regular" })).unwrap();
        s.call("view.set", json!({ "view": "movement" })).unwrap();
        let ctx = egui::Context::default();
        let input = egui::RawInput { screen_rect: Some(Rect::from_min_size(Pos2::ZERO, Vec2::new(900.0, 600.0))), ..Default::default() };
        let mut o = ctx.run_ui(input, |u| {
            crate::ui::show(u, &s, None);
        });
        o.textures_delta.clear();
        let texts: Vec<String> = o
            .shapes
            .iter()
            .filter_map(|c| if let egui::Shape::Text(t) = &c.shape { Some(t.galley.text().to_owned()) } else { None })
            .collect();
        assert!(texts.contains(&t!("movement-no-device-connected-use-connect")), "{texts:?}");
    }

    /// Axis labels are always `m:ss` (never `0.05`), in every layout; only the
    /// tick spacing differs with the width (5 s regular, 10 s compact).
    #[test]
    fn time_axis_labels_are_m_ss_in_every_layout() {
        let is_mss = |t: &str| {
            t.split_once(':').is_some_and(|(m, s)| !m.is_empty() && s.len() == 2 && m.bytes().chain(s.bytes()).all(|b| b.is_ascii_digit()))
        };
        for (layout, size) in [("regular", Vec2::new(1200.0, 800.0)), ("compact", Vec2::new(400.0, 850.0))] {
            let texts = render(layout, size, &[]);
            let axis: Vec<&String> = texts.iter().filter(|t| t.contains(':') && !t.contains(' ')).collect();
            assert!(axis.len() >= 3, "{layout}: {texts:?}");
            assert!(axis.iter().all(|t| is_mss(t)), "{layout}: {axis:?}");
            assert!(!texts.iter().any(|t| t.len() <= 4 && t.starts_with("0.")), "{layout}: no 0.05-style labels: {texts:?}");
        }
        assert_eq!(nf_core::rawtrace::elapsed_label(5.0, 5.0), "0:05");
        assert_eq!(nf_core::rawtrace::elapsed_label(125.0, 5.0), "2:05");
    }
}
