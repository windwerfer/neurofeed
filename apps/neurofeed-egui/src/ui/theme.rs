//! Colors and global style.

use egui::Color32;
use nf_core::Band;

pub const SIDEBAR_WIDTH: f32 = 170.0;
pub const TOPBAR_HEIGHT: f32 = 44.0;

pub fn apply(ctx: &egui::Context) {
    ctx.set_visuals(egui::Visuals::dark());
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
