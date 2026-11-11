//! Settings: a section rail (General, Devices, Training, AI, Recording,
//! About) with searchable cards.

use egui::RichText;
use nf_core::settings::{Appearance, Language, LayoutMode, SettingsPatch};
use nf_core::{Command, Session};
use nf_feedback_consts::{DEFAULT_DIFFICULTY, DEFAULT_WINDOW, MAX_DIFFICULTY, MAX_WINDOW, MIN_WINDOW};

/// Values shown while dragging (sent on release so a drag is one command).
#[derive(Default)]
pub struct SettingsUi {
    window: Option<u32>,
    difficulty: Option<f64>,
    section: Section,
    query: String,
    subject: Option<String>,
}

thread_local! {
    static UI: std::cell::RefCell<SettingsUi> = std::cell::RefCell::new(SettingsUi::default());
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
enum Section {
    #[default]
    General,
    Devices,
    Training,
    Ai,
    Recording,
    About,
}

const SECTIONS: [(Section, &str); 6] = [
    (Section::General, "General"),
    (Section::Devices, "Devices"),
    (Section::Training, "Training"),
    (Section::Ai, "AI"),
    (Section::Recording, "Recording"),
    (Section::About, "About"),
];

type CardFn = fn(&mut egui::Ui, &Session, &mut Vec<Command>, &mut crate::ui::Shell);

/// Every card: section, title, search terms, body.
const CARDS: &[(Section, &str, &str, CardFn)] = &[
    (Section::General, "Appearance", "theme system light dark brightness", |ui, s, o, _| appearance(ui, s, o)),
    (Section::General, "Language", "language sprache english deutsch german locale", |ui, s, o, _| language(ui, s, o)),
    (Section::General, "Layout", "layout compact regular phone desktop mobile sidebar bottom", |ui, s, o, _| layout(ui, s, o)),
    (Section::General, "Subject", "subject id nickname anonymous pseudonym", |ui, s, o, _| subject(ui, s, o)),
    (Section::General, "Feedback sound", "audio sound music volume chime binaural rain cutoff invert", |ui, s, o, _| {
        super::sound::show(ui, s, o)
    }),
    (Section::Devices, "Devices", "muse crown bluetooth scan connect simulator", |ui, s, o, _| super::devices::show(ui, s, o)),
    (Section::Devices, "Muse AUX channels", "muse aux auxiliary usb extra electrode", |ui, s, o, _| muse_aux(ui, s, o)),
    (Section::Devices, "Athena optical preset", "athena optics preset p1041 p1044 p1045 lanes", |ui, s, o, _| athena_preset(ui, s, o)),
    (Section::Devices, "Crown signal quality", "crown neurosity signal quality source pads", |ui, s, o, _| crown_quality(ui, s, o)),
    (Section::Devices, "Mains notch", "notch 50 60 hz mains power line filter", |ui, s, o, _| mains(ui, s, o)),
    (Section::Training, "Band Stability", "stability window difficulty steadier", |ui, s, o, _| stability(ui, s, o)),
    (Section::Training, "Calibration", "calibration staged simple artifacts eyes open baseline", |ui, s, o, _| calibration(ui, s, o)),
    (Section::Training, "Protocols", "protocol builder custom new edit", |ui, s, o, _| protocols(ui, s, o)),
    (Section::Ai, "AI sleep guard", "spur cbramod reve model sleep drowsiness import download scorer threshold", |ui, s, o, _| {
        super::ai::show(ui, s, o)
    }),
    (Section::Recording, "Storage", "folder storage database sqlite indexeddb", |ui, s, _, sh| storage(ui, s, sh)),
    (Section::Recording, "Record AUX", "aux auxiliary muse recording edf", |ui, s, o, _| record_aux(ui, s, o)),
    (Section::Recording, "Gesture markers", "eye up down blink clench double markers feedback", |ui, s, o, _| gestures(ui, s, o)),
    (Section::About, "About NeuroFeed", "about version licenses credits notices", |ui, _, _, _| super::about::card(ui)),
    (
        Section::About,
        "Debug mode",
        "debug simulator sim fault fps frame rate overlay discard confirm recording verwerfen",
        |ui, s, o, _| debug(ui, s, o),
    ),
    (Section::About, "Agents", "mcp bridge agent ai control", |ui, _, _, sh| agents(ui, sh)),
    (Section::About, "Getting started", "onboarding tour intro help welcome", |ui, _, o, _| tour(ui, o)),
];

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>, shell: &mut crate::ui::Shell) {
    let (mut section, mut query) = UI.with(|st| (st.borrow().section, st.borrow().query.clone()));
    ui.add_space(6.0);
    ui.horizontal(|ui| {
        ui.heading(RichText::new(t!("settings-settings")).size(24.0));
        ui.add_space(20.0);
        ui.add(egui::TextEdit::singleline(&mut query).hint_text(t!("settings-search-settings")).desired_width(240.0));
        if !query.is_empty() && ui.small_button(t!("settings-clear")).clicked() {
            query.clear();
        }
    });
    ui.add_space(8.0);
    let compact = crate::ui::layout::current(ui.ctx()).is_compact();
    if compact {
        ui.horizontal_wrapped(|ui| sections(ui, 0.0, &mut section, &mut query));
        ui.separator();
    }
    ui.horizontal_top(|ui| {
        if !compact {
            ui.vertical(|ui| {
                ui.set_width(150.0);
                sections(ui, 150.0, &mut section, &mut query);
            });
            ui.separator();
        }
        ui.vertical(|ui| {
            egui::ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
                let w = ui.available_width().min(760.0) - 24.0;
                let hits = matches(&query);
                if !query.is_empty() && hits.is_empty() {
                    ui.weak(t!("settings-no-setting-matches"));
                }
                for (s, title, _, body) in CARDS.iter().filter(|c| if query.is_empty() { c.0 == section } else { hits.contains(&c.1) }) {
                    ui.group(|ui| {
                        ui.set_width(w);
                        if !query.is_empty() {
                            ui.weak(title_tr(SECTIONS.iter().find(|x| x.0 == *s).map_or("", |x| x.1)));
                        }
                        ui.label(RichText::new(title_tr(title)).strong().size(17.0));
                        body(ui, session, out, shell);
                    });
                    ui.add_space(10.0);
                }
            })
        });
    });
    UI.with(|st| {
        let mut st = st.borrow_mut();
        st.section = section;
        st.query = query;
    });
}

/// Titles of cards whose section + title + terms contain every query token.
fn matches(q: &str) -> Vec<&'static str> {
    let tokens: Vec<String> = q.split_whitespace().map(str::to_lowercase).collect();
    if tokens.is_empty() {
        return Vec::new();
    }
    CARDS
        .iter()
        .filter(|(s, t, terms, _)| {
            let sec = SECTIONS.iter().find(|x| x.0 == *s).map_or("", |x| x.1);
            let blob = format!("{sec} {} {t} {} {terms}", title_tr(sec), title_tr(t)).to_lowercase();
            tokens.iter().all(|k| blob.contains(k.as_str()))
        })
        .map(|c| c.1)
        .collect()
}

/// Section buttons (a column in regular, a wrapped row in compact).
fn sections(ui: &mut egui::Ui, w: f32, section: &mut Section, query: &mut String) {
    for (s, name) in SECTIONS {
        if ui.add_sized([w, 28.0], egui::Button::selectable(*section == s && query.is_empty(), title_tr(name))).clicked() {
            *section = s;
            query.clear();
        }
    }
}

/// Translated section / card title (`settings-card-<slug>`; English fallback).
fn title_tr(en: &str) -> String {
    let slug: Vec<&str> = en.split(|c: char| !c.is_ascii_alphanumeric()).filter(|w| !w.is_empty()).collect();
    let key = format!("settings-card-{}", slug.join("-").to_lowercase());
    let s = crate::i18n::tr(&key, &[]);
    if s == key {
        en.to_owned()
    } else {
        s
    }
}

fn set(out: &mut Vec<Command>, p: SettingsPatch) {
    out.push(Command::SettingsSet(p));
}

fn language(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let cur = session.state().settings.language;
    ui.horizontal(|ui| {
        for (l, name) in
            [(Language::Auto, t!("settings-language-auto")), (Language::En, "English".to_owned()), (Language::De, "Deutsch".to_owned())]
        {
            if ui.selectable_label(cur == l, name).clicked() && cur != l {
                set(out, SettingsPatch { language: Some(l), ..Default::default() });
            }
        }
    });
    ui.weak(t!("settings-language-hint", lang = crate::i18n::resolve(Language::Auto)));
}

fn layout(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let cur = session.state().settings.layout;
    ui.horizontal(|ui| {
        for (m, name) in [
            (LayoutMode::Auto, t!("settings-auto")),
            (LayoutMode::Compact, t!("settings-compact")),
            (LayoutMode::Regular, t!("settings-regular")),
        ] {
            if ui.selectable_label(cur == m, name).clicked() && cur != m {
                set(out, SettingsPatch { layout: Some(m), ..Default::default() });
            }
        }
    });
    ui.weak(t!("settings-auto-uses-the-compact-phone"));
}

fn appearance(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let cur = session.state().settings.appearance;
    ui.horizontal(|ui| {
        for (a, name) in [
            (Appearance::System, t!("settings-system")),
            (Appearance::Light, t!("settings-light")),
            (Appearance::Dark, t!("settings-dark")),
        ] {
            if ui.selectable_label(cur == a, name).clicked() && cur != a {
                set(out, SettingsPatch { appearance: Some(a), ..Default::default() });
            }
        }
    });
    ui.weak(t!("settings-dark-is-tuned-for-dim"));
}

fn subject(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let saved = session.state().settings.subject.clone();
    ui.weak(t!("settings-a-pseudonymous-id-stored-with"));
    UI.with(|st| {
        let mut st = st.borrow_mut();
        let mut text = st.subject.clone().unwrap_or_else(|| saved.clone());
        ui.horizontal(|ui| {
            let r = ui.add(
                egui::TextEdit::singleline(&mut text).hint_text("e.g. p07").char_limit(nf_core::settings::MAX_SUBJECT).desired_width(200.0),
            );
            if r.changed() {
                st.subject = Some(text.clone());
            }
            let dirty = text.trim() != saved;
            if ui.add_enabled(dirty, egui::Button::new(t!("settings-save"))).clicked()
                || (dirty && r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)))
            {
                set(out, SettingsPatch { subject: Some(text.clone()), ..Default::default() });
                st.subject = None;
            }
        });
    });
}

fn mains(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    use nf_core::MainsMode as M;
    let cur = session.state().mains_mode;
    ui.horizontal(|ui| {
        for (m, name) in [(M::Auto, &*t!("settings-auto")), (M::Hz50, "50 Hz"), (M::Hz60, "60 Hz"), (M::Off, &*t!("settings-off"))] {
            if ui.selectable_label(cur == m, name).clicked() && cur != m {
                out.push(Command::MainsSet { mode: m });
            }
        }
    });
    ui.weak(t!("settings-removes-power-line-hum-auto"));
}

fn protocols(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let n = session.state().custom_protocols.len();
    ui.weak(t!("settings-n-custom-protocols", n = n));
    if ui.button(t!("settings-open-feedback")).clicked() {
        out.push(Command::ViewSet { view: nf_core::View::Feedback });
    }
}

fn calibration(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let mut on = session.state().settings.always_staged;
    if ui.checkbox(&mut on, t!("settings-always-staged")).changed() {
        set(out, SettingsPatch { always_staged: Some(on), ..Default::default() });
    }
    ui.weak(t!("settings-always-staged-help", s = nf_core::nf_feedback::BASELINE_VALID_S));
}

fn storage(ui: &mut egui::Ui, session: &Session, shell: &mut crate::ui::Shell) {
    let loc = &session.state().history_location;
    ui.label(t!("settings-stored-in", location = loc.as_str()));
    if let Some(p) = crate::platform::get() {
        ui.weak(t!("settings-android-the-database-stays-in"));
        ui.horizontal(|ui| {
            ui.label(t!("settings-export-folder", folder = p.folder_label().unwrap_or_else(|| t!("settings-ask-each-time"))));
            if ui.button(t!("settings-choose-folder")).clicked() {
                p.pick_folder();
            }
        });
        return;
    }
    ui.weak(t!("settings-desktop-sqlite-file-nf-db"));
    if cfg!(target_arch = "wasm32") || !std::path::Path::new(loc).is_file() {
        return;
    }
    let id = ui.scope_id().with("move-dir");
    let mut dir: String = ui.data(|d| d.get_temp(id)).unwrap_or_default();
    ui.horizontal(|ui| {
        ui.add(egui::TextEdit::singleline(&mut dir).hint_text(t!("settings-new-folder-hint")).desired_width(320.0));
        let busy = session.state().recording.as_ref().is_some_and(|r| r.active);
        let r = ui.add_enabled(!dir.trim().is_empty() && !busy, egui::Button::new(t!("settings-move-here")));
        if r.on_disabled_hover_text(t!("settings-enter-folder-not-recording")).clicked() {
            shell.move_store = Some(dir.clone());
        }
    });
    ui.data_mut(|d| d.insert_temp(id, dir));
    ui.weak(t!("settings-copies-the-database-checks-it"));
    if let Some(n) = &shell.store_note {
        ui.weak(n);
    }
}

fn gestures(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let mut on = session.state().settings.gesture_markers;
    if ui.checkbox(&mut on, t!("settings-show-blink-clench-markers-on")).changed() {
        set(out, SettingsPatch { gesture_markers: Some(on), ..Default::default() });
    }
    ui.weak(t!("settings-gestures-are-always-recorded-this"));
    let st = &session.state().settings;
    let mut eye = st.eye_markers;
    if ui.checkbox(&mut eye, t!("settings-detect-eye-up-down-glances")).changed() {
        set(out, SettingsPatch { eye_markers: Some(eye), ..Default::default() });
    }
    let mut fb = st.markers_in_feedback;
    if ui.checkbox(&mut fb, t!("settings-mark-double-blinks-double-clenches")).changed() {
        set(out, SettingsPatch { markers_in_feedback: Some(fb), ..Default::default() });
    }
    ui.weak(t!("settings-double-blink-double-clench-two"));
}

fn athena_preset(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let cur = session.state().settings.athena_preset.clone();
    let choices =
        [("p1041", t!("settings-athena-preset-16")), ("p1044", t!("settings-athena-preset-8")), ("p1045", t!("settings-athena-preset-4"))];
    let label = choices.iter().find(|(id, _)| *id == cur).map(|(_, l)| l.clone()).unwrap_or_else(|| cur.clone());
    egui::ComboBox::from_id_salt("nf_athena_preset").selected_text(label).show_ui(ui, |ui| {
        for (id, name) in &choices {
            if ui.selectable_label(cur == *id, name).clicked() && cur != *id {
                set(out, SettingsPatch { athena_preset: Some((*id).to_owned()), ..Default::default() });
            }
        }
    });
    ui.weak(t!("settings-athena-preset-hint"));
}

fn muse_aux(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let mut on = session.state().settings.muse_aux;
    if ui.checkbox(&mut on, t!("settings-show-muse-aux-channels")).changed() {
        set(out, SettingsPatch { muse_aux: Some(on), ..Default::default() });
    }
    ui.weak(t!("settings-muse-2-s-aux1-the"));
}

fn record_aux(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let st = &session.state().settings;
    let mut on = st.record_aux;
    ui.add_enabled_ui(st.muse_aux, |ui| {
        if ui.checkbox(&mut on, t!("settings-record-aux-channels")).changed() {
            set(out, SettingsPatch { record_aux: Some(on), ..Default::default() });
        }
    });
    ui.weak(if st.muse_aux { t!("settings-aux-is-saved-with-the") } else { t!("settings-turn-on-settings-devices-muse") });
}

fn crown_quality(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    use nf_core::settings::QualitySource;
    let cur = session.state().settings.crown_quality;
    ui.horizontal(|ui| {
        for (q, name) in [(QualitySource::Crown, t!("settings-crown-device")), (QualitySource::App, t!("settings-neurofeed-computed"))] {
            if ui.selectable_label(cur == q, name).clicked() && cur != q {
                set(out, SettingsPatch { crown_quality: Some(q), ..Default::default() });
            }
        }
    });
    ui.weak(t!("settings-crown-pad-colours-use-the"));
}

fn debug(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let mut on = session.state().settings.debug;
    if ui.checkbox(&mut on, t!("settings-show-simulated-devices-and-fault")).changed() {
        set(out, SettingsPatch { debug: Some(on), ..Default::default() });
    }
    let mut ask = session.state().settings.confirm_discard;
    if ui.checkbox(&mut ask, t!("settings-confirm-discard")).on_hover_text(t!("settings-confirm-discard-hint")).changed() {
        set(out, SettingsPatch { confirm_discard: Some(ask), ..Default::default() });
    }
    let mut perf = session.state().settings.perf_overlay;
    if ui.checkbox(&mut perf, t!("settings-perf-overlay")).on_hover_text(t!("settings-perf-overlay-hint")).changed() {
        set(out, SettingsPatch { perf_overlay: Some(perf), ..Default::default() });
    }
    if on {
        faults(ui, session, out);
    }
}

/// Debug: inject timed simulator faults mid-stream (`sim.fault.add` / `.clear`).
fn faults(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    use nf_core::faults::{BadValue, FaultTag};
    if let Err(why) = session.enabled("sim.fault.add") {
        ui.weak(t!("settings-fault-injection-unavailable", reason = why.to_string()));
        return;
    }
    let id = egui::Id::unique("fault_duration");
    let mut dur: f64 = ui.data(|d| d.get_temp(id)).unwrap_or(5.0);
    ui.horizontal(|ui| {
        ui.label(t!("settings-inject-fault-for"));
        ui.add(egui::DragValue::new(&mut dur).range(1.0..=600.0).suffix(" s"));
        ui.weak(t!("settings-fault-all-pads"));
    });
    ui.data_mut(|d| d.insert_temp(id, dur));
    let kinds = [
        (t!("settings-disconnect"), FaultTag::Disconnect),
        (t!("settings-movement"), FaultTag::Movement),
        (t!("settings-blink"), FaultTag::Blink),
        (t!("settings-jaw-clench"), FaultTag::Clench),
        (t!("settings-noise-20-clean"), FaultTag::Noise),
        (t!("settings-spikes"), FaultTag::Spikes),
        (t!("settings-glitch"), FaultTag::Glitch),
        (t!("settings-nan-values"), FaultTag::OutOfRange),
    ];
    ui.horizontal_wrapped(|ui| {
        for (label, kind) in kinds {
            if ui.button(label).clicked() {
                let disc = kind == FaultTag::Disconnect;
                out.push(Command::SimFaultAdd {
                    kind,
                    reconnect_after_s: disc.then_some(dur),
                    clean_fraction: (kind == FaultTag::Noise).then_some(0.2),
                    value: (kind == FaultTag::OutOfRange).then_some(BadValue::Nan),
                    duration_s: (!disc).then_some(dur),
                    channels: Vec::new(),
                });
            }
        }
    });
    let now = session.state().time;
    for f in &session.state().faults {
        ui.horizontal(|ui| {
            let left =
                f.end().map_or(t!("settings-until-cleared"), |e| t!("settings-seconds-left", s = format!("{:.0}", (e - now).max(0.0))));
            let chans = if f.channels.is_empty() { t!("settings-all-channels") } else { f.channels.join(", ") };
            ui.monospace(format!("#{} {:?} · {chans} · {left}", f.id, f.kind));
            if ui.small_button(t!("settings-clear")).clicked() {
                out.push(Command::SimFaultClear { id: Some(f.id) });
            }
        });
    }
    if !session.state().faults.is_empty() && ui.button(t!("settings-clear-all-faults")).clicked() {
        out.push(Command::SimFaultClear { id: None });
    }
}

fn agents(ui: &mut egui::Ui, shell: &mut crate::ui::Shell) {
    match &shell.bridge {
        None => {
            ui.weak(t!("settings-not-available-in-the-web"));
        }
        Some(bridge) => {
            let mut on = bridge.is_some();
            if ui.checkbox(&mut on, t!("settings-allow-ai-agents-to-control")).changed() {
                shell.set_bridge = Some(on);
            }
            match bridge {
                Some(addr) => ui.weak(t!("settings-bridge-listening", addr = addr.to_string())),
                None => ui.weak(t!("settings-off-also-enabled-by-starting")),
            };
        }
    }
}

fn tour(ui: &mut egui::Ui, out: &mut Vec<Command>) {
    ui.weak(t!("settings-the-short-first-run-tour"));
    if ui.button(t!("settings-show-the-tour-again")).clicked() {
        set(out, SettingsPatch { onboarded: Some(false), ..Default::default() });
    }
}

fn stability(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let cur = session.state().feedback.stability;
    let enabled = session.enabled("stability.set");
    {
        ui.weak(t!("settings-rewards-steadier-alpha-than-in"));
        if let Err(why) = &enabled {
            ui.colored_label(egui::Color32::from_rgb(230, 170, 60), why);
        }
        ui.add_enabled_ui(enabled.is_ok(), |ui| {
            UI.with(|st| {
                let mut st = st.borrow_mut();
                let mut w = st.window.unwrap_or(cur.window);
                let r = ui.add(egui::Slider::new(&mut w, MIN_WINDOW..=MAX_WINDOW).text(t!("settings-window-s")));
                st.window = (r.dragged() || r.has_focus()).then_some(w);
                if r.drag_stopped() || (r.changed() && !r.dragged()) {
                    out.push(Command::StabilitySet { window: Some(w), difficulty: None, reset: false });
                }
                let mut d = st.difficulty.unwrap_or(cur.difficulty);
                let r =
                    ui.add(egui::Slider::new(&mut d, 0.0..=MAX_DIFFICULTY).step_by(0.01).fixed_decimals(2).text(t!("settings-difficulty")));
                st.difficulty = (r.dragged() || r.has_focus()).then_some(d);
                if r.drag_stopped() || (r.changed() && !r.dragged()) {
                    out.push(Command::StabilitySet { window: None, difficulty: Some(d), reset: false });
                }
            });
            let is_default = cur.window == DEFAULT_WINDOW && (cur.difficulty - DEFAULT_DIFFICULTY).abs() < 1e-9;
            if ui
                .add_enabled(
                    !is_default,
                    egui::Button::new(t!(
                        "settings-reset-stability",
                        window = DEFAULT_WINDOW.to_string(),
                        difficulty = format!("{DEFAULT_DIFFICULTY:.2}")
                    )),
                )
                .clicked()
            {
                out.push(Command::StabilitySet { window: None, difficulty: None, reset: true });
            }
        });
    }
}

/// Re-exported bounds (nf-feedback is reached through nf-core).
mod nf_feedback_consts {
    use nf_core::StabilityConfig as S;
    pub const DEFAULT_WINDOW: u32 = S::DEFAULT_WINDOW;
    pub const MIN_WINDOW: u32 = S::MIN_WINDOW;
    pub const MAX_WINDOW: u32 = S::MAX_WINDOW;
    pub const DEFAULT_DIFFICULTY: f64 = S::DEFAULT_DIFFICULTY;
    pub const MAX_DIFFICULTY: f64 = S::MAX_DIFFICULTY;
}
