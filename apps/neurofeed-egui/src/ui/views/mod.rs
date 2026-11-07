//! One module per functional view.

mod ai;
pub(crate) mod bands;
mod devices;
mod feedback;
mod heart;
mod histogram;
mod history;
mod import;
/// egui temp-data key mirroring the gesture-markers setting.
pub const MARKS_ID: &str = "nf_gesture_markers";

mod about;
mod meta;
mod movement;
mod nerd;
mod plot;
mod protocol_builder;
mod psd;
mod raw;
mod settings;
mod sound;
mod spectrogram;
mod streaming;
mod trust;

use nf_core::{Command, Session, View};

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>, shell: &mut super::Shell) {
    let state = session.state();
    match state.view {
        View::Feedback => feedback::show(ui, session, out),
        View::History => history::show(ui, session, out),
        View::Bands => bands::show(ui, state, out),
        View::RawEeg => raw::show(ui, session, out),
        View::Psd => psd::show(ui, session, out),
        View::HeartRate => heart::show(ui, session),
        View::Movement => movement::show(ui, session),
        View::Histogram => histogram::show(ui, session, out),
        View::Spectrogram => spectrogram::show(ui, session, out),
        View::Streaming => streaming::show(ui, session, out),
        View::Settings => settings::show(ui, session, out, shell),
    }
}
