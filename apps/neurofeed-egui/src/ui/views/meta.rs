//! Session metadata: the notes editor (History detail and the summary) and
//! the recording-context panel (what was in effect while recording).

use egui::{Id, RichText};
use nf_core::{Command, Session};
use serde_json::Value;

/// Draft notes per session id; `None` = not editing (shows the saved text).
#[derive(Clone, Default)]
struct Draft(Option<String>);

/// Notes editor with Save / Revert; saving sends `history.notes`.
pub(super) fn notes(ui: &mut egui::Ui, session: &Session, id: u64, out: &mut Vec<Command>) {
    let saved = session.state().history.iter().find(|m| m.id == id).map(|m| m.notes.clone()).unwrap_or_default();
    let key = Id::unique(("notes", id));
    let mut d: Draft = ui.data(|x| x.get_temp(key)).unwrap_or_default();
    let mut text = d.0.clone().unwrap_or_else(|| saved.clone());
    ui.label(RichText::new("Notes").strong());
    let r = ui.add(
        egui::TextEdit::multiline(&mut text)
            .hint_text("How did it feel? Sleep, caffeine, posture, distractions…")
            .desired_rows(3)
            .desired_width(ui.available_width().min(820.0))
            .char_limit(nf_core::MAX_NOTES),
    );
    if r.changed() {
        d.0 = Some(text.clone());
    }
    let dirty = d.0.as_ref().is_some_and(|t| *t != saved);
    ui.horizontal(|ui| {
        let enabled = session.enabled("history.notes");
        if ui.add_enabled(dirty && enabled.is_ok(), egui::Button::new("Save notes")).clicked() {
            out.push(Command::HistoryNotes { id, notes: text.clone() });
            d.0 = None;
        }
        if ui.add_enabled(dirty, egui::Button::new("Revert")).clicked() {
            d.0 = None;
        }
        if dirty {
            ui.colored_label(egui::Color32::from_rgb(0xFF, 0xB7, 0x4D), "unsaved");
        } else if !saved.is_empty() {
            ui.weak("saved");
        }
        ui.weak(format!("{} / {}", text.chars().count(), nf_core::MAX_NOTES));
    });
    ui.data_mut(|x| x.insert_temp(key, d));
}

fn row(ui: &mut egui::Ui, k: &str, v: String) {
    ui.weak(k);
    ui.label(v);
    ui.end_row();
}

fn s(v: &Value) -> String {
    match v {
        Value::Null => "–".into(),
        Value::String(x) => x.clone(),
        Value::Bool(b) => if *b { "on" } else { "off" }.into(),
        other => other.to_string(),
    }
}

/// Collapsible "Recording context" from `SessionMeta::context`.
pub(super) fn context(ui: &mut egui::Ui, ctx: Option<&Value>) {
    let Some(c) = ctx else {
        ui.weak("No recording context (recorded before v4 or imported).");
        return;
    };
    egui::CollapsingHeader::new("Recording context").default_open(false).show(ui, |ui| {
        egui::Grid::new("ctx").num_columns(2).spacing([16.0, 4.0]).show(ui, |ui| {
            let p = &c["protocol"];
            if !p.is_null() {
                row(ui, "Protocol", format!("{} ({})", s(&p["title"]), s(&p["id"])));
                row(ui, "Reward feature", s(&p["feature"]));
                row(ui, "Planned minutes", s(&c["minutes"]));
                row(ui, "Threshold percentile", s(&c["percentile"]));
                row(ui, "Drowsiness guard", s(&c["guard"]));
            }
            let sub = c["settings"]["subject"].as_str().unwrap_or_default();
            row(ui, "Subject", if sub.is_empty() { "anonymous".into() } else { sub.to_owned() });
            row(ui, "Mains notch", s(&c["mains"]));
            let a = &c["audio"];
            row(ui, "Sound", format!("{} · background {} · master {}", s(&a["reward"]), s(&a["background"]), s(&a["master"])));
            row(ui, "App version", s(&c["app_version"]));
        });
    });
}
