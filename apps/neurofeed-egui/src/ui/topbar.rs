//! Top bar: sidebar toggle, device area (opens the Device dialog), analysis
//! exclusions / quality hint, record, pause. The notch is in Settings → Devices.

use super::layout::{Layout, TOUCH};
use super::{device_dialog, quality, theme};
use nf_core::{AppState, Command, LinkState, Session};

pub fn show(root: &mut egui::Ui, session: &Session, error: Option<&str>, layout: Layout, out: &mut Vec<Command>) {
    if layout.is_compact() {
        compact(root, session, error, out);
        return;
    }
    let state = session.state();
    egui::Panel::top("topbar").exact_size(theme::TOPBAR_HEIGHT).show(root, |ui| {
        ui.horizontal_centered(|ui| {
            if ui.button("☰").on_hover_text(t!("topbar-toggle-sidebar")).clicked() {
                out.push(Command::SidebarSet { open: !state.sidebar_open });
            }
            device(ui, session, out);
            if let Some(e) = error {
                ui.colored_label(ui.visuals().error_fg_color, e);
            }
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                stream_controls(ui, state, out);
                signal_controls(ui, session, out);
            });
        });
    });
}

/// Compact top bar: ☰ (navigation drawer), device area (tap opens the Device dialog), error
/// glyph, and icon-only record / pause. Notch lives in Settings → Devices.
fn compact(root: &mut egui::Ui, session: &Session, error: Option<&str>, out: &mut Vec<Command>) {
    let state = session.state();
    egui::Panel::top("topbar").exact_size(TOUCH).show(root, |ui| {
        ui.horizontal_centered(|ui| {
            if ui.add_sized([TOUCH, TOUCH - 8.0], egui::Button::new("☰")).on_hover_text(t!("topbar-menu")).clicked() {
                let open = super::sidebar::drawer_open(ui.ctx());
                super::sidebar::set_drawer(ui.ctx(), !open);
            }
            device(ui, session, out);
            if let Some(e) = error {
                ui.colored_label(ui.visuals().error_fg_color, "⚠").on_hover_text(e);
            }
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                analysis_chips(ui, session, out, true);
                if let Some(r) = state.recording.as_ref().filter(|r| r.active) {
                    if ui.add_sized([TOUCH + 24.0, TOUCH - 8.0], egui::Button::new(format!("⏹ {:.0}s", r.duration))).clicked() {
                        out.push(Command::RecordingStop);
                    }
                } else if record_dot(ui, state.device.is_some(), TOUCH - 8.0).clicked() {
                    out.push(Command::RecordingStart { wall_clock_unix_ms: None });
                }
                if pause_visible(state) {
                    let (icon, cmd) = if state.paused { ("▶", Command::StreamResume) } else { ("⏸", Command::StreamPause) };
                    if ui.add_sized([TOUCH, TOUCH - 8.0], egui::Button::new(icon)).on_hover_text(t!("topbar-pause-resume")).clicked() {
                        out.push(cmd);
                    }
                }
            });
        });
    });
}

/// Device area: `[ Connect device ]` when disconnected; else
/// `Muse S · <name>`, pad quality glyphs, battery, and a green LSL/OSC dot
/// while a stream server runs. Any click opens the Device dialog.
fn device(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    let open = Command::DeviceDialog { open: true };
    let Some(d) = &state.device else {
        if ui.button(t!("topbar-connect-device")).clicked() {
            out.push(open);
        }
        return;
    };
    let area = ui.horizontal(|ui| {
        ui.label(device_dialog::label(d));
        match &state.link {
            Some(LinkState::Connecting) => {
                ui.spinner();
                ui.weak(t!("topbar-connecting"));
            }
            Some(LinkState::Lost { reason }) => {
                ui.colored_label(ui.visuals().error_fg_color, reason);
            }
            _ => {
                quality::row(ui, &device_dialog::scores(session), d.channels.len(), device_dialog::shown_aux(session, d));
            }
        }
        if let Some(b) = state.battery {
            ui.label(format!("{b:.0}%")).on_hover_text(t!("topbar-battery"));
        }
        if let Some(proto) = state.streaming.running() {
            let (r, _) = ui.allocate_exact_size(egui::vec2(10.0, 10.0), egui::Sense::hover());
            ui.painter().circle_filled(r.center(), 4.5, theme::STREAM_ON);
            ui.weak(proto);
        }
    });
    let r = ui.interact(area.response.rect, egui::Id::unique("device-area"), egui::Sense::click());
    if r.on_hover_cursor(egui::CursorIcon::PointingHand).on_hover_text(t!("topbar-device")).clicked() {
        out.push(open);
    }
}

/// Record (red dot) / stop, and Pause immediately left of it — shown only
/// while a recording runs (manual or feedback auto-recording) or while
/// paused (so Resume stays reachable). Pause keeps its meaning (`stream.pause`:
/// freezes the views' incoming band data; acquisition and the recording
/// continue). Right-to-left order. The session clock moved to the debug
/// overlay.
fn stream_controls(ui: &mut egui::Ui, state: &AppState, out: &mut Vec<Command>) {
    let recording = state.recording.as_ref().filter(|r| r.active);
    if let Some(r) = recording {
        if ui.button(t!("topbar-stop-recording", s = format!("{:.0}", r.duration))).clicked() {
            out.push(Command::RecordingStop);
        }
    } else {
        // Legacy asked Save / Discard after Stop; here it is saved, and
        // Discard stays one click away until the next recording.
        let saved = state.recording.as_ref().and_then(|r| r.saved_id).filter(|id| state.history.iter().any(|h| h.id == *id));
        if let Some(id) = saved {
            if ui.small_button(t!("topbar-discard-last-recording")).on_hover_text(t!("topbar-it-was-saved-to-history")).clicked() {
                out.push(Command::HistoryDelete { id, confirm: true });
            }
        }
        if record_dot(ui, state.device.is_some(), 22.0).clicked() {
            out.push(Command::RecordingStart { wall_clock_unix_ms: None });
        }
    }
    if pause_visible(state) {
        let label = if state.paused { t!("topbar-resume") } else { t!("topbar-pause") };
        if ui.button(label).on_hover_text(t!("topbar-pause-resume")).clicked() {
            out.push(if state.paused { Command::StreamResume } else { Command::StreamPause });
        }
    }
}

/// Pause only while recording (or to Resume a pause).
pub fn pause_visible(state: &AppState) -> bool {
    state.paused || state.recording.as_ref().is_some_and(|r| r.active)
}

/// The Record button: a red dot, no text (tooltip names it).
/// "● Record": only the dot is red (painted, the font has no ● glyph); the
/// label keeps the normal text colour. `h` = button height (touch on mobile).
fn record_dot(ui: &mut egui::Ui, enabled: bool, h: f32) -> egui::Response {
    let label = format!("     {}", t!("topbar-record"));
    let r = ui.add_enabled(enabled, egui::Button::new(label).min_size(egui::vec2(28.0, h))).on_hover_text(t!("topbar-record-tip"));
    let col = if enabled { theme::RECORD_RED } else { theme::RECORD_RED.gamma_multiply(0.4) };
    ui.painter().circle_filled(egui::pos2(r.rect.left() + 13.0, r.rect.center().y), 5.5, col);
    r
}

/// Usable-pad count, analysis exclusions and the contact-quality hint.
/// (Notch moved to Settings → Devices only, owner 2026-11-07.)
fn signal_controls(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let Some((_, sig)) = session.live_signal() else { return };
    analysis_chips(ui, session, out, false);
    let good = (0..sig.quality.len()).filter(|&i| sig.usable(i)).count();
    ui.weak(t!("topbar-pads", good = good, total = sig.quality.len()));
}

/// `⊘ 1 excluded` (opens the Device dialog) and the dismissible hint.
fn analysis_chips(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>, compact: bool) {
    let a = &session.state().analysis;
    if let Some(ch) = &a.hint.active {
        if ui.small_button("×").on_hover_text(t!("analysis-hint-dismiss")).clicked() {
            out.push(Command::AnalysisHintDismiss);
        }
        let text = if compact { format!("⚠ {ch}") } else { t!("analysis-hint", channel = ch.clone()) };
        let b = ui.add(egui::Button::new(egui::RichText::new(text).color(ui.visuals().warn_fg_color)).small());
        if b.on_hover_text(t!("analysis-hint-tip", channel = ch.clone())).clicked() {
            device_dialog::highlight(ui.ctx(), ch);
            out.push(Command::DeviceDialog { open: true });
        }
    }
    if !a.excluded.is_empty() {
        let names: Vec<&str> = a.excluded.iter().map(String::as_str).collect();
        let text = if compact { t!("analysis-excluded-short", n = names.len()) } else { t!("analysis-excluded-count", n = names.len()) };
        if ui.small_button(text).on_hover_text(t!("analysis-excluded-tip", channels = names.join(", "))).clicked() {
            out.push(Command::DeviceDialog { open: true });
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use serde_json::json;

    #[test]
    fn pause_shows_only_while_recording_or_paused() {
        let mut s = Session::new();
        s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
        s.call("clock.advance", json!({ "seconds": 2.0 })).unwrap();
        assert!(!pause_visible(s.state()));
        s.call("recording.start", json!({})).unwrap();
        assert!(pause_visible(s.state()));
        s.call("stream.pause", json!({})).unwrap();
        s.call("recording.stop", json!({})).unwrap();
        assert!(pause_visible(s.state()), "Resume stays reachable");
        s.call("stream.resume", json!({})).unwrap();
        assert!(!pause_visible(s.state()));
    }
}
