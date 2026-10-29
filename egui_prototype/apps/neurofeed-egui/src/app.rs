//! eframe glue: owns the Session, ticks it, applies UI commands.

use crate::ui;
use nf_core::{Command, Session};

/// How often the UI repaints to show fresh band data.
const REPAINT_INTERVAL: std::time::Duration = std::time::Duration::from_millis(100);

pub struct NeuroFeedApp {
    session: Session,
    last_error: Option<String>,
}

impl NeuroFeedApp {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        ui::theme::apply(&cc.egui_ctx);
        let mut app = Self::with_session(Session::new());
        app.run(Command::DeviceConnect { id: "sim:muse".into() });
        app
    }

    /// Use a pre-configured session (e.g. with a real device provider).
    pub fn with_session(session: Session) -> Self {
        Self { session, last_error: None }
    }

    fn run(&mut self, cmd: Command) {
        if let Err(e) = self.session.execute(cmd) {
            log::warn!("{e}");
            self.last_error = Some(e.to_string());
        }
    }
}

impl eframe::App for NeuroFeedApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.session.tick(ctx.input(|i| i.time));
        let _ = self.session.drain_events(); // no UI consumer yet
        for cmd in ui::show(ctx, self.session.state(), self.last_error.as_deref()) {
            self.run(cmd);
        }
        ctx.request_repaint_after(REPAINT_INTERVAL);
    }
}
