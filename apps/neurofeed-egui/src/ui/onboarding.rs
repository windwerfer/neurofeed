//! First-run tour: a centred modal with five short pages. Finishing or
//! skipping sends `settings.set {onboarded: true}`; Settings → About →
//! "Show the tour again" resets it.

use egui::{Align2, Color32, Id, RichText, Vec2};
use nf_core::settings::SettingsPatch;
use nf_core::Command;

/// Fluent keys: (title, lead, points).
const PAGES: [(&str, &str, [&str; 3]); 5] = [
    ("onboarding-p1-title", "onboarding-p1-lead", ["onboarding-p1-point1", "onboarding-p1-point2", "onboarding-p1-point3"]),
    ("onboarding-p2-title", "onboarding-p2-lead", ["onboarding-p2-point1", "onboarding-p2-point2", "onboarding-p2-point3"]),
    ("onboarding-p3-title", "onboarding-p3-lead", ["onboarding-p3-point1", "onboarding-p3-point2", "onboarding-p3-point3"]),
    ("onboarding-p4-title", "onboarding-p4-lead", ["onboarding-p4-point1", "onboarding-p4-point2", "onboarding-p4-point3"]),
    ("onboarding-p5-title", "onboarding-p5-lead", ["onboarding-p5-point1", "onboarding-p5-point2", "onboarding-p5-point3"]),
];

pub fn show(ctx: &egui::Context, out: &mut Vec<Command>) {
    let key = Id::unique("onboarding_page");
    let mut page: usize = ctx.data(|d| d.get_temp(key)).unwrap_or(0).min(PAGES.len() - 1);
    let screen = ctx.content_rect();
    egui::Area::new(Id::unique("onboarding_dim")).fixed_pos(screen.min).order(egui::Order::Middle).show(ctx, |ui| {
        ui.painter().rect_filled(screen, 0.0, Color32::from_black_alpha(160));
        ui.allocate_rect(screen, egui::Sense::click());
    });
    let finish = |out: &mut Vec<Command>| out.push(Command::SettingsSet(SettingsPatch { onboarded: Some(true), ..Default::default() }));
    let (title, lead, points) = PAGES[page];
    egui::Window::new("onboarding")
        .title_bar(false)
        .resizable(false)
        .collapsible(false)
        .order(egui::Order::Foreground)
        .anchor(Align2::CENTER_CENTER, Vec2::ZERO)
        .fixed_size(if super::layout::current(ctx).is_compact() {
            [screen.width() - 24.0, (screen.height() - 24.0).min(520.0)]
        } else {
            [560.0, 340.0]
        })
        .show(ctx, |ui| {
            ui.add_space(6.0);
            ui.weak(t!("onboarding-page-of", page = page + 1, total = PAGES.len()));
            ui.label(RichText::new(crate::i18n::tr(title, &[])).size(24.0).strong());
            ui.add_space(4.0);
            ui.label(RichText::new(crate::i18n::tr(lead, &[])).size(15.0));
            ui.add_space(10.0);
            for p in points {
                ui.horizontal_wrapped(|ui| {
                    ui.label(RichText::new("•").color(Color32::from_rgb(0x66, 0xBB, 0x6A)));
                    ui.label(crate::i18n::tr(p, &[]));
                });
            }
            ui.add_space(ui.available_height().max(0.0) - 40.0);
            ui.separator();
            ui.horizontal(|ui| {
                dots(ui, page);
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let last = page + 1 == PAGES.len();
                    let next = egui::Button::new(RichText::new(if last { t!("onboarding-start") } else { t!("onboarding-next") }).strong())
                        .min_size(Vec2::new(90.0, 30.0));
                    if ui.add(next).clicked() {
                        if last {
                            finish(out);
                            out.push(Command::ViewSet { view: nf_core::View::Feedback });
                        } else {
                            page += 1;
                        }
                    }
                    if page > 0 && ui.button(t!("onboarding-back")).clicked() {
                        page -= 1;
                    }
                    if !last && ui.button(t!("onboarding-skip-tour")).clicked() {
                        finish(out);
                    }
                });
            });
        });
    ctx.data_mut(|d| d.insert_temp(key, page));
}

fn dots(ui: &mut egui::Ui, page: usize) {
    let (rect, _) = ui.allocate_exact_size(Vec2::new(PAGES.len() as f32 * 16.0, 12.0), egui::Sense::hover());
    for i in 0..PAGES.len() {
        let c = rect.left_center() + Vec2::new(6.0 + i as f32 * 16.0, 0.0);
        let col = if i == page { Color32::from_rgb(0x66, 0xBB, 0x6A) } else { ui.visuals().weak_text_color() };
        ui.painter().circle_filled(c, if i == page { 5.0 } else { 3.5 }, col);
    }
}
