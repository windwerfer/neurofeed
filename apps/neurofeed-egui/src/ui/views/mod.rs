//! One module per functional view.

mod bands;
mod devices;
mod feedback;
mod heart;
mod histogram;
mod history;
mod import;
mod plot;
mod protocol_builder;
mod psd;
mod raw;
mod settings;
mod sound;
mod spectrogram;
mod streaming;

use nf_core::{Command, Session, View};

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>, shell: &mut super::Shell) {
    let state = session.state();
    match state.view {
        View::Feedback => feedback::show(ui, session, out),
        View::History => history::show(ui, session, out),
        View::Bands => bands::show(ui, state, out),
        View::RawEeg => raw::show(ui, session),
        View::Psd => psd::show(ui, session),
        View::HeartRate => heart::show(ui, session),
        View::Histogram => histogram::show(ui, session),
        View::Spectrogram => spectrogram::show(ui, session, out),
        View::Streaming => streaming::show(ui, session, out),
        View::Settings => settings::show(ui, session, out, shell),
    }
}
