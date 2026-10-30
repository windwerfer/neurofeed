//! eframe glue: owns the Session, ticks it, applies UI commands.

use crate::audio::{self, Audio};
use crate::ui;
use nf_core::{Command, Event, Session};

/// How often the UI repaints to show fresh band data.
const REPAINT_INTERVAL: std::time::Duration = std::time::Duration::from_millis(100);

pub struct NeuroFeedApp {
    session: Session,
    last_error: Option<String>,
    audio: Box<dyn Audio>,
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
        #[cfg(not(target_arch = "wasm32"))]
        if let Ok(demo) = std::env::var("NF_DEMO") {
            app.demo(&demo);
        }
        app
    }

    /// Use a pre-configured session (e.g. with a real device provider).
    pub fn with_session(session: Session) -> Self {
        Self { session, last_error: None, audio: audio::platform() }
    }

    /// Screenshot/demo states of the feedback flow (NF_DEMO=fit|calibrating|training|paused|summary).
    #[cfg(not(target_arch = "wasm32"))]
    fn demo(&mut self, which: &str) {
        let adv = |s: f64| Command::ClockAdvance { seconds: s };
        let fault = |pads: &[&str]| Command::SimFault {
            bad_pads: pads.iter().map(|p| (*p).to_owned()).collect(),
            dropout: false,
            motion: false,
            blink: false,
            clench: false,
        };
        let mut steps = vec![Command::ViewSet { view: nf_core::View::Feedback }, adv(3.0)];
        let start = [Command::FeedbackStart { minutes: Some(10) }, adv(4.0)];
        match which {
            "fit" => steps.extend([Command::FeedbackStart { minutes: None }, fault(&["AF7"]), adv(3.0)]),
            "calibrating" => {
                steps.extend(start.into_iter().chain([Command::CalibrationStart { anyway: false }, adv(20.0), fault(&["AF8"]), adv(3.0)]))
            }
            "training" => steps.extend(start.into_iter().chain([Command::CalibrationStart { anyway: false }, adv(50.0), adv(150.0)])),
            "paused" => steps.extend(start.into_iter().chain([
                Command::CalibrationStart { anyway: false },
                adv(50.0),
                adv(60.0),
                fault(&["AF7", "AF8"]),
                adv(12.0),
            ])),
            "summary" => steps.extend([
                Command::FeedbackStart { minutes: Some(2) },
                adv(4.0),
                Command::CalibrationStart { anyway: false },
                adv(50.0),
                adv(125.0),
            ]),
            _ => {}
        }
        steps.into_iter().for_each(|c| self.run(c));
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
        for e in self.session.drain_events() {
            if e == Event::Chime {
                self.audio.chime();
            }
        }
        for cmd in ui::show(ctx, &self.session, self.last_error.as_deref()) {
            self.run(cmd);
        }
        ctx.request_repaint_after(REPAINT_INTERVAL);
    }
}
