//! Histogram view: amplitude distribution of the last 2 s per channel.

use super::plot;
use egui::{Align2, Color32, Rect};
use nf_core::Session;

const BINS: usize = 64;
const HALF_RANGE_UV: f64 = 100.0;

pub fn show(ui: &mut egui::Ui, session: &Session) {
    let Some((dev, sig)) = plot::header(ui, session, &t!("histogram-histogram"), "conditioned amplitude, last 2 s, 64 bins over ±100 µV")
    else {
        return;
    };
    let n = (2.0 * sig.rate) as usize;
    // Excluded electrodes are left out (analysis exclusion); no fallback.
    let idx = session.state().analysis.eligible(&dev.channels);
    if idx.is_empty() {
        let (rect, _) = ui.allocate_exact_size(ui.available_size(), egui::Sense::hover());
        crate::ui::monitor::no_eligible(ui, rect);
        return;
    }
    let names: Vec<String> = idx.iter().map(|&i| dev.channels[i].clone()).collect();
    plot::cards(ui, &names, |p, r, card| {
        let ch = idx[card];
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

#[cfg(test)]
pub(crate) mod tests {
    #![allow(clippy::unwrap_used)]
    use nf_core::Session;
    use serde_json::json;

    /// All painted text of one frame of `view`.
    pub(crate) fn texts(s: &Session, view: impl Fn(&mut egui::Ui, &Session)) -> Vec<String> {
        let ctx = egui::Context::default();
        let input = egui::RawInput {
            screen_rect: Some(egui::Rect::from_min_size(egui::Pos2::ZERO, egui::vec2(1000.0, 800.0))),
            ..Default::default()
        };
        let mut out = ctx.run_ui(input, |u| view(u, s));
        out.textures_delta.clear();
        let mut t = Vec::new();
        for c in out.shapes {
            if let egui::Shape::Text(x) = c.shape {
                t.push(x.galley.text().to_owned());
            }
        }
        t
    }

    #[test]
    fn excluded_channels_get_no_card() {
        let _lang = crate::i18n::lang_lock();
        let mut s = Session::new();
        s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
        s.call("clock.advance", json!({ "seconds": 2.0 })).unwrap();
        s.call("analysis.exclude", json!({ "channel": "AF7", "confirm": true })).unwrap();
        let t = texts(&s, super::show);
        assert!(t.iter().any(|x| x == "AF8") && !t.iter().any(|x| x == "AF7"), "{t:?}");
        for c in ["TP9", "AF8", "TP10"] {
            s.call("analysis.exclude", json!({ "channel": c, "confirm": true })).unwrap();
        }
        let t = texts(&s, super::show);
        let none = t!("channels-none-eligible");
        assert!(t.contains(&none) && !t.iter().any(|x| x == "AF8"), "{t:?}");
    }
}
