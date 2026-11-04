//! Streaming out: OSC over UDP to a PC tool, or LSL outlets (desktop).
//! Every change is one `streaming.set`.

use egui::RichText;
use nf_core::streaming::{groups, outlet_specs, StreamPatch, StreamProtocol};
use nf_core::{Command, Session};
use std::cell::RefCell;

thread_local! {
    /// (ip, port, prefix) being edited; None = show the stored values.
    static DRAFT: RefCell<Option<(String, String, String)>> = const { RefCell::new(None) };
}

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    let st = &state.streaming;
    let s = &st.settings;
    ui.add_space(6.0);
    ui.heading(RichText::new(t!("streaming-streaming")).size(24.0));
    ui.weak(t!("streaming-send-the-live-signal-to"));
    ui.add_space(10.0);
    protocol_tabs(ui, st, out);
    let lsl = s.protocol == StreamProtocol::Lsl;
    ui.weak(if lsl { t!("streaming-lab-streaming-layer-one-outlet") } else { t!("streaming-open-sound-control-raw-samples") });
    ui.add_space(8.0);
    let mut on = s.enabled;
    let available = if lsl { st.lsl_transport } else { st.transport };
    let en = session.enabled("streaming.set").and_then(|()| if available { Ok(()) } else { Err(unavailable(lsl).into()) });
    let r = ui.add_enabled(en.is_ok() || on, egui::Checkbox::new(&mut on, t!("streaming-stream-while-connected")));
    if let Err(why) = &en {
        r.on_disabled_hover_text(why.as_str());
    } else if r.changed() {
        out.push(Command::StreamingSet(StreamPatch { enabled: Some(on), ..Default::default() }));
    }
    if !lsl {
        destination(ui, s, out);
    }
    let mut sep = s.separate_groups;
    if ui.checkbox(&mut sep, t!("streaming-separate-streams-for-ppg-imu")).changed() {
        out.push(Command::StreamingSet(StreamPatch { separate_groups: Some(sep), ..Default::default() }));
    }
    ui.add_space(10.0);
    if lsl {
        lsl_streams(ui, state);
    } else {
        osc_addresses(ui, state);
    }
    ui.add_space(10.0);
    stats(ui, state, lsl);
}

fn unavailable(lsl: bool) -> &'static str {
    if lsl {
        "LSL needs the desktop app"
    } else {
        "the web app cannot send UDP"
    }
}

fn protocol_tabs(ui: &mut egui::Ui, st: &nf_core::streaming::StreamState, out: &mut Vec<Command>) {
    ui.horizontal(|ui| {
        for (p, label, ok) in [(StreamProtocol::Osc, "OSC", st.transport), (StreamProtocol::Lsl, "LSL", st.lsl_transport)] {
            let r = ui.add_enabled(ok, egui::Button::selectable(st.settings.protocol == p, label));
            let r = r.on_disabled_hover_text(unavailable(p == StreamProtocol::Lsl));
            if r.clicked() && st.settings.protocol != p {
                out.push(Command::StreamingSet(StreamPatch { protocol: Some(p), ..Default::default() }));
            }
        }
    });
}

fn osc_addresses(ui: &mut egui::Ui, state: &nf_core::AppState) {
    let s = &state.streaming.settings;
    ui.label(RichText::new(t!("streaming-addresses")).strong());
    let gs = groups(state.device.as_ref(), s.separate_groups);
    if gs.is_empty() {
        ui.weak(t!("streaming-connect-a-device-to-see"));
    }
    for g in gs {
        ui.monospace(format!("{}/{}  {} ch @ {} Hz · {} rows/message", s.prefix, g.id, g.channels.len(), g.rate, g.chunk));
    }
    ui.weak(t!("streaming-each-message-time-s-of"));
}

fn lsl_streams(ui: &mut egui::Ui, state: &nf_core::AppState) {
    ui.label(RichText::new(t!("streaming-outlets")).strong());
    let specs = outlet_specs(state.device.as_ref(), state.streaming.settings.separate_groups);
    if specs.is_empty() {
        ui.weak(t!("streaming-connect-a-device-to-see"));
    }
    for o in specs {
        ui.monospace(format!("{}  type {} · {} ch @ {} Hz · float32", o.name, o.kind, o.channels.len(), o.rate_hz));
    }
    ui.weak(t!("streaming-timestamps-are-the-lsl-clock"));
}

fn stats(ui: &mut egui::Ui, state: &nf_core::AppState, lsl: bool) {
    let (s, x) = (&state.streaming.settings, &state.streaming.stats);
    let live = s.enabled && state.device.is_some();
    let who = if lsl { format!(" · {} inlet(s) connected", x.lsl_consumers) } else { String::new() };
    let unit = if lsl { "chunks" } else { "messages" };
    ui.label(format!(
        "{}{who} · {} {unit} · {:.1} kB · {} samples dropped",
        if live { t!("streaming-streaming") } else { t!("streaming-idle") },
        x.packets_sent,
        x.bytes_sent as f64 / 1e3,
        x.dropped_samples
    ));
    if let Some(e) = &x.last_error {
        ui.colored_label(egui::Color32::from_rgb(0xE5, 0x73, 0x73), e);
    }
}

fn destination(ui: &mut egui::Ui, s: &nf_core::streaming::StreamSettings, out: &mut Vec<Command>) {
    let stored = (s.ip.clone(), s.port.to_string(), s.prefix.clone());
    let mut d = DRAFT.with(|d| d.borrow().clone()).unwrap_or_else(|| stored.clone());
    let mut applied = false;
    ui.horizontal(|ui| {
        ui.label(t!("streaming-ip"));
        ui.add(egui::TextEdit::singleline(&mut d.0).desired_width(140.0));
        ui.label(t!("streaming-port"));
        ui.add(egui::TextEdit::singleline(&mut d.1).desired_width(60.0));
        ui.label(t!("streaming-prefix"));
        ui.add(egui::TextEdit::singleline(&mut d.2).desired_width(100.0));
        if ui.add_enabled(d != stored, egui::Button::new(t!("streaming-apply"))).clicked() {
            let port = Some(d.1.trim().parse().unwrap_or(0));
            out.push(Command::StreamingSet(StreamPatch { ip: Some(d.0.clone()), port, prefix: Some(d.2.clone()), ..Default::default() }));
            applied = true;
        }
    });
    let keep = !applied && d != stored;
    DRAFT.with(|x| *x.borrow_mut() = keep.then_some(d));
}
