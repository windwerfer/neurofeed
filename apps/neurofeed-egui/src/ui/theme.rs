//! Colors and global style.

use egui::Color32;
use nf_core::Band;

pub const SIDEBAR_WIDTH: f32 = 170.0;
pub const TOPBAR_HEIGHT: f32 = 44.0;

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

pub fn band_color(band: Band) -> Color32 {
    match band {
        Band::Delta => Color32::from_rgb(0xE5, 0x73, 0x73),
        Band::Theta => Color32::from_rgb(0xFF, 0xB7, 0x4D),
        Band::Alpha => Color32::from_rgb(0x81, 0xC7, 0x84),
        Band::Beta => Color32::from_rgb(0x64, 0xB5, 0xF6),
        Band::Gamma => Color32::from_rgb(0xBA, 0x68, 0xC8),
    }
}
