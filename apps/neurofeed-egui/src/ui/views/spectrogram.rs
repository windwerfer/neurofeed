//! Spectrogram view: PSD dB columns of one channel over the last 30 s.

use egui::{Align2, Color32, Rect, Sense};
use nf_core::{Command, Session};

const MAX_HZ: usize = 50;
const DB_RANGE: (f32, f32) = (-20.0, 25.0);

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    ui.horizontal(|ui| {
        ui.heading("Spectrogram");
        ui.weak("1 s Hamming windows every 0.25 s, 0–50 Hz, dB re µV²/Hz");
    });
    let Some((dev, sig)) = session.live_signal() else {
        ui.separator();
        ui.label("No device connected. Use Connect device in the top bar.");
        return;
    };
    ui.horizontal(|ui| {
        for (i, name) in dev.channels.iter().enumerate() {
            if ui.selectable_label(state.channel == i, name).clicked() {
                out.push(Command::ChannelSet { channel: name.clone() });
            }
        }
    });
    let vp = super::plot::viewport(ui, "spectrogram", &[10.0, 20.0, 30.0], state.time);
    let max_back = 30.0 - vp.window_s;
    let back = vp.back_s(state.time, max_back);
    ui.separator();
    let all: Vec<_> = sig.spectrogram.get(state.channel).map(|d| d.iter().cloned().collect()).unwrap_or_default();
    let per_s = nf_core::signal::SPEC_COLUMNS as f64 / 30.0;
    let end = all.len().saturating_sub((back * per_s) as usize);
    let shown = (vp.window_s * per_s) as usize;
    let cols = &all[end.saturating_sub(shown)..end];
    let (rect, resp) = ui.allocate_exact_size(ui.available_size() - egui::vec2(0.0, 18.0), Sense::drag());
    super::plot::drag(ui, "spectrogram", &resp, state.time, max_back);
    let r = Rect::from_min_max(rect.left_top() + egui::vec2(36.0, 0.0), rect.right_bottom());
    let p = ui.painter_at(rect.expand(16.0));
    p.rect_filled(r, 0.0, Color32::BLACK);
    let cw = r.width() / shown.max(1) as f32;
    let bh = r.height() / (MAX_HZ + 1) as f32;
    let x0 = r.right() - cw * cols.len() as f32;
    for (c, col) in cols.iter().enumerate() {
        for (k, &db) in col.iter().take(MAX_HZ + 1).enumerate() {
            let x = x0 + c as f32 * cw;
            let y = r.bottom() - (k + 1) as f32 * bh;
            p.rect_filled(Rect::from_min_size(egui::pos2(x, y), egui::vec2(cw + 0.5, bh + 0.5)), 0.0, colormap(db));
        }
    }
    for hz in [0, 10, 20, 30, 40, 50] {
        let y = r.bottom() - (hz as f32 + 0.5) * bh;
        p.text(egui::pos2(r.left() - 4.0, y), Align2::RIGHT_CENTER, format!("{hz}"), egui::FontId::monospace(10.0), Color32::GRAY);
    }
    p.text(
        r.left_bottom() + egui::vec2(0.0, 4.0),
        Align2::LEFT_TOP,
        format!("-{:.0} s", vp.window_s + back),
        egui::FontId::monospace(10.0),
        Color32::GRAY,
    );
    let now = if back > 0.05 { format!("-{back:.1} s") } else { "now".into() };
    p.text(r.right_bottom() + egui::vec2(0.0, 4.0), Align2::RIGHT_TOP, now, egui::FontId::monospace(10.0), Color32::GRAY);
}

/// Dark blue → cyan → yellow → red over `DB_RANGE`.
fn colormap(db: f32) -> Color32 {
    let t = ((db - DB_RANGE.0) / (DB_RANGE.1 - DB_RANGE.0)).clamp(0.0, 1.0);
    let stops = [(10.0, 10.0, 40.0), (20.0, 120.0, 200.0), (80.0, 220.0, 200.0), (250.0, 230.0, 60.0), (230.0, 50.0, 30.0)];
    let x = t * (stops.len() - 1) as f32;
    let i = (x as usize).min(stops.len() - 2);
    let f = x - i as f32;
    let (a, b) = (stops[i], stops[i + 1]);
    let m = |u: f32, v: f32| (u + (v - u) * f) as u8;
    Color32::from_rgb(m(a.0, b.0), m(a.1, b.1), m(a.2, b.2))
}
