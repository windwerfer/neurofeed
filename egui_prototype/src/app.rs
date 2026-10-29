//! eframe glue: owns the state and the data source, ticks them every frame.

use crate::data::{BandSource, MockBandSource};
use crate::state::AppState;
use crate::ui;

/// How often the UI repaints to show fresh band data.
const REPAINT_INTERVAL: std::time::Duration = std::time::Duration::from_millis(100);

pub struct NeuroFeedApp {
    state: AppState,
    source: Box<dyn BandSource>,
}

impl NeuroFeedApp {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        ui::theme::apply(&cc.egui_ctx);
        Self::with_source(Box::new(MockBandSource::muse()))
    }

    /// Construct with any data source (e.g. a real headset later).
    pub fn with_source(source: Box<dyn BandSource>) -> Self {
        Self { state: AppState::new(source.device_info()), source }
    }
}

impl eframe::App for NeuroFeedApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        let now = ctx.input(|i| i.time);
        if !self.state.paused {
            if let Some(snapshot) = self.source.poll(now) {
                self.state.bands.push(snapshot);
            }
        }
        let actions = ui::show(ctx, &self.state);
        for action in actions {
            self.state.apply(action);
        }
        ctx.request_repaint_after(REPAINT_INTERVAL);
    }
}
