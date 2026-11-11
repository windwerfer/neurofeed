//! Left navigation rail.

use super::{layout::TOUCH, theme};
use nf_core::{AppState, Command, View};

/// Icon for the narrow (icon-only) rail.
fn icon(view: View) -> &'static str {
    match view {
        View::Feedback => "🎯",
        View::History => "🕘",
        View::Bands => "📊",
        View::RawEeg => "📉",
        View::Histogram => "📶",
        View::Spectrogram => "🌈",
        View::Psd => "📈",
        View::HeartRate => "❤",
        View::Optics => "✨",
        View::Movement => "🏃",
        View::Streaming => "📡",
        View::Settings => "⚙",
    }
}

/// `narrow`: medium-width windows get an icon-only rail (label on hover).
pub fn show(root: &mut egui::Ui, state: &AppState, narrow: bool, out: &mut Vec<Command>) {
    let width = if narrow { theme::SIDEBAR_NARROW } else { theme::SIDEBAR_WIDTH };
    egui::Panel::left("sidebar").exact_size(width).resizable(false).show(root, |ui| {
        ui.add_space(6.0);
        for view in View::ALL {
            if view == View::Settings {
                ui.separator();
            }
            let text = if narrow { icon(view).to_owned() } else { super::view_label(view) };
            let button = egui::Button::selectable(state.view == view, text);
            if ui.add_sized([ui.available_width(), 28.0], button).on_hover_text(super::view_label(view)).clicked() {
                out.push(Command::ViewSet { view });
            }
        }
    });
}

fn drawer_id() -> egui::Id {
    egui::Id::unique("nf_nav_drawer_open")
}

/// Compact navigation drawer (hamburger) open? Pure view chrome.
pub fn drawer_open(ctx: &egui::Context) -> bool {
    ctx.data(|d| d.get_temp::<bool>(drawer_id())).unwrap_or(false)
}

pub fn set_drawer(ctx: &egui::Context, open: bool) {
    ctx.data_mut(|d| d.insert_temp(drawer_id(), open));
}

/// Compact layout: modal navigation drawer over a scrim, every view in
/// sidebar order. Picking a view or tapping the scrim closes it.
pub fn drawer(ctx: &egui::Context, state: &AppState, out: &mut Vec<Command>) {
    if !drawer_open(ctx) {
        return;
    }
    let screen = ctx.content_rect();
    egui::Area::new(egui::Id::unique("nf_nav_scrim")).order(egui::Order::Middle).fixed_pos(screen.min).show(ctx, |ui| {
        let r = ui.allocate_rect(screen, egui::Sense::click());
        ui.painter().rect_filled(screen, 0.0, theme::SCRIM);
        if r.clicked() {
            set_drawer(ctx, false);
        }
    });
    let width = theme::DRAWER_WIDTH.min(screen.width() * 0.85);
    egui::Area::new(egui::Id::unique("nf_nav_drawer")).order(egui::Order::Foreground).fixed_pos(screen.min).show(ctx, |ui| {
        egui::Frame::side_top_panel(ui.style()).show(ui, |ui| {
            ui.set_min_size(egui::vec2(width, screen.height()));
            ui.set_max_width(width);
            egui::ScrollArea::vertical().show(ui, |ui| {
                ui.add_space(8.0);
                for view in View::ALL {
                    if view == View::Settings {
                        ui.separator();
                    }
                    let b = egui::Button::selectable(state.view == view, format!("{}  {}", icon(view), super::view_label(view)));
                    if ui.add_sized([width - 16.0, TOUCH], b).clicked() {
                        out.push(Command::ViewSet { view });
                        set_drawer(ctx, false);
                    }
                }
            });
        });
    });
}
