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
    /// Phone portrait (or a narrow desktop window): hamburger drawer.
    Compact,
    #[default]
    Regular,
    /// Phone landscape: monitor screens show the graph only (no top bar,
    /// navigation or toolbars). Other screens fall back to `Compact`.
    Immersive,
}

impl Layout {
    /// Compact or immersive (phone-style touch sizing).
    #[must_use]
    pub fn is_compact(self) -> bool {
        self != Layout::Regular
    }
}

/// Phone-class device: a touch platform (Android, mobile web) whose short
/// side is below [`COMPACT_MAX_WIDTH`]. Tablets and desktops are not.
#[must_use]
pub fn phone(size: egui::Vec2) -> bool {
    cfg!(any(target_os = "android", target_arch = "wasm32")) && size.x.min(size.y) < COMPACT_MAX_WIDTH
}

/// Pick the layout for a window `size` (logical px). `phone`: see [`phone`].
/// A forced `compact` setting means "behave like a phone" (also on desktop).
/// Phone landscape is never classed regular just because it is wide.
#[must_use]
pub fn pick(mode: LayoutMode, size: egui::Vec2, phone: bool) -> Layout {
    let landscape = size.x > size.y;
    match mode {
        LayoutMode::Regular => Layout::Regular,
        LayoutMode::Compact if landscape => Layout::Immersive,
        LayoutMode::Compact => Layout::Compact,
        LayoutMode::Auto if phone && landscape => Layout::Immersive,
        LayoutMode::Auto if phone || size.x < COMPACT_MAX_WIDTH => Layout::Compact,
        LayoutMode::Auto => Layout::Regular,
    }
}

/// Views whose immersive form is "graph only".
#[must_use]
pub fn is_monitor(view: nf_core::View) -> bool {
    use nf_core::View as V;
    matches!(view, V::Bands | V::RawEeg | V::Histogram | V::Spectrogram | V::Psd | V::HeartRate | V::Movement)
}

/// The layout a view actually gets: immersive only on monitor screens.
#[must_use]
pub fn for_view(l: Layout, view: nf_core::View) -> Layout {
    if l == Layout::Immersive && !is_monitor(view) {
        Layout::Compact
    } else {
        l
    }
}

fn key() -> egui::Id {
    egui::Id::unique("nf_layout")
}

/// Remember this frame's layout for [`current`].
pub fn store(ctx: &egui::Context, l: Layout) {
    ctx.data_mut(|d| d.insert_temp(key(), l));
}

/// This frame's layout (Regular before the first frame).
#[must_use]
pub fn current(ctx: &egui::Context) -> Layout {
    ctx.data(|d| d.get_temp::<Layout>(key())).unwrap_or_default()
}

/// Bigger touch targets for the compact layout.
pub fn touch_style(ui: &mut egui::Ui) {
    let s = ui.style_mut();
    s.spacing.interact_size.y = s.spacing.interact_size.y.max(40.0);
    s.spacing.button_padding = egui::vec2(10.0, 8.0);
    s.spacing.item_spacing.y = s.spacing.item_spacing.y.max(6.0);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(w: f32, h: f32) -> egui::Vec2 {
        egui::vec2(w, h)
    }

    #[test]
    fn auto_switches_at_threshold() {
        assert_eq!(pick(LayoutMode::Auto, v(390.0, 800.0), false), Layout::Compact);
        assert_eq!(pick(LayoutMode::Auto, v(599.0, 800.0), false), Layout::Compact);
        assert_eq!(pick(LayoutMode::Auto, v(600.0, 800.0), false), Layout::Regular);
        assert_eq!(pick(LayoutMode::Compact, v(400.0, 1600.0), false), Layout::Compact);
        assert_eq!(pick(LayoutMode::Regular, v(300.0, 200.0), true), Layout::Regular);
    }

    #[test]
    fn phone_landscape_is_immersive_not_regular() {
        // 850x400 phone landscape: wider than 600 but still a phone.
        assert_eq!(pick(LayoutMode::Auto, v(850.0, 400.0), true), Layout::Immersive);
        assert_eq!(pick(LayoutMode::Auto, v(400.0, 850.0), true), Layout::Compact);
        // Forced compact behaves like a phone (desktop emulation).
        assert_eq!(pick(LayoutMode::Compact, v(850.0, 400.0), false), Layout::Immersive);
        // Desktop / tablet landscape stays regular.
        assert_eq!(pick(LayoutMode::Auto, v(850.0, 400.0), false), Layout::Regular);
        assert_eq!(pick(LayoutMode::Auto, v(1280.0, 800.0), false), Layout::Regular);
    }

    #[test]
    fn immersive_only_on_monitors() {
        assert_eq!(for_view(Layout::Immersive, nf_core::View::Bands), Layout::Immersive);
        assert_eq!(for_view(Layout::Immersive, nf_core::View::Settings), Layout::Compact);
        assert_eq!(for_view(Layout::Immersive, nf_core::View::Feedback), Layout::Compact);
        assert!(Layout::Immersive.is_compact());
    }
}
