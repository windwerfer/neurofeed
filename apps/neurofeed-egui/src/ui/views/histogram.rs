//! Histogram view: amplitude distribution of the last 2 s per channel.

use super::plot;
use egui::{Align2, Color32, Rect};
use nf_core::Session;

const BINS: usize = 64;
const HALF_RANGE_UV: f64 = 100.0;

pub fn show(ui: &mut egui::Ui, session: &Session) {
    let Some((dev, sig)) = plot::header(ui, session, "Histogram", "conditioned amplitude, last 2 s, 64 bins over ±100 µV") else {
        return;
    };
    let n = (2.0 * sig.rate) as usize;
    plot::cards(ui, &dev.channels, |p, r, ch| {
        let h = nf_core::dsp::histogram(&sig.last(ch, n, true), BINS, HALF_RANGE_UV);
        let max = h.iter().copied().max().unwrap_or(0).max(1) as f32;
        let w = r.width() / BINS as f32;
        for (i, &c) in h.iter().enumerate() {
            let x = r.left() + i as f32 * w;
            let top = r.bottom() - r.height() * c as f32 / max;
            p.rect_filled(
                Rect::from_min_max(egui::pos2(x + 0.5, top), egui::pos2(x + w - 0.5, r.bottom())),
                0.0,
                Color32::from_rgb(0x81, 0xC7, 0x84),
            );
        }
        plot::label(p, r.left_bottom(), Align2::LEFT_TOP, "-100");
        plot::label(p, r.center_bottom(), Align2::CENTER_TOP, "0 µV");
        plot::label(p, r.right_bottom(), Align2::RIGHT_TOP, "100");
        let std = nf_core::dsp::sample_std(&sig.last(ch, n, true)).unwrap_or(0.0);
        plot::label(p, r.right_top(), Align2::RIGHT_BOTTOM, format!("σ {std:.1} µV"));
    });
}
