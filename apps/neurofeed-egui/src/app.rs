//! eframe glue: owns the Session, ticks it, applies UI commands.

use crate::audio::{self, Audio};
use crate::ui;
use nf_core::{Command, Event, Session};

/// How often the UI repaints to show fresh band data.
const REPAINT_INTERVAL: std::time::Duration = std::time::Duration::from_millis(100);

/// Start parameter: env `NF_<NAME>` (desktop) or URL query `name` (web).
fn param(name: &str) -> Option<String> {
    #[cfg(not(target_arch = "wasm32"))]
    return std::env::var(format!("NF_{}", name.to_uppercase())).ok();
    #[cfg(target_arch = "wasm32")]
    return web_sys::window()
        .and_then(|w| w.location().search().ok())
        .and_then(|q| web_sys::UrlSearchParams::new_with_str(&q).ok())
        .and_then(|p| p.get(name));
}

pub struct NeuroFeedApp {
    session: Session,
    last_error: Option<String>,
    audio: Box<dyn Audio>,
    #[cfg(not(target_arch = "wasm32"))]
    bridge: Option<crate::bridge::Bridge>,
}

impl NeuroFeedApp {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        ui::theme::apply(&cc.egui_ctx);
        #[allow(unused_mut)]
        let mut session = Session::new().with_store(crate::store::open());
        #[cfg(not(target_arch = "wasm32"))]
        for p in nf_device::native_providers() {
            session.register_provider(p);
        }
        let mut app = Self::with_session(session);
        #[cfg(not(target_arch = "wasm32"))]
        if param("bridge").is_some_and(|v| v != "0") {
            app.set_bridge(&cc.egui_ctx, true);
        }
        app.run(Command::DeviceConnect { id: "sim:muse_s".into() });
        // Optional start view / demo (screenshots): NF_VIEW=psd NF_DEMO=history
        // on desktop, `?view=psd&demo=history` on the web.
        if let Some(demo) = param("demo") {
            app.demo(&demo);
        }
        if let Some(view) = param("view").and_then(|v| serde_json::from_value(serde_json::Value::String(v)).ok()) {
            app.run(Command::ViewSet { view });
        }
        app
    }

    /// Use a pre-configured session (e.g. with a real device provider).
    pub fn with_session(session: Session) -> Self {
        Self {
            session,
            last_error: None,
            audio: audio::platform(),
            #[cfg(not(target_arch = "wasm32"))]
            bridge: None,
        }
    }

    /// Start/stop the agent bridge (Settings toggle, `NF_BRIDGE=1`).
    #[cfg(not(target_arch = "wasm32"))]
    fn set_bridge(&mut self, ctx: &egui::Context, on: bool) {
        if !on {
            self.bridge = None;
        } else if self.bridge.is_none() {
            match crate::bridge::Bridge::start(ctx) {
                Ok(b) => self.bridge = Some(b),
                Err(e) => self.last_error = Some(format!("agent bridge: {e}")),
            }
        }
    }

    /// Screenshot/demo states of the feedback flow (NF_DEMO=fit|calibrating|training|paused|summary|history).
    fn demo(&mut self, which: &str) {
        let adv = |s: f64| Command::ClockAdvance { seconds: s };
        let fault = |pads: &[&str]| Command::SimFault {
            bad_pads: pads.iter().map(|p| (*p).to_owned()).collect(),
            dropout: false,
            motion: false,
            blink: false,
            clench: false,
            drowsy: false,
        };
        let mut steps = vec![Command::ViewSet { view: nf_core::View::Feedback }, adv(3.0)];
        let start = [Command::FeedbackStart { minutes: Some(10), wall_clock_unix_ms: None }, adv(4.0)];
        match which {
            "fit" => steps.extend([Command::FeedbackStart { minutes: None, wall_clock_unix_ms: None }, fault(&["AF7"]), adv(3.0)]),
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
                Command::FeedbackStart { minutes: Some(2), wall_clock_unix_ms: None },
                adv(4.0),
                Command::CalibrationStart { anyway: false },
                adv(50.0),
                adv(125.0),
            ]),
            "history" => {
                for (i, p) in ["restAwake", "alertOpen", "openMonitor"].into_iter().enumerate() {
                    let blink = |on| Command::SimFault {
                        bad_pads: Vec::new(),
                        dropout: false,
                        motion: false,
                        blink: on,
                        clench: false,
                        drowsy: false,
                    };
                    steps.extend([
                        Command::ProtocolSet { id: p.into(), minutes: None },
                        Command::FeedbackStart { minutes: Some(2 + i as u32), wall_clock_unix_ms: None },
                        adv(4.0),
                        Command::CalibrationStart { anyway: false },
                        adv(60.0),
                        blink(i == 1),
                        adv(30.0),
                        blink(false),
                        adv(200.0),
                    ]);
                }
                steps.push(Command::ViewSet { view: nf_core::View::History });
            }
            _ => {}
        }
        steps.into_iter().for_each(|c| self.run(c));
    }

    fn run(&mut self, mut cmd: Command) {
        // Shell-side injection: the core never reads a clock.
        if let Command::RecordingStart { wall_clock_unix_ms: w @ None } = &mut cmd {
            *w = wall_ms();
        }
        if let Command::FeedbackStart { wall_clock_unix_ms: w @ None, .. } = &mut cmd {
            *w = wall_ms();
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
            match e {
                Event::Chime => self.audio.trigger(nf_core::nf_audio::OneShot::Reward),
                Event::GuardChime => self.audio.trigger(nf_core::nf_audio::OneShot::Guard),
                _ => {}
            }
        }
        let state = self.session.state();
        self.audio.update(&nf_core::audio::cue(state), state.music_dir.as_deref());
        #[cfg(not(target_arch = "wasm32"))]
        if let Some(b) = &mut self.bridge {
            b.poll(ctx, &mut self.session, self.last_error.as_deref());
        }
        #[cfg(not(target_arch = "wasm32"))]
        let bridge = Some(self.bridge.as_ref().map(crate::bridge::Bridge::addr));
        #[cfg(target_arch = "wasm32")]
        let bridge: Option<Option<String>> = None;
        let mut shell = ui::Shell { bridge, ..Default::default() };
        for cmd in ui::show_with(ctx, &self.session, self.last_error.as_deref(), &mut shell) {
            self.run(cmd);
        }
        #[cfg(not(target_arch = "wasm32"))]
        if let Some(on) = shell.set_bridge {
            self.set_bridge(ctx, on);
        }
        ctx.request_repaint_after(REPAINT_INTERVAL);
    }
}

fn wall_ms() -> Option<f64> {
    web_time::SystemTime::now().duration_since(web_time::UNIX_EPOCH).ok().map(|d| d.as_secs_f64() * 1000.0)
}
