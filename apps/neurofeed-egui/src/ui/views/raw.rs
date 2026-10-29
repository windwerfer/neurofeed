//! Raw EEG view: last 5 s of the conditioned signal per channel.

use super::plot;
use egui::{Align2, Color32};
use nf_core::Session;

const SECONDS: f32 = 5.0;
const RANGE_UV: f32 = 60.0;

pub fn show(ui: &mut egui::Ui, session: &Session) {
    let Some((dev, sig)) = plot::header(ui, session, "Raw EEG", "conditioned (0.5 Hz high-pass + notch), ±60 µV, last 5 s") else {
        return;
    };
    let n = (SECONDS as f64 * sig.rate) as usize;
    plot::cards(ui, &dev.channels, |p, r, ch| {
        let s = sig.last(ch, n, true);
        let step = (s.len() as f32 / r.width()).max(1.0);
        let pts = (0..(s.len() as f32 / step) as usize)
            .filter_map(|i| s.get((i as f32 * step) as usize).map(|&y| (i as f32 * step, y)))
            .map(|(i, y)| plot::to_screen(r, (0.0, n as f32), (-RANGE_UV, RANGE_UV), i, y))
            .collect();
        p.line_segment([r.left_center(), r.right_center()], (0.5_f32, Color32::DARK_GRAY));
        plot::trace(p, pts, Color32::from_rgb(0x4F, 0xC3, 0xF7));
        plot::label(p, r.left_top(), Align2::RIGHT_TOP, format!("{RANGE_UV:.0} "));
        plot::label(p, r.left_bottom(), Align2::RIGHT_BOTTOM, format!("-{RANGE_UV:.0} "));
        plot::label(p, r.right_bottom(), Align2::RIGHT_TOP, "now");
        let q = sig.quality[ch];
        let c = if sig.usable(ch) { Color32::from_rgb(0x66, 0xBB, 0x6A) } else { Color32::from_rgb(0xEF, 0x53, 0x50) };
        p.text(r.right_top() + egui::vec2(-4.0, -18.0), Align2::RIGHT_TOP, format!("quality {q:.0}"), egui::FontId::monospace(11.0), c);
    });
}
