//! Top bar: sidebar toggle, device area (opens the Device dialog), mains, record, pause.

use super::layout::{Layout, TOUCH};
use super::{device_dialog, quality, theme};
use nf_core::{mains_name, AppState, Command, LinkState, MainsMode, Session};

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
                let (icon, cmd) = if state.paused { ("▶", Command::StreamResume) } else { ("⏸", Command::StreamPause) };
                if ui.add_sized([TOUCH, TOUCH - 8.0], egui::Button::new(icon)).on_hover_text(t!("topbar-pause-resume")).clicked() {
                    out.push(cmd);
                }
                if let Some(r) = state.recording.as_ref().filter(|r| r.active) {
                    if ui.add_sized([TOUCH + 24.0, TOUCH - 8.0], egui::Button::new(format!("⏹ {:.0}s", r.duration))).clicked() {
                        out.push(Command::RecordingStop);
                    }
                } else if ui
                    .add_enabled(state.device.is_some(), egui::Button::new("⏺").min_size(egui::vec2(TOUCH, TOUCH - 8.0)))
                    .on_hover_text(t!("topbar-record"))
                    .clicked()
                {
                    out.push(Command::RecordingStart { wall_clock_unix_ms: None });
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

/// Pause/resume, clock, record/stop (right-to-left order).
fn stream_controls(ui: &mut egui::Ui, state: &AppState, out: &mut Vec<Command>) {
    let label = if state.paused { t!("topbar-resume") } else { t!("topbar-pause") };
    if ui.button(label).clicked() {
        out.push(if state.paused { Command::StreamResume } else { Command::StreamPause });
    }
    ui.weak(t!("topbar-time", s = state.time.round()));
    if let Some(r) = state.recording.as_ref().filter(|r| r.active) {
        if ui.button(t!("topbar-stop-recording", s = format!("{:.0}", r.duration))).clicked() {
            out.push(Command::RecordingStop);
        }
    } else {
        if ui.add_enabled(state.device.is_some(), egui::Button::new(t!("topbar-record-2"))).clicked() {
            out.push(Command::RecordingStart { wall_clock_unix_ms: None });
        }
        // Legacy asked Save / Discard after Stop; here it is saved, and
        // Discard stays one click away until the next recording.
        let saved = state.recording.as_ref().and_then(|r| r.saved_id).filter(|id| state.history.iter().any(|h| h.id == *id));
        if let Some(id) = saved {
            if ui.small_button(t!("topbar-discard-last-recording")).on_hover_text(t!("topbar-it-was-saved-to-history")).clicked() {
                out.push(Command::HistoryDelete { id, confirm: true });
            }
        }
    }
}

/// Notch picker and usable-pad count.
fn signal_controls(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let Some((_, sig)) = session.live_signal() else { return };
    let state = session.state();
    let notch = match sig.applied() {
        nf_core::dsp::Mains::Unknown => "50+60".to_owned(),
        m => mains_name(m).to_owned(),
    };
    let lock = if sig.locked() { " 🔒" } else { "" };
    egui::ComboBox::from_id_salt("mains").selected_text(t!("topbar-notch", notch = format!("{notch}{lock}"))).show_ui(ui, |ui| {
        for (mode, label) in [(MainsMode::Auto, "auto"), (MainsMode::Hz50, "50 Hz"), (MainsMode::Hz60, "60 Hz"), (MainsMode::Off, "off")] {
            if ui.selectable_label(state.mains_mode == mode, label).clicked() {
                out.push(Command::MainsSet { mode });
            }
        }
    });
    let good = (0..sig.quality.len()).filter(|&i| sig.usable(i)).count();
    ui.weak(t!("topbar-pads", good = good, total = sig.quality.len()));
}
