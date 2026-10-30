//! One module per functional view; everything else is a placeholder.

mod bands;
mod devices;
mod feedback;
mod heart;
mod histogram;
mod history;
mod placeholder;
mod plot;
mod psd;
mod raw;
mod settings;
mod spectrogram;

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
        View::Settings => settings::show(ui, session, out, shell),
        other => placeholder::show(ui, other),
    }
}
