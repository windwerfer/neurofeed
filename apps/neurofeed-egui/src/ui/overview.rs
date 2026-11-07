//! Overview timeline (minimap) shared by the monitor views: the Bands
//! history (up to 1 h) with the host view's visible window shaded.
//!
//! - Each view has its own overview viewport (`MonitorId::overview`), its
//!   own pan/zoom (drag outside the shade, pinch / Ctrl+wheel, double-click
//!   = Follow) and only ever moves its own host view: no cross-view link.
//! - Drag the shade = pan the host (enters Inspect at the presented edge,
//!   so Raw sweep → Inspect does not jump); drag a shade edge = resize the
//!   host window (when the host allows more than one length); tap = jump
//!   the host there (Inspect, clamped by the core to its data).
//! - Time older than the host's detailed data (raw ring 5 min, spectrogram
//!   history 5 min) is shaded and labelled: the overview never suggests
//!   detail that is not retained.
//! - Toggle in the view toolbar (saved per view, `monitor.overview`); the
//!   graph-only phone landscape has no toolbar but keeps an enabled overview.

use super::views::bands;
use super::{layout, monitor, theme};
use egui::{Align2, FontId, Rect, Sense, Ui};
use nf_core::monitor::{MonitorId, Span, Viewport, ViewportMode};
use nf_core::{AppState, Command};

/// Grab tolerance of the shade edges (points).
const EDGE: f32 = 8.0;
/// Below this total height an enabled overview is dropped (space).
const MIN_TOTAL: f32 = 200.0;

/// Height to reserve at the bottom for the overview of `host` (0 = none).
pub fn height(ui: &Ui, state: &AppState, host: MonitorId, total: f32) -> f32 {
    if !state.monitors.overview_on(host) || total < MIN_TOTAL || state.bands.latest().is_none() {
        return 0.0;
    }
    let share = if monitor::immersive(ui) { 0.25 } else { 0.3 };
    (total * share).clamp(56.0, 260.0)
}

/// Toolbar toggle (hidden with the toolbar in graph-only landscape).
pub fn toggle(ui: &mut Ui, state: &AppState, host: MonitorId, out: &mut Vec<Command>) {
    let on = state.monitors.overview_on(host);
    if ui.selectable_label(on, t!("overview-toggle")).on_hover_text(t!("overview-toggle-hint")).clicked() {
        out.push(Command::MonitorOverview { monitor: host, on: !on });
    }
}

/// What the host shows and where its detailed data exists.
pub struct Host {
    pub id: MonitorId,
    /// The host's presented `(start, end)` (session s).
    pub range: (f64, f64),
    /// Oldest time the host has detailed data for (raw ring, spectral history…).
    pub detail_oldest: f64,
    /// Label for the shaded part without detail.
    pub no_detail: String,
}

/// Shade edge hit by a drag start.
#[derive(Clone, Copy, PartialEq, Debug)]
enum Grab {
    Body,
    Left,
    Right,
    None,
}

/// Classify a drag start at `x` against shade `[l, r]`; edges only when
/// the host window is resizable.
fn grab_at(x: f32, l: f32, r: f32, resizable: bool) -> Grab {
    let narrow = r - l < 3.0 * EDGE;
    if resizable && !narrow && (x - l).abs() <= EDGE {
        Grab::Left
    } else if resizable && !narrow && (x - r).abs() <= EDGE {
        Grab::Right
    } else if x >= l - EDGE && x <= r + EDGE {
        Grab::Body
    } else {
        Grab::None
    }
}

/// Draw the overview in the bottom `h` points of the remaining space.
pub fn show(ui: &mut Ui, state: &AppState, chans: &[usize], host: &Host, h: f32, out: &mut Vec<Command>) {
    let Some(oid) = host.id.overview() else { return };
    let (Some(a), Some(b)) = (state.bands.oldest(), state.bands.latest()) else { return };
    let avail = ui.available_rect_before_wrap();
    let rect = Rect::from_min_max(egui::pos2(avail.left(), (avail.bottom() - h).max(avail.top())), avail.max);
    let ovp = state.monitors.viewport(oid);
    let span = Span::new(a.time, b.time);
    let range = monitor::presented_range(ui, state, oid, ovp, span);
    let resp = ui.allocate_rect(rect, Sense::click_and_drag());
    let compact = layout::current(ui.ctx()) != layout::Layout::Regular;
    let plot = Rect::from_min_max(rect.left_top() + egui::vec2(40.0, 14.0), rect.right_bottom() - egui::vec2(8.0, 18.0));
    let p = ui.painter_at(rect);
    let v = ui.visuals().clone();
    p.line_segment([rect.left_top(), rect.right_top()], theme::grid(&v));
    if chans.is_empty() {
        monitor::no_eligible(ui, plot);
    } else {
        bands::strip(&p, state, chans, plot, range);
    }
    let x = |t: f64| monitor::x_of(plot, range, t).clamp(plot.left(), plot.right());
    if host.detail_oldest > range.0.max(a.time) {
        let r = Rect::from_x_y_ranges(x(range.0.max(a.time))..=x(host.detail_oldest), plot.y_range());
        p.rect_filled(r, 0.0, theme::GAP_SHADE);
        if r.width() > 120.0 {
            p.text(r.center(), Align2::CENTER_CENTER, &host.no_detail, FontId::proportional(10.0), theme::axis_text(&v));
        }
    }
    let (l, r) = (x(host.range.0), x(host.range.1).max(x(host.range.0) + 2.0));
    let shade = Rect::from_x_y_ranges(l..=r, plot.y_range());
    let accent = theme::band_color(nf_core::Band::Alpha);
    p.rect_filled(shade, 0.0, accent.gamma_multiply(0.22));
    p.rect_stroke(shade, 0.0, egui::Stroke::new(if compact { 1.5 } else { 1.0 }, accent), egui::StrokeKind::Inside);
    ui.ctx().data_mut(|d| d.insert_temp(shade_id(oid), shade));
    gestures(ui, state, host, oid, ovp, &resp, plot, range, (l, r), out);
}

/// Where the shade was drawn last frame (tests, screenshots).
pub fn shade_id(oid: MonitorId) -> egui::Id {
    egui::Id::unique(("nf-overview-shade", oid.name()))
}

#[allow(clippy::too_many_arguments)]
fn gestures(
    ui: &Ui,
    state: &AppState,
    host: &Host,
    oid: MonitorId,
    ovp: Viewport,
    resp: &egui::Response,
    plot: Rect,
    range: (f64, f64),
    (l, r): (f32, f32),
    out: &mut Vec<Command>,
) {
    let spec = host.id.spec();
    let gid = egui::Id::unique(("nf-overview-grab", oid.name()));
    if resp.drag_started() {
        let origin = ui.input(|i| i.pointer.press_origin()).or_else(|| resp.interact_pointer_pos());
        let g = origin.map_or(Grab::None, |q| grab_at(q.x, l, r, spec.max_s > spec.min_s));
        ui.ctx().data_mut(|d| d.insert_temp(gid, g));
    }
    let grab = if resp.dragged() { ui.ctx().data(|d| d.get_temp::<Grab>(gid)).unwrap_or(Grab::None) } else { Grab::None };
    let w = f64::from(plot.width().max(1.0));
    let per_px = (range.1 - range.0) / w;
    let dx = f64::from(resp.drag_delta().x) * per_px;
    let hvp = state.monitors.viewport(host.id);
    match grab {
        Grab::Body => {
            if dx != 0.0 {
                monitor::freeze_at_presented(ui, host.id, hvp, out);
                out.push(Command::MonitorPan { monitor: host.id, seconds: dx });
            }
        }
        Grab::Left | Grab::Right if dx != 0.0 => {
            let (s, e) = host.range;
            let (s, e) = if grab == Grab::Left { (s + dx, e) } else { (s, e + dx) };
            let window = (e - s).clamp(spec.min_s, spec.max_s);
            out.push(Command::MonitorViewport {
                monitor: host.id,
                window_s: Some(window),
                mode: Some(ViewportMode::Inspect),
                end_s: Some(e),
            });
        }
        Grab::Left | Grab::Right => {}
        Grab::None => {
            if resp.clicked() {
                if let Some(q) = resp.interact_pointer_pos() {
                    let t = range.0 + f64::from(q.x - plot.left()) * per_px;
                    let half = (host.range.1 - host.range.0) / 2.0;
                    out.push(Command::MonitorViewport {
                        monitor: host.id,
                        window_s: None,
                        mode: Some(ViewportMode::Inspect),
                        end_s: Some(t + half),
                    });
                }
            } else {
                // Vertical drags (phone scroll intent) never pan the timeline.
                let d = resp.drag_delta();
                if d.y.abs() <= d.x.abs() || !resp.dragged() {
                    monitor::interact(ui, resp, plot, oid, ovp, out);
                }
            }
        }
    }
    if grab != Grab::None {
        ui.ctx().set_cursor_icon(if matches!(grab, Grab::Body) { egui::CursorIcon::Grabbing } else { egui::CursorIcon::ResizeHorizontal });
    } else if let Some(hx) = resp.hover_pos().map(|q| grab_at(q.x, l, r, spec.max_s > spec.min_s)) {
        match hx {
            Grab::Left | Grab::Right => ui.ctx().set_cursor_icon(egui::CursorIcon::ResizeHorizontal),
            Grab::Body => ui.ctx().set_cursor_icon(egui::CursorIcon::Grab),
            Grab::None => {}
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::panic)]
    use super::*;
    use egui::{Pos2, Vec2};
    use nf_core::Session;

    fn cmd(id: &str, p: serde_json::Value) -> Command {
        match nf_core::Request::parse(id, p) {
            Ok(nf_core::Request::Command(c)) => c,
            _ => panic!("{id}"),
        }
    }

    fn session(view: &str, extra: &[(&str, serde_json::Value)]) -> Session {
        let mut s = Session::new();
        for (id, p) in [
            ("settings.set", serde_json::json!({ "onboarded": true, "layout": "regular" })),
            ("device.connect", serde_json::json!({ "id": "sim:muse" })),
            ("view.set", serde_json::json!({ "view": view })),
            ("clock.advance", serde_json::json!({ "seconds": 200.0 })),
        ] {
            s.execute(cmd(id, p)).unwrap();
        }
        for (id, p) in extra {
            s.execute(cmd(id, p.clone())).unwrap();
        }
        s
    }

    /// Press at `at` (or at `pick(shade)` of the drawn shade), move by
    /// `steps`, release; apply and return commands.
    fn gesture(s: &mut Session, at: Pos2, steps: &[Vec2]) -> Vec<Command> {
        gesture_at(s, |_| at, steps)
    }

    fn gesture_at(s: &mut Session, pick: impl Fn(Rect) -> Pos2, steps: &[Vec2]) -> Vec<Command> {
        let _lang = crate::i18n::lang_lock();
        let ctx = egui::Context::default();
        let screen = Rect::from_min_size(Pos2::ZERO, Vec2::new(1200.0, 800.0));
        let mut t = 0.0;
        let mut all = Vec::new();
        let mut frame = |events: Vec<egui::Event>, s: &mut Session, all: &mut Vec<Command>| {
            t += 1.0 / 60.0;
            let input = egui::RawInput { screen_rect: Some(screen), time: Some(t), events, ..Default::default() };
            let mut cmds = Vec::new();
            ctx.run_ui(input, |u| cmds = crate::ui::show(u, s, None)).textures_delta.clear();
            for c in cmds {
                s.execute(c.clone()).ok();
                all.push(c);
            }
        };
        let button = |pos, pressed| egui::Event::PointerButton {
            pos,
            button: egui::PointerButton::Primary,
            pressed,
            modifiers: egui::Modifiers::NONE,
        };
        frame(vec![], s, &mut all);
        frame(vec![], s, &mut all);
        let shade = ctx.data(|d| d.get_temp::<Rect>(shade_id(MonitorId::BandsOverview))).unwrap_or(Rect::NOTHING);
        let mut p = pick(shade);
        frame(vec![egui::Event::PointerMoved(p), button(p, true)], s, &mut all);
        for d in steps {
            p += *d;
            frame(vec![egui::Event::PointerMoved(p)], s, &mut all);
        }
        frame(vec![button(p, false)], s, &mut all);
        all
    }

    fn mode(s: &Session, id: MonitorId) -> bool {
        s.state().monitors.viewport(id).following()
    }

    /// Bands overview at the bottom of a 1200×800 window: the 30 s host
    /// window is the right third of the 90 s overview.
    const INSIDE: Pos2 = Pos2::new(1120.0, 760.0);
    const OUTSIDE: Pos2 = Pos2::new(420.0, 760.0);

    fn bands_on() -> Session {
        session("bands", &[("monitor.overview", serde_json::json!({ "monitor": "bands", "on": true }))])
    }

    #[test]
    fn dragging_the_shade_pans_only_the_host() {
        let mut s = bands_on();
        let before = s.state().monitors.viewport(MonitorId::Bands);
        assert!(before.following());
        let out = gesture(&mut s, INSIDE, &[Vec2::new(-40.0, 0.0), Vec2::new(-40.0, 0.0)]);
        assert!(out.iter().any(|c| matches!(c, Command::MonitorPan { monitor: MonitorId::Bands, seconds } if *seconds < 0.0)), "{out:?}");
        assert!(!mode(&s, MonitorId::Bands), "host inspects");
        assert!(mode(&s, MonitorId::BandsOverview), "overview itself did not move");
        assert!(mode(&s, MonitorId::PsdStrip) && mode(&s, MonitorId::RawEeg), "no cross-view link");
    }

    #[test]
    fn tap_jumps_the_host_and_outside_drag_pans_the_overview() {
        let mut s = bands_on();
        let out = gesture(&mut s, OUTSIDE, &[]);
        let jump = out.iter().find_map(|c| match c {
            Command::MonitorViewport { monitor: MonitorId::Bands, mode: Some(ViewportMode::Inspect), end_s, .. } => *end_s,
            _ => None,
        });
        let end = jump.expect("tap → host inspect");
        assert!(end < 190.0, "{end}");
        let mut s = bands_on();
        gesture(&mut s, OUTSIDE, &[Vec2::new(60.0, 0.0), Vec2::new(60.0, 0.0)]);
        assert!(!mode(&s, MonitorId::BandsOverview) && mode(&s, MonitorId::Bands));
    }

    #[test]
    fn vertical_drag_on_the_overview_does_not_pan() {
        let mut s = bands_on();
        let out = gesture(&mut s, OUTSIDE, &[Vec2::new(0.0, -30.0), Vec2::new(2.0, -30.0)]);
        assert!(!out.iter().any(|c| matches!(c, Command::MonitorPan { .. })), "{out:?}");
    }

    #[test]
    fn dragging_a_shade_edge_resizes_the_host_window() {
        let mut s = bands_on();
        let out = gesture_at(&mut s, |r| Pos2::new(r.left() + 1.0, r.center().y), &[Vec2::new(-30.0, 0.0), Vec2::new(-30.0, 0.0)]);
        let w = s.state().monitors.viewport(MonitorId::Bands).window_s;
        assert!(w > 31.0, "window grew: {w} {out:?}");
    }

    #[test]
    fn defaults_draw_on_psd_and_spectrogram_only() {
        let _lang = crate::i18n::lang_lock();
        let on = |view: &str| {
            let s = session(view, &[]);
            s.state().monitors.overview_on(nf_core::monitor::MonitorId::ALL.into_iter().find(|m| m.name() == view).unwrap())
        };
        assert!(on("psd") && on("spectrogram"));
        assert!(!on("bands") && !on("raw_eeg") && !on("histogram"));
    }

    #[test]
    fn landscape_has_no_toggle_but_keeps_the_overview() {
        let _lang = crate::i18n::lang_lock();
        let mut s = session("spectrogram", &[]);
        s.execute(cmd("settings.set", serde_json::json!({ "layout": "compact" }))).unwrap();
        let ctx = egui::Context::default();
        let mut shapes = Vec::new();
        for i in 0..3 {
            let input = egui::RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, Vec2::new(860.0, 400.0))),
                time: Some(f64::from(i) / 60.0),
                ..Default::default()
            };
            let mut o = ctx.run_ui(input, |u| {
                crate::ui::show(u, &s, None);
            });
            o.textures_delta.clear();
            shapes = o.shapes;
        }
        let texts: Vec<String> = shapes
            .iter()
            .filter_map(|c| if let egui::Shape::Text(t) = &c.shape { Some(t.galley.text().to_owned()) } else { None })
            .collect();
        assert!(!texts.contains(&t!("overview-toggle")), "no chrome in graph-only landscape: {texts:?}");
        // Overview time labels sit below the heatmap's (two m:ss rows).
        let rows: std::collections::BTreeSet<i32> = shapes
            .iter()
            .filter_map(|c| match &c.shape {
                egui::Shape::Text(t) if t.galley.text().contains(':') => Some(t.pos.y as i32),
                _ => None,
            })
            .collect();
        assert!(rows.len() >= 2, "heatmap + overview axes: {rows:?}");
    }

    #[test]
    fn grab_zones() {
        assert_eq!(grab_at(100.0, 100.0, 200.0, true), Grab::Left);
        assert_eq!(grab_at(205.0, 100.0, 200.0, true), Grab::Right);
        assert_eq!(grab_at(150.0, 100.0, 200.0, true), Grab::Body);
        assert_eq!(grab_at(50.0, 100.0, 200.0, true), Grab::None);
        // Not resizable, or too narrow for edges: the whole shade moves.
        assert_eq!(grab_at(100.0, 100.0, 200.0, false), Grab::Body);
        assert_eq!(grab_at(100.0, 100.0, 110.0, true), Grab::Body);
    }
}
