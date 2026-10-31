//! Pad quality glyphs, reproduced from the legacy Flutter status bar
//! (`lib/src/status_bar.dart`, tag `pre-rust-port`): the Muse head outline
//! `/‾‾\` (AUX dots between the overlines, `/‾••‾\`), a top-down 4×4 ring of
//! `•` for the Crown, and one `•` per pad otherwise. 18 px bold monospace,
//! coloured by [`theme::quality_color`].

use super::theme;
use egui::{Align2, FontId, Sense, Vec2};

/// Legacy glyph size and the gap between Muse glyphs.
const GLYPH_PX: f32 = 18.0;
const GAP_PX: f32 = 2.0;
/// Crown ring cell (the bullet's ink).
const CELL_PX: f32 = 7.0;

/// One pad: its glyph and the electrode whose score colours it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Pad {
    pub glyph: char,
    pub electrode: usize,
}

/// Legacy `signalPads`: `/‾‾\` for the 4-pad Muse with `aux` dots
/// (electrodes 4..) between the overlines, else one `•` per pad.
pub fn pads(head: usize, aux: usize) -> Vec<Pad> {
    if head != 4 {
        return (0..head).map(|electrode| Pad { glyph: '•', electrode }).collect();
    }
    let p = |glyph, electrode| Pad { glyph, electrode };
    let mut v = vec![p('/', 0), p('‾', 1)];
    v.extend((0..aux.min(4)).map(|k| p('•', 4 + k)));
    v.extend([p('‾', 2), p('\\', 3)]);
    v
}

/// Legacy `_crownQualityRing`, nose up: F5 F6 / C3 C4 / CP3 CP4 / PO3 PO4
/// (Crown order CP3 C3 F5 PO3 PO4 F6 C4 CP4). `None` is an empty cell.
pub const CROWN_RING: [[Option<usize>; 4]; 4] =
    [[None, Some(2), Some(5), None], [Some(1), None, None, Some(6)], [Some(0), None, None, Some(7)], [None, Some(3), Some(4), None]];

/// The row as plain text, for tests and agents (`/‾‾\`, Crown ring rows).
#[cfg(test)]
pub fn ascii(head: usize, aux: usize) -> String {
    if head == 8 {
        return CROWN_RING
            .iter()
            .map(|r| r.iter().map(|c| if c.is_some() { '•' } else { ' ' }).collect::<String>())
            .collect::<Vec<_>>()
            .join("\n");
    }
    pads(head, aux).iter().map(|p| p.glyph).collect()
}

fn color(quality: &[f32], electrode: usize) -> egui::Color32 {
    quality.get(electrode).map_or(theme::QUALITY_NONE, |&s| theme::quality_color(s))
}

fn font() -> FontId {
    FontId::monospace(GLYPH_PX)
}

/// Draw the quality glyphs. `quality` is 0..=100 per electrode (EEG first,
/// then AUX); `head` is the EEG pad count, `aux` the AUX pads shown.
pub fn row(ui: &mut egui::Ui, quality: &[f32], head: usize, aux: usize) -> egui::Response {
    if head == 8 {
        return crown_ring(ui, quality);
    }
    let pads = pads(head, aux);
    let galleys: Vec<_> =
        pads.iter().map(|p| ui.painter().layout_no_wrap(p.glyph.to_string(), font(), color(quality, p.electrode))).collect();
    let w: f32 = galleys.iter().map(|g| g.size().x).sum::<f32>() + GAP_PX * pads.len().saturating_sub(1) as f32;
    let h = galleys.iter().map(|g| g.size().y).fold(GLYPH_PX, f32::max);
    let (rect, resp) = ui.allocate_exact_size(Vec2::new(w, h), Sense::hover());
    let mut x = rect.left();
    for g in galleys {
        let gw = g.size().x;
        // Bold like the legacy `FontWeight.bold`: overprint 0.6 px right.
        ui.painter().galley(egui::pos2(x + 0.6, rect.top()), g.clone(), egui::Color32::PLACEHOLDER);
        ui.painter().galley(egui::pos2(x, rect.top()), g, egui::Color32::PLACEHOLDER);
        x += gw + GAP_PX;
    }
    resp
}

/// Crown 4×4 ring of `•`, cells [`CELL_PX`] wide; the glyph overflows its cell.
fn crown_ring(ui: &mut egui::Ui, quality: &[f32]) -> egui::Response {
    let (rect, resp) = ui.allocate_exact_size(Vec2::splat(CELL_PX * 4.0), Sense::hover());
    for (r, cells) in CROWN_RING.iter().enumerate() {
        for (c, cell) in cells.iter().enumerate() {
            let Some(e) = *cell else { continue };
            let center = rect.left_top() + Vec2::new((c as f32 + 0.5) * CELL_PX, (r as f32 + 0.5) * CELL_PX);
            let col = color(quality, e);
            for dx in [0.0, 0.6] {
                ui.painter().text(center + Vec2::new(dx, 0.0), Align2::CENTER_CENTER, '•', font(), col);
            }
        }
    }
    resp
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn muse_outline_matches_legacy() {
        assert_eq!(ascii(4, 0), "/‾‾\\");
        assert_eq!(ascii(4, 1), "/‾•‾\\");
        assert_eq!(ascii(4, 9), "/‾••••‾\\", "AUX capped at 4");
        let p = pads(4, 2);
        assert_eq!(p.iter().map(|p| p.electrode).collect::<Vec<_>>(), [0, 1, 4, 5, 2, 3]);
    }

    #[test]
    fn crown_ring_is_top_down() {
        assert_eq!(ascii(8, 0), " •• \n•  •\n•  •\n •• ");
        let mut seen: Vec<usize> = CROWN_RING.iter().flatten().flatten().copied().collect();
        seen.sort_unstable();
        assert_eq!(seen, (0..8).collect::<Vec<_>>(), "every Crown pad once");
    }

    #[test]
    fn other_montages_are_bullets() {
        assert_eq!(ascii(2, 0), "••");
    }

    #[test]
    fn legacy_thresholds() {
        assert_eq!(theme::quality_color(80.0), theme::quality_color(100.0));
        assert_eq!(theme::quality_color(40.0), theme::quality_color(79.9));
        assert_ne!(theme::quality_color(39.9), theme::quality_color(40.0));
        assert_ne!(theme::quality_color(79.9), theme::quality_color(80.0));
    }
}
