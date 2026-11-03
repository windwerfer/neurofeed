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
    let modal = egui::Modal::new(egui::Id::unique("device-dialog")).show(ctx, |ui| {
        ui.set_width(380.0_f32.min(ctx.content_rect().width() - 32.0));
        ui.horizontal(|ui| {
            ui.heading("Device");
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button("Close").clicked() {
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
        ui.weak("Not connected.");
        return;
    };
    egui::Frame::group(ui.style()).show(ui, |ui| {
        ui.set_width(ui.available_width());
        ui.horizontal(|ui| {
            ui.strong(label(d));
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button("Disconnect").clicked() {
                    out.push(Command::DeviceDisconnect);
                }
            });
        });
        match &state.link {
            Some(LinkState::Connecting) => {
                ui.horizontal(|ui| {
                    ui.spinner();
                    ui.weak("connecting…");
                });
            }
            Some(LinkState::Lost { reason }) => {
                ui.colored_label(ui.visuals().error_fg_color, format!("lost: {reason}"));
            }
            _ => {}
        }
        ui.label(match state.battery {
            Some(b) => format!("Battery {b:.0}%"),
            None => "Battery —".to_owned(),
        });
        let q = scores(session);
        ui.horizontal(|ui| {
            ui.label("Signal");
            quality::row(ui, &q, d.channels.len(), shown_aux(session, d));
        });
        egui::Grid::new("pad-quality").num_columns(4).spacing([14.0, 2.0]).show(ui, |ui| {
            for (i, ch) in d.channels.iter().enumerate() {
                let s = q.get(i).copied();
                let col = s.map_or(theme::QUALITY_NONE, theme::quality_color);
                ui.label(egui::RichText::new(format!("• {ch}")).color(col));
                ui.weak(s.map_or("—".to_owned(), |s| format!("{s:.0}")));
                if i % 2 == 1 {
                    ui.end_row();
                }
            }
        });
    });
}

/// Scan-list group: title and membership test.
type Group = (&'static str, fn(&DeviceInfo) -> bool);

fn scan_list(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    let scanning = !session.scanning().is_empty();
    ui.horizontal(|ui| {
        ui.strong("Nearby devices");
        if scanning {
            ui.spinner();
            ui.weak("scanning…");
            ui.ctx().request_repaint_after(std::time::Duration::from_millis(250));
        }
        if !scanning {
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                let can = session.enabled("device.scan");
                let r = ui.add_enabled(can.is_ok(), egui::Button::new("Scan"));
                let r = match &can {
                    Err(why) => r.on_disabled_hover_text(why),
                    Ok(()) => r.on_hover_text("Keep looking for a Muse (Bluetooth) and a Crown (OSC, UDP 9000)"),
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
        ui.weak(format!("Waiting for {t} to come back (reconnects on its own)."));
    } else if let (Some(t), true) = (&auto.target, auto.suspended) {
        ui.weak(format!("Auto-reconnect to {t} is off until you connect a device."));
    }
    for e in session.provider_errors() {
        ui.colored_label(ui.visuals().error_fg_color, e);
    }
    let list = session.device_list();
    let groups: [Group; 3] = [
        ("Muse", |d| !d.simulated && d.kind == DeviceKind::Muse),
        ("Neurosity Crown", |d| !d.simulated && d.kind == DeviceKind::Crown),
        ("Simulated", |d| d.simulated),
    ];
    let connected = state.device.is_some();
    egui::ScrollArea::vertical().max_height(320.0).show(ui, |ui| {
        for (title, keep) in &groups {
            let rows: Vec<&DeviceInfo> = list.iter().filter(|d| keep(d)).collect();
            if rows.is_empty() {
                continue;
            }
            ui.add_space(4.0);
            ui.weak(*title);
            for d in rows {
                row(ui, d, state.device.as_ref().is_some_and(|c| c.id == d.id), connected, out);
            }
        }
    });
    let real = list.iter().any(|d| !d.simulated);
    if !real && !scanning {
        ui.add_space(4.0);
        ui.weak(if state.scanners.is_empty() {
            "Bluetooth scanning isn't available in this build."
        } else {
            "No headset found. Turn the Muse on and keep it close; for a Crown, enable OSC in the Neurosity app on this network."
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
            } else if ui.button(if connected { "Switch" } else { "Connect" }).clicked() {
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
    resp.on_hover_text(rssi.map_or("no RSSI (network device, or not reported yet)".to_owned(), |r| format!("{r} dBm")));
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
