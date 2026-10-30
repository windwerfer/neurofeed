//! Feedback: protocol cards → fit check → calibration → training → summary.
//! Calm by design: one status chip, one reason line, no expert tuning.

use egui::{Align2, Color32, FontId, Pos2, RichText, Sense, Stroke, Vec2};
use nf_core::feedback::{PadFit, PauseReason, Phase, Trainer, FIT_GREEN_S};
use nf_core::nf_feedback::{Eyes, PROTOCOLS};
use nf_core::{Command, Session};

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

fn protocols(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>) {
    header(ui, "Choose a protocol", "Pick what to train, then start. Calibration takes about 45 seconds.");
    if let Some(m) = &t.message {
        chip(ui, m, FAIR);
        ui.add_space(8.0);
    }
    let w = ((ui.available_width() - 3.0 * 26.0 - 24.0) / 3.0).max(200.0);
    egui::Grid::new("protocol_cards").spacing([12.0, 12.0]).show(ui, |ui| {
        for (i, p) in PROTOCOLS.iter().enumerate() {
            let selected = p.id == t.protocol.id;
            let stroke = if selected {
                Stroke::new(2.0_f32, CALM)
            } else {
                Stroke::new(1.0_f32, ui.visuals().widgets.noninteractive.bg_stroke.color)
            };
            let resp = egui::Frame::group(ui.style()).stroke(stroke).rounding(10.0).inner_margin(12.0).show(ui, |ui| {
                ui.set_width(w);
                ui.set_height(92.0);
                ui.vertical(|ui| {
                    ui.horizontal(|ui| {
                        ui.label(RichText::new(p.title).strong().size(17.0));
                        if p.experimental {
                            ui.label(RichText::new("experimental").small().color(FAIR));
                        }
                    });
                    ui.label(p.summary);
                    ui.weak(match p.unavailable {
                        Some(r) => format!("Not available: {r}"),
                        None => format!("{} · {} min", eyes(p.eyes), p.default_minutes),
                    });
                });
            });
            let resp = ui.interact(resp.response.rect, ui.id().with(p.id), Sense::click());
            if resp.clicked() && !selected {
                out.push(Command::ProtocolSet { id: p.id.into(), minutes: None });
            }
            if i % 3 == 2 {
                ui.end_row();
            }
        }
    });
    ui.add_space(14.0);
    ui.horizontal(|ui| {
        ui.label("Length:");
        for m in MINUTES {
            if ui.selectable_label(t.minutes == m, format!("{m} min")).clicked() {
                out.push(Command::ProtocolSet { id: t.protocol.id.into(), minutes: Some(m) });
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
    let instruction = match t.protocol.eyes {
        Eyes::Closed => "Close your eyes, relax and sit still.",
        Eyes::Open => "Keep your eyes open on a calm point and sit still.",
    };
    header(ui, "Calibrating", instruction);
    ui.add(
        egui::ProgressBar::new(c.valid_s as f32 / c.needed_s.max(1) as f32)
            .desired_width(520.0)
            .text(format!("{} of {} good seconds", c.valid_s, c.needed_s)),
    );
    ui.weak(format!("{} s elapsed · stops at {} s even if the signal was poor", c.wall_s, c.max_s));
    ui.add_space(10.0);
    match &c.waiting {
        Some(w) => chip(ui, &format!("Paused: {w}"), FAIR),
        None => chip(ui, "Collecting", GOOD),
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

fn training(ui: &mut egui::Ui, session: &Session, t: &Trainer, out: &mut Vec<Command>) {
    let last = t.last();
    let in_target = last.is_some_and(|r| r.in_target) && t.phase == Phase::Playing;
    let (status, color) = match t.phase {
        Phase::Paused { reason: PauseReason::User } => ("Paused".to_owned(), FAIR),
        Phase::Paused { reason: PauseReason::BadSignal } => ("Paused: waiting for good signal".to_owned(), FAIR),
        Phase::Paused { reason: PauseReason::Disconnected } => ("Paused: device disconnected".to_owned(), BAD),
        _ if in_target => ("In target".to_owned(), GOOD),
        _ => ("Training".to_owned(), CALM),
    };
    ui.horizontal(|ui| {
        ui.heading(t.protocol.title);
        ui.weak(format!("{} left", mmss(t.total_s().saturating_sub(t.played_s))));
    });
    let avail = ui.available_size();
    let h = (avail.y - 120.0).max(200.0);
    let (rect, _) = ui.allocate_exact_size(Vec2::new(avail.x, h), Sense::hover());
    let p = ui.painter_at(rect);
    let r = h.min(avail.x) * 0.32;
    let glow = if in_target { GOOD } else { CALM.gamma_multiply(0.35) };
    for k in 0..6 {
        let f = 1.0 + k as f32 * 0.08;
        p.circle_filled(rect.center(), r * f, glow.gamma_multiply(0.18 / (k as f32 + 1.0)));
    }
    p.circle_filled(rect.center(), r, glow.gamma_multiply(0.55));
    p.circle_stroke(rect.center(), r, Stroke::new(2.0_f32, glow));
    ui.vertical_centered(|ui| {
        chip(ui, &status, color);
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
    let stat = |ui: &mut egui::Ui, label: &str, value: String| {
        ui.vertical(|ui| {
            ui.weak(label);
            ui.label(RichText::new(value).size(30.0).strong());
        });
        ui.add_space(30.0);
    };
    ui.horizontal(|ui| {
        stat(ui, "Time in target", s.success.map_or("--".into(), |x| format!("{:.0} %", x * 100.0)));
        stat(ui, "Trained", mmss(s.played_s));
        stat(ui, "Counted seconds", format!("{}", s.counted_s));
        stat(ui, "Rewards", format!("{}", s.chimes));
    });
    ui.add_space(10.0);
    let thr = |x: Option<f64>| x.map_or("--".into(), |v| format!("{v:.3}"));
    ui.weak(format!(
        "Threshold {} to {} ({} adjustments) · {} pauses",
        thr(s.threshold_start),
        thr(s.threshold_end),
        s.adapt_steps,
        s.pauses
    ));
    ui.add_space(20.0);
    ui.horizontal(|ui| {
        action(ui, session, "feedback.start", "Train again", true, Command::FeedbackStart { minutes: None, wall_clock_unix_ms: None }, out);
        action(
            ui,
            session,
            "protocol.set",
            "Choose protocol",
            false,
            Command::ProtocolSet { id: t.protocol.id.into(), minutes: None },
            out,
        );
    });
}
