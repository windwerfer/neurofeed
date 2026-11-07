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

/// Height to reserve at the bottom for the overview of `host` (0 = none),
/// including the bookmark row when that view has bookmarks.
pub fn height(ui: &Ui, state: &AppState, host: MonitorId, total: f32) -> f32 {
    if !state.monitors.overview_on(host) || total < MIN_TOTAL || state.bands.latest().is_none() {
        return 0.0;
    }
    let share = if monitor::immersive(ui) { 0.25 } else { 0.3 };
    let row = if state.monitors.bookmarks_of(host).is_empty() { 0.0 } else { row_h(ui) };
    (total * share).clamp(56.0, 260.0) + row
}

/// Bookmark row height (touch size on phones).
fn row_h(ui: &Ui) -> f32 {
    if layout::current(ui.ctx()).is_compact() {
        40.0
    } else {
        28.0
    }
}

/// Hold this long without moving = long press (bookmark add / remove).
pub const HOLD_S: f64 = 0.55;
/// Movement (points) that turns a hold into a drag.
pub const HOLD_SLOP: f32 = 8.0;

/// Touch-only platform (all Android phones and tablets): long press only,
/// no bookmark icon or × buttons. Platform identity, not the layout.
pub fn touch_only(ctx: &egui::Context) -> bool {
    ctx.data(|d| d.get_temp::<bool>(egui::Id::unique("nf-touch-only"))).unwrap_or(cfg!(target_os = "android"))
}

/// Tests: pretend to be (or not be) Android.
#[cfg(test)]
pub fn set_touch_only(ctx: &egui::Context, on: bool) {
    ctx.data_mut(|d| d.insert_temp(egui::Id::unique("nf-touch-only"), on));
}

/// One press: when it started and whether its long press fired / moved.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Hold {
    start: f64,
    fired: bool,
    moved: bool,
}

/// Long-press detector shared by the shade and the chips; `target` = the
/// rect the press must start in. Returns `(fire, consumed)`: `fire` is true
/// exactly once per press (stationary ≥ [`HOLD_S`], never after moving more
/// than [`HOLD_SLOP`]); `consumed` stays true until and including the
/// release frame, so the same press cannot also tap, pan or jump.
fn hold(ui: &Ui, key: egui::Id, target: Rect) -> (bool, bool) {
    let (down, origin, start, pos, now) =
        ui.input(|i| (i.pointer.primary_down(), i.pointer.press_origin(), i.pointer.press_start_time(), i.pointer.latest_pos(), i.time));
    let id = key.with("hold");
    let prev = ui.ctx().data(|d| d.get_temp::<Hold>(id));
    if !down {
        if prev.is_some() {
            ui.ctx().data_mut(|d| d.remove::<Hold>(id));
        }
        return (false, prev.is_some_and(|h| h.fired));
    }
    let (Some(origin), Some(start)) = (origin, start) else { return (false, false) };
    if !target.contains(origin) {
        return (false, false);
    }
    let mut h = prev.filter(|h| (h.start - start).abs() < 1e-9).unwrap_or(Hold { start, fired: false, moved: false });
    if pos.is_some_and(|p| p.distance(origin) > HOLD_SLOP) {
        h.moved = true;
    }
    let fire = !h.fired && !h.moved && now - start >= HOLD_S;
    h.fired |= fire;
    ui.ctx().data_mut(|d| d.insert_temp(id, h));
    if !h.fired && !h.moved {
        ui.ctx().request_repaint_after(std::time::Duration::from_millis(50));
    }
    (fire, h.fired)
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

/// Bookmark the window the host shows right now.
fn add_bookmark(host: &Host, out: &mut Vec<Command>) {
    out.push(Command::MonitorBookmarkAdd { monitor: host.id, end_s: Some(host.range.1), window_s: Some(host.range.1 - host.range.0) });
}

/// Draw the overview in the bottom `h` points of the remaining space.
pub fn show(ui: &mut Ui, state: &AppState, chans: &[usize], host: &Host, h: f32, out: &mut Vec<Command>) {
    let Some(oid) = host.id.overview() else { return };
    let (Some(a), Some(b)) = (state.bands.oldest(), state.bands.latest()) else { return };
    let avail = ui.available_rect_before_wrap();
    let rect = Rect::from_min_max(egui::pos2(avail.left(), (avail.bottom() - h).max(avail.top())), avail.max);
    let marks = state.monitors.bookmarks_of(host.id);
    let row = if marks.is_empty() { 0.0 } else { row_h(ui) };
    let graph = Rect::from_min_max(rect.min, egui::pos2(rect.right(), rect.bottom() - row));
    let ovp = state.monitors.viewport(oid);
    let span = Span::new(a.time, b.time);
    let range = monitor::presented_range(ui, state, oid, ovp, span);
    let resp = ui.allocate_rect(graph, Sense::click_and_drag());
    let compact = layout::current(ui.ctx()) != layout::Layout::Regular;
    let plot = Rect::from_min_max(graph.left_top() + egui::vec2(40.0, 14.0), graph.right_bottom() - egui::vec2(8.0, 18.0));
    let p = ui.painter_at(graph);
    let v = ui.visuals().clone();
    p.line_segment([graph.left_top(), graph.right_top()], theme::grid(&v));
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
    let accent = theme::band_color(nf_core::Band::Alpha);
    // Bookmark markers: a short tick at each bookmarked window end.
    for m in marks.iter().filter(|m| m.end_s >= range.0 && m.end_s <= range.1) {
        let mx = x(m.end_s);
        p.line_segment([egui::pos2(mx, plot.top()), egui::pos2(mx, plot.top() + 8.0)], egui::Stroke::new(2.0, v.strong_text_color()));
    }
    let (l, r) = (x(host.range.0), x(host.range.1).max(x(host.range.0) + 2.0));
    let shade = Rect::from_x_y_ranges(l..=r, plot.y_range());
    p.rect_filled(shade, 0.0, accent.gamma_multiply(0.22));
    p.rect_stroke(shade, 0.0, egui::Stroke::new(if compact { 1.5 } else { 1.0 }, accent), egui::StrokeKind::Inside);
    ui.ctx().data_mut(|d| d.insert_temp(shade_id(oid), shade));
    // In-graph overview span menu (top-left; same presets/style as the
    // toolbar's). Laid out after the plot response so it gets the input.
    let menu_rect = Rect::from_min_size(plot.left_top() + egui::vec2(4.0, 2.0), egui::vec2(96.0, if compact { 36.0 } else { 22.0 }));
    let menu = ui
        .scope_builder(egui::UiBuilder::new().max_rect(menu_rect).layout(egui::Layout::left_to_right(egui::Align::Min)), |ui| {
            monitor::window_menu(ui, oid, ovp, out)
        })
        .inner;
    ui.ctx().data_mut(|d| d.insert_temp(shade_id(oid).with("menu"), menu.rect));
    let skey = egui::Id::unique(("nf-overview-shade-hold", oid.name()));
    let (fire, mut consumed) = hold(ui, skey, shade.expand2(egui::vec2(EDGE, 0.0)));
    // Mouse affordance (not on Android): bookmark icon at the shade's
    // bottom-left corner.
    if !touch_only(ui.ctx()) && shade.width() >= 20.0 && shade.height() >= 24.0 {
        let ir = Rect::from_min_size(shade.left_bottom() + egui::vec2(2.0, -18.0), egui::vec2(16.0, 16.0));
        let ib = ui.put(ir, egui::Button::new("").frame(false)).on_hover_text(t!("overview-bookmark-add"));
        paint_bookmark_icon(&p, ir, if ib.hovered() { v.strong_text_color() } else { accent });
        if ib.clicked() {
            add_bookmark(host, out);
            consumed = true;
        }
        ui.ctx().data_mut(|d| d.insert_temp(icon_id(oid), ir));
    }
    let popup = egui::Popup::is_any_open(ui.ctx());
    let on_menu = ui.input(|i| i.pointer.press_origin()).is_some_and(|o| menu.rect.contains(o));
    if fire {
        add_bookmark(host, out);
    }
    if !consumed && !popup && !on_menu && !menu.hovered() {
        gestures(ui, state, host, oid, ovp, &resp, plot, range, (l, r), out);
    }
    if row > 0.0 {
        let rr = Rect::from_min_max(egui::pos2(rect.left() + 40.0, graph.bottom()), rect.max);
        chips(ui, state, host, marks, rr, out);
    }
}

/// Where the shade was drawn last frame (tests, screenshots).
pub fn shade_id(oid: MonitorId) -> egui::Id {
    egui::Id::unique(("nf-overview-shade", oid.name()))
}

pub fn icon_id(oid: MonitorId) -> egui::Id {
    egui::Id::unique(("nf-overview-icon", oid.name()))
}

pub fn chip_id(host: MonitorId, id: u32) -> egui::Id {
    egui::Id::unique(("nf-overview-chip", host.name(), id))
}

/// A bookmark ribbon: rectangle with a notch at the bottom.
fn paint_bookmark_icon(p: &egui::Painter, r: Rect, c: egui::Color32) {
    let (l, rt, t, b) = (r.left() + 3.0, r.right() - 3.0, r.top() + 1.0, r.bottom() - 1.0);
    let pts = vec![egui::pos2(l, t), egui::pos2(rt, t), egui::pos2(rt, b), egui::pos2((l + rt) / 2.0, b - 4.0), egui::pos2(l, b)];
    p.add(egui::Shape::convex_polygon(pts, c, egui::Stroke::NONE));
}

/// The bookmark row: tap = jump the host there; long press = remove;
/// mouse platforms also get a small × per chip.
fn chips(ui: &mut Ui, state: &AppState, host: &Host, marks: &[nf_core::monitor::Bookmark], rr: Rect, out: &mut Vec<Command>) {
    let touch = touch_only(ui.ctx());
    let compact = layout::current(ui.ctx()).is_compact();
    let span_ok = |m: &nf_core::monitor::Bookmark| m.end_s - m.window_s >= host.detail_oldest - 1e-6;
    let _ = state;
    ui.scope_builder(egui::UiBuilder::new().max_rect(rr).layout(egui::Layout::left_to_right(egui::Align::Center)), |ui| {
        egui::ScrollArea::horizontal().id_salt(("nf-overview-chips", host.id.name())).show(ui, |ui| {
            ui.spacing_mut().item_spacing.x = 6.0;
            for m in marks {
                let ok = span_ok(m);
                let label = t!("overview-bookmark-chip", t = nf_core::monitor::mmss(m.end_s), w = monitor::window_label(m.window_s));
                let text = if ok { egui::RichText::new(label) } else { egui::RichText::new(label).weak().strikethrough() };
                let tip = if !ok {
                    t!("overview-bookmark-gone")
                } else if touch {
                    t!("overview-bookmark-tip-touch")
                } else {
                    t!("overview-bookmark-tip")
                };
                let size = egui::vec2(0.0, if compact { 36.0 } else { 22.0 });
                let resp = ui.add(egui::Button::new(text).min_size(size)).on_hover_text(tip);
                let key = chip_id(host.id, m.id);
                ui.ctx().data_mut(|d| d.insert_temp(key, resp.rect));
                let (fire, consumed) = hold(ui, key, resp.rect);
                if fire {
                    out.push(Command::MonitorBookmarkRemove { monitor: host.id, id: m.id });
                } else if resp.clicked() && !consumed && ok {
                    out.push(Command::MonitorBookmarkGo { monitor: host.id, id: m.id });
                }
                if !touch {
                    let x = ui
                        .add(egui::Button::new(egui::RichText::new("×").small()).frame(false))
                        .on_hover_text(t!("overview-bookmark-remove"));
                    ui.ctx().data_mut(|d| d.insert_temp(key.with("x"), x.rect));
                    if x.clicked() {
                        out.push(Command::MonitorBookmarkRemove { monitor: host.id, id: m.id });
                    }
                }
            }
        });
    });
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

    /// Frame-by-frame driver with a pointer (applies every command).
    struct Drive {
        ctx: egui::Context,
        s: Session,
        t: f64,
        out: Vec<Command>,
        pos: Pos2,
    }

    impl Drive {
        fn new(s: Session, android: bool) -> Self {
            let ctx = egui::Context::default();
            set_touch_only(&ctx, android);
            let mut d = Self { ctx, s, t: 0.0, out: Vec::new(), pos: Pos2::ZERO };
            d.frame(vec![]);
            d.frame(vec![]);
            d.out.clear();
            d
        }
        fn frame(&mut self, events: Vec<egui::Event>) {
            let _lang = crate::i18n::lang_lock();
            self.t += 0.05;
            let input = egui::RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, Vec2::new(1200.0, 800.0))),
                time: Some(self.t),
                events,
                ..Default::default()
            };
            let mut cmds = Vec::new();
            let s = &self.s;
            self.ctx.run_ui(input, |u| cmds = crate::ui::show(u, s, None)).textures_delta.clear();
            for c in cmds {
                self.s.execute(c.clone()).ok();
                self.out.push(c);
            }
        }
        fn btn(&self, pressed: bool) -> egui::Event {
            egui::Event::PointerButton { pos: self.pos, button: egui::PointerButton::Primary, pressed, modifiers: egui::Modifiers::NONE }
        }
        fn press(&mut self, at: Pos2) {
            self.pos = at;
            let e = vec![egui::Event::PointerMoved(at), self.btn(true)];
            self.frame(e);
        }
        fn hold(&mut self, secs: f64) {
            for _ in 0..(secs / 0.05).round() as usize {
                self.frame(vec![]);
            }
        }
        fn drag(&mut self, d: Vec2) {
            self.pos += d;
            let p = self.pos;
            self.frame(vec![egui::Event::PointerMoved(p)]);
        }
        fn release(&mut self) {
            let e = vec![self.btn(false)];
            self.frame(e);
            self.frame(vec![]);
        }
        fn rect(&self, id: egui::Id) -> Option<Rect> {
            self.ctx.data(|d| d.get_temp::<Rect>(id))
        }
        fn shade(&self) -> Rect {
            self.rect(shade_id(MonitorId::BandsOverview)).unwrap()
        }
        fn count(&self, f: impl Fn(&Command) -> bool) -> usize {
            self.out.iter().filter(|c| f(c)).count()
        }
        fn marks(&self) -> usize {
            self.s.state().monitors.bookmarks_of(MonitorId::Bands).len()
        }
    }

    fn is_add(c: &Command) -> bool {
        matches!(c, Command::MonitorBookmarkAdd { .. })
    }

    fn is_host_move(c: &Command) -> bool {
        matches!(c, Command::MonitorPan { .. } | Command::MonitorViewport { monitor: MonitorId::Bands, .. })
    }

    #[test]
    fn long_press_on_the_shade_bookmarks_once_without_jumping() {
        for android in [false, true] {
            let mut d = Drive::new(bands_on(), android);
            let c = d.shade().center();
            d.press(c);
            d.hold(1.5);
            d.release();
            assert_eq!(d.count(is_add), 1, "android={android}: one gesture, one bookmark: {:?}", d.out);
            assert_eq!(d.marks(), 1);
            assert_eq!(d.count(is_host_move), 0, "no pan / jump on release: {:?}", d.out);
            assert!(mode(&d.s, MonitorId::Bands));
            // The bookmark row appeared (the plot shrank to make room).
            assert!(d.rect(chip_id(MonitorId::Bands, 1)).is_some());
        }
    }

    #[test]
    fn moving_before_the_hold_pans_and_does_not_bookmark() {
        let mut d = Drive::new(bands_on(), false);
        let c = d.shade().center();
        d.press(c);
        d.drag(Vec2::new(-20.0, 0.0));
        d.hold(1.0);
        d.drag(Vec2::new(-20.0, 0.0));
        d.release();
        assert_eq!(d.count(is_add), 0);
        assert!(!mode(&d.s, MonitorId::Bands), "it was a pan");
        // A short tap is a jump, not a bookmark.
        let mut d = Drive::new(bands_on(), false);
        let c = d.shade().center();
        d.press(c);
        d.release();
        assert_eq!(d.count(is_add), 0);
    }

    #[test]
    fn chips_jump_remove_by_long_press_and_x_on_desktop_only() {
        let mut s = bands_on();
        s.execute(cmd("monitor.bookmark_add", serde_json::json!({ "monitor": "bands", "end_s": 150.0, "window_s": 20.0 }))).unwrap();
        let mut d = Drive::new(s, false);
        let chip = d.rect(chip_id(MonitorId::Bands, 1)).unwrap();
        assert!(d.rect(chip_id(MonitorId::Bands, 1).with("x")).is_some(), "desktop ×");
        assert!(d.rect(icon_id(MonitorId::BandsOverview)).is_some(), "desktop icon");
        d.press(chip.center());
        d.release();
        let v = d.s.state().monitors.viewport(MonitorId::Bands);
        assert_eq!((v.window_s, v.end_s), (20.0, Some(150.0)), "tap = jump to the stored window");
        d.press(chip.center());
        d.hold(1.0);
        d.release();
        assert_eq!(d.marks(), 0, "long press removed it");
        assert_eq!(d.count(|c| matches!(c, Command::MonitorBookmarkGo { .. })), 1, "release after the hold did not jump again");
        // × removes on desktop; the icon adds.
        let icon = d.rect(icon_id(MonitorId::BandsOverview)).unwrap();
        d.press(icon.center());
        d.release();
        assert_eq!(d.marks(), 1);
        d.frame(vec![]);
        let x = d.rect(chip_id(MonitorId::Bands, 2).with("x")).unwrap();
        d.press(x.center());
        d.release();
        assert_eq!(d.marks(), 0);
    }

    #[test]
    fn android_has_no_icon_and_no_x() {
        let mut s = bands_on();
        s.execute(cmd("monitor.bookmark_add", serde_json::json!({ "monitor": "bands", "end_s": 150.0, "window_s": 20.0 }))).unwrap();
        let d = Drive::new(s, true);
        assert!(d.rect(chip_id(MonitorId::Bands, 1)).is_some());
        assert!(d.rect(chip_id(MonitorId::Bands, 1).with("x")).is_none());
        assert!(d.rect(icon_id(MonitorId::BandsOverview)).is_none());
    }

    #[test]
    fn in_graph_span_menu_does_not_pan_or_jump() {
        let mut d = Drive::new(bands_on(), false);
        let menu = d.rect(shade_id(MonitorId::BandsOverview).with("menu")).unwrap();
        assert!(menu.top() >= d.shade().top() - 1.0, "inside the plot: {menu:?}");
        d.press(menu.center());
        d.drag(Vec2::new(30.0, 0.0));
        d.release();
        assert_eq!(d.count(|c| matches!(c, Command::MonitorPan { .. })), 0, "{:?}", d.out);
        assert_eq!(d.count(is_host_move), 0);
        assert!(mode(&d.s, MonitorId::BandsOverview));
    }

    #[test]
    fn custom_zoom_shows_its_length_without_a_suffix() {
        let _lang = crate::i18n::lang_lock();
        let mut s = bands_on();
        s.execute(cmd("monitor.viewport", serde_json::json!({ "monitor": "bands", "window_s": 66.0 }))).unwrap();
        s.execute(cmd("monitor.viewport", serde_json::json!({ "monitor": "bands_overview", "window_s": 125.0 }))).unwrap();
        let t = crate::ui::views::histogram::tests::texts(&s, |u, s| {
            crate::ui::show(u, s, None);
        });
        assert!(t.iter().any(|x| x == "1m06s"), "{t:?}");
        assert!(t.iter().any(|x| x == "2m05s"), "overview menu: {t:?}");
        assert!(!t.iter().any(|x| x.contains("custom") || x.contains("eigene")));
    }

    #[test]
    fn follow_after_overview_drag_resets_both() {
        let mut d = Drive::new(bands_on(), false);
        d.press(OUTSIDE);
        d.drag(Vec2::new(60.0, 0.0));
        d.drag(Vec2::new(60.0, 0.0));
        d.release();
        assert!(!mode(&d.s, MonitorId::BandsOverview));
        d.s.execute(cmd("monitor.pan", serde_json::json!({ "monitor": "bands", "seconds": -20.0 }))).unwrap();
        // Double-click on the main plot = Follow.
        let main = Pos2::new(700.0, 300.0);
        for _ in 0..2 {
            d.press(main);
            d.pos = main;
            let e = vec![d.btn(false)];
            d.frame(e);
        }
        d.frame(vec![]);
        assert!(mode(&d.s, MonitorId::Bands) && mode(&d.s, MonitorId::BandsOverview));
    }
}
