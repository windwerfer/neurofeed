//! Raw EEG view: the conditioned signal per channel (plus Muse AUX when
//! enabled) with a Follow/Inspect viewport over the 10 s buffer.

use super::plot;
use egui::{Align2, Color32};
use nf_core::Session;

const RANGE_UV: f32 = 60.0;
const WINDOWS: [f64; 4] = [2.0, 4.0, 8.0, 10.0];
const BUFFER_S: f64 = 10.0;

pub fn show(ui: &mut egui::Ui, session: &Session) {
    let Some((dev, sig)) = plot::header(ui, session, "Raw EEG", "conditioned (0.5 Hz high-pass + notch), ±60 µV") else {
        return;
    };
    let now = session.state().time;
    let vp = plot::viewport(ui, "raw", &WINDOWS, now);
    let max_back = BUFFER_S - vp.window_s;
    let back = vp.back_s(now, max_back);
    let n = (vp.window_s * sig.rate) as usize;
    let skip = (back * sig.rate) as usize;
    let aux: Vec<(String, Vec<f32>)> = session
        .side()
        .map(|s| {
            s.live_aux()
                .map(|(name, buf)| (name.to_owned(), tail(buf.iter().copied(), buf.len(), n, (back * s.aux_rate) as usize)))
                .collect()
        })
        .unwrap_or_default();
    let mut names = dev.channels.clone();
    names.extend(aux.iter().map(|(n, _)| format!("{n} (AUX)")));
    let n_eeg = dev.channels.len();
    let resp = plot::cards_resp(ui, &names, |p, r, ch| {
        let s = if ch < n_eeg {
            let all = sig.last(ch, n + skip, true);
            all[..all.len().saturating_sub(skip)].to_vec()
        } else {
            aux.get(ch - n_eeg).map(|a| a.1.clone()).unwrap_or_default()
        };
        draw(p, r, &s, n);
        let end = if back > 0.05 { format!("-{back:.1} s") } else { "now".into() };
        plot::label(p, r.right_bottom(), Align2::RIGHT_TOP, end);
        plot::label(p, r.left_bottom(), Align2::LEFT_TOP, format!("-{:.0} s", vp.window_s + back));
        if ch < n_eeg {
            let q = sig.quality[ch];
            let c = if sig.usable(ch) { Color32::from_rgb(0x66, 0xBB, 0x6A) } else { Color32::from_rgb(0xEF, 0x53, 0x50) };
            p.text(r.right_top() + egui::vec2(-4.0, -18.0), Align2::RIGHT_TOP, format!("quality {q:.0}"), egui::FontId::monospace(11.0), c);
        }
    });
    if let Some(resp) = resp {
        plot::drag(ui, "raw", &resp, now, max_back);
    }
}

/// The `n` samples ending `skip` samples before the newest.
fn tail(it: impl Iterator<Item = f32>, len: usize, n: usize, skip: usize) -> Vec<f32> {
    let end = len.saturating_sub(skip);
    it.take(end).skip(end.saturating_sub(n)).collect()
}

fn draw(p: &egui::Painter, r: egui::Rect, s: &[f32], n: usize) {
    let step = (s.len() as f32 / r.width()).max(1.0);
    let off = n.saturating_sub(s.len()) as f32;
    let pts = (0..(s.len() as f32 / step) as usize)
        .filter_map(|i| s.get((i as f32 * step) as usize).map(|&y| (off + i as f32 * step, y)))
        .map(|(i, y)| plot::to_screen(r, (0.0, n as f32), (-RANGE_UV, RANGE_UV), i, y))
        .collect();
    p.line_segment([r.left_center(), r.right_center()], (0.5_f32, Color32::DARK_GRAY));
    plot::trace(p, pts, Color32::from_rgb(0x4F, 0xC3, 0xF7));
    plot::label(p, r.left_top(), Align2::RIGHT_TOP, format!("{RANGE_UV:.0} "));
    plot::label(p, r.left_bottom(), Align2::RIGHT_BOTTOM, format!("-{RANGE_UV:.0} "));
}
