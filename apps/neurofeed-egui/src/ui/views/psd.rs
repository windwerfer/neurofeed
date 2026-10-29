//! PSD view: log power spectrum of the last 1 s per channel, 1–50 Hz.

use super::plot;
use egui::{Align2, Color32, Stroke};
use nf_core::Session;

const MAX_HZ: f32 = 50.0;
const LOG_RANGE: (f32, f32) = (-2.0, 3.0);

pub fn show(ui: &mut egui::Ui, session: &Session) {
    let Some((dev, sig)) = plot::header(ui, session, "PSD", "log10 µV²/Hz, last 1 s (Hamming); marker = alpha peak") else {
        return;
    };
    let w = sig.window_len();
    plot::cards(ui, &dev.channels, |p, r, ch| {
        let Some(psd) = nf_core::dsp::psd(&sig.last(ch, w, true), sig.rate) else { return };
        for hz in [10.0_f32, 20.0, 30.0, 40.0] {
            let x = plot::to_screen(r, (0.0, MAX_HZ), LOG_RANGE, hz, LOG_RANGE.0).x;
            p.line_segment([egui::pos2(x, r.top()), egui::pos2(x, r.bottom())], Stroke::new(0.5_f32, Color32::DARK_GRAY));
            plot::label(p, egui::pos2(x, r.bottom()), Align2::CENTER_TOP, format!("{hz:.0}"));
        }
        for y in [-1.0_f32, 0.0, 1.0, 2.0] {
            plot::label(p, plot::to_screen(r, (0.0, MAX_HZ), LOG_RANGE, 0.0, y), Align2::RIGHT_CENTER, format!("{y:.0} "));
        }
        let pts = psd
            .power
            .iter()
            .enumerate()
            .map(|(k, &v)| (k as f32 * psd.df as f32, (v.max(1e-6)).log10() as f32))
            .filter(|(f, _)| *f <= MAX_HZ)
            .map(|(f, y)| plot::to_screen(r, (0.0, MAX_HZ), LOG_RANGE, f, y))
            .collect();
        plot::trace(p, pts, Color32::from_rgb(0xFF, 0xB7, 0x4D));
        if let Some(hz) = nf_core::dsp::peak_frequency(&psd, 8.0, 13.0) {
            let pos = plot::to_screen(r, (0.0, MAX_HZ), LOG_RANGE, hz as f32, LOG_RANGE.1);
            p.text(pos, Align2::CENTER_TOP, format!("▲ {hz:.1} Hz"), egui::FontId::monospace(11.0), Color32::WHITE);
        }
    });
}
