//! Feedback: protocol cards → fit check → calibration → training → summary.
//! Calm by design: one status chip, one reason line, no expert tuning.

use egui::{Align2, Color32, FontId, Pos2, RichText, Sense, Stroke, Vec2};
use nf_core::feedback::{PadFit, PauseReason, Phase, Trainer, FIT_GREEN_S};
use nf_core::nf_feedback::{Eyes, HeldBack, Protocol};
use nf_core::trust::Trust;
use nf_core::{Command, Session};
use std::sync::Arc;

const GOOD: Color32 = Color32::from_rgb(0x66, 0xBB, 0x6A);
const FAIR: Color32 = Color32::from_rgb(0xFF, 0xB7, 0x4D);
const BAD: Color32 = Color32::from_rgb(0xE5, 0x73, 0x73);
const CALM: Color32 = Color32::from_rgb(0x4D, 0xB6, 0xAC);
const MINUTES: [u32; 4] = [5, 10, 20, 30];

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let t = session.trainer();
    // Phones: the text-heavy phases scroll vertically and never widen past
    // the screen. Live training sizes itself to the panel (no scroll).
    if compact(ui) && !matches!(t.phase, Phase::Playing | Phase::Paused { .. }) {
        egui::ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
            ui.set_max_width(ui.available_width());
            phase(ui, session, t, out);
        });
    } else {
        phase(ui, session, t, out);
    }
}

fn compact(ui: &egui::Ui) -> bool {
    crate::ui::layout::current(ui.ctx()).is_compact()
}

fn phase(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>) {
    match t.phase {
        Phase::Idle => protocols(ui, session, t, out),
        Phase::Ended if t.summary.is_none() => protocols(ui, session, t, out),
        Phase::Ended => summary(ui, session, t, out),
        Phase::FitCheck => fit_check(ui, session, t, out),
        Phase::Calibrating => calibrating(ui, session, t, out),
        Phase::Playing | Phase::Paused { .. } => training(ui, session, t, out),
    }
}

/// A button bound to a command id: disabled with the core's reason.
fn action(ui: &mut egui::Ui, session: &Session, id: &str, label: &str, primary: bool, cmd: Command, out: &mut Vec<Command>) {
    let enabled = session.enabled(id);
    let text = if primary { RichText::new(label).strong().size(16.0) } else { RichText::new(label) };
    let mut b = egui::Button::new(text).min_size(Vec2::new(0.0, if primary { 36.0 } else { 28.0 }));
    if primary {
        b = b.fill(CALM.gamma_multiply(0.6));
    }
    let r = ui.add_enabled(enabled.is_ok(), b);
    let r = match &enabled {
        Err(why) => r.on_disabled_hover_text(why),
        Ok(()) => r,
    };
    if r.clicked() {
        out.push(cmd);
    }
}

fn header(ui: &mut egui::Ui, title: &str, sub: &str) {
    ui.add_space(6.0);
    ui.heading(RichText::new(title).size(24.0));
    ui.weak(sub);
    ui.add_space(10.0);
}

fn chip(ui: &mut egui::Ui, text: &str, color: Color32) {
    let galley = ui.painter().layout_no_wrap(text.to_owned(), FontId::proportional(15.0), color);
    let (rect, _) = ui.allocate_exact_size(galley.size() + Vec2::new(28.0, 12.0), Sense::hover());
    let p = ui.painter();
    p.rect(rect, 14.0, color.gamma_multiply(0.2), Stroke::new(1.0_f32, color), egui::StrokeKind::Inside);
    p.galley(rect.center() - galley.size() / 2.0, galley, color);
}

fn eyes(e: Eyes) -> String {
    match e {
        Eyes::Open => t!("feedback-eyes-open"),
        Eyes::Closed => t!("feedback-eyes-closed"),
    }
}

/// One protocol card (picker and builder preview).
pub(super) fn card(ui: &mut egui::Ui, p: &Protocol, selected: bool, w: f32) -> egui::Response {
    let stroke =
        if selected { Stroke::new(2.0_f32, CALM) } else { Stroke::new(1.0_f32, ui.visuals().widgets.noninteractive.bg_stroke.color) };
    egui::Frame::group(ui.style())
        .stroke(stroke)
        .corner_radius(10.0)
        .inner_margin(12.0)
        .show(ui, |ui| {
            ui.set_width(w);
            ui.set_min_height(92.0);
            ui.vertical(|ui| {
                ui.horizontal(|ui| {
                    ui.label(RichText::new(crate::i18n::protocol_title(p)).strong().size(17.0));
                    if p.experimental {
                        ui.label(RichText::new(t!("feedback-tag-experimental")).small().color(FAIR));
                    }
                    if p.custom {
                        ui.label(RichText::new(t!("feedback-tag-custom")).small().color(CALM));
                    }
                    if p.guard_only {
                        ui.label(RichText::new(t!("feedback-tag-needs-ai")).small().color(FAIR));
                    }
                });
                ui.label(crate::i18n::protocol_summary(p));
                ui.weak(match &p.unavailable {
                    Some(r) => t!("feedback-not-available", reason = r.to_string()),
                    None => t!("feedback-eyes-minutes", eyes = eyes(p.eyes), min = p.default_minutes),
                });
            });
        })
        .response
}

fn protocols(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>) {
    let cal = if t.protocol.guard_only {
        t!(
            "feedback-calibrates-three-steps",
            title = crate::i18n::protocol_title(&t.protocol),
            s = nf_core::nf_feedback::STAGED_TIMED_S + nf_core::nf_feedback::BASELINE_VALID_S
        )
    } else {
        t!("feedback-calibration-takes", s = nf_core::nf_feedback::BASELINE_VALID_S)
    };
    header(ui, &t!("feedback-choose-a-protocol"), &format!("{} {cal}", t!("feedback-pick-then-start")));
    if let Some(m) = &t.message {
        chip(ui, m, FAIR);
        ui.add_space(8.0);
    }
    let narrow = compact(ui);
    // Regular: three columns. Compact: one full-width column (card frame
    // adds 12 px margin + stroke on each side).
    let (cols, w) = if narrow {
        (1, (ui.available_width() - 2.0 * 14.0).max(120.0))
    } else {
        (3, ((ui.available_width() - 3.0 * 26.0 - 24.0) / 3.0).max(200.0))
    };
    let all = nf_core::protocols::all(&session.state().custom_protocols);
    egui::Grid::new("protocol_cards").spacing([12.0, if narrow { 8.0 } else { 12.0 }]).show(ui, |ui| {
        for (i, p) in all.iter().enumerate() {
            let selected = p.id == t.protocol.id;
            let rect = card(ui, p, selected, w).rect;
            let resp = ui.interact(rect, ui.scope_id().with(&p.id), Sense::click());
            if resp.clicked() && !selected {
                out.push(Command::ProtocolSet { id: p.id.clone(), minutes: None });
            }
            if i % cols == cols - 1 {
                ui.end_row();
            }
        }
    });
    ui.add_space(6.0);
    super::protocol_builder::launcher(ui, session);
    super::protocol_builder::window(ui.ctx(), session, out);
    ui.add_space(14.0);
    super::sound::guard_row(ui, session, out);
    let lengths = |ui: &mut egui::Ui, out: &mut Vec<Command>| {
        ui.label(t!("feedback-length"));
        for m in MINUTES {
            if ui.selectable_label(t.minutes == m, t!("feedback-n-min", min = m)).clicked() {
                out.push(Command::ProtocolSet { id: t.protocol.id.clone(), minutes: Some(m) });
            }
        }
    };
    if narrow {
        // Lengths on one row, Start full width below (never clipped).
        ui.horizontal_wrapped(|ui| lengths(ui, out));
        ui.add_space(10.0);
        ui.scope(|ui| {
            ui.spacing_mut().button_padding.y = 8.0;
            let title = t!("feedback-start-title", title = crate::i18n::protocol_title(&t.protocol));
            let enabled = session.enabled("feedback.start");
            let b = egui::Button::new(RichText::new(title).strong().size(16.0))
                .fill(CALM.gamma_multiply(0.6))
                .min_size(Vec2::new(ui.available_width(), 44.0));
            let r = ui.add_enabled(enabled.is_ok(), b);
            let r = match &enabled {
                Err(why) => r.on_disabled_hover_text(why),
                Ok(()) => r,
            };
            if r.clicked() {
                out.push(Command::FeedbackStart { minutes: None, wall_clock_unix_ms: None });
            }
        });
        return;
    }
    ui.horizontal(|ui| {
        lengths(ui, out);
        ui.add_space(16.0);
        action(
            ui,
            session,
            "feedback.start",
            &t!("feedback-start-title", title = crate::i18n::protocol_title(&t.protocol)),
            true,
            Command::FeedbackStart { minutes: None, wall_clock_unix_ms: None },
            out,
        );
    });
}

/// Pad position on a top-down head (x right, y towards the nose), unit circle.
fn pad_pos(name: &str) -> Option<(f32, f32)> {
    Some(match name {
        "TP9" => (-0.92, -0.15),
        "AF7" => (-0.42, 0.82),
        "AF8" => (0.42, 0.82),
        "TP10" => (0.92, -0.15),
        "PO3" => (-0.3, -0.85),
        "PO4" => (0.3, -0.85),
        "F5" => (-0.6, 0.55),
        "F6" => (0.6, 0.55),
        "C3" => (-0.5, 0.0),
        "C4" => (0.5, 0.0),
        "CP3" => (-0.55, -0.35),
        "CP4" => (0.55, -0.35),
        _ => return None,
    })
}

fn pad_color(p: &PadFit) -> Color32 {
    if p.good {
        GOOD
    } else if p.quality >= 50.0 {
        FAIR
    } else {
        BAD
    }
}

fn hint(name: &str) -> String {
    match name {
        "AF7" | "AF8" => t!("feedback-hint-forehead"),
        "TP9" | "TP10" => t!("feedback-hint-ear"),
        _ => t!("feedback-hint-scalp"),
    }
}

fn head(ui: &mut egui::Ui, session: &Session, pads: &[PadFit], size: f32) {
    let (rect, _) = ui.allocate_exact_size(Vec2::splat(size), Sense::hover());
    let p = ui.painter_at(rect);
    let c = rect.center();
    let r = size * 0.38;
    let line = Stroke::new(2.0_f32, ui.visuals().weak_text_color());
    p.circle_stroke(c, r, line);
    p.line_segment([c + Vec2::new(-12.0, -r + 2.0), c + Vec2::new(0.0, -r - 16.0)], line);
    p.line_segment([c + Vec2::new(12.0, -r + 2.0), c + Vec2::new(0.0, -r - 16.0)], line);
    p.circle_stroke(c + Vec2::new(-r - 6.0, 0.0), 8.0, line);
    p.circle_stroke(c + Vec2::new(r + 6.0, 0.0), 8.0, line);
    let to = |(x, y): (f32, f32)| Pos2::new(c.x + x * r, c.y - y * r);
    // Other pads of the device (not used for reward) in grey.
    let channels = session.state().device.as_ref().map(|d| d.channels.clone()).unwrap_or_default();
    for n in channels.iter().filter(|n| !pads.iter().any(|p| &p.name == *n)) {
        if let Some(xy) = pad_pos(n) {
            p.circle_filled(to(xy), 9.0, ui.visuals().widgets.inactive.bg_fill);
            p.text(to(xy) + Vec2::new(0.0, 16.0), Align2::CENTER_TOP, n, FontId::proportional(11.0), ui.visuals().weak_text_color());
        }
    }
    for (i, pad) in pads.iter().enumerate() {
        let xy = pad_pos(&pad.name).unwrap_or((-0.5 + i as f32 * 0.3, 0.5));
        p.circle_filled(to(xy), 14.0, pad_color(pad));
        p.text(to(xy) + Vec2::new(0.0, 18.0), Align2::CENTER_TOP, &pad.name, FontId::proportional(13.0), ui.visuals().strong_text_color());
    }
}

fn fit_check(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>) {
    header(ui, &t!("feedback-fit-check"), &t!("feedback-put-the-headband-on-the"));
    if compact(ui) {
        // Head on top (scaled to the width), status and buttons below.
        let size = ui.available_width().clamp(160.0, 260.0);
        ui.vertical_centered(|ui| head(ui, session, &t.pads, size));
        ui.add_space(6.0);
        fit_controls(ui, session, t, out, true);
        return;
    }
    ui.horizontal(|ui| {
        head(ui, session, &t.pads, 260.0);
        ui.vertical(|ui| {
            ui.add_space(20.0);
            fit_controls(ui, session, t, out, false);
        });
    });
}

/// Fit status, per-pad hints and the calibrate/cancel buttons. `narrow`
/// wraps the button row instead of letting it run off a phone screen.
fn fit_controls(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>, narrow: bool) {
    if t.fit_ready() {
        chip(ui, &t!("feedback-good-fit-ready-to-calibrate"), GOOD);
    } else if t.pads.iter().all(|p| p.good) && !t.pads.is_empty() {
        chip(ui, &t!("feedback-hold-still", n = t.green_for, total = FIT_GREEN_S), GOOD);
    } else {
        chip(ui, &t!("feedback-adjust-the-headband"), FAIR);
    }
    ui.add_space(10.0);
    for p in t.pads.iter().filter(|p| !p.good) {
        ui.label(format!("{}: {}", p.name, hint(&p.name)));
    }
    if let Some(m) = &t.message {
        ui.add_space(6.0);
        ui.colored_label(FAIR, m);
    }
    ui.add_space(16.0);
    let row = |ui: &mut egui::Ui, out: &mut Vec<Command>| {
        ui.add_enabled_ui(t.fit_ready(), |ui| {
            action(ui, session, "calibration.start", &t!("feedback-calibrate"), true, Command::CalibrationStart { anyway: false }, out);
        });
        action(ui, session, "calibration.start", &t!("feedback-start-anyway"), false, Command::CalibrationStart { anyway: true }, out);
        action(ui, session, "calibration.reuse", &t!("feedback-reuse-last-baseline"), false, Command::CalibrationReuse, out);
    };
    if narrow {
        ui.horizontal_wrapped(|ui| row(ui, out));
    } else {
        ui.horizontal(|ui| row(ui, out));
    }
    ui.add_space(8.0);
    action(ui, session, "feedback.stop", &t!("feedback-cancel"), false, Command::FeedbackStop, out);
}

fn calibrating(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>) {
    let Some(c) = &t.calibration else { return };
    use nf_core::nf_feedback::CalStage;
    let instruction = match (c.staged, c.stage, t.protocol.eyes) {
        (true, CalStage::Artifacts, _) => t!("feedback-step-1-3-sit-still"),
        (true, CalStage::EyesOpen, _) => t!("feedback-step-2-3-eyes-open"),
        (true, CalStage::EyesClosed, _) => t!("feedback-step-3-3-close-your"),
        (false, _, Eyes::Closed) => t!("feedback-close-your-eyes-relax-and"),
        (false, _, Eyes::Open) => t!("feedback-keep-your-eyes-open-on"),
    };
    header(ui, &t!("feedback-calibrating"), &instruction);
    let narrow = compact(ui);
    let bar_w = if narrow { ui.available_width() } else { 520.0 };
    ui.add(egui::ProgressBar::new(c.valid_s as f32 / c.needed_s.max(1) as f32).desired_width(bar_w).text(t!(
        "feedback-good-seconds",
        n = c.valid_s,
        total = c.needed_s
    )));
    ui.weak(t!("feedback-elapsed-stops-at", s = c.wall_s, max = c.max_s));
    ui.add_space(10.0);
    if c.awake_missing {
        egui::Frame::group(ui.style()).stroke(Stroke::new(1.5_f32, BAD)).inner_margin(10.0).show(ui, |ui| {
            ui.set_max_width(bar_w);
            ui.label(RichText::new(t!("feedback-no-awake-reference")).strong().color(BAD));
            ui.label(t!("feedback-the-ai-model-gave-no"));
            ui.weak(t!("feedback-cancel-check-the-model-is"));
        });
    } else {
        match &c.waiting {
            Some(w) => chip(ui, &t!("feedback-paused-reason", reason = w.to_string()), FAIR),
            None => chip(ui, &t!("feedback-collecting"), GOOD),
        }
    }
    ui.add_space(16.0);
    let row = |ui: &mut egui::Ui, out: &mut Vec<Command>| {
        action(ui, session, "calibration.skip", &t!("feedback-start-now"), false, Command::CalibrationSkip, out);
        action(ui, session, "calibration.reuse", &t!("feedback-reuse-last-baseline"), false, Command::CalibrationReuse, out);
        action(ui, session, "feedback.stop", &t!("feedback-cancel"), false, Command::FeedbackStop, out);
    };
    if narrow {
        ui.horizontal_wrapped(|ui| row(ui, out));
    } else {
        ui.horizontal(|ui| row(ui, out));
    }
}

fn mmss(s: u32) -> String {
    format!("{}:{:02}", s / 60, s % 60)
}

/// Dashboard view state (per app run).
#[derive(Clone, Default)]
struct Dash {
    show_trust: bool,
    show_nerd: bool,
    plot: super::trust::Plot,
    /// (results seen, trust built from them).
    cache: Option<(usize, f64, Arc<Trust>)>,
}

fn dash_id() -> egui::Id {
    egui::Id::unique("feedback_dashboard")
}

/// Trust of the current run, rebuilt only when a second was added.
fn live_trust(t: &Trainer, d: &mut Dash) -> Arc<Trust> {
    let key = (t.results.len(), t.results.last().map_or(0.0, |r| r.time));
    match &d.cache {
        Some((n, at, tr)) if (*n, *at) == key => tr.clone(),
        _ => {
            let tr = Arc::new(nf_core::trust::build(nf_core::trust::rows_from_results(&t.results), Vec::new()));
            d.cache = Some((key.0, key.1, tr.clone()));
            tr
        }
    }
}

/// Status chip text and colour for the training screen.
fn status(t: &Trainer) -> (String, Color32) {
    let last = t.last();
    let rec = last.and_then(|r| r.record.as_ref());
    let held = rec.and_then(|r| r.held_back.as_ref()).and_then(|h| h.first());
    match t.phase {
        Phase::Paused { reason: PauseReason::User } => (t!("feedback-paused").to_owned(), FAIR),
        Phase::Paused { reason: PauseReason::BadSignal } => (t!("feedback-paused-waiting-for-good-signal").to_owned(), FAIR),
        Phase::Paused { reason: PauseReason::Disconnected } => (t!("feedback-paused-device-disconnected").to_owned(), BAD),
        _ if last.is_some_and(|r| r.in_target) => (t!("feedback-in-target").to_owned(), GOOD),
        _ if held.is_some() => {
            (t!("feedback-held-back", reason = format!("{:?}", held.copied().unwrap_or(HeldBack::NoThreshold)).to_lowercase()), FAIR)
        }
        _ => (t!("feedback-training").to_owned(), CALM),
    }
}

fn training(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>) {
    let mut d: Dash = ui.data(|x| x.get_temp(dash_id())).unwrap_or_default();
    let narrow = compact(ui);
    let header = |ui: &mut egui::Ui, d: &mut Dash| {
        ui.heading(crate::i18n::protocol_title(&t.protocol));
        ui.weak(t!("feedback-time-left", time = mmss(t.total_s().saturating_sub(t.played_s))));
        let frac = t.played_s as f32 / t.total_s().max(1) as f32;
        ui.add(egui::ProgressBar::new(frac).desired_width(160.0).desired_height(6.0));
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.toggle_value(&mut d.show_nerd, t!("feedback-nerd")).on_hover_text(t!("feedback-the-numbers-behind-the-reward"));
            ui.toggle_value(&mut d.show_trust, t!("feedback-trust")).on_hover_text(t!("feedback-live-trust-trace-what-each"));
        });
    };
    if narrow {
        // Phones: title + time left on one line, progress and toggles below.
        ui.horizontal_wrapped(|ui| {
            ui.heading(crate::i18n::protocol_title(&t.protocol));
            ui.weak(t!("feedback-time-left", time = mmss(t.total_s().saturating_sub(t.played_s))));
        });
        ui.horizontal(|ui| {
            let frac = t.played_s as f32 / t.total_s().max(1) as f32;
            ui.add(egui::ProgressBar::new(frac).desired_width((ui.available_width() - 120.0).max(60.0)).desired_height(6.0));
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.toggle_value(&mut d.show_nerd, t!("feedback-nerd"));
                ui.toggle_value(&mut d.show_trust, t!("feedback-trust"));
            });
        });
    } else {
        ui.horizontal(|ui| header(ui, &mut d));
    }
    if session.state().settings.debug {
        feature_override(ui, t, out);
    }
    if d.show_nerd {
        let n = nf_core::nerd::build(t, session.state().time);
        super::nerd::window(ui.ctx(), &mut d.show_nerd, &n);
    }
    if d.show_trust {
        let trust = live_trust(t, &mut d);
        if crate::ui::layout::current(ui.ctx()).is_compact() {
            indicator(ui, session, t, out);
            super::trust::pane(ui, &trust, &mut d.plot, 180.0, false);
        } else {
            ui.columns(2, |c| {
                indicator(&mut c[0], session, t, out);
                super::trust::pane(&mut c[1], &trust, &mut d.plot, 180.0, false);
            });
        }
    } else {
        indicator(ui, session, t, out);
    }
    ui.data_mut(|x| x.insert_temp(dash_id(), d));
}

/// Percentile meter: fill = last percentile, tick = threshold percentile.
fn meter(p: &egui::Painter, rect: egui::Rect, pct: Option<f64>, thr: Option<f64>, color: Color32) {
    p.rect(rect, 4.0, color.gamma_multiply(0.12), Stroke::new(1.0_f32, color.gamma_multiply(0.6)), egui::StrokeKind::Inside);
    let y = |v: f64| rect.bottom() - (v.clamp(0.0, 100.0) as f32 / 100.0) * rect.height();
    if let Some(v) = pct {
        p.rect_filled(egui::Rect::from_min_max(Pos2::new(rect.left(), y(v)), rect.right_bottom()), 4.0, color.gamma_multiply(0.7));
    }
    if let Some(v) = thr {
        let yy = y(v);
        p.line_segment([Pos2::new(rect.left() - 6.0, yy), Pos2::new(rect.right() + 6.0, yy)], Stroke::new(2.0_f32, FAIR));
        p.text(Pos2::new(rect.right() + 9.0, yy), Align2::LEFT_CENTER, "threshold", FontId::proportional(11.0), FAIR);
    }
}

fn indicator(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>) {
    let last = t.last();
    let in_target = last.is_some_and(|r| r.in_target) && t.phase == Phase::Playing;
    let (status, color) = status(t);
    let avail = ui.available_size();
    let h = (avail.y - 120.0).max(200.0);
    let (rect, _) = ui.allocate_exact_size(Vec2::new(avail.x, h), Sense::hover());
    let p = ui.painter_at(rect);
    let r = (h * 0.32).min((avail.x - 140.0) * 0.36).max(40.0);
    let glow = if in_target { GOOD } else { CALM.gamma_multiply(0.35) };
    for k in 0..6 {
        let f = 1.0 + k as f32 * 0.08;
        p.circle_filled(rect.center(), r * f, glow.gamma_multiply(0.18 / (k as f32 + 1.0)));
    }
    p.circle_filled(rect.center(), r, glow.gamma_multiply(0.55));
    p.circle_stroke(rect.center(), r, Stroke::new(2.0_f32, glow));
    let rec = last.and_then(|x| x.record.as_ref());
    let bar = egui::Rect::from_center_size(
        Pos2::new((rect.center().x + r * 1.45).min(rect.right() - 80.0), rect.center().y),
        Vec2::new(14.0, r * 1.8),
    );
    if bar.right() + 60.0 < rect.right() {
        meter(&p, bar, rec.and_then(|x| x.pct), rec.and_then(|x| x.thr_pct), if in_target { GOOD } else { CALM });
    }
    ui.vertical_centered(|ui| {
        chip(ui, &status, color);
        if rec.and_then(|r| r.warn) == Some(true) {
            ui.add_space(4.0);
            chip(ui, &t!("feedback-drowsiness-warning"), FAIR);
        }
        ui.add_space(6.0);
        let why = last.and_then(|r| (!r.counted).then(|| r.reason.clone()).flatten());
        ui.weak(why.map_or(" ".to_owned(), |w| t!("feedback-last-second-didnt-count", reason = w.to_string())));
        ui.add_space(8.0);
        ui.horizontal(|ui| {
            ui.add_space((ui.available_width() - 200.0).max(0.0) / 2.0);
            if matches!(t.phase, Phase::Paused { .. }) {
                action(ui, session, "feedback.resume", &t!("feedback-resume"), false, Command::FeedbackResume, out);
            } else {
                action(ui, session, "feedback.pause", &t!("feedback-pause"), false, Command::FeedbackPause, out);
            }
            action(ui, session, "feedback.stop", &t!("feedback-end-session"), false, Command::FeedbackStop, out);
        });
    });
}

fn summary(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>) {
    let Some(s) = &t.summary else { return };
    header(
        ui,
        &t!("feedback-session-complete"),
        &t!("feedback-ended-by", title = crate::i18n::protocol_title(&t.protocol), reason = s.ended_by.to_string()),
    );
    let mut d: Dash = ui.data(|x| x.get_temp(dash_id())).unwrap_or_default();
    let trust = live_trust(t, &mut d);
    let narrow = compact(ui);
    let plot_h = if narrow { 160.0 } else { 200.0 };
    ui.allocate_ui(Vec2::new(ui.available_width().min(900.0), 360.0), |ui| super::trust::pane(ui, &trust, &mut d.plot, plot_h, true));
    ui.data_mut(|x| x.insert_temp(dash_id(), d));
    ui.add_space(6.0);
    let thr = |x: Option<f64>| x.map_or("--".into(), |v| format!("{v:.3}"));
    ui.weak(t!(
        "feedback-summary-line",
        from = thr(s.threshold_start),
        to = thr(s.threshold_end),
        steps = s.adapt_steps,
        counted = s.counted_s,
        pauses = s.pauses
    ));
    if let Some(id) = t.saved_id {
        ui.add_space(8.0);
        super::meta::notes(ui, session, id, out);
    }
    ui.add_space(14.0);
    let row = |ui: &mut egui::Ui, out: &mut Vec<Command>| {
        action(
            ui,
            session,
            "feedback.start",
            &t!("feedback-train-again"),
            true,
            Command::FeedbackStart { minutes: None, wall_clock_unix_ms: None },
            out,
        );
        action(
            ui,
            session,
            "protocol.set",
            &t!("feedback-choose-protocol"),
            false,
            Command::ProtocolSet { id: t.protocol.id.clone(), minutes: None },
            out,
        );
        action(ui, session, "view.set", &t!("feedback-open-history"), false, Command::ViewSet { view: nf_core::View::History }, out);
    };
    if narrow {
        ui.horizontal_wrapped(|ui| row(ui, out));
    } else {
        ui.horizontal(|ui| row(ui, out));
    }
}

/// Debug feature override (legacy `feature_override.dart`): latch the
/// protocol feature to a slider value. Ratios 0..3 (start 0.4), shares 0..1 (start 0.3).
fn feature_override(ui: &mut egui::Ui, t: &Trainer, out: &mut Vec<Command>) {
    use nf_core::nf_feedback::Feature;
    let (max, init) = match t.protocol.feature {
        Feature::Atr | Feature::Tar | Feature::Btr => (3.0, 0.4),
        _ => (1.0, 0.3),
    };
    ui.horizontal(|ui| {
        ui.weak(t!("feedback-debug"));
        let mut on = t.feature_override.is_some();
        if ui.checkbox(&mut on, t!("feedback-override-feature")).changed() {
            out.push(Command::FeedbackOverride { value: on.then_some(init) });
        }
        if let Some(mut v) = t.feature_override {
            let r = ui.add(egui::Slider::new(&mut v, 0.0..=max).fixed_decimals(2));
            if r.changed() {
                out.push(Command::FeedbackOverride { value: Some(v) });
            }
        }
    });
}

#[cfg(test)]
mod compact_tests {
    #![allow(clippy::unwrap_used, clippy::panic)]
    use super::*;
    use egui::{Pos2, Rect};
    use serde_json::json;

    /// Text shapes of the last of `n` full-app frames: (text, left, right).
    fn texts(s: &mut Session, size: Vec2, n: usize) -> Vec<(String, f32, f32)> {
        let _lang = crate::i18n::lang_lock();
        let ctx = egui::Context::default();
        let mut last = Vec::new();
        for i in 0..n {
            let input = egui::RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, size)),
                time: Some(i as f64 / 60.0),
                ..Default::default()
            };
            let mut o = ctx.run_ui(input, |u| {
                crate::ui::show(u, s, None);
            });
            o.textures_delta.clear();
            last = o.shapes;
        }
        last.iter()
            .filter_map(|c| match &c.shape {
                egui::Shape::Text(t) => {
                    let r = t.galley.rect.translate(t.pos.to_vec2());
                    Some((t.galley.text().to_owned(), r.left(), r.right()))
                }
                _ => None,
            })
            .collect()
    }

    fn session(layout: &str) -> Session {
        let mut s = Session::new();
        s.call("settings.set", json!({ "onboarded": true, "layout": layout })).unwrap();
        s.call("device.connect", json!({ "id": "sim:muse_s" })).unwrap();
        s.call("view.set", json!({ "view": "feedback" })).unwrap();
        s.call("protocol.set", json!({ "id": "alertOpen" })).unwrap();
        s.call("clock.advance", json!({ "seconds": 5.0 })).unwrap();
        s
    }

    fn to_fit_check(s: &mut Session) {
        s.call("feedback.start", json!({})).unwrap();
        s.call("clock.advance", json!({ "seconds": 5.0 })).unwrap();
        assert_eq!(s.trainer().phase, Phase::FitCheck);
    }

    fn to_summary(s: &mut Session) {
        to_fit_check(s);
        s.call("calibration.start", json!({ "anyway": false })).unwrap();
        for _ in 0..20 {
            s.call("clock.advance", json!({ "seconds": 5.0 })).unwrap();
        }
        assert_eq!(s.trainer().phase, Phase::Playing);
        s.call("clock.advance", json!({ "seconds": 30.0 })).unwrap();
        s.call("feedback.stop", json!({})).unwrap();
        assert!(s.trainer().summary.is_some());
    }

    /// Every text stays inside the screen width (nothing clipped at the right).
    fn assert_fits(t: &[(String, f32, f32)], w: f32, what: &str) {
        let bad: Vec<_> = t.iter().filter(|(_, l, r)| *r > w + 0.5 || *l < -0.5).collect();
        assert!(bad.is_empty(), "{what} at {w} px: off-screen texts {bad:?}");
    }

    const PHONES: [(f32, f32); 2] = [(400.0, 850.0), (360.0, 800.0)];

    #[test]
    fn compact_overview_fits_and_start_is_fully_visible() {
        for (w, h) in PHONES {
            let mut s = session("compact");
            let t = texts(&mut s, Vec2::new(w, h), 3);
            assert_fits(&t, w, "overview");
            // Taller frame so the scrolled-off part is painted too.
            let t = texts(&mut s, Vec2::new(w, 1800.0), 3);
            assert_fits(&t, w, "overview (full)");
            let start = t.iter().find(|(x, ..)| x.starts_with("Start ")).expect("start button");
            assert!(start.2 <= w, "{start:?}");
            // One card per row: all titles start at the same x.
            let lefts: Vec<f32> = ["Rest Awake", "Open Monitor", "Alert, Eyes Open"]
                .iter()
                .map(|n| t.iter().find(|(x, ..)| x == n).unwrap_or_else(|| panic!("{n}")).1)
                .collect();
            assert!(lefts.iter().all(|l| (l - lefts[0]).abs() < 2.0), "{lefts:?}");
        }
    }

    #[test]
    fn compact_fit_check_and_summary_fit_the_screen() {
        for (w, h) in PHONES {
            let mut s = session("compact");
            to_fit_check(&mut s);
            let t = texts(&mut s, Vec2::new(w, h), 3);
            assert_fits(&t, w, "fit check");
            assert!(t.iter().any(|(x, ..)| x == "Calibrate"));

            let mut s = session("compact");
            to_summary(&mut s);
            let t = texts(&mut s, Vec2::new(w, h), 3);
            assert_fits(&t, w, "summary");
            // Stats are whole cells: label and value each on one line.
            for n in ["In zone", "Clean", "Held back", "Trained", "Rewards", "100 %"] {
                assert!(t.iter().any(|(x, ..)| x == n), "{n} split or missing: {t:?}");
            }
        }
    }

    #[test]
    fn compact_live_header_fits() {
        for (w, h) in PHONES {
            let mut s = session("compact");
            to_fit_check(&mut s);
            s.call("calibration.start", json!({ "anyway": false })).unwrap();
            for _ in 0..20 {
                s.call("clock.advance", json!({ "seconds": 5.0 })).unwrap();
            }
            assert_eq!(s.trainer().phase, Phase::Playing);
            let t = texts(&mut s, Vec2::new(w, h), 3);
            assert_fits(&t, w, "live");
            assert!(t.iter().any(|(x, ..)| x == "Nerd") && t.iter().any(|(x, ..)| x == "End session"), "{t:?}");
        }
    }

    #[test]
    fn regular_overview_keeps_three_columns() {
        let mut s = session("regular");
        let t = texts(&mut s, Vec2::new(1280.0, 800.0), 3);
        let left = |n: &str| t.iter().find(|(x, ..)| x == n).unwrap_or_else(|| panic!("{n}")).1;
        assert!(left("Rest Awake") < left("Open Monitor") && left("Open Monitor") < left("Alert, Eyes Open"));
        assert!((left("Rest Awake") - left("Alert, Eyes Closed")).abs() < 1.0);
    }
}
