//! History: saved sessions (newest first) and one session's detail with its
//! per-second feedback trace. Delete asks for confirmation first.

use super::plot::{label, to_screen, trace};
use egui::{Align2, Color32, RichText, Sense, Stroke, Vec2};
use nf_core::{Command, ExportFormat, Query, Session, SessionMeta};

const CALM: Color32 = Color32::from_rgb(0x4D, 0xB6, 0xAC);
const THR: Color32 = Color32::from_rgb(0xFF, 0xB7, 0x4D);
const BAD: Color32 = Color32::from_rgb(0xE5, 0x73, 0x73);

/// View-local UI state (egui memory): selection, pending delete, export note.
#[derive(Clone, Default)]
struct Ui {
    selected: Option<u64>,
    confirm: Option<u64>,
    /// (session id, message) of the last export.
    note: Option<(u64, String)>,
    /// (id, [t, value, threshold, flags]) of the selected session.
    trace: Option<(u64, Vec<[f32; 4]>)>,
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

fn title(m: &SessionMeta) -> String {
    m.protocol.clone().map_or_else(
        || if m.import.is_some() { "Imported recording".into() } else { "Recording".into() },
        |p| nf_core::nf_feedback::PROTOCOLS.iter().find(|x| x.id == p).map_or(p, |x| x.title.to_owned()),
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
                        title(m),
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
    ui.label(RichText::new(title(m)).size(20.0).strong());
    ui.weak(format!("{} · {} · {}", date(m), m.device_name, mmss(m.duration_s)));
    ui.add_space(8.0);
    let s = m.summary.as_ref();
    let num = |k: &str| s.and_then(|s| s.get(k)).and_then(serde_json::Value::as_f64);
    ui.horizontal(|ui| {
        for (label, value) in [
            ("Time in target", success(m).map_or("--".into(), |x| format!("{:.0} %", x * 100.0))),
            ("Trained", num("played_s").map_or("--".into(), mmss)),
            ("Rewards", num("chimes").map_or("--".into(), |x| format!("{x:.0}"))),
            ("Pauses", num("pauses").map_or("--".into(), |x| format!("{x:.0}"))),
        ] {
            ui.vertical(|ui| {
                ui.weak(label);
                ui.label(RichText::new(value).size(24.0).strong());
            });
            ui.add_space(24.0);
        }
    });
    ui.weak(format!(
        "{} EEG samples · {} PPG samples · {} feedback seconds · {:.1} MB",
        m.eeg_samples,
        m.ppg_samples,
        m.feedback_seconds,
        m.bytes as f64 / 1e6
    ));
    provenance(ui, m);
    ui.add_space(8.0);
    if st.trace.as_ref().is_none_or(|(i, _)| *i != m.id) {
        let pts = session
            .query(&Query::HistoryGet { id: m.id })
            .ok()
            .and_then(|r| r["feedback"].as_array().cloned())
            .unwrap_or_default()
            .iter()
            .map(|r| {
                let f = |k: &str| r[k].as_f64().map_or(f32::NAN, |v| v as f32);
                [f("t"), f("value"), f("threshold"), f("flags")]
            })
            .collect();
        st.trace = Some((m.id, pts));
    }
    if let Some((_, pts)) = &st.trace {
        chart(ui, pts);
    }
    ui.add_space(10.0);
    ui.horizontal(|ui| {
        for (fmt, name) in [(ExportFormat::Nfed6, "Export .neurofeed"), (ExportFormat::Edf, "Export EDF")] {
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

/// Feedback value (teal) and threshold (amber) per second; dirty seconds
/// marked red along the bottom.
fn chart(ui: &mut egui::Ui, pts: &[[f32; 4]]) {
    let (rect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width().min(760.0), 220.0), Sense::hover());
    let p = ui.painter_at(rect);
    p.rect_stroke(rect, 6.0, Stroke::new(1.0_f32, ui.visuals().widgets.noninteractive.bg_stroke.color));
    let fin = |i: usize| pts.iter().map(move |r| r[i]).filter(|v| v.is_finite());
    let (Some(t0), Some(t1)) = (fin(0).reduce(f32::min), fin(0).reduce(f32::max)) else {
        label(&p, rect.center(), Align2::CENTER_CENTER, "no feedback seconds in this session");
        return;
    };
    let ys = fin(1).chain(fin(2));
    let (lo, hi) = ys.fold((f32::MAX, f32::MIN), |(a, b), v| (a.min(v), b.max(v)));
    if lo > hi {
        label(&p, rect.center(), Align2::CENTER_CENTER, "no values (calibration only)");
        return;
    }
    let pad = ((hi - lo) * 0.1).max(1e-3);
    let inner = rect.shrink2(Vec2::new(10.0, 18.0));
    let x = (t0, t1.max(t0 + 1.0));
    let y = (lo - pad, hi + pad);
    let cal = pts.iter().filter(|r| (r[3] as u16) & nf_core::feedback_flags::CALIBRATING != 0).map(|r| r[0]).fold(f32::NAN, f32::max);
    if cal.is_finite() {
        let a = to_screen(inner, x, y, t0, y.1);
        let b = to_screen(inner, x, y, cal, y.0);
        p.rect_filled(egui::Rect::from_two_pos(a, b), 0.0, ui.visuals().faint_bg_color);
        label(&p, egui::Rect::from_two_pos(a, b).center(), Align2::CENTER_CENTER, "calibration");
    }
    for (i, c) in [(1, CALM), (2, THR)] {
        let line: Vec<_> = pts.iter().filter(|r| r[i].is_finite()).map(|r| to_screen(inner, x, y, r[0], r[i])).collect();
        trace(&p, line, c);
    }
    let dirty = nf_core::feedback_flags::DIRTY;
    for r in pts.iter().filter(|r| r[3].is_finite() && (r[3] as u16) & dirty != 0) {
        let a = to_screen(inner, x, y, r[0], y.0);
        p.line_segment([a + Vec2::new(0.0, 6.0), a + Vec2::new(0.0, 12.0)], Stroke::new(2.0_f32, BAD));
    }
    label(&p, rect.left_top() + Vec2::new(8.0, 4.0), Align2::LEFT_TOP, "feedback value · threshold · red = artifact / dirty");
    label(&p, rect.right_bottom() + Vec2::new(-8.0, -4.0), Align2::RIGHT_BOTTOM, format!("{} s", (t1 - t0).round()));
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
