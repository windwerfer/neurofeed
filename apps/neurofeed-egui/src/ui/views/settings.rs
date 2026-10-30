//! Settings: a section rail (General, Devices, Training, AI, Recording,
//! About) with searchable cards.

use egui::RichText;
use nf_core::settings::{Appearance, SettingsPatch};
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
    (Section::General, "Subject", "subject id nickname anonymous pseudonym", |ui, s, o, _| subject(ui, s, o)),
    (Section::General, "Feedback sound", "audio sound music volume chime binaural rain cutoff invert", |ui, s, o, _| {
        super::sound::show(ui, s, o)
    }),
    (Section::Devices, "Devices", "muse crown bluetooth scan connect simulator", |ui, s, o, _| super::devices::show(ui, s, o)),
    (Section::Devices, "Mains notch", "notch 50 60 hz mains power line filter", |ui, s, o, _| mains(ui, s, o)),
    (Section::Training, "Band Stability", "stability window difficulty steadier", |ui, s, o, _| stability(ui, s, o)),
    (Section::Training, "Protocols", "protocol builder custom new edit", |ui, s, o, _| protocols(ui, s, o)),
    (Section::Ai, "AI sleep guard", "spur cbramod reve model sleep drowsiness import download scorer threshold", |ui, s, o, _| {
        super::ai::show(ui, s, o)
    }),
    (Section::Recording, "Storage", "folder storage database sqlite indexeddb", |ui, s, _, _| storage(ui, s)),
    (Section::Recording, "Gesture markers", "eye blink clench markers", |ui, s, o, _| gestures(ui, s, o)),
    (Section::About, "About NeuroFeed", "about version licenses credits notices", |ui, _, _, _| super::about::card(ui)),
    (Section::About, "Debug mode", "debug simulator sim fault", |ui, s, o, _| debug(ui, s, o)),
    (Section::About, "Agents", "mcp bridge agent ai control", |ui, _, _, sh| agents(ui, sh)),
    (Section::About, "Getting started", "onboarding tour intro help welcome", |ui, _, o, _| tour(ui, o)),
];

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>, shell: &mut crate::ui::Shell) {
    let (mut section, mut query) = UI.with(|st| (st.borrow().section, st.borrow().query.clone()));
    ui.add_space(6.0);
    ui.horizontal(|ui| {
        ui.heading(RichText::new("Settings").size(24.0));
        ui.add_space(20.0);
        ui.add(egui::TextEdit::singleline(&mut query).hint_text("Search settings").desired_width(240.0));
        if !query.is_empty() && ui.small_button("Clear").clicked() {
            query.clear();
        }
    });
    ui.add_space(8.0);
    ui.horizontal_top(|ui| {
        ui.vertical(|ui| {
            ui.set_width(150.0);
            for (s, name) in SECTIONS {
                if ui.add_sized([150.0, 28.0], egui::SelectableLabel::new(section == s && query.is_empty(), name)).clicked() {
                    section = s;
                    query.clear();
                }
            }
        });
        ui.separator();
        ui.vertical(|ui| {
            egui::ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
                let w = ui.available_width().min(760.0) - 24.0;
                let hits = matches(&query);
                if !query.is_empty() && hits.is_empty() {
                    ui.weak("No setting matches.");
                }
                for (s, title, _, body) in CARDS.iter().filter(|c| if query.is_empty() { c.0 == section } else { hits.contains(&c.1) }) {
                    ui.group(|ui| {
                        ui.set_width(w);
                        if !query.is_empty() {
                            ui.weak(SECTIONS.iter().find(|x| x.0 == *s).map_or("", |x| x.1));
                        }
                        ui.label(RichText::new(*title).strong().size(17.0));
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
            let blob = format!("{} {t} {terms}", SECTIONS.iter().find(|x| x.0 == *s).map_or("", |x| x.1)).to_lowercase();
            tokens.iter().all(|k| blob.contains(k.as_str()))
        })
        .map(|c| c.1)
        .collect()
}

fn set(out: &mut Vec<Command>, p: SettingsPatch) {
    out.push(Command::SettingsSet(p));
}

fn appearance(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let cur = session.state().settings.appearance;
    ui.horizontal(|ui| {
        for (a, name) in [(Appearance::System, "System"), (Appearance::Light, "Light"), (Appearance::Dark, "Dark")] {
            if ui.selectable_label(cur == a, name).clicked() && cur != a {
                set(out, SettingsPatch { appearance: Some(a), ..Default::default() });
            }
        }
    });
    ui.weak("Dark is tuned for dim rooms during training; System follows the OS.");
}

fn subject(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let saved = session.state().settings.subject.clone();
    ui.weak("A pseudonymous id stored with each recording (leave empty to stay anonymous). Never use your real name if you share files.");
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
            if ui.add_enabled(dirty, egui::Button::new("Save")).clicked()
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
        for (m, name) in [(M::Auto, "Auto"), (M::Hz50, "50 Hz"), (M::Hz60, "60 Hz"), (M::Off, "Off")] {
            if ui.selectable_label(cur == m, name).clicked() && cur != m {
                out.push(Command::MainsSet { mode: m });
            }
        }
    });
    ui.weak("Removes power-line hum. Auto detects 50 or 60 Hz from the signal. Saved across launches.");
}

fn protocols(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let n = session.state().custom_protocols.len();
    ui.weak(format!("{n} custom protocol(s). Create and edit them from the Feedback screen (\"New protocol…\" under the cards)."));
    if ui.button("Open Feedback").clicked() {
        out.push(Command::ViewSet { view: nf_core::View::Feedback });
    }
}

fn storage(ui: &mut egui::Ui, session: &Session) {
    ui.label(format!("Sessions and settings are stored in: {}", session.state().history_location));
    ui.weak("Desktop: SQLite file (NF_DB overrides the path). Web: IndexedDB in this browser. Export from History to move sessions.");
}

fn gestures(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let mut on = session.state().settings.gesture_markers;
    if ui.checkbox(&mut on, "Show blink / clench markers on trust plots").changed() {
        set(out, SettingsPatch { gesture_markers: Some(on), ..Default::default() });
    }
    ui.weak("Gestures are always recorded; this only controls drawing them.");
}

fn debug(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let mut on = session.state().settings.debug;
    if ui.checkbox(&mut on, "Show simulated devices and fault injection").changed() {
        set(out, SettingsPatch { debug: Some(on), ..Default::default() });
    }
}

fn agents(ui: &mut egui::Ui, shell: &mut crate::ui::Shell) {
    match &shell.bridge {
        None => {
            ui.weak("Not available in the web build.");
        }
        Some(bridge) => {
            let mut on = bridge.is_some();
            if ui.checkbox(&mut on, "Allow AI agents to control this app (MCP bridge)").changed() {
                shell.set_bridge = Some(on);
            }
            match bridge {
                Some(addr) => ui.weak(format!("Listening on {addr} (local only, token in bridge.json). Run: neurofeed-mcp --bridge")),
                None => ui.weak("Off. Also enabled by starting with NF_BRIDGE=1."),
            };
        }
    }
}

fn tour(ui: &mut egui::Ui, out: &mut Vec<Command>) {
    ui.weak("The short first-run tour: what neurofeedback is, fitting the headband, calibration and reading the trust pane.");
    if ui.button("Show the tour again").clicked() {
        set(out, SettingsPatch { onboarded: Some(false), ..Default::default() });
    }
}

fn stability(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let cur = session.state().feedback.stability;
    let enabled = session.enabled("stability.set");
    {
        ui.weak("Rewards steadier alpha than in calibration. Window = clean seconds in the rolling fluctuation; difficulty = how much steadier than baseline you must be (in target when r ≤ 1 − difficulty).");
        if let Err(why) = &enabled {
            ui.colored_label(egui::Color32::from_rgb(230, 170, 60), why);
        }
        ui.add_enabled_ui(enabled.is_ok(), |ui| {
            UI.with(|st| {
                let mut st = st.borrow_mut();
                let mut w = st.window.unwrap_or(cur.window);
                let r = ui.add(egui::Slider::new(&mut w, MIN_WINDOW..=MAX_WINDOW).text("window (s)"));
                st.window = (r.dragged() || r.has_focus()).then_some(w);
                if r.drag_stopped() || (r.changed() && !r.dragged()) {
                    out.push(Command::StabilitySet { window: Some(w), difficulty: None, reset: false });
                }
                let mut d = st.difficulty.unwrap_or(cur.difficulty);
                let r = ui.add(egui::Slider::new(&mut d, 0.0..=MAX_DIFFICULTY).step_by(0.01).fixed_decimals(2).text("difficulty"));
                st.difficulty = (r.dragged() || r.has_focus()).then_some(d);
                if r.drag_stopped() || (r.changed() && !r.dragged()) {
                    out.push(Command::StabilitySet { window: None, difficulty: Some(d), reset: false });
                }
            });
            let is_default = cur.window == DEFAULT_WINDOW && (cur.difficulty - DEFAULT_DIFFICULTY).abs() < 1e-9;
            if ui
                .add_enabled(!is_default, egui::Button::new(format!("Reset to defaults ({DEFAULT_WINDOW} s, {DEFAULT_DIFFICULTY:.2})")))
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
