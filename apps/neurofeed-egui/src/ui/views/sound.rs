//! Feedback sound settings (Settings view) and the guard row used on the
//! protocol picker. Every change is one `audio.set` / `guard.set`.

use nf_core::audio::AudioPatch;
use nf_core::nf_audio::{AudioSettings, Background, BinauralPreset, GuardSound, RewardOutput};
use nf_core::{Command, Session};
use std::cell::RefCell;
use std::collections::HashMap;

thread_local! {
    /// Slider values while dragging (sent on release) and the folder draft.
    static DRAFT: RefCell<(HashMap<&'static str, f64>, Option<String>)> = RefCell::new(Default::default());
}

const REWARDS: [(RewardOutput, &str, &str); 5] = [
    (RewardOutput::Chime, "Chime", "A singing bowl each time you enter the target."),
    (RewardOutput::Rain, "Rain", "Five rain stages: heavy far from target, near-silent on target."),
    (RewardOutput::Binaural, "Binaural swell", "A binaural beat that grows louder as you improve (headphones)."),
    (RewardOutput::Music, "Music", "Your music; it opens up (low-pass) as you improve. Desktop only."),
    (RewardOutput::None, "None", "No reward sound."),
];
const BACKGROUNDS: [(Background, &str); 5] = [
    (Background::Drone, "Drone"),
    (Background::DroneLoop, "Drone loop"),
    (Background::Rain, "Rain"),
    (Background::Binaural, "Binaural"),
    (Background::None, "None"),
];
const GUARDS: [(GuardSound, &str); 5] = [
    (GuardSound::SoftBowl, "Soft bowl"),
    (GuardSound::Chime, "Chime"),
    (GuardSound::Cough, "Cough"),
    (GuardSound::Alarm, "Alarm (ramps up)"),
    (GuardSound::None, "None"),
];

fn send(out: &mut Vec<Command>, p: AudioPatch) {
    out.push(Command::AudioSet(p));
}

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let a = session.state().audio;
    ui.scope(|ui| {
        ui.weak("Changes apply live, also during a session.");
        reward_row(ui, a, out);
        choice_rows(ui, a, out);
        volumes(ui, a, out);
        if a.reward == RewardOutput::Music {
            music(ui, session, out);
        }
    });
}

fn reward_row(ui: &mut egui::Ui, a: AudioSettings, out: &mut Vec<Command>) {
    ui.horizontal_wrapped(|ui| {
        ui.label("Reward:");
        for (r, label, about) in REWARDS {
            if ui.selectable_label(a.reward == r, label).on_hover_text(about).clicked() {
                send(out, AudioPatch { reward_output: Some(r), ..Default::default() });
            }
        }
    });
    if let Some((_, _, about)) = REWARDS.iter().find(|(r, ..)| *r == a.reward) {
        ui.weak(*about);
    }
}

fn choice_rows(ui: &mut egui::Ui, a: AudioSettings, out: &mut Vec<Command>) {
    ui.horizontal_wrapped(|ui| {
        ui.label("Background:");
        for (b, label) in BACKGROUNDS {
            if ui.selectable_label(a.background == b, label).clicked() {
                send(out, AudioPatch { background: Some(b), ..Default::default() });
            }
        }
    });
    ui.horizontal_wrapped(|ui| {
        ui.label("Guard warning:");
        for (g, label) in GUARDS {
            if ui.selectable_label(a.guard == g, label).clicked() {
                send(out, AudioPatch { guard_sound: Some(g), ..Default::default() });
            }
        }
    });
    if a.reward == RewardOutput::Binaural || a.background == Background::Binaural {
        egui::ComboBox::from_label("Binaural preset").selected_text(a.binaural.label()).show_ui(ui, |ui| {
            for p in BinauralPreset::ALL {
                let (label, about, ..) = p.spec();
                if ui.selectable_label(a.binaural == p, label).on_hover_text(about).clicked() {
                    send(out, AudioPatch { binaural_preset: Some(p), ..Default::default() });
                }
            }
        });
    }
}

/// (draft key, label, current value, patch builder).
type VolumeRow = (&'static str, &'static str, f64, fn(f64) -> AudioPatch);

fn volumes(ui: &mut egui::Ui, a: AudioSettings, out: &mut Vec<Command>) {
    let mut muted = a.muted;
    if ui.checkbox(&mut muted, "Mute all").changed() {
        send(out, AudioPatch { muted: Some(muted), ..Default::default() });
    }
    let rows: [VolumeRow; 4] = [
        ("master", "master", a.master, |v| AudioPatch { master_volume: Some(v), ..Default::default() }),
        ("feedback", "reward", a.feedback, |v| AudioPatch { feedback_volume: Some(v), ..Default::default() }),
        ("background", "background", a.background_volume, |v| AudioPatch { background_volume: Some(v), ..Default::default() }),
        ("guard", "guard", a.guard_volume, |v| AudioPatch { guard_volume: Some(v), ..Default::default() }),
    ];
    for (key, label, cur, patch) in rows {
        DRAFT.with(|d| {
            let mut d = d.borrow_mut();
            let mut v = d.0.get(key).copied().unwrap_or(cur);
            let r = ui.add(egui::Slider::new(&mut v, 0.0..=1.0).fixed_decimals(2).text(label));
            if r.dragged() || r.has_focus() {
                d.0.insert(key, v);
            } else {
                d.0.remove(key);
            }
            if r.drag_stopped() || (r.changed() && !r.dragged()) {
                send(out, patch(v));
            }
        });
    }
}

fn music(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    if cfg!(target_arch = "wasm32") {
        ui.weak("Music needs the desktop app (local folder).");
        return;
    }
    let cur = session.state().music_dir.clone().unwrap_or_default();
    ui.horizontal(|ui| {
        ui.label("Music folder:");
        DRAFT.with(|d| {
            let mut d = d.borrow_mut();
            let text = d.1.get_or_insert_with(|| cur.clone());
            let r = ui.add(egui::TextEdit::singleline(text).hint_text("/path/to/music (.ogg .mp3 .flac .wav)").desired_width(320.0));
            let enter = r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter));
            if (ui.add_enabled(*text != cur, egui::Button::new("Load")).clicked() || enter) && *text != cur {
                send(out, AudioPatch { music_dir: Some(text.clone()), ..Default::default() });
            }
        });
    });
}

/// Guard toggle row for the protocol picker.
pub fn guard_row(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let t = &session.state().feedback;
    let Some(g) = t.protocol.guard else { return };
    let mute = if g.muffle_reward { " and mutes the reward" } else { "" };
    let ai = &session.state().ai;
    if ai.ready() {
        let thr = match ai.settings.threshold_mode {
            nf_core::ai::ThresholdMode::Fixed => format!("P(drowsy) above {:.2}", ai.settings.fixed_threshold),
            nf_core::ai::ThresholdMode::Percentile => "above your calibration (p75)".into(),
        };
        ui.horizontal(|ui| {
            ui.label(egui::RichText::new("✔ AI drowsiness guard").color(egui::Color32::from_rgb(0x66, 0xBB, 0x6A)));
            ui.weak(format!("{} warns{mute} when {thr}. Change it in Settings → AI.", ai.settings.model().label()));
        });
        return;
    }
    ui.horizontal(|ui| {
        let mut on = t.guard;
        let enabled = session.enabled("guard.set");
        let r = ui.add_enabled(enabled.is_ok(), egui::Checkbox::new(&mut on, "Band-math drowsiness guard"));
        if r.changed() {
            out.push(Command::GuardSet { enabled: on });
        }
        ui.weak(format!("Warns{mute} when delta rises above your calibration (p75). Load an AI model (Settings → AI) for the AI guard."));
    });
}
