//! Feedback start screen (protocol tiles + Recent row) and the generic
//! session-setup screen: the layer stack Background → Feedback → Guardrail.
//! Views only read `&Session` and emit commands (`feedback.setup`,
//! `protocol.set`, `layers.*`); which tile is expanded is view chrome.

use egui::RichText;
use nf_core::layers::{Layer, LayerConfig, LayerKind, LayerPatch};
use nf_core::nf_audio::{Background, BinauralPreset, GuardSound, RewardOutput};
use nf_core::nf_feedback::Protocol;
use nf_core::{Command, Session};

/// Columns for the tile grid from the width available: 1 on phones, more
/// on wide screens so the space is used.
pub(super) fn columns(width: f32) -> usize {
    if width < 560.0 {
        1
    } else if width < 940.0 {
        2
    } else {
        3
    }
}

/// Tile width for `cols` columns inside `width` (card frame margins and the grid gap included).
fn tile_width(width: f32, cols: usize) -> f32 {
    let gap = 12.0;
    let chrome = 2.0 * 14.0;
    ((width - gap * (cols.saturating_sub(1)) as f32) / cols.max(1) as f32 - chrome).max(120.0)
}

fn open_setup(id: &str, out: &mut Vec<Command>) {
    out.push(Command::ProtocolSet { id: id.to_owned(), minutes: None });
    out.push(Command::FeedbackSetup { open: true });
}

fn tile_grid(ui: &mut egui::Ui, salt: &str, list: &[Protocol], selected: &str, out: &mut Vec<Command>) {
    let width = ui.available_width();
    let cols = columns(width);
    let w = tile_width(width, cols);
    egui::Grid::new(("protocol_tiles", salt)).spacing([12.0, 12.0]).show(ui, |ui| {
        for (i, p) in list.iter().enumerate() {
            let rect = super::feedback::card(ui, p, p.id == selected, w).rect;
            if ui.interact(rect, ui.scope_id().with((salt, &p.id)), egui::Sense::click()).clicked() {
                open_setup(&p.id, out);
            }
            if i % cols == cols - 1 {
                ui.end_row();
            }
        }
    });
}

/// The start screen body: Recent row, then every protocol.
pub(super) fn tiles(ui: &mut egui::Ui, session: &Session, selected: &str, out: &mut Vec<Command>) {
    let s = session.state();
    let recent: Vec<Protocol> = s
        .recent_protocols
        .iter()
        .filter_map(|id| nf_core::protocols::find(&s.custom_protocols, id))
        .take(nf_core::layers::RECENT_SHOWN)
        .collect();
    if !recent.is_empty() {
        ui.label(RichText::new(t!("feedback-recent")).strong());
        tile_grid(ui, "recent", &recent, selected, out);
        ui.add_space(10.0);
        ui.label(RichText::new(t!("feedback-all-protocols")).strong());
    }
    tile_grid(ui, "all", &nf_core::protocols::all(&s.custom_protocols), selected, out);
}

fn kind_title(kind: LayerKind) -> String {
    match kind {
        LayerKind::Background => t!("feedback-layer-background"),
        LayerKind::Feedback => t!("feedback-layer-feedback"),
        LayerKind::Guardrail => t!("feedback-layer-guardrail"),
    }
}

/// The setup screen body: back, the stack by section, "+", reset.
pub(super) fn setup(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    ui.horizontal(|ui| {
        if ui.button(format!("← {}", t!("feedback-setup-back"))).clicked() {
            out.push(Command::FeedbackSetup { open: false });
        }
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), super::volume_dialog::button);
    });
    super::volume_dialog::window(ui.ctx(), session, out);
    let p = &session.trainer().protocol;
    ui.add_space(4.0);
    ui.heading(RichText::new(crate::i18n::protocol_title(p)).size(24.0));
    ui.weak(t!("feedback-setup-hint"));
    ui.add_space(8.0);
    let layers = &session.state().layers;
    for kind in LayerKind::ALL {
        if layers.count(kind) == 0 {
            continue; // only layers present in the session are shown
        }
        ui.label(RichText::new(kind_title(kind)).strong());
        for l in layers.of_kind(kind) {
            layer_tile(ui, session, l, layers.shows_volume(kind), out);
        }
        ui.add_space(8.0);
    }
    if LayerKind::ALL.iter().any(|k| layers.count(*k) > 1) {
        ui.weak(t!("feedback-layer-extra-note"));
    }
    add_menu(ui, session, out);
}

fn add_menu(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let can = session.enabled("layers.add");
    ui.horizontal(|ui| {
        ui.add_enabled_ui(can.is_ok(), |ui| {
            ui.menu_button(t!("feedback-layer-add"), |ui| {
                let items = [
                    (LayerKind::Background, t!("feedback-layer-add-background")),
                    (LayerKind::Feedback, t!("feedback-layer-add-feedback")),
                    (LayerKind::Guardrail, t!("feedback-layer-add-guardrail")),
                ];
                for (kind, label) in items {
                    let full = session.state().layers.count(kind) >= nf_core::layers::MAX_PER_KIND;
                    if ui.add_enabled(!full, egui::Button::new(label)).clicked() {
                        out.push(Command::LayersAdd { kind, settings: LayerPatch::default() });
                        ui.close();
                    }
                }
            });
        });
        if ui.add_enabled(session.enabled("layers.reset").is_ok(), egui::Button::new(t!("feedback-layer-reset"))).clicked() {
            out.push(Command::LayersReset);
        }
    });
}

fn layer_tile(ui: &mut egui::Ui, session: &Session, l: &Layer, own_volume: bool, out: &mut Vec<Command>) {
    let open_id = ui.scope_id().with(("layer_open", l.id));
    let mut open = ui.data(|d| d.get_temp::<bool>(open_id)).unwrap_or(false);
    egui::Frame::group(ui.style()).corner_radius(10.0).inner_margin(10.0).show(ui, |ui| {
        ui.set_width(ui.available_width());
        ui.horizontal(|ui| {
            let head = ui.add(egui::Button::new(RichText::new(l.config.kind().label()).strong()).frame(false));
            ui.weak(l.config.summary());
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                let can = session.enabled("layers.remove").is_ok();
                if ui.add_enabled(can, egui::Button::new("✕")).on_hover_text(t!("feedback-layer-remove")).clicked() {
                    out.push(Command::LayersRemove { id: l.id });
                }
                if ui.button(if open { "▾" } else { "⚙" }).clicked() || head.clicked() {
                    open = !open;
                }
            });
        });
        if open {
            ui.separator();
            layer_settings(ui, l, own_volume, out);
        }
    });
    ui.data_mut(|d| d.insert_temp(open_id, open));
}

fn set(out: &mut Vec<Command>, id: u32, settings: LayerPatch) {
    out.push(Command::LayersSet { id, settings });
}

/// The sound-specific controls of an expanded tile. The tile's own volume
/// slider appears only when its group has several layers (`own_volume`).
fn layer_settings(ui: &mut egui::Ui, l: &Layer, own_volume: bool, out: &mut Vec<Command>) {
    match &l.config {
        LayerConfig::Background { sound, .. } => {
            choice(ui, *sound, &BACKGROUNDS, |s| set(out, l.id, LayerPatch { sound: Some(s), ..Default::default() }));
        }
        LayerConfig::Feedback { output, binaural, .. } => {
            choice(ui, *output, &REWARDS, |o| set(out, l.id, LayerPatch { output: Some(o), ..Default::default() }));
            if *output == RewardOutput::Binaural {
                preset_combo(ui, l.id, *binaural, out);
            }
        }
        LayerConfig::Guardrail { sound, .. } => {
            choice(ui, *sound, &GUARDS, |g| set(out, l.id, LayerPatch { guard_sound: Some(g), ..Default::default() }));
        }
    }
    if let Some(m) = l.config.music() {
        super::layer_music::show(ui, l, m, out);
    }
    if own_volume {
        volume_row(ui, l.id, l.config.volume(), out);
    }
}

const REWARDS: [(RewardOutput, &str); 5] = [
    (RewardOutput::Chime, "sound-reward-chime"),
    (RewardOutput::Rain, "sound-reward-rain"),
    (RewardOutput::Binaural, "sound-reward-binaural"),
    (RewardOutput::Music, "sound-reward-music"),
    (RewardOutput::None, "sound-reward-none"),
];
const BACKGROUNDS: [(Background, &str); 5] = [
    (Background::Drone, "sound-bg-drone"),
    (Background::DroneLoop, "sound-bg-drone-loop"),
    (Background::Rain, "sound-bg-rain"),
    (Background::Binaural, "sound-bg-binaural"),
    (Background::Music, "sound-bg-music"),
];
const GUARDS: [(GuardSound, &str); 5] = [
    (GuardSound::SoftBowl, "sound-guard-soft-bowl"),
    (GuardSound::Chime, "sound-guard-chime"),
    (GuardSound::Cough, "sound-guard-cough"),
    (GuardSound::Alarm, "sound-guard-alarm"),
    (GuardSound::None, "sound-guard-none"),
];

fn choice<T: PartialEq + Copy>(ui: &mut egui::Ui, cur: T, options: &[(T, &str)], mut pick: impl FnMut(T)) {
    ui.horizontal_wrapped(|ui| {
        ui.label(t!("feedback-layer-sound"));
        for (v, key) in options {
            if ui.selectable_label(cur == *v, crate::i18n::tr(key, &[])).clicked() && cur != *v {
                pick(*v);
            }
        }
    });
}

fn preset_combo(ui: &mut egui::Ui, id: u32, cur: BinauralPreset, out: &mut Vec<Command>) {
    egui::ComboBox::from_id_salt(("layer_preset", id)).selected_text(cur.label()).show_ui(ui, |ui| {
        for p in BinauralPreset::ALL {
            let (label, about, ..) = p.spec();
            if ui.selectable_label(cur == p, label).on_hover_text(about).clicked() && cur != p {
                set(out, id, LayerPatch { binaural: Some(p), ..Default::default() });
            }
        }
    });
}

/// Slider previews locally and commits one `layers.set` on release.
fn volume_row(ui: &mut egui::Ui, id: u32, cur: f64, out: &mut Vec<Command>) {
    let key = ui.scope_id().with(("layer_vol", id));
    let mut v = ui.data(|d| d.get_temp::<f64>(key)).unwrap_or(cur);
    let r = ui.add(egui::Slider::new(&mut v, 0.0..=1.0).fixed_decimals(2).text(t!("feedback-layer-volume")));
    if r.dragged() || r.has_focus() {
        ui.data_mut(|d| d.insert_temp(key, v));
    } else {
        ui.data_mut(|d| d.remove::<f64>(key));
    }
    if r.drag_stopped() || (r.changed() && !r.dragged()) {
        set(out, id, LayerPatch { volume: Some(v), ..Default::default() });
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::panic)]
    use super::*;
    use egui::{Pos2, Rect, Vec2};
    use nf_core::layers::MusicSettings;

    #[test]
    fn grid_is_one_column_on_phones_and_more_on_wide_screens() {
        assert_eq!([columns(360.0), columns(559.0), columns(700.0), columns(1000.0), columns(1600.0)], [1, 1, 2, 3, 3]);
        assert!(tile_width(1000.0, 3) > 200.0 && tile_width(300.0, 1) >= 120.0);
    }

    /// Text (string, left, right) of the last of three frames of `body` at `width`.
    fn render(width: f32, mut body: impl FnMut(&mut egui::Ui, &egui::Context)) -> Vec<(String, f32, f32)> {
        let _lang = crate::i18n::lang_lock();
        let ctx = egui::Context::default();
        let mut last = Vec::new();
        for i in 0..3 {
            let input = egui::RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, Vec2::new(width, 1200.0))),
                time: Some(f64::from(i) / 60.0),
                ..Default::default()
            };
            let mut o = ctx.run_ui(input, |u| {
                let c = u.ctx().clone();
                body(u, &c);
            });
            o.textures_delta.clear();
            last = o.shapes;
        }
        last.iter()
            .filter_map(|c| match &c.shape {
                egui::Shape::Text(t) => {
                    let r = t.galley.rect.translate(t.pos.to_vec2());
                    Some((t.galley.text().to_owned(), r.left(), r.right()))
                }
                _ => None,
            })
            .collect()
    }

    fn layer(kind: LayerKind, patch: LayerPatch) -> Layer {
        Layer { id: 7, config: patch.apply(&LayerConfig::default_of(kind)).unwrap() }
    }

    fn has(t: &[(String, f32, f32)], s: &str) -> bool {
        t.iter().any(|(x, ..)| x == s)
    }

    #[test]
    fn music_block_shows_its_controls_and_fits_phones() {
        for w in [360.0, 400.0, 1000.0] {
            let patch = LayerPatch { output: Some(RewardOutput::Music), music_folder: Some("/m/calm".into()), ..Default::default() };
            let l = layer(LayerKind::Feedback, patch);
            let t = render(w, |ui, _| {
                egui::CentralPanel::default().show(ui, |ui| layer_settings(ui, &l, false, &mut Vec::new()));
            });
            for n in ["Invert mapping", "Shuffle track order", "Cutoff range (low-pass)", "200 Hz", "8000 Hz"] {
                assert!(has(&t, n), "{n} missing at {w}: {t:?}");
            }
            assert!(t.iter().all(|(_, l, r)| *l >= -0.5 && *r <= w + 0.5), "off-screen text at {w}: {t:?}");
            assert!(t.iter().any(|(x, ..)| x.starts_with("/m/calm")), "path and track count line");
        }
    }

    #[test]
    fn no_music_block_for_other_sounds_and_background_music_has_one() {
        let chime = layer(LayerKind::Feedback, LayerPatch::default());
        let t = render(600.0, |ui, _| layer_settings(ui, &chime, false, &mut Vec::new()));
        assert!(!has(&t, "Invert mapping"));
        let bg = layer(LayerKind::Background, LayerPatch { sound: Some(Background::Music), ..Default::default() });
        let t = render(600.0, |ui, _| layer_settings(ui, &bg, false, &mut Vec::new()));
        assert!(has(&t, "Invert mapping") && has(&t, "No music folder chosen."), "{t:?}");
        assert_eq!(bg.config.music().map(MusicSettings::summary).as_deref(), Some("no folder • low-pass 200–8000 Hz"));
    }

    #[test]
    fn own_volume_slider_only_when_the_group_has_several_layers() {
        let l = layer(LayerKind::Feedback, LayerPatch::default());
        let one = render(600.0, |ui, _| layer_settings(ui, &l, false, &mut Vec::new()));
        let many = render(600.0, |ui, _| layer_settings(ui, &l, true, &mut Vec::new()));
        assert!(!has(&one, "Volume"), "{one:?}");
        assert!(has(&many, "Volume"), "{many:?}");
    }

    #[test]
    fn volume_dialog_lists_one_slider_per_group_with_reset_and_done() {
        let session = Session::new();
        for w in [360.0, 1000.0] {
            let t = render(w, |ui, ctx| {
                ctx.data_mut(|d| d.insert_temp(super::super::volume_dialog::open_id(), true));
                super::super::volume_dialog::window(ctx, &session, &mut Vec::new());
                let _ = ui;
            });
            for n in ["Master", "Background", "Feedback", "Guardrail", "Intro", "End bell", "Reset", "Done"] {
                assert_eq!(t.iter().filter(|(x, ..)| x == n).count(), 1, "{n} at {w}: {t:?}");
            }
            assert!(t.iter().all(|(_, l, r)| *l >= -0.5 && *r <= w + 0.5), "off-screen text at {w}: {t:?}");
        }
    }

    #[test]
    fn setup_screen_has_the_speaker_button() {
        let session = Session::new();
        let t = render(400.0, |ui, _| setup(ui, &session, &mut Vec::new()));
        assert!(has(&t, "🔊"), "{t:?}");
    }
}
