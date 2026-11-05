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
        ui.weak(t!("ai-sleep-guard-and-the-ai"));
        return;
    }
    ui.weak(t!("ai-the-ai-guard-scores-2"));
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
        ui.label(t!("ai-scorer"));
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
        ui.label(t!("ai-warn-when"));
        let mut mode = a.settings.threshold_mode;
        let fixed = ui.radio_value(&mut mode, ThresholdMode::Fixed, t!("ai-p-drowsy-is-above"));
        let mut v = a.settings.fixed_threshold;
        let (lo, hi) = nf_feedback_range();
        let s = ui.add_enabled(mode == ThresholdMode::Fixed, egui::Slider::new(&mut v, lo..=hi).step_by(0.01).fixed_decimals(2));
        let pct = ui.radio_value(&mut mode, ThresholdMode::Percentile, t!("ai-above-my-calibration"));
        if fixed.changed() || pct.changed() {
            out.push(Command::AiSet(AiPatch { threshold_mode: Some(mode), ..AiPatch::default() }));
        }
        if s.drag_stopped() || (s.changed() && !s.dragged()) {
            out.push(Command::AiSet(AiPatch { fixed_threshold: Some(v), ..AiPatch::default() }));
        }
    });
    let mut auto = a.settings.auto_load;
    if ui.checkbox(&mut auto, t!("ai-load-the-model-when-the")).changed() {
        out.push(Command::AiSet(AiPatch { auto_load: Some(auto), ..AiPatch::default() }));
    }
}

fn nf_feedback_range() -> (f64, f64) {
    nf_core::nf_feedback::AI_FIXED_RANGE
}

fn scorer_label(id: &str) -> String {
    let what = if id.contains("wake_light") { t!("ai-scorer-wake-light") } else { t!("ai-scorer-drowsiness") };
    let model = AiModel::for_scorer(id).map_or("?", AiModel::label);
    format!("{what} · {model}")
}

fn state_text(s: &AiModelState) -> (String, Color32) {
    match s {
        AiModelState::Missing => (t!("ai-not-installed"), Color32::GRAY),
        AiModelState::Installing { progress: Some(p) } => (t!("ai-installing-pct", pct = format!("{:.0}", p * 100.0)), WARN),
        AiModelState::Installing { progress: None } => (t!("ai-installing"), WARN),
        AiModelState::Installed => (t!("ai-installed-not-loaded"), Color32::GRAY),
        AiModelState::Loading => (t!("ai-loading"), WARN),
        AiModelState::Ready { description } => (t!("ai-ready-desc", description = description.to_string()), OK),
        AiModelState::Failed { message } => (t!("ai-error-msg", message = message.to_string()), Color32::from_rgb(210, 70, 60)),
    }
}

fn card(ui: &mut egui::Ui, session: &Session, m: &ModelStatus, selected: bool, i: usize, out: &mut Vec<Command>) {
    ui.horizontal(|ui| {
        ui.label(RichText::new(m.label).strong().size(16.0));
        if selected {
            ui.label(RichText::new(t!("ai-selected")).small().color(OK));
        }
        ui.weak(t!("ai-size-window", mb = m.size_mb.to_string(), s = format!("{:.0}", m.window_s)));
    });
    ui.weak(m.description);
    let (txt, col) = state_text(&m.state);
    ui.label(RichText::new(txt).color(col));
    let busy = matches!(m.state, AiModelState::Installing { .. } | AiModelState::Loading);
    ui.horizontal(|ui| {
        let model = Some(m.model);
        match &m.state {
            AiModelState::Missing | AiModelState::Failed { .. } => {
                if m.download_url.is_some() && ui.button(t!("ai-download")).clicked() {
                    out.push(Command::AiInstall { model, path: None });
                }
            }
            AiModelState::Installed => {
                if ui.button(t!("ai-load")).clicked() {
                    out.push(Command::AiLoad { model });
                }
            }
            AiModelState::Ready { .. } => {
                let r = ui.add_enabled(session.enabled("ai.unload").is_ok(), egui::Button::new(t!("ai-unload")));
                if r.clicked() {
                    out.push(Command::AiUnload);
                }
            }
            _ => {}
        }
        if !selected && ui.button(t!("ai-use-this-model")).clicked() {
            out.push(Command::AiSet(AiPatch { model, ..AiPatch::default() }));
        }
        let installed = matches!(m.state, AiModelState::Installed | AiModelState::Ready { .. });
        let rm = session.enabled("ai.remove");
        if installed && !busy {
            let r = ui.add_enabled(rm.is_ok(), egui::Button::new(t!("ai-remove")));
            if r.clicked() {
                out.push(Command::AiRemove { model: m.model, confirm: true });
            }
        }
        ui.hyperlink_to(t!("ai-model-page"), m.page_url);
    });
    if matches!(m.state, AiModelState::Missing | AiModelState::Failed { .. }) {
        import_row(ui, m, i, out);
    }
    if let Some(f) = &m.folder {
        ui.weak(t!("ai-folder", folder = f.to_string()));
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
                egui::TextEdit::singleline(&mut p[i]).hint_text(t!("ai-path-hint", file = m.weights_file.to_string())).desired_width(360.0),
            );
            if ui.add_enabled(!p[i].trim().is_empty(), egui::Button::new(t!("ai-import"))).clicked() {
                out.push(Command::AiInstall { model: Some(m.model), path: Some(p[i].trim().to_owned()) });
            }
        });
    });
}

fn live(ui: &mut egui::Ui, session: &Session) {
    let s = session.state();
    let Some(l) = &s.ai.live else {
        if let Err(r) = s.ai.ready_reason() {
            ui.weak(t!("ai-not-scoring", reason = r.to_string()));
        } else {
            ui.weak(t!("ai-ready-scores-appear-once-a"));
        }
        return;
    };
    let age = s.time - l.t;
    let heads: Vec<String> = l.heads.iter().map(|(k, v)| format!("{k} {v:.2}")).collect();
    ui.label(t!(
        "ai-live-line",
        model = l.model.label(),
        heads = heads.join("  "),
        ms = format!("{:.0}", l.ms),
        windows = l.windows,
        ago = format!("{age:.0}")
    ));
    if let (Some(c), Some(d)) = (l.clarity, l.sleep_dir) {
        ui.weak(t!("ai-anchors", clarity = format!("{c:.2}"), sleep = format!("{d:.2}")));
    }
}
