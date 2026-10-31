//! First-run tour: a centred modal with five short pages. Finishing or
//! skipping sends `settings.set {onboarded: true}`; Settings → About →
//! "Show the tour again" resets it.

use egui::{Align2, Color32, Id, RichText, Vec2};
use nf_core::settings::SettingsPatch;
use nf_core::Command;

const PAGES: [(&str, &str, &[&str]); 5] = [
    (
        "Welcome to NeuroFeed",
        "Neurofeedback shows your brain activity back to you, second by second, so you can learn to steer it.",
        &[
            "Pick a protocol (what to train), sit still, and follow the sound and the circle.",
            "Sessions are short: 5–20 minutes. Regular practice matters more than length.",
            "Not a medical device. It does not diagnose or treat anything.",
        ],
    ),
    (
        "Fit the headband",
        "Good contact is everything. The fit check waits until all pads read clean.",
        &[
            "Forehead pads sit flat, just above the eyebrows; ear pads touch skin behind the ears.",
            "Move hair aside and wipe the skin; a little water helps dry skin.",
            "Relax your jaw and face: clenching and blinking show up as noise.",
        ],
    ),
    (
        "Calibration",
        "Each session starts by measuring your own baseline, so the threshold fits you today.",
        &[
            "Follow the spoken instructions (eyes open or closed) for about a minute.",
            "Dirty seconds (blinks, movement, bad pads) are left out of the baseline.",
            "You can reuse the last baseline for the same device and protocol.",
        ],
    ),
    (
        "Training and trust",
        "During training you are rewarded when the feature is above your threshold percentile.",
        &[
            "The trust pane shows what every second really was: in zone, below, held back or dirty.",
            "Held-back seconds are not rewarded even if they look good: the signal was not trustworthy.",
            "The threshold adapts slowly so you stay at about the reward rate you chose.",
        ],
    ),
    (
        "Your data stays here",
        "Recordings, notes and settings are stored only on this device.",
        &[
            "Add a pseudonymous subject id in Settings > General if you want to tell sessions apart.",
            "Export a session from History (.neurofeed or EDF) to share or analyse it.",
            "AI agents can only control the app if you switch on the bridge in Settings > About.",
        ],
    ),
];

pub fn show(ctx: &egui::Context, out: &mut Vec<Command>) {
    let key = Id::new("onboarding_page");
    let mut page: usize = ctx.data(|d| d.get_temp(key)).unwrap_or(0).min(PAGES.len() - 1);
    let screen = ctx.screen_rect();
    egui::Area::new(Id::new("onboarding_dim")).fixed_pos(screen.min).order(egui::Order::Middle).show(ctx, |ui| {
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
        .fixed_size([560.0, 340.0])
        .show(ctx, |ui| {
            ui.add_space(6.0);
            ui.weak(format!("{} of {}", page + 1, PAGES.len()));
            ui.label(RichText::new(title).size(24.0).strong());
            ui.add_space(4.0);
            ui.label(RichText::new(lead).size(15.0));
            ui.add_space(10.0);
            for p in points {
                ui.horizontal_wrapped(|ui| {
                    ui.label(RichText::new("•").color(Color32::from_rgb(0x66, 0xBB, 0x6A)));
                    ui.label(*p);
                });
            }
            ui.add_space(ui.available_height().max(0.0) - 40.0);
            ui.separator();
            ui.horizontal(|ui| {
                dots(ui, page);
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let last = page + 1 == PAGES.len();
                    let next =
                        egui::Button::new(RichText::new(if last { "Start" } else { "Next" }).strong()).min_size(Vec2::new(90.0, 30.0));
                    if ui.add(next).clicked() {
                        if last {
                            finish(out);
                            out.push(Command::ViewSet { view: nf_core::View::Feedback });
                        } else {
                            page += 1;
                        }
                    }
                    if page > 0 && ui.button("Back").clicked() {
                        page -= 1;
                    }
                    if !last && ui.button("Skip tour").clicked() {
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
