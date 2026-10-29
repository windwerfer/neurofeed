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
        app.run(Command::DeviceConnect { id: "sim:muse_s".into() });
        // Optional start view (screenshots/demos), e.g. NF_VIEW=psd.
        #[cfg(not(target_arch = "wasm32"))]
        if let Some(view) = std::env::var("NF_VIEW").ok().and_then(|v| serde_json::from_value(serde_json::Value::String(v)).ok()) {
            app.run(Command::ViewSet { view });
        }
        app
    }

    /// Use a pre-configured session (e.g. with a real device provider).
    pub fn with_session(session: Session) -> Self {
        Self { session, last_error: None }
    }

    fn run(&mut self, mut cmd: Command) {
        // Shell-side injection: the core never reads a clock.
        if let Command::RecordingStart { wall_clock_unix_ms: w @ None } = &mut cmd {
            *w = web_time::SystemTime::now().duration_since(web_time::UNIX_EPOCH).ok().map(|d| d.as_secs_f64() * 1000.0);
        }
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
        for cmd in ui::show(ctx, &self.session, self.last_error.as_deref()) {
            self.run(cmd);
        }
        ctx.request_repaint_after(REPAINT_INTERVAL);
    }
}
