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
    p.rect(rect, 14.0, color.gamma_multiply(0.2), Stroke::new(1.0_f32, color));
    p.galley(rect.center() - galley.size() / 2.0, galley, color);
}

fn eyes(e: Eyes) -> &'static str {
    match e {
        Eyes::Open => "eyes open",
        Eyes::Closed => "eyes closed",
    }
}

/// One protocol card (picker and builder preview).
pub(super) fn card(ui: &mut egui::Ui, p: &Protocol, selected: bool, w: f32) -> egui::Response {
    let stroke =
        if selected { Stroke::new(2.0_f32, CALM) } else { Stroke::new(1.0_f32, ui.visuals().widgets.noninteractive.bg_stroke.color) };
    egui::Frame::group(ui.style())
        .stroke(stroke)
        .rounding(10.0)
        .inner_margin(12.0)
        .show(ui, |ui| {
            ui.set_width(w);
            ui.set_height(92.0);
            ui.vertical(|ui| {
                ui.horizontal(|ui| {
                    ui.label(RichText::new(&p.title).strong().size(17.0));
                    if p.experimental {
                        ui.label(RichText::new("experimental").small().color(FAIR));
                    }
                    if p.custom {
                        ui.label(RichText::new("custom").small().color(CALM));
                    }
                    if p.guard_only {
                        ui.label(RichText::new("needs AI model").small().color(FAIR));
                    }
                });
                ui.label(&p.summary);
                ui.weak(match &p.unavailable {
                    Some(r) => format!("Not available: {r}"),
                    None => format!("{} · {} min", eyes(p.eyes), p.default_minutes),
                });
            });
        })
        .response
}

fn protocols(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>) {
    let cal = if t.protocol.guard_only {
        format!(
            "{} calibrates in three steps, about {} s.",
            t.protocol.title,
            nf_core::nf_feedback::STAGED_TIMED_S + nf_core::nf_feedback::BASELINE_VALID_S
        )
    } else {
        format!("Calibration takes about {} seconds.", nf_core::nf_feedback::BASELINE_VALID_S)
    };
    header(ui, "Choose a protocol", &format!("Pick what to train, then start. {cal}"));
    if let Some(m) = &t.message {
        chip(ui, m, FAIR);
        ui.add_space(8.0);
    }
    let w = ((ui.available_width() - 3.0 * 26.0 - 24.0) / 3.0).max(200.0);
    let all = nf_core::protocols::all(&session.state().custom_protocols);
    egui::Grid::new("protocol_cards").spacing([12.0, 12.0]).show(ui, |ui| {
        for (i, p) in all.iter().enumerate() {
            let selected = p.id == t.protocol.id;
            let rect = card(ui, p, selected, w).rect;
            let resp = ui.interact(rect, ui.id().with(&p.id), Sense::click());
            if resp.clicked() && !selected {
                out.push(Command::ProtocolSet { id: p.id.clone(), minutes: None });
            }
            if i % 3 == 2 {
                ui.end_row();
            }
        }
    });
    ui.add_space(6.0);
    super::protocol_builder::launcher(ui, session);
    super::protocol_builder::window(ui.ctx(), session, out);
    ui.add_space(14.0);
    super::sound::guard_row(ui, session, out);
    ui.horizontal(|ui| {
        ui.label("Length:");
        for m in MINUTES {
            if ui.selectable_label(t.minutes == m, format!("{m} min")).clicked() {
                out.push(Command::ProtocolSet { id: t.protocol.id.clone(), minutes: Some(m) });
            }
        }
        ui.add_space(16.0);
        action(
            ui,
            session,
            "feedback.start",
            &format!("Start {}", t.protocol.title),
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

fn hint(name: &str) -> &'static str {
    match name {
        "AF7" | "AF8" => "forehead sensor: press flat on bare skin, move hair away",
        "TP9" | "TP10" => "ear sensor: tuck behind the ear, touching skin",
        _ => "press the sensor onto the scalp, part the hair",
    }
}

fn head(ui: &mut egui::Ui, session: &Session, pads: &[PadFit]) {
    let size = 260.0;
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
    header(ui, "Fit check", "Put the headband on. The sensors used for training should turn green.");
    ui.horizontal(|ui| {
        head(ui, session, &t.pads);
        ui.vertical(|ui| {
            ui.add_space(20.0);
            if t.fit_ready() {
                chip(ui, "Good fit, ready to calibrate", GOOD);
            } else if t.pads.iter().all(|p| p.good) && !t.pads.is_empty() {
                chip(ui, &format!("Hold still… {}/{FIT_GREEN_S} s", t.green_for), GOOD);
            } else {
                chip(ui, "Adjust the headband", FAIR);
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
            ui.horizontal(|ui| {
                ui.add_enabled_ui(t.fit_ready(), |ui| {
                    action(ui, session, "calibration.start", "Calibrate", true, Command::CalibrationStart { anyway: false }, out);
                });
                action(ui, session, "calibration.start", "Start anyway", false, Command::CalibrationStart { anyway: true }, out);
                action(ui, session, "calibration.reuse", "Reuse last baseline", false, Command::CalibrationReuse, out);
            });
            ui.add_space(8.0);
            action(ui, session, "feedback.stop", "Cancel", false, Command::FeedbackStop, out);
        });
    });
}

fn calibrating(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>) {
    let Some(c) = &t.calibration else { return };
    use nf_core::nf_feedback::CalStage;
    let instruction = match (c.staged, c.stage, t.protocol.eyes) {
        (true, CalStage::Artifacts, _) => "Step 1/3: sit still, eyes open, while the signal settles.",
        (true, CalStage::EyesOpen, _) => "Step 2/3: eyes open, look at a calm point — this is your 'awake' reference.",
        (true, CalStage::EyesClosed, _) => "Step 3/3: close your eyes and relax — this sets your drowsiness baseline.",
        (false, _, Eyes::Closed) => "Close your eyes, relax and sit still.",
        (false, _, Eyes::Open) => "Keep your eyes open on a calm point and sit still.",
    };
    header(ui, "Calibrating", instruction);
    ui.add(
        egui::ProgressBar::new(c.valid_s as f32 / c.needed_s.max(1) as f32)
            .desired_width(520.0)
            .text(format!("{} of {} good seconds", c.valid_s, c.needed_s)),
    );
    ui.weak(format!("{} s elapsed · stops at {} s even if the signal was poor", c.wall_s, c.max_s));
    ui.add_space(10.0);
    if c.awake_missing {
        egui::Frame::group(ui.style()).stroke(Stroke::new(1.5_f32, BAD)).inner_margin(10.0).show(ui, |ui| {
            ui.set_max_width(520.0);
            ui.label(RichText::new("No awake reference").strong().color(BAD));
            ui.label("The AI model gave no score during the eyes-open step, so Sleep Guard cannot learn your drowsiness baseline and these seconds do not count.");
            ui.weak("Cancel, check the model is Ready (Settings → AI), then calibrate again.");
        });
    } else {
        match &c.waiting {
            Some(w) => chip(ui, &format!("Paused: {w}"), FAIR),
            None => chip(ui, "Collecting", GOOD),
        }
    }
    ui.add_space(16.0);
    ui.horizontal(|ui| {
        action(ui, session, "calibration.skip", "Start now", false, Command::CalibrationSkip, out);
        action(ui, session, "calibration.reuse", "Reuse last baseline", false, Command::CalibrationReuse, out);
        action(ui, session, "feedback.stop", "Cancel", false, Command::FeedbackStop, out);
    });
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
    egui::Id::new("feedback_dashboard")
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
        Phase::Paused { reason: PauseReason::User } => ("Paused".to_owned(), FAIR),
        Phase::Paused { reason: PauseReason::BadSignal } => ("Paused: waiting for good signal".to_owned(), FAIR),
        Phase::Paused { reason: PauseReason::Disconnected } => ("Paused: device disconnected".to_owned(), BAD),
        _ if last.is_some_and(|r| r.in_target) => ("In target".to_owned(), GOOD),
        _ if held.is_some() => {
            (format!("Held back ({})", format!("{:?}", held.copied().unwrap_or(HeldBack::NoThreshold)).to_lowercase()), FAIR)
        }
        _ => ("Training".to_owned(), CALM),
    }
}

fn training(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>) {
    let mut d: Dash = ui.data(|x| x.get_temp(dash_id())).unwrap_or_default();
    ui.horizontal(|ui| {
        ui.heading(&t.protocol.title);
        ui.weak(format!("{} left", mmss(t.total_s().saturating_sub(t.played_s))));
        let frac = t.played_s as f32 / t.total_s().max(1) as f32;
        ui.add(egui::ProgressBar::new(frac).desired_width(160.0).desired_height(6.0));
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.toggle_value(&mut d.show_nerd, "Nerd").on_hover_text("The numbers behind the reward decision");
            ui.toggle_value(&mut d.show_trust, "Trust").on_hover_text("Live trust trace: what each second really was");
        });
    });
    if session.state().settings.debug {
        feature_override(ui, t, out);
    }
    if d.show_nerd {
        let n = nf_core::nerd::build(t, session.state().time);
        super::nerd::window(ui.ctx(), &mut d.show_nerd, &n);
    }
    if d.show_trust {
        let trust = live_trust(t, &mut d);
        ui.columns(2, |c| {
            indicator(&mut c[0], session, t, out);
            super::trust::pane(&mut c[1], &trust, &mut d.plot, 180.0, false);
        });
    } else {
        indicator(ui, session, t, out);
    }
    ui.data_mut(|x| x.insert_temp(dash_id(), d));
}

/// Percentile meter: fill = last percentile, tick = threshold percentile.
fn meter(p: &egui::Painter, rect: egui::Rect, pct: Option<f64>, thr: Option<f64>, color: Color32) {
    p.rect(rect, 4.0, color.gamma_multiply(0.12), Stroke::new(1.0_f32, color.gamma_multiply(0.6)));
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
            chip(ui, "Drowsiness warning", FAIR);
        }
        ui.add_space(6.0);
        let why = last.and_then(|r| (!r.counted).then(|| r.reason.clone()).flatten());
        ui.weak(why.map_or(" ".to_owned(), |w| format!("Last second didn't count: {w}")));
        ui.add_space(8.0);
        ui.horizontal(|ui| {
            ui.add_space((ui.available_width() - 200.0).max(0.0) / 2.0);
            if matches!(t.phase, Phase::Paused { .. }) {
                action(ui, session, "feedback.resume", "Resume", false, Command::FeedbackResume, out);
            } else {
                action(ui, session, "feedback.pause", "Pause", false, Command::FeedbackPause, out);
            }
            action(ui, session, "feedback.stop", "End session", false, Command::FeedbackStop, out);
        });
    });
}

fn summary(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>) {
    let Some(s) = &t.summary else { return };
    header(ui, "Session complete", &format!("{} · ended: {}", t.protocol.title, s.ended_by));
    let mut d: Dash = ui.data(|x| x.get_temp(dash_id())).unwrap_or_default();
    let trust = live_trust(t, &mut d);
    ui.allocate_ui(Vec2::new(ui.available_width().min(900.0), 360.0), |ui| super::trust::pane(ui, &trust, &mut d.plot, 200.0, true));
    ui.data_mut(|x| x.insert_temp(dash_id(), d));
    ui.add_space(6.0);
    let thr = |x: Option<f64>| x.map_or("--".into(), |v| format!("{v:.3}"));
    ui.weak(format!(
        "Threshold {} to {} ({} adjustments) · {} counted seconds · {} pauses · saved to History",
        thr(s.threshold_start),
        thr(s.threshold_end),
        s.adapt_steps,
        s.counted_s,
        s.pauses
    ));
    if let Some(id) = t.saved_id {
        ui.add_space(8.0);
        super::meta::notes(ui, session, id, out);
    }
    ui.add_space(14.0);
    ui.horizontal(|ui| {
        action(ui, session, "feedback.start", "Train again", true, Command::FeedbackStart { minutes: None, wall_clock_unix_ms: None }, out);
        action(
            ui,
            session,
            "protocol.set",
            "Choose protocol",
            false,
            Command::ProtocolSet { id: t.protocol.id.clone(), minutes: None },
            out,
        );
        action(ui, session, "view.set", "Open History", false, Command::ViewSet { view: nf_core::View::History }, out);
    });
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
        ui.weak("Debug");
        let mut on = t.feature_override.is_some();
        if ui.checkbox(&mut on, "Override feature").changed() {
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
