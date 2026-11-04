//! Layout modes: `Compact` (phones, narrow windows) vs `Regular` (desktop).
//!
//! The mode is picked once per frame from the `layout` setting and the
//! available width, stored in egui temp data, and read by views through
//! [`current`] so they can adapt (stack instead of side-by-side) without
//! duplicating logic.

use nf_core::settings::LayoutMode;

/// Below this width (logical px) `auto` picks the compact layout.
pub const COMPACT_MAX_WIDTH: f32 = 600.0;
/// Regular layout narrower than this shows an icon-only sidebar.
pub const NARROW_SIDEBAR_WIDTH: f32 = 900.0;
/// Minimum touch target height in compact mode (≈ 48 dp).
pub const TOUCH: f32 = 48.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Layout {
    Compact,
    #[default]
    Regular,
}

impl Layout {
    #[must_use]
    pub fn is_compact(self) -> bool {
        self == Layout::Compact
    }
}

/// Pick the layout for a window `width` logical px wide.
#[must_use]
pub fn pick(mode: LayoutMode, width: f32) -> Layout {
    match mode {
        LayoutMode::Compact => Layout::Compact,
        LayoutMode::Regular => Layout::Regular,
        LayoutMode::Auto if width < COMPACT_MAX_WIDTH => Layout::Compact,
        LayoutMode::Auto => Layout::Regular,
    }
}

fn key() -> egui::Id {
    egui::Id::unique("nf_layout")
}

/// Remember this frame's layout for [`current`].
pub fn store(ctx: &egui::Context, l: Layout) {
    ctx.data_mut(|d| d.insert_temp(key(), l == Layout::Compact));
}

/// This frame's layout (Regular before the first frame).
#[must_use]
pub fn current(ctx: &egui::Context) -> Layout {
    if ctx.data(|d| d.get_temp::<bool>(key())).unwrap_or(false) {
        Layout::Compact
    } else {
        Layout::Regular
    }
}

/// Bigger touch targets for the compact layout.
pub fn touch_style(ui: &mut egui::Ui) {
    let s = ui.style_mut();
    s.spacing.interact_size.y = s.spacing.interact_size.y.max(40.0);
    s.spacing.button_padding = egui::vec2(10.0, 8.0);
    s.spacing.item_spacing.y = s.spacing.item_spacing.y.max(6.0);
}

/// Primary destinations in the compact bottom bar; the rest go under "More".
pub const PRIMARY: [nf_core::View; 4] = [nf_core::View::Feedback, nf_core::View::Bands, nf_core::View::History, nf_core::View::Settings];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auto_switches_at_threshold() {
        assert_eq!(pick(LayoutMode::Auto, 390.0), Layout::Compact);
        assert_eq!(pick(LayoutMode::Auto, 599.0), Layout::Compact);
        assert_eq!(pick(LayoutMode::Auto, 600.0), Layout::Regular);
        assert_eq!(pick(LayoutMode::Compact, 1600.0), Layout::Compact);
        assert_eq!(pick(LayoutMode::Regular, 300.0), Layout::Regular);
    }
}
