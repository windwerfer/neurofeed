//! Left navigation rail.

use super::theme;
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
