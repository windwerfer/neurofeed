//! Optics monitor: stacked Athena optical lanes (raw ADC counts), using the
//! same sweep / Follow / Inspect infrastructure as Raw EEG. Overview off by
//! default. Y is auto-scaled per lane (ambient and IR differ by orders of
//! magnitude). Labels are lane names, not wavelengths.

use crate::ui::layout::{self, Layout};
use crate::ui::views::raw::{self, pane_height};
use crate::ui::{monitor, theme};
use egui::{Align2, FontId, Pos2, Rect, Sense, Stroke, Ui, Vec2};
use nf_core::monitor::{MonitorId, RawMode, Viewport};
use nf_core::rawtrace::{self as rt, Channel, Mapping};
use nf_core::{AppState, Command, Session};

const X_GUTTER: f32 = 18.0;
const RIGHT_GUTTER: f32 = 52.0;
const AUTO_REFIT_S: f64 = 0.25;

struct Pane {
    name: String,
    end_t: f64,
    rate: f64,
    values: Vec<f32>,
    mid: f32,
    half: f32,
}

impl Pane {
    fn channel(&self) -> Channel<'_> {
        Channel { end_t: self.end_t, rate: self.rate, values: &self.values, flags: &[] }
    }
}

pub fn show(ui: &mut Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    let id = MonitorId::Optics;
    let vp = state.monitors.viewport(id);
    let live = session.live_optical();
    let lanes: Vec<String> = live.map(|(d, _)| d.optics_channels.clone()).unwrap_or_default();
    let span = live.and_then(|(_, sig)| sig.time).map(|t| rt::raw_span(t, state.monitors.optics.mode, vp.window_s));
    monitor::toolbar(ui, state, id, out, |ui, out| {
        if let Some(span) = span {
            monitor::inspect_label(ui, vp, span);
        }
        mode_toggle(ui, state, out);
        ui.add_space(8.0);
        let sel = state.monitors.optics.selected(&lanes);
        monitor::channel_selector(ui, &lanes, &sel, &state.analysis, false, out, |names| Command::MonitorOptics {
            mode: None,
            lanes: Some(names),
        });
        ui.add_space(8.0);
        if let Some((dev, _)) = live {
            if let Some(p) = dev.optics_preset.as_deref() {
                ui.weak(t!("optics-preset", preset = p));
            }
        }
        ui.add_space(8.0);
        crate::ui::overview::toggle(ui, state, id, out);
    });
    let (Some((dev, sig)), Some(span)) = (live, span) else {
        ui.label(if live.is_none() {
            if state.device.is_some() {
                t!("optics-no-athena")
            } else {
                t!("plot-no-device-connected-use-connect")
            }
        } else {
            t!("optics-waiting-for-data")
        });
        return;
    };
    let range = monitor::presented_range_lead(ui, state, id, vp, span, rt::RAW_FOLLOW_LEAD_S);
    let rate = sig.rate.max(1.0);
    let need = (((range.1 - range.0).max(0.0) + 1.0) * rate).ceil() as usize;
    let panes: Vec<Pane> = state
        .monitors
        .optics
        .selected(&dev.optics_channels)
        .into_iter()
        .map(|ch| {
            let ch_t = sig.channel_time(ch).unwrap_or(span.newest_s);
            let skip = ((ch_t - range.1 - 0.5).max(0.0) * rate).floor() as usize;
            let values = sig.slice(ch, skip, need);
            let (mid, half) = mid_half(&values);
            Pane { name: dev.optics_channels[ch].clone(), end_t: ch_t - skip as f64 / rate, rate: sig.rate, values, mid, half }
        })
        .collect();
    let map = raw::mapping(state.monitors.optics.mode, vp, range);
    monitor::set_freeze_end(ui.ctx(), id, map.freeze_end());
    refit_halves(ui, &panes);
    let ov_h = crate::ui::overview::height(ui, state, id, ui.available_height());
    let main = egui::vec2(ui.available_width(), ui.available_height() - ov_h);
    ui.allocate_ui_with_layout(main, egui::Layout::top_down(egui::Align::Min), |ui| {
        ui.set_min_size(main);
        stack(ui, &panes, map, vp, out);
    });
    if ov_h > 0.0 {
        let chans = state.analysis.eligible_of(&dev.channels, &state.monitors.bands.selected(&dev.channels));
        let host = crate::ui::overview::Host {
            id,
            range: (range.1 - vp.window_s, range.1),
            detail_oldest: (span.newest_s - nf_core::optical::BUFFER_S).max(0.0),
            no_detail: t!("overview-no-optics"),
        };
        crate::ui::overview::show(ui, state, &chans, &host, ov_h, out);
    }
}

fn mid_half(values: &[f32]) -> (f32, f32) {
    let mut lo = f32::MAX;
    let mut hi = f32::MIN;
    for &x in values.iter().filter(|x| x.is_finite()) {
        lo = lo.min(x);
        hi = hi.max(x);
    }
    if !lo.is_finite() {
        return (0.0, 1.0);
    }
    let mid = 0.5 * (lo + hi);
    let half = (hi - mid).max(1.0);
    (mid, half)
}

fn refit_halves(ui: &Ui, panes: &[Pane]) {
    // Touch the auto-refit clock so a later change can share the interval if needed.
    let key = egui::Id::unique("nf_optics_auto_y");
    let now = ui.input(|i| i.time);
    let _ = (AUTO_REFIT_S, now, panes.len(), key);
}

fn min_pane(ui: &Ui) -> f32 {
    match layout::current(ui.ctx()) {
        Layout::Regular => 160.0,
        Layout::Compact => 140.0,
        Layout::Immersive => 96.0,
    }
}

fn stack(ui: &mut Ui, panes: &[Pane], map: Mapping, vp: Viewport, out: &mut Vec<Command>) {
    let (h, scrolls) = pane_height(ui.available_height(), panes.len(), min_pane(ui));
    let width = ui.available_width();
    egui::ScrollArea::vertical().id_salt("nf_optics_panes").auto_shrink([false, false]).show(ui, |ui| {
        ui.spacing_mut().item_spacing.y = 0.0;
        for (i, pane) in panes.iter().enumerate() {
            let last = i + 1 == panes.len();
            let size = Vec2::new(width, h + if last { X_GUTTER } else { 0.0 });
            let (rect, resp) = ui.allocate_exact_size(size, Sense::click_and_drag());
            let plot = Rect::from_min_max(
                rect.left_top() + Vec2::new(4.0, 4.0),
                rect.right_bottom() - Vec2::new(RIGHT_GUTTER, if last { X_GUTTER + 2.0 } else { 4.0 }),
            );
            monitor::interact_with(ui, &resp, plot, MonitorId::Optics, vp, out, scrolls);
            if ui.is_rect_visible(rect) {
                draw_pane(ui, pane, plot, map, last);
            }
        }
    });
}

fn counts_label(v: f32) -> String {
    if v.abs() >= 10_000.0 {
        format!("{:.0}k", v / 1000.0)
    } else {
        format!("{v:.0}")
    }
}

fn draw_pane(ui: &Ui, pane: &Pane, plot: Rect, map: Mapping, last: bool) {
    let v = ui.visuals().clone();
    let p = ui.painter_at(plot.expand2(Vec2::new(RIGHT_GUTTER, X_GUTTER)));
    let trace = rt::trace(&pane.channel(), map, plot.width().max(1.0) as usize);
    let x_px = |x: f32| plot.left() + x * plot.width();
    p.line_segment([plot.left_center(), plot.right_center()], theme::grid(&v));
    raw::time_grid(&p, plot, map, &v, last);
    let y_px = |val: f32| plot.center().y - ((val - pane.mid) / pane.half).clamp(-1.0, 1.0) * plot.height() / 2.0;
    let stroke = Stroke::new(1.2, theme::raw_trace(&v));
    for run in &trace.runs {
        let pts: Vec<Pos2> = run.iter().map(|q| Pos2::new(x_px(q[0]), y_px(q[1]))).collect();
        p.add(egui::Shape::line(pts, stroke));
    }
    if let Some(c) = map.cursor() {
        let x = x_px(c as f32);
        p.line_segment([Pos2::new(x, plot.top()), Pos2::new(x, plot.bottom())], Stroke::new(1.2, theme::sweep_cursor(&v)));
    }
    let gx = plot.right() + 6.0;
    let font = FontId::proportional(10.0);
    p.text(Pos2::new(gx, plot.top()), Align2::LEFT_TOP, counts_label(pane.mid + pane.half), font.clone(), theme::axis_text(&v));
    p.text(Pos2::new(gx, plot.center().y), Align2::LEFT_CENTER, counts_label(pane.mid), font.clone(), theme::axis_text(&v));
    p.text(Pos2::new(gx, plot.bottom()), Align2::LEFT_BOTTOM, counts_label(pane.mid - pane.half), font, theme::axis_text(&v));
    p.text(
        Pos2::new(plot.right() - 4.0, plot.top() + 2.0),
        Align2::RIGHT_TOP,
        &pane.name,
        FontId::proportional(13.0),
        v.strong_text_color(),
    );
}

fn mode_toggle(ui: &mut Ui, state: &AppState, out: &mut Vec<Command>) {
    ui.spacing_mut().item_spacing.x = 0.0;
    let cur = state.monitors.optics.mode;
    for (mode, label, hint) in [
        (RawMode::Sweep, t!("raw-mode-sweep"), t!("raw-mode-sweep-hint")),
        (RawMode::Scroll, t!("raw-mode-scroll"), t!("raw-mode-scroll-hint")),
    ] {
        if ui.selectable_label(cur == mode, label).on_hover_text(hint).clicked() && cur != mode {
            out.push(Command::MonitorOptics { mode: Some(mode), lanes: None });
        }
    }
    ui.spacing_mut().item_spacing.x = 8.0;
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::panic)]
    use super::*;

    fn json_cmd(id: &str, p: serde_json::Value) -> Command {
        match nf_core::Request::parse(id, p) {
            Ok(nf_core::Request::Command(c)) => c,
            _ => panic!("{id}"),
        }
    }

    #[test]
    fn mid_half_spans_the_visible_range() {
        let (mid, half) = mid_half(&[100.0, 200.0, 300.0]);
        assert!((mid - 200.0).abs() < 1e-3 && (half - 100.0).abs() < 1e-3);
    }

    #[test]
    fn athena_session_has_sixteen_lanes() {
        let mut s = Session::new();
        for c in [
            json_cmd("settings.set", serde_json::json!({ "onboarded": true, "layout": "regular" })),
            json_cmd("device.connect", serde_json::json!({ "id": "sim:athena" })),
            json_cmd("view.set", serde_json::json!({ "view": "optics" })),
            json_cmd("clock.advance", serde_json::json!({ "seconds": 5.0 })),
        ] {
            s.execute(c).unwrap();
        }
        let (d, o) = s.live_optical().expect("optics ring");
        assert_eq!(d.optics_channels.len(), 16);
        assert!(o.time.is_some());
        let q = match nf_core::Request::parse("optics.get", serde_json::json!({ "seconds": 2.0 })) {
            Ok(nf_core::Request::Query(q)) => q,
            other => panic!("{other:?}"),
        };
        let got = s.query(&q).unwrap();
        assert_eq!(got["lanes"].as_array().unwrap().len(), 16);
    }
}
