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

pub fn apply(ctx: &egui::Context) {
    ctx.set_visuals(egui::Visuals::dark());
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

/// Follow the Appearance setting (cheap; egui ignores an unchanged value).
pub fn follow(ctx: &egui::Context, a: nf_core::settings::Appearance) {
    use nf_core::settings::Appearance;
    let want = match a {
        Appearance::System => egui::ThemePreference::System,
        Appearance::Light => egui::ThemePreference::Light,
        Appearance::Dark => egui::ThemePreference::Dark,
    };
    if ctx.options(|o| o.theme_preference) != want {
        ctx.set_theme(want);
    }
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
