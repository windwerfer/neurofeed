//! Raw EEG (Flutter `raw_eeg_view.dart` + `sweep_pane.dart`): one full-width
//! pane per shown channel, stacked, scrolling vertically when they do not
//! fit at their minimum height. Sweep (default) or scroll traces of the
//! conditioned signal (0.5 Hz high-pass + notch), shared Y scale, shared
//! `m:ss` axis under the last pane. Muse AUX inputs (when enabled) follow
//! the EEG panes. Geometry lives in `nf_core::rawtrace`; the viewport in
//! `nf_core::monitor` (`raw_eeg`).

use crate::ui::layout::{self, Layout};
use crate::ui::{monitor, theme};
use egui::{Align2, FontId, Pos2, Rect, Sense, Stroke, Ui, Vec2};
use nf_core::monitor::{self as m, MonitorId, RawMode, RawScale, Span, Viewport};
use nf_core::rawtrace::{self as rt, Channel, Mapping};
use nf_core::signal::{FLAG_BAD, FLAG_GAP};
use nf_core::{AppState, Command, Session};

/// Minimum pane height per layout (Flutter regular: 160).
const MIN_PANE_REGULAR: f32 = 160.0;
const MIN_PANE_COMPACT: f32 = 140.0;
const MIN_PANE_IMMERSIVE: f32 = 96.0;
/// Height of the time labels under the last pane.
const X_GUTTER: f32 = 18.0;
/// Right gutter: electrode name and Y labels.
const RIGHT_GUTTER: f32 = 46.0;
/// Auto scale re-fit interval (Flutter: 250 ms).
const AUTO_REFIT_S: f64 = 0.25;

/// One pane's input: a label, its samples and an optional quality score.
struct Pane {
    name: String,
    end_t: f64,
    rate: f64,
    values: Vec<f32>,
    flags: Vec<u8>,
    quality: Option<f32>,
}

impl Pane {
    fn channel(&self) -> Channel<'_> {
        Channel { end_t: self.end_t, rate: self.rate, values: &self.values, flags: &self.flags }
    }
}

pub fn show(ui: &mut Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    let id = MonitorId::RawEeg;
    let vp = state.monitors.viewport(id);
    let live = session.live_signal();
    let channels: Vec<String> = live.map(|(d, _)| d.channels.clone()).unwrap_or_default();
    let span = live.and_then(|(_, sig)| sig.time).map(|t| Span { oldest_s: (t - nf_core::signal::BUFFER_S).max(0.0), newest_s: t });
    monitor::toolbar(ui, state, id, out, |ui, out| {
        if let Some(span) = span {
            monitor::inspect_label(ui, vp, span);
        }
        mode_toggle(ui, state, out);
        ui.add_space(8.0);
        scale_menu(ui, state, out);
        ui.add_space(8.0);
        let sel = state.monitors.raw.selected(&channels);
        monitor::electrode_chips(ui, &channels, &sel, &t!("raw-electrode-hint"), out, |names| Command::MonitorRaw {
            mode: None,
            scale: None,
            electrodes: Some(names),
        });
    });
    let (Some((dev, sig)), Some(span)) = (live, span) else {
        ui.label(if live.is_none() { t!("plot-no-device-connected-use-connect") } else { t!("raw-waiting-for-data") });
        return;
    };
    let range = monitor::presented_range_lead(ui, state, id, vp, span, rt::RAW_FOLLOW_LEAD_S);
    // Only the samples of the visible window (+1 s margin) are copied, from
    // wherever it sits in the 300 s ring.
    let rate = sig.rate.max(1.0);
    let need = (((range.1 - range.0).max(0.0) + 1.0) * rate).ceil() as usize;
    let mut panes: Vec<Pane> = state
        .monitors
        .raw
        .selected(&dev.channels)
        .into_iter()
        .map(|ch| {
            let ch_t = sig.channel_time(ch).unwrap_or(span.newest_s);
            let skip = ((ch_t - range.1 - 0.5).max(0.0) * rate).floor() as usize;
            let (values, flags) = sig.slice(ch, skip, need, true);
            Pane {
                name: dev.channels[ch].clone(),
                end_t: ch_t - skip as f64 / rate,
                rate: sig.rate,
                values,
                flags,
                quality: Some(sig.quality[ch]),
            }
        })
        .collect();
    if let Some(side) = session.side() {
        for (name, buf) in side.live_aux() {
            // AUX has no own clock: aligned to the EEG's newest sample.
            panes.push(Pane {
                name: t!("raw-aux", name = name),
                end_t: span.newest_s,
                rate: side.aux_rate,
                values: buf.range(buf.len().saturating_sub(need)..).copied().collect(),
                flags: Vec::new(),
                quality: None,
            });
        }
    }
    let map = mapping(state.monitors.raw.mode, vp, range);
    let half = half_range(ui, state.monitors.raw.scale, &panes, map);
    stack(ui, &panes, map, half, vp, out);
}

/// Sweep only while following; Inspect holds a time-ordered window.
fn mapping(mode: RawMode, vp: Viewport, (start, end): (f64, f64)) -> Mapping {
    if mode == RawMode::Sweep && vp.following() {
        Mapping::Sweep { now: end, window: vp.window_s }
    } else {
        Mapping::Scroll { start, end }
    }
}

/// Fixed or shared Auto half range (µV); Auto re-fits every 250 ms.
fn half_range(ui: &Ui, scale: RawScale, panes: &[Pane], map: Mapping) -> f32 {
    if let Some(h) = scale.fixed_uv() {
        return h;
    }
    let key = egui::Id::unique("nf_raw_auto_y");
    let now = ui.input(|i| i.time);
    let prev = ui.data(|d| d.get_temp::<(f64, f32)>(key));
    if let Some((t, h)) = prev.filter(|(t, _)| now - t < AUTO_REFIT_S && now >= *t) {
        let _ = t;
        return h;
    }
    let chans: Vec<Channel> = panes.iter().map(Pane::channel).collect();
    let h = rt::auto_half_range(&chans, map);
    ui.data_mut(|d| d.insert_temp(key, (now, h)));
    h
}

/// `(pane height, needs scrolling)` for `n` panes in `avail` points.
pub fn pane_height(avail: f32, n: usize, min_h: f32) -> (f32, bool) {
    let n = n.max(1) as f32;
    let fill = (avail - X_GUTTER) / n;
    if fill >= min_h {
        (fill, false)
    } else {
        (min_h, true)
    }
}

fn min_pane(ui: &Ui) -> f32 {
    match layout::current(ui.ctx()) {
        Layout::Regular => MIN_PANE_REGULAR,
        Layout::Compact => MIN_PANE_COMPACT,
        Layout::Immersive => MIN_PANE_IMMERSIVE,
    }
}

fn stack(ui: &mut Ui, panes: &[Pane], map: Mapping, half: f32, vp: Viewport, out: &mut Vec<Command>) {
    let (h, scrolls) = pane_height(ui.available_height(), panes.len(), min_pane(ui));
    let width = ui.available_width();
    egui::ScrollArea::vertical().id_salt("nf_raw_panes").auto_shrink([false, false]).show(ui, |ui| {
        ui.spacing_mut().item_spacing.y = 0.0;
        for (i, pane) in panes.iter().enumerate() {
            let last = i + 1 == panes.len();
            let size = Vec2::new(width, h + if last { X_GUTTER } else { 0.0 });
            let (rect, resp) = ui.allocate_exact_size(size, Sense::click_and_drag());
            let plot = Rect::from_min_max(
                rect.left_top() + Vec2::new(4.0, 4.0),
                rect.right_bottom() - Vec2::new(RIGHT_GUTTER, if last { X_GUTTER + 2.0 } else { 4.0 }),
            );
            monitor::interact_with(ui, &resp, plot, MonitorId::RawEeg, vp, out, scrolls);
            if ui.is_rect_visible(rect) {
                draw_pane(ui, pane, plot, map, half, last);
            }
        }
    });
}

fn draw_pane(ui: &Ui, pane: &Pane, plot: Rect, map: Mapping, half: f32, last: bool) {
    let v = ui.visuals().clone();
    let p = ui.painter_at(plot.expand2(Vec2::new(RIGHT_GUTTER, X_GUTTER)));
    let trace = rt::trace(&pane.channel(), map, plot.width().max(1.0) as usize);
    let x_px = |x: f32| plot.left() + x * plot.width();
    for (a, b, f) in &trace.spans {
        let fill = if *f == FLAG_GAP {
            theme::GAP_SHADE
        } else if *f == FLAG_BAD {
            theme::BAD_SHADE
        } else {
            continue;
        };
        p.rect_filled(Rect::from_x_y_ranges(x_px(*a)..=x_px(*b), plot.y_range()), 0.0, fill);
    }
    p.line_segment([plot.left_center(), plot.right_center()], theme::grid(&v));
    time_grid(&p, plot, map, &v, last);
    let y_px = |uv: f32| plot.center().y - (uv / half).clamp(-1.0, 1.0) * plot.height() / 2.0;
    let stroke = Stroke::new(1.2, theme::raw_trace(&v));
    for run in &trace.runs {
        let pts: Vec<Pos2> = run.iter().map(|q| Pos2::new(x_px(q[0]), y_px(q[1]))).collect();
        p.add(egui::Shape::line(pts, stroke));
        for q in run.iter().filter(|q| q[1].abs() > half) {
            p.circle_filled(Pos2::new(x_px(q[0]), y_px(q[1])), 1.6, theme::CLIPPED);
        }
    }
    if let Some(c) = map.cursor() {
        let x = x_px(c as f32);
        p.line_segment([Pos2::new(x, plot.top()), Pos2::new(x, plot.bottom())], Stroke::new(1.2, theme::sweep_cursor(&v)));
    }
    let gx = plot.right() + 6.0;
    let font = FontId::proportional(10.0);
    p.text(Pos2::new(gx, plot.top()), Align2::LEFT_TOP, format!("{half:.0}"), font.clone(), theme::axis_text(&v));
    p.text(Pos2::new(gx, plot.center().y), Align2::LEFT_CENTER, "0 µV", font.clone(), theme::axis_text(&v));
    p.text(Pos2::new(gx, plot.bottom()), Align2::LEFT_BOTTOM, format!("-{half:.0}"), font, theme::axis_text(&v));
    let name_pos = Pos2::new(plot.right() - 4.0, plot.top() + 2.0);
    let r = p.text(name_pos, Align2::RIGHT_TOP, &pane.name, FontId::proportional(13.0), v.strong_text_color());
    if let Some(q) = pane.quality {
        p.circle_filled(Pos2::new(r.left() - 7.0, r.center().y), 3.5, theme::quality_color(q));
    }
}

/// Vertical grid at `m:ss` steps; labels under the last pane only. In a
/// sweep, ticks sit at fixed phases and show the time drawn there.
fn time_grid(p: &egui::Painter, plot: Rect, map: Mapping, v: &egui::Visuals, labels: bool) {
    let (start, end) = match map {
        Mapping::Scroll { start, end } => (start, end),
        Mapping::Sweep { window, .. } => (0.0, window),
    };
    let target = ((plot.width() / 90.0).floor() as usize).clamp(2, 10);
    let step = m::tick_step_s(end - start, target);
    let mut t = (start / step).ceil() * step;
    let mut n = 0;
    while t <= end + 1e-9 && n < 64 {
        let x = ((t - start) / (end - start).max(1e-9)) as f32;
        let px = plot.left() + x * plot.width();
        p.line_segment([Pos2::new(px, plot.top()), Pos2::new(px, plot.bottom())], theme::grid(v));
        if labels {
            let shown = match map {
                Mapping::Scroll { .. } => t,
                Mapping::Sweep { .. } => map.time_at(f64::from(x)),
            };
            let align = if n == 0 && x < 0.02 { Align2::LEFT_TOP } else { Align2::CENTER_TOP };
            p.text(
                Pos2::new(px, plot.bottom() + 3.0),
                align,
                rt::elapsed_label(shown, step),
                FontId::proportional(10.0),
                theme::axis_text(v),
            );
        }
        t += step;
        n += 1;
    }
}

fn mode_toggle(ui: &mut Ui, state: &AppState, out: &mut Vec<Command>) {
    ui.spacing_mut().item_spacing.x = 0.0;
    let cur = state.monitors.raw.mode;
    for (mode, label, hint) in [
        (RawMode::Sweep, t!("raw-mode-sweep"), t!("raw-mode-sweep-hint")),
        (RawMode::Scroll, t!("raw-mode-scroll"), t!("raw-mode-scroll-hint")),
    ] {
        if ui.selectable_label(cur == mode, label).on_hover_text(hint).clicked() && cur != mode {
            out.push(Command::MonitorRaw { mode: Some(mode), scale: None, electrodes: None });
        }
    }
    ui.spacing_mut().item_spacing.x = 8.0;
}

fn scale_label(s: RawScale) -> String {
    s.fixed_uv().map_or_else(|| t!("raw-scale-auto"), |h| format!("±{h:.0} µV"))
}

fn scale_menu(ui: &mut Ui, state: &AppState, out: &mut Vec<Command>) {
    let cur = state.monitors.raw.scale;
    egui::ComboBox::from_id_salt("nf_raw_scale")
        .selected_text(scale_label(cur))
        .width(78.0)
        .show_ui(ui, |ui| {
            for s in RawScale::ALL {
                if ui.selectable_label(cur == s, scale_label(s)).clicked() && cur != s {
                    out.push(Command::MonitorRaw { mode: None, scale: Some(s), electrodes: None });
                }
            }
        })
        .response
        .on_hover_text(t!("raw-scale-hint"));
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::panic)]
    use super::*;

    #[test]
    fn panes_fill_or_scroll() {
        // Muse (4) fills a tall regular window; Crown (8) scrolls at 160.
        assert_eq!(pane_height(818.0, 4, 160.0), (200.0, false));
        assert_eq!(pane_height(818.0, 8, 160.0), (160.0, true));
        // Unusual counts and an empty list never divide by zero.
        let (h, s) = pane_height(818.0, 5, 160.0);
        assert!((h - 160.0).abs() < 1e-3 && !s);
        assert_eq!(pane_height(400.0, 0, 96.0), (382.0, false));
        assert_eq!(pane_height(394.0, 7, 96.0), (96.0, true));
    }

    #[test]
    fn sweep_only_while_following() {
        let mut vp = Viewport::new(MonitorId::RawEeg.spec());
        assert!(matches!(mapping(RawMode::Sweep, vp, (2.0, 10.0)), Mapping::Sweep { now, window } if now == 10.0 && window == 8.0));
        assert!(matches!(mapping(RawMode::Scroll, vp, (2.0, 10.0)), Mapping::Scroll { .. }));
        vp.end_s = Some(9.0);
        assert!(matches!(mapping(RawMode::Sweep, vp, (1.0, 9.0)), Mapping::Scroll { start, end } if start == 1.0 && end == 9.0));
    }

    /// Drive the whole UI with a pointer drag over the first Raw pane and
    /// return the summed `monitor.pan` seconds (commands are applied).
    fn drag(session: &mut Session, steps: &[Vec2], size: Vec2) -> f64 {
        let _lang = crate::i18n::lang_lock();
        let ctx = egui::Context::default();
        let screen = Rect::from_min_size(Pos2::ZERO, size);
        let mut t = 0.0;
        let mut frame = |events: Vec<egui::Event>, s: &mut Session| -> f64 {
            t += 1.0 / 60.0;
            let input = egui::RawInput { screen_rect: Some(screen), time: Some(t), events, ..Default::default() };
            let mut cmds = Vec::new();
            ctx.run_ui(input, |u| cmds = crate::ui::show(u, s, None)).textures_delta.clear();
            let mut sum = 0.0;
            for c in cmds {
                if let Command::MonitorPan { seconds, .. } = c {
                    sum += seconds;
                }
                s.execute(c).ok();
            }
            sum
        };
        frame(vec![], session);
        frame(vec![], session);
        let mut at = Pos2::new(size.x * 0.5, 200.0);
        let button = |pos, pressed| egui::Event::PointerButton {
            pos,
            button: egui::PointerButton::Primary,
            pressed,
            modifiers: egui::Modifiers::NONE,
        };
        let mut total = frame(vec![egui::Event::PointerMoved(at), button(at, true)], session);
        for d in steps {
            at += *d;
            total += frame(vec![egui::Event::PointerMoved(at)], session);
        }
        total + frame(vec![button(at, false)], session)
    }

    fn raw_session(dev: &str) -> Session {
        let mut s = Session::new();
        for c in [
            json_cmd("settings.set", serde_json::json!({ "onboarded": true, "layout": "regular" })),
            json_cmd("device.connect", serde_json::json!({ "id": dev })),
            json_cmd("view.set", serde_json::json!({ "view": "raw_eeg" })),
            json_cmd("clock.advance", serde_json::json!({ "seconds": 40.0 })),
            json_cmd("monitor.viewport", serde_json::json!({ "monitor": "raw_eeg", "mode": "inspect" })),
        ] {
            s.execute(c).unwrap();
        }
        s
    }

    fn json_cmd(id: &str, p: serde_json::Value) -> Command {
        match nf_core::Request::parse(id, p) {
            Ok(nf_core::Request::Command(c)) => c,
            _ => panic!("{id}"),
        }
    }

    fn end(s: &Session) -> f64 {
        s.state().monitors.viewport(MonitorId::RawEeg).end_s.unwrap_or(f64::NAN)
    }

    #[test]
    fn inspect_drag_follows_the_finger() {
        // 4 panes fit (no list scrolling) and 8 overflow: horizontal drags
        // pan by finger distance / plot width x window in both.
        for (dev, size) in [("sim:muse", Vec2::new(1000.0, 900.0)), ("sim:crown", Vec2::new(1000.0, 700.0))] {
            let mut s = raw_session(dev);
            let e0 = end(&s);
            let steps = vec![Vec2::new(30.0, 0.0); 10]; // 300 px right = earlier
            let panned = drag(&mut s, &steps, size);
            let plot_w = 1000.0 - crate::ui::theme::SIDEBAR_WIDTH - 2.0 * 8.0 - 4.0 - RIGHT_GUTTER;
            let want = -300.0 / f64::from(plot_w) * 8.0;
            assert!((panned - want).abs() < 0.25, "{dev}: commands {panned} vs {want}");
            assert!((end(&s) - (e0 + panned)).abs() < 1e-6, "{dev}: view moved {} of {panned}", end(&s) - e0);
        }
    }

    #[test]
    fn vertical_drag_in_an_overflowing_stack_does_not_pan() {
        let mut s = raw_session("sim:crown");
        let e0 = end(&s);
        let steps = vec![Vec2::new(3.0, -25.0); 8];
        assert_eq!(drag(&mut s, &steps, Vec2::new(1000.0, 700.0)), 0.0);
        assert!((end(&s) - e0).abs() < 1e-9);
    }
}
