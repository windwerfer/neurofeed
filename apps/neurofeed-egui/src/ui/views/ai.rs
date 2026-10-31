//! Settings → AI: the model cards (legacy `reve_card` / `model_selector` /
//! `reve_import`) and the guard scorer + threshold. Every change is one
//! `ai.*` command; state comes from `AppState::ai`.

use egui::{Color32, RichText};
use nf_core::ai::{AiPatch, ModelStatus, ThresholdMode};
use nf_core::{AiModel, AiModelState};
use nf_core::{Command, Session};
use std::cell::RefCell;

thread_local! {
    /// Import path being typed, per model.
    static PATH: RefCell<[String; 2]> = const { RefCell::new([String::new(), String::new()]) };
}

const OK: Color32 = Color32::from_rgb(70, 170, 90);
const WARN: Color32 = Color32::from_rgb(220, 140, 40);

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let a = &session.state().ai;
    if !a.runtime {
        ui.label(RichText::new(nf_core::ai::NO_RUNTIME).color(WARN));
        ui.weak("Sleep Guard and the AI drowsiness guard need the desktop app. Other protocols run here with the band-math guard (opt-in under Feedback sound).");
        return;
    }
    ui.weak("The AI guard scores 2 s of EEG once per second on this computer (nothing is uploaded). Sleep Guard needs it; Rest Awake, Open Monitor, Alert Eyes Closed and Band Stability use it for their drowsiness warning when a model is loaded.");
    ui.add_space(6.0);
    guard_settings(ui, session, out);
    ui.add_space(8.0);
    for (i, m) in a.models.iter().enumerate() {
        egui::Frame::group(ui.style()).show(ui, |ui| {
            ui.set_width(ui.available_width());
            card(ui, session, m, a.settings.model() == m.model, i, out);
        });
        ui.add_space(6.0);
    }
    live(ui, session);
}

fn guard_settings(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let a = &session.state().ai;
    let en = session.enabled("ai.set").is_ok();
    let locked = session.state().feedback.phase.active();
    ui.horizontal(|ui| {
        ui.label("Scorer");
        ui.add_enabled_ui(en && !locked, |ui| {
            egui::ComboBox::from_id_salt("ai-scorer").selected_text(scorer_label(&a.settings.scorer)).show_ui(ui, |ui| {
                for m in AiModel::ALL {
                    for s in m.scorers() {
                        if ui.selectable_label(a.settings.scorer == *s, scorer_label(s)).clicked() {
                            out.push(Command::AiSet(AiPatch { scorer: Some((*s).into()), ..AiPatch::default() }));
                        }
                    }
                }
            });
        });
    });
    ui.horizontal(|ui| {
        ui.label("Warn when");
        let mut mode = a.settings.threshold_mode;
        let fixed = ui.radio_value(&mut mode, ThresholdMode::Fixed, "P(drowsy) is above");
        let mut v = a.settings.fixed_threshold;
        let (lo, hi) = nf_feedback_range();
        let s = ui.add_enabled(mode == ThresholdMode::Fixed, egui::Slider::new(&mut v, lo..=hi).step_by(0.01).fixed_decimals(2));
        let pct = ui.radio_value(&mut mode, ThresholdMode::Percentile, "above my calibration (p75)");
        if fixed.changed() || pct.changed() {
            out.push(Command::AiSet(AiPatch { threshold_mode: Some(mode), ..AiPatch::default() }));
        }
        if s.drag_stopped() || (s.changed() && !s.dragged()) {
            out.push(Command::AiSet(AiPatch { fixed_threshold: Some(v), ..AiPatch::default() }));
        }
    });
    let mut auto = a.settings.auto_load;
    if ui.checkbox(&mut auto, "Load the model when the app starts").changed() {
        out.push(Command::AiSet(AiPatch { auto_load: Some(auto), ..AiPatch::default() }));
    }
}

fn nf_feedback_range() -> (f64, f64) {
    nf_core::nf_feedback::AI_FIXED_RANGE
}

fn scorer_label(id: &str) -> String {
    let what = if id.contains("wake_light") { "wake vs light sleep" } else { "drowsiness (A-vig)" };
    let model = AiModel::for_scorer(id).map_or("?", AiModel::label);
    format!("{what} · {model}")
}

fn state_text(s: &AiModelState) -> (String, Color32) {
    match s {
        AiModelState::Missing => ("Not installed".into(), Color32::GRAY),
        AiModelState::Installing { progress: Some(p) } => (format!("Installing… {:.0} %", p * 100.0), WARN),
        AiModelState::Installing { progress: None } => ("Installing…".into(), WARN),
        AiModelState::Installed => ("Installed (not loaded)".into(), Color32::GRAY),
        AiModelState::Loading => ("Loading…".into(), WARN),
        AiModelState::Ready { description } => (format!("Ready — {description}"), OK),
        AiModelState::Failed { message } => (format!("Error: {message}"), Color32::from_rgb(210, 70, 60)),
    }
}

fn card(ui: &mut egui::Ui, session: &Session, m: &ModelStatus, selected: bool, i: usize, out: &mut Vec<Command>) {
    ui.horizontal(|ui| {
        ui.label(RichText::new(m.label).strong().size(16.0));
        if selected {
            ui.label(RichText::new("selected").small().color(OK));
        }
        ui.weak(format!("~{} MB · {:.0} s window", m.size_mb, m.window_s));
    });
    ui.weak(m.description);
    let (txt, col) = state_text(&m.state);
    ui.label(RichText::new(txt).color(col));
    let busy = matches!(m.state, AiModelState::Installing { .. } | AiModelState::Loading);
    ui.horizontal(|ui| {
        let model = Some(m.model);
        match &m.state {
            AiModelState::Missing | AiModelState::Failed { .. } => {
                if m.download_url.is_some() && ui.button("Download").clicked() {
                    out.push(Command::AiInstall { model, path: None });
                }
            }
            AiModelState::Installed => {
                if ui.button("Load").clicked() {
                    out.push(Command::AiLoad { model });
                }
            }
            AiModelState::Ready { .. } => {
                let r = ui.add_enabled(session.enabled("ai.unload").is_ok(), egui::Button::new("Unload"));
                if r.clicked() {
                    out.push(Command::AiUnload);
                }
            }
            _ => {}
        }
        if !selected && ui.button("Use this model").clicked() {
            out.push(Command::AiSet(AiPatch { model, ..AiPatch::default() }));
        }
        let installed = matches!(m.state, AiModelState::Installed | AiModelState::Ready { .. });
        let rm = session.enabled("ai.remove");
        if installed && !busy {
            let r = ui.add_enabled(rm.is_ok(), egui::Button::new("Remove"));
            if r.clicked() {
                out.push(Command::AiRemove { model: m.model, confirm: true });
            }
        }
        ui.hyperlink_to("Model page", m.page_url);
    });
    if matches!(m.state, AiModelState::Missing | AiModelState::Failed { .. }) {
        import_row(ui, m, i, out);
    }
    if let Some(f) = &m.folder {
        ui.weak(format!("Folder: {f}"));
    }
}

fn import_row(ui: &mut egui::Ui, m: &ModelStatus, i: usize, out: &mut Vec<Command>) {
    ui.weak(m.guide);
    let dropped = ui.ctx().input(|x| x.raw.dropped_files.first().map(|f| f.path().to_path_buf()));
    PATH.with(|p| {
        let mut p = p.borrow_mut();
        if let Some(d) = dropped.filter(|d| d.file_name().is_some_and(|n| n == m.weights_file)) {
            p[i] = d.display().to_string();
        }
        ui.horizontal(|ui| {
            ui.add(
                egui::TextEdit::singleline(&mut p[i])
                    .hint_text(format!("path to {} (or drop it here)", m.weights_file))
                    .desired_width(360.0),
            );
            if ui.add_enabled(!p[i].trim().is_empty(), egui::Button::new("Import")).clicked() {
                out.push(Command::AiInstall { model: Some(m.model), path: Some(p[i].trim().to_owned()) });
            }
        });
    });
}

fn live(ui: &mut egui::Ui, session: &Session) {
    let s = session.state();
    let Some(l) = &s.ai.live else {
        if let Err(r) = s.ai.ready_reason() {
            ui.weak(format!("Not scoring: {r}"));
        } else {
            ui.weak("Ready — scores appear once a headband streams (first after ~2 s).");
        }
        return;
    };
    let age = s.time - l.t;
    let heads: Vec<String> = l.heads.iter().map(|(k, v)| format!("{k} {v:.2}")).collect();
    ui.label(format!(
        "Live ({}): {}   · {:.0} ms/window · {} windows · {:.0} s ago",
        l.model.label(),
        heads.join("  "),
        l.ms,
        l.windows,
        age
    ));
    if let (Some(c), Some(d)) = (l.clarity, l.sleep_dir) {
        ui.weak(format!("Anchors: clarity {c:.2} · sleep direction {d:.2}"));
    }
}
