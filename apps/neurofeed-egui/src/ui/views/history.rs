//! History: saved sessions (newest first) and one session's detail with its
//! per-second feedback trace. Delete asks for confirmation first.

use egui::{Color32, RichText, Vec2};
use nf_core::{Command, ExportFormat, Session, SessionMeta};

const THR: Color32 = Color32::from_rgb(0xFF, 0xB7, 0x4D);
const BAD: Color32 = Color32::from_rgb(0xE5, 0x73, 0x73);

/// View-local UI state (egui memory): selection, pending delete, export note.
#[derive(Clone, Default)]
struct Ui {
    selected: Option<u64>,
    confirm: Option<u64>,
    /// (session id, message) of the last export.
    note: Option<(u64, String)>,
    /// Trust trace of the selected session.
    trust: Option<(u64, std::sync::Arc<nf_core::trust::Trust>)>,
    plot: super::trust::Plot,
}

fn date(m: &SessionMeta) -> String {
    m.started_unix_ms.map_or("(no date)".into(), local_time)
}

/// `YYYY-MM-DD HH:MM` in the viewer's local zone (shell concern; the core
/// stores UTC Unix ms).
pub fn local_time(unix_ms: f64) -> String {
    use chrono::TimeZone;
    match chrono::Local.timestamp_millis_opt(unix_ms as i64) {
        chrono::LocalResult::Single(t) | chrono::LocalResult::Ambiguous(t, _) => t.format("%Y-%m-%d %H:%M").to_string(),
        chrono::LocalResult::None => "(bad date)".into(),
    }
}

fn mmss(s: f64) -> String {
    let s = s.max(0.0).round() as u64;
    format!("{}:{:02}", s / 60, s % 60)
}

fn success(m: &SessionMeta) -> Option<f64> {
    m.summary.as_ref()?.get("success")?.as_f64()
}

fn title(m: &SessionMeta, custom: &[nf_core::nf_feedback::Protocol]) -> String {
    m.protocol.clone().map_or_else(
        || if m.import.is_some() { "Imported recording".into() } else { "Recording".into() },
        |p| nf_core::protocols::find(custom, &p).map_or(p, |x| x.title),
    )
}

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let id = ui.id().with("history");
    let mut st: Ui = ui.data(|d| d.get_temp(id)).unwrap_or_default();
    let state = session.state();
    ui.add_space(6.0);
    ui.heading(RichText::new("History").size(24.0));
    ui.horizontal(|ui| {
        ui.weak(format!("{} saved session(s) · {}", state.history.len(), state.history_location));
        super::import::show(ui, session, out);
    });
    ui.add_space(10.0);
    if state.history.is_empty() {
        ui.label("No sessions yet. Every training is saved here when it ends.");
    }
    if st.selected.is_some_and(|s| !state.history.iter().any(|m| m.id == s)) {
        st.selected = None;
    }
    let selected = st.selected.or_else(|| state.history.first().map(|m| m.id));
    ui.horizontal_top(|ui| {
        ui.vertical(|ui| {
            ui.set_width(330.0);
            egui::ScrollArea::vertical().id_salt("history-list").show(ui, |ui| {
                for m in &state.history {
                    let on = selected == Some(m.id);
                    let text = format!(
                        "{}\n{} · {} · {}",
                        title(m, &state.custom_protocols),
                        date(m),
                        mmss(m.duration_s),
                        success(m).map_or("--".into(), |x| format!("{:.0} % in target", x * 100.0))
                    );
                    let b = egui::Button::new(RichText::new(text).size(14.0)).min_size(Vec2::new(320.0, 48.0)).selected(on);
                    if ui.add(b).clicked() {
                        st.selected = Some(m.id);
                        st.confirm = None;
                        st.note = None;
                    }
                }
            });
        });
        ui.separator();
        if let Some(m) = selected.and_then(|s| state.history.iter().find(|m| m.id == s)) {
            ui.vertical(|ui| detail(ui, session, m, &mut st, out));
        }
    });
    ui.data_mut(|d| d.insert_temp(id, st));
}

fn detail(ui: &mut egui::Ui, session: &Session, m: &SessionMeta, st: &mut Ui, out: &mut Vec<Command>) {
    ui.label(RichText::new(title(m, &session.state().custom_protocols)).size(20.0).strong());
    ui.weak(format!("{} · {} · {}", date(m), m.device_name, mmss(m.duration_s)));
    ui.add_space(8.0);
    ui.weak(format!(
        "{} pause(s) · {} EEG samples · {} PPG samples · {} feedback seconds · {:.1} MB",
        m.summary.as_ref().and_then(|s| s.get("pauses")).and_then(serde_json::Value::as_u64).unwrap_or(0),
        m.eeg_samples,
        m.ppg_samples,
        m.feedback_seconds,
        m.bytes as f64 / 1e6
    ));
    provenance(ui, m);
    super::meta::context(ui, m.context.as_ref());
    ui.add_space(8.0);
    if st.trust.as_ref().is_none_or(|(i, _)| *i != m.id) {
        st.trust = Some((m.id, std::sync::Arc::new(session.history_trust(m.id).unwrap_or_default())));
    }
    if let Some((_, t)) = st.trust.clone() {
        ui.allocate_ui(Vec2::new(ui.available_width().min(820.0), 320.0), |ui| super::trust::pane(ui, &t, &mut st.plot, 200.0, true));
    }
    ui.add_space(8.0);
    super::meta::notes(ui, session, m.id, out);
    ui.add_space(10.0);
    ui.horizontal(|ui| {
        for (fmt, name) in
            [(ExportFormat::Nfed6, "Export .neurofeed"), (ExportFormat::Edf, "Export EDF"), (ExportFormat::Pdf, "Export PDF")]
        {
            let r = ui.add_enabled(cfg!(not(target_arch = "wasm32")), egui::Button::new(name));
            let r = r.on_disabled_hover_text("export from the web build is not available yet");
            if r.clicked() {
                st.note = Some((m.id, export(session, m.id, fmt)));
            }
        }
        ui.add_space(20.0);
        if st.confirm == Some(m.id) {
            ui.label(RichText::new("Delete this session permanently?").color(BAD));
            if ui.add(egui::Button::new(RichText::new("Delete").color(Color32::WHITE)).fill(BAD.gamma_multiply(0.8))).clicked() {
                out.push(Command::HistoryDelete { id: m.id, confirm: true });
                st.confirm = None;
            }
            if ui.button("Cancel").clicked() {
                st.confirm = None;
            }
        } else {
            let en = session.enabled("history.delete");
            let r = ui.add_enabled(en.is_ok(), egui::Button::new(RichText::new("Delete…").color(BAD)));
            if r.clicked() {
                st.confirm = Some(m.id);
            }
        }
    });
    if let Some((_, n)) = st.note.as_ref().filter(|(id, _)| *id == m.id) {
        ui.weak(n);
    }
}

/// Where an imported session came from and what was lost on the way.
fn provenance(ui: &mut egui::Ui, m: &SessionMeta) {
    let Some(p) = &m.import else { return };
    let s = |k: &str| p[k].as_str().unwrap_or("?").to_owned();
    let mut line = format!("Imported from {} ({})", s("source_file_name"), s("source_format"));
    if p["resampled"].as_bool() == Some(true) {
        line += &format!(" · resampled from {} Hz", p["original_rate_hz"].as_f64().unwrap_or(0.0));
    }
    if p["bands_from_file"].as_bool() == Some(true) {
        line += " · bands from file";
    }
    if let Some(n) = p["annotations"].as_array().map(Vec::len).filter(|n| *n > 0) {
        line += &format!(" · {n} note(s)");
    }
    ui.label(RichText::new(line).color(THR));
    for w in p["warnings"].as_array().into_iter().flatten().filter_map(|w| w.as_str()) {
        ui.weak(format!("⚠ {w}"));
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn export(session: &Session, id: u64, format: ExportFormat) -> String {
    let bytes = match session.history_export(id, format) {
        Ok(b) => b,
        Err(e) => return e.to_string(),
    };
    let ext = format.extension();
    let dir = std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join("Downloads")).unwrap_or_else(std::env::temp_dir);
    let path = dir.join(format!("neurofeed-session-{id}.{ext}"));
    match std::fs::create_dir_all(&dir).and_then(|()| std::fs::write(&path, bytes)) {
        Ok(()) => format!("Saved {}", path.display()),
        Err(e) => format!("Export failed: {e}"),
    }
}

#[cfg(target_arch = "wasm32")]
fn export(_: &Session, _: u64, _: ExportFormat) -> String {
    String::new()
}
