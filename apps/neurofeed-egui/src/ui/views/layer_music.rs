//! Music settings inside a layer tile: folder (path + track count), the
//! two-handle cutoff slider, "Invert mapping" and "Shuffle track order".
//! Every change is one `layers.set`; nothing here touches the core directly.

use egui::{Sense, Stroke, Vec2};
use nf_core::layers::{Layer, LayerPatch, MusicSettings};
use nf_core::Command;

const GAP_HZ: f64 = 50.0;
const STEP_HZ: f64 = 10.0;

fn patch(out: &mut Vec<Command>, id: u32, settings: LayerPatch) {
    out.push(Command::LayersSet { id, settings });
}

/// The music block of an expanded layer tile.
pub(super) fn show(ui: &mut egui::Ui, l: &Layer, m: &MusicSettings, out: &mut Vec<Command>) {
    ui.add_space(4.0);
    folder_row(ui, l.id, m, out);
    ui.label(t!("layer-music-cutoff"));
    if let Some((lo, hi)) = range_slider(ui, ("layer_cutoff", l.id), (m.min_hz, m.max_hz)) {
        patch(out, l.id, LayerPatch { music_min_hz: Some(lo), music_max_hz: Some(hi), ..Default::default() });
    }
    let (mut invert, mut shuffle) = (m.invert, m.shuffle);
    if ui.checkbox(&mut invert, t!("layer-music-invert")).on_hover_text(t!("layer-music-invert-about")).changed() {
        patch(out, l.id, LayerPatch { music_invert: Some(invert), ..Default::default() });
    }
    if ui.checkbox(&mut shuffle, t!("layer-music-shuffle")).changed() {
        patch(out, l.id, LayerPatch { music_shuffle: Some(shuffle), ..Default::default() });
    }
}

fn folder_row(ui: &mut egui::Ui, id: u32, m: &MusicSettings, out: &mut Vec<Command>) {
    if cfg!(target_arch = "wasm32") {
        ui.weak(t!("sound-music-needs-the-desktop-app"));
        return;
    }
    let cur = m.folder.clone().unwrap_or_default();
    let key = ui.scope_id().with(("layer_folder_draft", id));
    let mut text = ui.data(|d| d.get_temp::<String>(key)).unwrap_or_else(|| cur.clone());
    ui.horizontal_wrapped(|ui| {
        ui.label(t!("sound-music-folder"));
        let r = ui.add(egui::TextEdit::singleline(&mut text).hint_text(t!("sound-music-path-hint")).desired_width(260.0));
        let enter = r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter));
        let load = ui.add_enabled(text != cur, egui::Button::new(t!("sound-load"))).clicked();
        if (load || enter) && text != cur {
            patch(out, id, LayerPatch { music_folder: Some(text.clone()), ..Default::default() });
        }
        if ui.add_enabled(!cur.is_empty(), egui::Button::new(t!("layer-music-clear"))).clicked() {
            text.clear();
            patch(out, id, LayerPatch { music_folder: Some(String::new()), ..Default::default() });
        }
    });
    ui.data_mut(|d| d.insert_temp(key, text));
    if let Some(dir) = m.folder.as_deref() {
        let n = tracks(ui.ctx(), dir);
        ui.weak(format!("{dir} • {}", t!("layer-music-tracks", n = n as i64)));
    } else {
        ui.weak(t!("layer-music-no-folder"));
    }
}

/// Playable files in `dir`, cached per path so `ui()` never scans a folder every frame.
#[cfg(not(target_arch = "wasm32"))]
fn tracks(ctx: &egui::Context, dir: &str) -> usize {
    let key = egui::Id::unique(("music_track_count", dir));
    if let Some(n) = ctx.data(|d| d.get_temp::<usize>(key)) {
        return n;
    }
    let n = count_tracks(std::path::Path::new(dir));
    ctx.data_mut(|d| d.insert_temp(key, n));
    n
}

#[cfg(target_arch = "wasm32")]
fn tracks(_: &egui::Context, _: &str) -> usize {
    0
}

/// Count files with a decodable extension; at most [`MAX_SCANNED`] entries are looked at.
#[cfg(not(target_arch = "wasm32"))]
fn count_tracks(dir: &std::path::Path) -> usize {
    const MAX_SCANNED: usize = 10_000;
    let Ok(rd) = std::fs::read_dir(dir) else { return 0 };
    rd.flatten()
        .take(MAX_SCANNED)
        .filter(|e| {
            let name = e.file_name().to_string_lossy().to_lowercase();
            nf_core::nf_audio::decode::EXTENSIONS.iter().any(|x| name.ends_with(&format!(".{x}")))
        })
        .count()
}

/// Position of `hz` on the slider track, 0..=1 (logarithmic: more room for the low end).
pub(super) fn hz_to_frac(hz: f64) -> f64 {
    let (lo, hi) = (MusicSettings::CUTOFF_MIN_HZ, MusicSettings::CUTOFF_MAX_HZ);
    ((hz.clamp(lo, hi) / lo).ln() / (hi / lo).ln()).clamp(0.0, 1.0)
}

pub(super) fn frac_to_hz(f: f64) -> f64 {
    let (lo, hi) = (MusicSettings::CUTOFF_MIN_HZ, MusicSettings::CUTOFF_MAX_HZ);
    let hz = lo * (hi / lo).powf(f.clamp(0.0, 1.0));
    (hz / STEP_HZ).round() * STEP_HZ
}

/// Keep both handles inside the range and at least [`GAP_HZ`] apart; `moved`
/// (0 = low, 1 = high) is the handle the user is dragging and wins.
pub(super) fn keep_gap(lo: f64, hi: f64, moved: usize) -> (f64, f64) {
    let (min, max) = (MusicSettings::CUTOFF_MIN_HZ, MusicSettings::CUTOFF_MAX_HZ);
    let (lo, hi) = (lo.clamp(min, max), hi.clamp(min, max));
    if hi - lo >= GAP_HZ {
        (lo, hi)
    } else if moved == 0 {
        (lo.min(max - GAP_HZ), lo.min(max - GAP_HZ) + GAP_HZ)
    } else {
        ((hi - GAP_HZ).max(min), (hi - GAP_HZ).max(min) + GAP_HZ)
    }
}

/// Two-handle range slider. Previews locally while dragging and returns the
/// final `(low, high)` once, on release.
fn range_slider(ui: &mut egui::Ui, salt: impl std::hash::Hash + std::fmt::Debug + Copy, cur: (f64, f64)) -> Option<(f64, f64)> {
    let state_id = ui.scope_id().with(salt);
    let mut v = ui.data(|d| d.get_temp::<(f64, f64)>(state_id)).unwrap_or(cur);
    let w = ui.available_width().clamp(120.0, 380.0);
    let (rect, _) = ui.allocate_exact_size(Vec2::new(w, 26.0), Sense::hover());
    let (x0, x1) = (rect.left() + 9.0, rect.right() - 9.0);
    let at = |hz: f64| x0 + (x1 - x0) * hz_to_frac(hz) as f32;
    let mut done = false;
    for i in 0..2 {
        let hz = if i == 0 { v.0 } else { v.1 };
        let hr = egui::Rect::from_center_size(egui::pos2(at(hz), rect.center().y), Vec2::splat(18.0));
        let r = ui.interact(hr, state_id.with(i), Sense::drag()).on_hover_cursor(egui::CursorIcon::ResizeHorizontal);
        if let Some(p) = r.interact_pointer_pos().filter(|_| r.dragged()) {
            let moved = frac_to_hz(f64::from((p.x - x0) / (x1 - x0).max(1.0)));
            v = if i == 0 { keep_gap(moved, v.1, 0) } else { keep_gap(v.0, moved, 1) };
        }
        done |= r.drag_stopped();
    }
    paint(ui, rect, (at(v.0), at(v.1)));
    ui.horizontal(|ui| {
        ui.weak(format!("{:.0} Hz", v.0));
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| ui.weak(format!("{:.0} Hz", v.1)));
    });
    if done {
        ui.data_mut(|d| d.remove::<(f64, f64)>(state_id));
        return (v != cur).then_some(v);
    }
    let dragging = ui.ctx().egui_is_using_pointer() && v != cur;
    ui.data_mut(|d| {
        if dragging {
            d.insert_temp(state_id, v);
        } else {
            d.remove::<(f64, f64)>(state_id);
        }
    });
    None
}

fn paint(ui: &egui::Ui, rect: egui::Rect, (xl, xh): (f32, f32)) {
    let vis = ui.visuals();
    let y = rect.center().y;
    let p = ui.painter();
    p.line_segment([egui::pos2(rect.left() + 9.0, y), egui::pos2(rect.right() - 9.0, y)], Stroke::new(4.0, vis.widgets.inactive.bg_fill));
    p.line_segment([egui::pos2(xl, y), egui::pos2(xh, y)], Stroke::new(4.0, vis.selection.bg_fill));
    for x in [xl, xh] {
        p.circle(egui::pos2(x, y), 8.0, vis.widgets.active.bg_fill, Stroke::new(1.5, vis.selection.stroke.color));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hz_mapping_round_trips_and_hits_the_ends() {
        assert_eq!(frac_to_hz(0.0), 200.0);
        assert_eq!(frac_to_hz(1.0), 8000.0);
        for hz in [200.0, 440.0, 1000.0, 4000.0, 8000.0] {
            assert!((frac_to_hz(hz_to_frac(hz)) - hz).abs() <= STEP_HZ, "{hz}");
        }
        assert_eq!((hz_to_frac(1.0), hz_to_frac(1e9)), (0.0, 1.0), "out of range clamps");
    }

    #[test]
    fn handles_keep_their_gap_and_the_dragged_one_wins() {
        assert_eq!(keep_gap(300.0, 5000.0, 0), (300.0, 5000.0));
        assert_eq!(keep_gap(4000.0, 4010.0, 0), (4000.0, 4050.0), "dragging low keeps low");
        assert_eq!(keep_gap(4000.0, 4010.0, 1), (3960.0, 4010.0), "dragging high keeps high");
        assert_eq!(keep_gap(7990.0, 8000.0, 0), (7950.0, 8000.0), "stays inside the range");
        assert_eq!(keep_gap(200.0, 210.0, 1), (200.0, 250.0));
        let (lo, hi) = keep_gap(-5.0, 99999.0, 0);
        assert_eq!((lo, hi), (200.0, 8000.0));
    }

    #[cfg(not(target_arch = "wasm32"))]
    #[test]
    fn track_count_counts_only_audio_files() {
        let dir = std::env::temp_dir().join(format!("nf-tracks-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        for f in ["a.ogg", "b.MP3", "c.txt", "d.flac"] {
            std::fs::write(dir.join(f), b"x").unwrap();
        }
        assert_eq!(count_tracks(&dir), 3);
        assert_eq!(count_tracks(&dir.join("missing")), 0);
        std::fs::remove_dir_all(&dir).ok();
    }
}
