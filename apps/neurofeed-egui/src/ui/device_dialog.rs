//! The one Device dialog, opened from the top bar's device area: the
//! connected device (battery, per-electrode quality, Disconnect) on top, then
//! the scan list grouped Muse / Neurosity Crown / Simulated. Muse BLE and
//! Crown OSC stay in discovery for as long as this window is open.

use super::{quality, theme};
use nf_core::{Command, DeviceInfo, DeviceKind, LinkState, Session};

/// "Muse S" / "Muse 2" / "Muse S Athena" / "Crown", read from the name.
pub fn model(d: &DeviceInfo) -> &'static str {
    let n = d.name.to_ascii_lowercase().replace(['-', '_'], " ");
    match d.kind {
        DeviceKind::Crown => "Crown",
        DeviceKind::Muse if n.contains("athena") => "Muse S Athena",
        DeviceKind::Muse if n.contains("muse 2") || n.starts_with("muse2") => "Muse 2",
        DeviceKind::Muse if n.contains("muse s") || n.starts_with("muses") => "Muse S",
        DeviceKind::Muse => "Muse",
    }
}

/// Top bar label `Muse S · <name>`; a simulator reads `Muse S · simulated`.
pub fn label(d: &DeviceInfo) -> String {
    let name = if d.simulated { "simulated" } else { d.name.as_str() };
    format!("{} · {name}", model(d))
}

/// AUX pads the quality row shows: Muse with Settings → "Muse AUX channels" on.
pub fn shown_aux(session: &Session, d: &DeviceInfo) -> usize {
    if d.kind == DeviceKind::Muse && session.state().settings.muse_aux {
        d.aux_channels.len().min(4)
    } else {
        0
    }
}

/// Pad scores 0..=100, EEG pads first (AUX have none yet).
pub fn scores(session: &Session) -> Vec<f32> {
    session.live_signal().map(|(_, s)| s.quality.clone()).unwrap_or_default()
}

/// 1..=4 bars from an advertised RSSI (dBm).
pub fn bars(rssi: i16) -> usize {
    match rssi {
        r if r >= -60 => 4,
        r if r >= -70 => 3,
        r if r >= -80 => 2,
        _ => 1,
    }
}

pub fn show(ctx: &egui::Context, session: &Session, out: &mut Vec<Command>) {
    if !session.state().device_dialog {
        return;
    }
    let compact = super::layout::current(ctx).is_compact();
    let mut modal = egui::Modal::new(egui::Id::unique("device-dialog"));
    if compact {
        // Full-screen sheet: the whole content rect, no rounded card.
        modal =
            modal.area(egui::Modal::default_area(egui::Id::unique("device-dialog-sheet")).anchor(egui::Align2::LEFT_TOP, egui::Vec2::ZERO));
        modal = modal.frame(egui::Frame::window(&ctx.global_style()).corner_radius(0.0).inner_margin(12.0));
    }
    let modal = modal.show(ctx, |ui| {
        if compact {
            let r = ctx.content_rect();
            super::layout::touch_style(ui);
            ui.set_width(r.width() - 24.0);
            ui.set_min_height(r.height() - 24.0);
        } else {
            ui.set_width(380.0_f32.min(ctx.content_rect().width() - 32.0));
        }
        ui.horizontal(|ui| {
            ui.heading(t!("device-dialog-device"));
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button(t!("device-dialog-close")).clicked() {
                    out.push(Command::DeviceDialog { open: false });
                }
            });
        });
        current(ui, session, out);
        ui.separator();
        scan_list(ui, session, out);
    });
    if modal.should_close() {
        out.push(Command::DeviceDialog { open: false });
    }
}

fn current(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    let Some(d) = &state.device else {
        ui.weak(t!("device-dialog-not-connected"));
        return;
    };
    egui::Frame::group(ui.style()).show(ui, |ui| {
        ui.set_width(ui.available_width());
        ui.horizontal(|ui| {
            ui.strong(label(d));
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button(t!("device-dialog-disconnect")).clicked() {
                    out.push(Command::DeviceDisconnect);
                }
            });
        });
        match &state.link {
            Some(LinkState::Connecting) => {
                ui.horizontal(|ui| {
                    ui.spinner();
                    ui.weak(t!("topbar-connecting"));
                });
            }
            Some(LinkState::Lost { reason }) => {
                ui.colored_label(ui.visuals().error_fg_color, t!("device-dialog-lost", reason = reason.to_string()));
            }
            _ => {}
        }
        ui.label(match state.battery {
            Some(b) => t!("device-dialog-battery-pct", pct = format!("{b:.0}")),
            None => t!("device-dialog-battery").to_owned(),
        });
        let q = scores(session);
        ui.horizontal(|ui| {
            ui.label(t!("device-dialog-signal"));
            quality::row(ui, &q, d.channels.len(), shown_aux(session, d));
        });
        analysis_rows(ui, session, d, &q, out);
    });
    confirm_exclude(ui.ctx(), out);
}

/// Pending "exclude?" confirmation: (channel, remember).
fn pending_id() -> egui::Id {
    egui::Id::unique("nf-exclude-pending")
}

/// Ask the device dialog to highlight a channel's exclusion control (the
/// quality hint's tap target).
pub fn highlight(ctx: &egui::Context, channel: &str) {
    ctx.data_mut(|d| d.insert_temp(egui::Id::unique("nf-exclude-highlight"), channel.to_owned()));
}

/// Per pad: quality, the "use in analysis" switch, remembered tag.
fn analysis_rows(ui: &mut egui::Ui, session: &Session, d: &DeviceInfo, q: &[f32], out: &mut Vec<Command>) {
    let a = &session.state().analysis;
    if !a.restored.is_empty() {
        ui.horizontal_wrapped(|ui| {
            ui.colored_label(ui.visuals().warn_fg_color, t!("analysis-restored", channels = a.restored.join(", ")));
            if ui.small_button(t!("analysis-ok")).clicked() {
                out.push(Command::AnalysisAckRestored);
            }
        });
    }
    let hl: Option<String> = ui.ctx().data(|m| m.get_temp(egui::Id::unique("nf-exclude-highlight")));
    ui.weak(t!("analysis-use-caption"));
    egui::Grid::new("pad-quality").num_columns(3).spacing([14.0, 4.0]).show(ui, |ui| {
        for (i, ch) in d.channels.iter().enumerate() {
            let s = q.get(i).copied();
            let col = s.map_or(theme::QUALITY_NONE, theme::quality_color);
            let row = ui.label(egui::RichText::new(format!("• {ch}  {}", s.map_or("—".to_owned(), |s| format!("{s:.0}")))).color(col));
            if hl.as_deref() == Some(ch.as_str()) {
                ui.painter().rect_stroke(
                    row.rect.expand(3.0),
                    3.0,
                    egui::Stroke::new(2.0, ui.visuals().warn_fg_color),
                    egui::StrokeKind::Outside,
                );
            }
            let mut on = !a.is_excluded(ch);
            if ui.checkbox(&mut on, t!("analysis-use")).on_hover_text(t!("analysis-use-hint")).changed() {
                if on {
                    out.push(Command::AnalysisInclude { channel: ch.clone() });
                } else {
                    let c = ch.clone();
                    ui.ctx().data_mut(|m| m.insert_temp(pending_id(), (c, false)));
                }
            }
            if a.is_remembered(ch) {
                ui.weak(t!("analysis-remembered"));
            } else {
                ui.label("");
            }
            ui.end_row();
        }
    });
}

/// The confirmation: applies only on Confirm; Cancel changes nothing.
fn confirm_exclude(ctx: &egui::Context, out: &mut Vec<Command>) {
    let Some((ch, mut remember)) = ctx.data(|m| m.get_temp::<(String, bool)>(pending_id())) else { return };
    let mut done = false;
    let r = egui::Modal::new(egui::Id::unique("nf-exclude-confirm")).show(ctx, |ui| {
        ui.set_max_width(340.0);
        ui.strong(t!("analysis-confirm-title", channel = ch.clone()));
        ui.label(t!("analysis-confirm-body"));
        ui.checkbox(&mut remember, t!("analysis-confirm-remember"));
        ui.horizontal(|ui| {
            if ui.button(t!("analysis-cancel")).clicked() {
                done = true;
            }
            if ui.button(t!("analysis-exclude")).clicked() {
                out.push(Command::AnalysisExclude { channel: ch.clone(), confirm: true, remember });
                done = true;
            }
        });
    });
    if done || r.should_close() {
        ctx.data_mut(|m| m.remove::<(String, bool)>(pending_id()));
    } else {
        ctx.data_mut(|m| m.insert_temp(pending_id(), (ch, remember)));
    }
}

/// Scan-list group: title and membership test.
type Group = (&'static str, fn(&DeviceInfo) -> bool);

fn scan_list(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    let scanning = !session.scanning().is_empty();
    ui.horizontal(|ui| {
        ui.strong(t!("device-dialog-nearby-devices"));
        if scanning {
            ui.spinner();
            ui.weak(t!("device-dialog-scanning"));
            ui.ctx().request_repaint_after(std::time::Duration::from_millis(250));
        }
        if !scanning {
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                let can = session.enabled("device.scan");
                let r = ui.add_enabled(can.is_ok(), egui::Button::new(t!("device-dialog-scan")));
                let r = match &can {
                    Err(why) => r.on_disabled_hover_text(why),
                    Ok(()) => r.on_hover_text(t!("device-dialog-keep-looking-for-a-muse")),
                };
                if r.clicked() {
                    // Already open: `device.dialog` arms watch again after an error.
                    out.push(Command::DeviceDialog { open: true });
                }
            });
        }
    });
    let auto = &state.auto;
    if let (Some(t), Some(_)) = (&auto.target, auto.searching_since) {
        ui.weak(t!("device-dialog-waiting-for", device = t.to_string()));
    } else if let (Some(t), true) = (&auto.target, auto.suspended) {
        ui.weak(t!("device-dialog-auto-reconnect-off", device = t.to_string()));
    }
    for e in session.provider_errors() {
        ui.colored_label(ui.visuals().error_fg_color, e);
    }
    let list = session.device_list();
    let groups: [Group; 3] = [
        ("Muse", |d| !d.simulated && d.kind == DeviceKind::Muse),
        ("Neurosity Crown", |d| !d.simulated && d.kind == DeviceKind::Crown),
        ("device-dialog-group-simulated", |d| d.simulated),
    ];
    let connected = state.device.is_some();
    egui::ScrollArea::vertical().max_height(320.0).show(ui, |ui| {
        for (title, keep) in &groups {
            let rows: Vec<&DeviceInfo> = list.iter().filter(|d| keep(d)).collect();
            if rows.is_empty() {
                continue;
            }
            ui.add_space(4.0);
            ui.weak(crate::i18n::tr(title, &[]));
            for d in rows {
                row(ui, d, state.device.as_ref().is_some_and(|c| c.id == d.id), connected, out);
            }
        }
    });
    let real = list.iter().any(|d| !d.simulated);
    if !real && !scanning {
        ui.add_space(4.0);
        ui.weak(if state.scanners.is_empty() {
            t!("device-dialog-bluetooth-scanning-isn-t-available")
        } else {
            t!("device-dialog-no-headset-found-turn-the")
        });
    }
}

fn row(ui: &mut egui::Ui, d: &DeviceInfo, current: bool, connected: bool, out: &mut Vec<Command>) {
    ui.horizontal(|ui| {
        signal_bars(ui, d.rssi);
        ui.label(&d.name).on_hover_text(&d.id);
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if current {
                ui.weak("connected");
            } else if ui.button(if connected { t!("device-dialog-switch") } else { t!("device-dialog-connect") }).clicked() {
                out.push(Command::DeviceConnect { id: d.id.clone() });
                out.push(Command::DeviceDialog { open: false });
            }
            if let Some(r) = d.rssi {
                ui.weak(format!("{r} dBm"));
            }
        });
    });
}

/// Four rising bars, lit by RSSI; none lit for a LAN device (no RSSI).
fn signal_bars(ui: &mut egui::Ui, rssi: Option<i16>) {
    let (rect, resp) = ui.allocate_exact_size(egui::vec2(18.0, 14.0), egui::Sense::hover());
    let lit = rssi.map_or(0, bars);
    let on = ui.visuals().strong_text_color();
    let off = ui.visuals().weak_text_color().gamma_multiply(0.4);
    for i in 0..4 {
        let h = 3.5 * (i + 1) as f32;
        let x = rect.left() + i as f32 * 4.5;
        let r = egui::Rect::from_min_max(egui::pos2(x, rect.bottom() - h), egui::pos2(x + 3.0, rect.bottom()));
        ui.painter().rect_filled(r, 0.5, if i < lit { on } else { off });
    }
    resp.on_hover_text(rssi.map_or(t!("device-dialog-no-rssi"), |r| format!("{r} dBm")));
}

#[cfg(test)]
mod tests {
    use super::*;

    fn info(name: &str, kind: DeviceKind, simulated: bool) -> DeviceInfo {
        DeviceInfo {
            id: "x".into(),
            name: name.into(),
            kind,
            channels: Vec::new(),
            sample_rate_hz: 256.0,
            simulated,
            ppg_channels: Vec::new(),
            ppg_rate_hz: None,
            accel_rate_hz: None,
            aux_channels: Vec::new(),
            rssi: None,
        }
    }

    #[test]
    fn labels() {
        assert_eq!(label(&info("MuseS-1A2B", DeviceKind::Muse, false)), "Muse S · MuseS-1A2B");
        assert_eq!(label(&info("Muse-2 7F", DeviceKind::Muse, false)), "Muse 2 · Muse-2 7F");
        assert_eq!(label(&info("Muse S Athena (simulated)", DeviceKind::Muse, true)), "Muse S Athena · simulated");
        assert_eq!(label(&info("Crown-42", DeviceKind::Crown, false)), "Crown · Crown-42");
        assert_eq!(model(&info("Muse-1234", DeviceKind::Muse, false)), "Muse");
    }

    #[test]
    fn rssi_bars() {
        assert_eq!([-40, -60, -65, -75, -90].map(bars), [4, 4, 3, 2, 1]);
    }
}

#[cfg(test)]
mod exclusion_tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use serde_json::json;

    fn run(ctx: &egui::Context, s: &mut Session, events: Vec<egui::Event>, t: f64) -> Vec<Command> {
        let input = egui::RawInput {
            screen_rect: Some(egui::Rect::from_min_size(egui::Pos2::ZERO, egui::vec2(1000.0, 800.0))),
            time: Some(t),
            events,
            ..Default::default()
        };
        let mut cmds = Vec::new();
        ctx.run_ui(input, |u| cmds = crate::ui::show(u, s, None)).textures_delta.clear();
        cmds
    }

    #[test]
    fn exclusion_applies_only_on_confirm_escape_cancels() {
        let _lang = crate::i18n::lang_lock();
        let mut s = Session::new();
        s.call("settings.set", json!({ "onboarded": true, "layout": "regular" })).unwrap();
        s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
        s.call("device.dialog", json!({ "open": true })).unwrap();
        let ctx = egui::Context::default();
        run(&ctx, &mut s, vec![], 0.0);
        ctx.data_mut(|m| m.insert_temp(pending_id(), ("AF7".to_owned(), false)));
        for i in 1..4 {
            let out = run(&ctx, &mut s, vec![], f64::from(i) / 60.0);
            assert!(!out.iter().any(|c| matches!(c, Command::AnalysisExclude { .. })), "no change while asking");
        }
        let key =
            egui::Event::Key { key: egui::Key::Escape, physical_key: None, pressed: true, repeat: false, modifiers: egui::Modifiers::NONE };
        let out = run(&ctx, &mut s, vec![key], 0.1);
        assert!(!out.iter().any(|c| matches!(c, Command::AnalysisExclude { .. })));
        assert!(ctx.data(|m| m.get_temp::<(String, bool)>(pending_id())).is_none(), "cancelled");
        assert!(s.state().analysis.excluded.is_empty());
    }
}
