//! Colors and global style.

use egui::Color32;
use nf_core::Band;

pub const SIDEBAR_WIDTH: f32 = 170.0;
pub const SIDEBAR_NARROW: f32 = 48.0;
pub const TOPBAR_HEIGHT: f32 = 44.0;
/// Compact navigation drawer width (Material: 256..=320 dp).
pub const DRAWER_WIDTH: f32 = 280.0;
/// Dim layer behind the navigation drawer.
pub const SCRIM: Color32 = Color32::from_black_alpha(110);
/// Monitor toolbar row height (regular; compact uses the touch height).
pub const MONITOR_TOOLBAR: f32 = 40.0;

/// Fonts. Both egui styles stay installed (egui's own dark and light
/// visuals); [`follow`] picks one, so nothing is forced to dark here.
pub fn apply(ctx: &egui::Context) {
    ctx.set_fonts(fonts());
}

/// egui's default fonts plus a DejaVu Sans subset (arrows, ≤ ≥ ±, play/pause
/// glyphs) as the last fallback, so "→" renders instead of a box.
pub fn fonts() -> egui::FontDefinitions {
    let mut f = egui::FontDefinitions::default();
    f.font_data.insert("arrows".into(), std::sync::Arc::new(egui::FontData::from_static(include_bytes!("../../assets/arrows.ttf"))));
    for fam in [egui::FontFamily::Proportional, egui::FontFamily::Monospace] {
        f.families.entry(fam).or_default().push("arrows".into());
    }
    f
}

/// Follow the Appearance setting every frame (cheap; unchanged values are
/// not written). `System` keeps egui on [`egui::ThemePreference::System`]:
/// eframe feeds the OS theme on macOS, Windows and the web (live). Where it
/// reports none (X11, Android, some Wayland) our own probe
/// ([`crate::os_theme`]) becomes egui's fallback theme.
pub fn follow(ctx: &egui::Context, a: nf_core::settings::Appearance) {
    let want = preference(a);
    if ctx.options(|o| o.theme_preference) != want {
        ctx.set_theme(want);
    }
    if let Some(t) = fallback(a, ctx.system_theme(), crate::os_theme::get) {
        if ctx.options(|o| o.fallback_theme) != t {
            ctx.options_mut(|o| o.fallback_theme = t);
        }
    }
}

/// egui theme preference for an Appearance setting.
#[must_use]
pub fn preference(a: nf_core::settings::Appearance) -> egui::ThemePreference {
    use nf_core::settings::Appearance;
    match a {
        Appearance::System => egui::ThemePreference::System,
        Appearance::Light => egui::ThemePreference::Light,
        Appearance::Dark => egui::ThemePreference::Dark,
    }
}

/// The fallback theme to install: only for `System`, only when eframe gave
/// no system theme, and only when the probe knows one (`probe` is not even
/// called otherwise).
pub fn fallback(
    a: nf_core::settings::Appearance,
    system: Option<egui::Theme>,
    probe: impl FnOnce() -> Option<egui::Theme>,
) -> Option<egui::Theme> {
    (a == nf_core::settings::Appearance::System && system.is_none()).then(probe).flatten()
}

/// Band palette of the legacy app (`charts/band_style.dart`).
pub fn band_color(band: Band) -> Color32 {
    match band {
        Band::Delta => Color32::from_rgb(0x4F, 0xC3, 0xF7),
        Band::Theta => Color32::from_rgb(0xFF, 0x70, 0x43),
        Band::Alpha => Color32::from_rgb(0x66, 0xBB, 0x6A),
        Band::Beta => Color32::from_rgb(0xAB, 0x47, 0xBC),
        Band::Gamma => Color32::from_rgb(0xFF, 0xA7, 0x26),
    }
}

/// Graph grid line (both themes).
pub fn grid(v: &egui::Visuals) -> egui::Stroke {
    egui::Stroke::new(0.6, v.weak_text_color().gamma_multiply(0.35))
}

/// Axis label colour.
pub fn axis_text(v: &egui::Visuals) -> Color32 {
    v.weak_text_color()
}

/// Raw EEG trace (light, as Flutter's onSurface trace).
pub fn raw_trace(v: &egui::Visuals) -> Color32 {
    v.text_color().gamma_multiply(0.9)
}

/// Raw EEG sweep cursor.
pub fn sweep_cursor(v: &egui::Visuals) -> Color32 {
    v.strong_text_color().gamma_multiply(0.6)
}

/// Raw EEG shading: no data (gap) and samples the device sent as invalid.
pub const GAP_SHADE: Color32 = Color32::from_rgba_premultiplied(0x39, 0x39, 0x39, 40);
pub const BAD_SHADE: Color32 = Color32::from_rgba_premultiplied(0x2F, 0x10, 0x10, 50);

/// Debug overlay backdrop (perf counter).
pub fn overlay_bg(v: &egui::Visuals) -> Color32 {
    v.extreme_bg_color.gamma_multiply(0.85)
}

/// Off-scale marker (value clipped at the axis edge).
pub const CLIPPED: Color32 = Color32::from_rgb(0xEF, 0x53, 0x50);

/// Pad quality colours of the legacy status bar (`_signalColor`):
/// green ≥ 80, orange ≥ 40, red below.
pub fn quality_color(score: f32) -> Color32 {
    if score >= 80.0 {
        Color32::from_rgb(0x4C, 0xAF, 0x50)
    } else if score >= 40.0 {
        Color32::from_rgb(0xFF, 0x98, 0x00)
    } else {
        Color32::from_rgb(0xF4, 0x43, 0x36)
    }
}

/// A pad with no score yet (AUX before data).
pub const QUALITY_NONE: Color32 = Color32::from_rgb(0x75, 0x75, 0x75);
/// The "streaming server running" dot.
/// Record button dot.
pub const RECORD_RED: Color32 = Color32::from_rgb(0xE5, 0x39, 0x35);
pub const STREAM_ON: Color32 = Color32::from_rgb(0x4C, 0xAF, 0x50);

#[cfg(test)]
mod tests {
    use super::*;
    use egui::{Theme, ThemePreference};
    use nf_core::settings::Appearance;

    /// One frame with the OS reporting `system`, Appearance `a`.
    fn frame(ctx: &egui::Context, a: Appearance, system: Option<Theme>) -> Theme {
        let input = egui::RawInput { system_theme: system, ..Default::default() };
        ctx.run_ui(input, |ui| follow(ui.ctx(), a)).textures_delta.clear();
        // The theme of the next frame (preference changes apply from there).
        ctx.run_ui(egui::RawInput { system_theme: system, ..Default::default() }, |_| {}).textures_delta.clear();
        ctx.theme()
    }

    #[test]
    fn system_follows_the_os_live_and_a_choice_overrides_it() {
        let ctx = egui::Context::default();
        assert_eq!(frame(&ctx, Appearance::System, Some(Theme::Light)), Theme::Light);
        assert_eq!(frame(&ctx, Appearance::System, Some(Theme::Dark)), Theme::Dark, "OS switched while running");
        assert_eq!(frame(&ctx, Appearance::System, Some(Theme::Light)), Theme::Light);
        assert_eq!(frame(&ctx, Appearance::Dark, Some(Theme::Light)), Theme::Dark);
        assert_eq!(frame(&ctx, Appearance::Light, Some(Theme::Dark)), Theme::Light);
        assert_eq!(ctx.options(|o| o.theme_preference), ThemePreference::Light);
    }

    #[test]
    fn both_styles_keep_egui_visuals_for_their_theme() {
        let ctx = egui::Context::default();
        apply(&ctx);
        assert!(!ctx.style_of(Theme::Light).visuals.dark_mode);
        assert!(ctx.style_of(Theme::Dark).visuals.dark_mode);
    }

    #[test]
    fn probe_only_fills_a_missing_os_theme_for_system() {
        let light = || Some(Theme::Light);
        assert_eq!(fallback(Appearance::System, None, light), Some(Theme::Light));
        assert_eq!(fallback(Appearance::System, None, || None), None);
        let never = || -> Option<Theme> { panic!("probe must not run") };
        assert_eq!(fallback(Appearance::System, Some(Theme::Dark), never), None);
        assert_eq!(fallback(Appearance::Dark, None, never), None);
        assert_eq!(fallback(Appearance::Light, None, never), None);
        assert_eq!(preference(Appearance::System), ThemePreference::System);
    }
}
