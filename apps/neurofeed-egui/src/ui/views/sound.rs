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
    (RewardOutput::Chime, "sound-reward-chime", "sound-reward-chime-about"),
    (RewardOutput::Rain, "sound-reward-rain", "sound-reward-rain-about"),
    (RewardOutput::Binaural, "sound-reward-binaural", "sound-reward-binaural-about"),
    (RewardOutput::Music, "sound-reward-music", "sound-reward-music-about"),
    (RewardOutput::None, "sound-reward-none", "sound-reward-none-about"),
];
const BACKGROUNDS: [(Background, &str); 5] = [
    (Background::Drone, "sound-bg-drone"),
    (Background::DroneLoop, "sound-bg-drone-loop"),
    (Background::Rain, "sound-bg-rain"),
    (Background::Binaural, "sound-bg-binaural"),
    (Background::None, "sound-bg-none"),
];
const GUARDS: [(GuardSound, &str); 5] = [
    (GuardSound::SoftBowl, "sound-guard-soft-bowl"),
    (GuardSound::Chime, "sound-guard-chime"),
    (GuardSound::Cough, "sound-guard-cough"),
    (GuardSound::Alarm, "sound-guard-alarm"),
    (GuardSound::None, "sound-guard-none"),
];

fn send(out: &mut Vec<Command>, p: AudioPatch) {
    out.push(Command::AudioSet(p));
}

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let a = session.state().audio;
    ui.scope(|ui| {
        ui.weak(t!("sound-changes-apply-live-also-during"));
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
        ui.label(t!("sound-reward"));
        for (r, label, about) in REWARDS {
            if ui.selectable_label(a.reward == r, crate::i18n::tr(label, &[])).on_hover_text(crate::i18n::tr(about, &[])).clicked() {
                send(out, AudioPatch { reward_output: Some(r), ..Default::default() });
            }
        }
    });
    if let Some((_, _, about)) = REWARDS.iter().find(|(r, ..)| *r == a.reward) {
        ui.weak(crate::i18n::tr(about, &[]));
    }
}

fn choice_rows(ui: &mut egui::Ui, a: AudioSettings, out: &mut Vec<Command>) {
    ui.horizontal_wrapped(|ui| {
        ui.label(t!("sound-background"));
        for (b, label) in BACKGROUNDS {
            if ui.selectable_label(a.background == b, crate::i18n::tr(label, &[])).clicked() {
                send(out, AudioPatch { background: Some(b), ..Default::default() });
            }
        }
    });
    ui.horizontal_wrapped(|ui| {
        ui.label(t!("sound-guard-warning"));
        for (g, label) in GUARDS {
            if ui.selectable_label(a.guard == g, crate::i18n::tr(label, &[])).clicked() {
                send(out, AudioPatch { guard_sound: Some(g), ..Default::default() });
            }
        }
    });
    if a.reward == RewardOutput::Binaural || a.background == Background::Binaural {
        egui::ComboBox::from_label(t!("sound-binaural-preset")).selected_text(a.binaural.label()).show_ui(ui, |ui| {
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
    if ui.checkbox(&mut muted, t!("sound-mute-all")).changed() {
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
        ui.weak(t!("sound-music-needs-the-desktop-app"));
        return;
    }
    let cur = session.state().music_dir.clone().unwrap_or_default();
    ui.horizontal(|ui| {
        ui.label(t!("sound-music-folder"));
        DRAFT.with(|d| {
            let mut d = d.borrow_mut();
            let text = d.1.get_or_insert_with(|| cur.clone());
            let r = ui.add(egui::TextEdit::singleline(text).hint_text(t!("sound-music-path-hint")).desired_width(320.0));
            let enter = r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter));
            if (ui.add_enabled(*text != cur, egui::Button::new(t!("sound-load"))).clicked() || enter) && *text != cur {
                send(out, AudioPatch { music_dir: Some(text.clone()), ..Default::default() });
            }
        });
    });
}

/// Guard toggle row for the protocol picker.
pub fn guard_row(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let t = &session.state().feedback;
    let Some(g) = t.protocol.guard else { return };
    let mute = if g.muffle_reward { "yes" } else { "no" };
    let ai = &session.state().ai;
    if ai.ready() {
        let thr = match ai.settings.threshold_mode {
            nf_core::ai::ThresholdMode::Fixed => t!("sound-p-drowsy-above", thr = format!("{:.2}", ai.settings.fixed_threshold)),
            nf_core::ai::ThresholdMode::Percentile => t!("sound-above-your-calibration"),
        };
        ui.horizontal(|ui| {
            ui.label(egui::RichText::new(t!("sound-ai-drowsiness-guard")).color(egui::Color32::from_rgb(0x66, 0xBB, 0x6A)));
            ui.weak(t!("sound-ai-guard-warns", model = ai.settings.model().label(), mute = mute, when = thr));
        });
        return;
    }
    ui.horizontal(|ui| {
        let mut on = t.guard;
        let enabled = session.enabled("guard.set");
        let r = ui.add_enabled(enabled.is_ok(), egui::Checkbox::new(&mut on, t!("sound-band-math-drowsiness-guard")));
        if r.changed() {
            out.push(Command::GuardSet { enabled: on });
        }
        ui.weak(t!("sound-band-guard-warns", mute = mute));
    });
}
