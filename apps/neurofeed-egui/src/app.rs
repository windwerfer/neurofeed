//! eframe glue: owns the Session, ticks it, applies UI commands.

use crate::audio::{self, Audio};
use crate::ui;
use nf_core::{Command, Event, Session};

/// How often the UI repaints to show fresh band data.
const REPAINT_INTERVAL: std::time::Duration = std::time::Duration::from_millis(100);

/// Start parameter: env `NF_<NAME>` (desktop) or URL query `name` (web).
/// Device to connect at start: `device` param, else the simulator only for
/// the web demo and screenshot runs. `none` connects nothing.
fn startup_device() -> Option<String> {
    let demo = cfg!(target_arch = "wasm32") || param("demo").is_some() || param("view").is_some();
    param("device").or_else(|| demo.then(|| "sim:muse_s".to_owned())).filter(|d| !d.is_empty() && d != "none")
}

/// SIGINT / SIGTERM close the window, so `on_exit` disconnects the headset.
#[cfg(not(target_arch = "wasm32"))]
fn exit_on_signal(ctx: &egui::Context) {
    let ctx = ctx.clone();
    if let Err(e) = ctrlc::set_handler(move || ctx.send_viewport_cmd(egui::ViewportCommand::Close)) {
        log::warn!("no signal handler: {e}");
    }
}

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
    /// Demo / start-view runs skip the first-run tour (not persisted).
    no_tour: bool,
    /// Result of the last Settings → Storage move.
    store_note: Option<String>,
    /// Last value sent to [`crate::platform::Platform::keep_screen_on`].
    screen_on: bool,
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
        #[cfg(not(target_arch = "wasm32"))]
        {
            session.set_stream_sink(Box::new(nf_device::UdpSink::new()));
            session.set_stream_outlets(Box::new(nf_device::LslOutlets::new()));
            session.set_ai_runtime(Box::new(nf_ai::NativeAi::with_default_root()));
        }
        let mut app = Self::with_session(session);
        #[cfg(not(target_arch = "wasm32"))]
        if param("bridge").is_some_and(|v| v != "0") {
            app.set_bridge(&cc.egui_ctx, true);
        }
        // Never auto-connect a simulator on a real build: the remembered device
        // reconnects on its own (.ai/contracts/device-autoconnect.md rule 9).
        // Explicit: NF_DEVICE=sim:muse_s (`?device=` on the web). Demo/view
        // screenshot runs and the web build (no hardware) start the simulator.
        if let Some(id) = startup_device() {
            app.run(Command::DeviceConnect { id });
        }
        #[cfg(not(target_arch = "wasm32"))]
        exit_on_signal(&cc.egui_ctx);
        // Optional start view / demo (screenshots): NF_VIEW=psd NF_DEMO=history
        // on desktop, `?view=psd&demo=history` on the web.
        app.no_tour = param("demo").is_some() || param("view").is_some();
        if let Some(demo) = param("demo") {
            app.demo(&demo);
        }
        // NF_FAULTS / `?faults=` : a JSON list of `sim.fault.add` params (screenshots).
        let faults: Vec<serde_json::Value> = param("faults").and_then(|f| serde_json::from_str(&f).ok()).unwrap_or_default();
        for p in faults {
            if let Ok(nf_core::Request::Command(c)) = nf_core::Request::parse("sim.fault.add", p) {
                app.run(c);
            }
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
            no_tour: false,
            store_note: None,
            screen_on: false,
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
    /// Keep the UI out from under the status / navigation bars (Android).
    fn raw_input_hook(&mut self, ctx: &egui::Context, raw: &mut egui::RawInput) {
        let Some(p) = crate::platform::get() else { return };
        let [left, top, right, bottom] = crate::platform::insets_pt(p.safe_insets_px(), ctx.pixels_per_point(), p.min_top_inset_pt());
        raw.safe_area_insets = Some(egui::SafeAreaInsets(egui::epaint::MarginF32 { left, right, top, bottom }));
    }

    /// Window closed / app exit: stop streaming and wait (max 10 s) until the
    /// headset is disconnected, so it advertises again for the next start.
    fn on_exit(&mut self, _gl: Option<&eframe::glow::Context>) {
        for e in self.session.shutdown(nf_core::SHUTDOWN_TIMEOUT_S) {
            log::warn!("shutdown: {e}");
        }
    }

    fn ui(&mut self, root: &mut egui::Ui, _frame: &mut eframe::Frame) {
        let ctx = &root.ctx().clone();
        self.session.tick(ctx.input(|i| i.time));
        for e in self.session.drain_events() {
            match e {
                Event::Chime => self.audio.trigger(nf_core::nf_audio::OneShot::Reward),
                Event::GuardChime => self.audio.trigger(nf_core::nf_audio::OneShot::Guard),
                _ => {}
            }
        }
        // Legacy graph_cinema: F11 toggles fullscreen (desktop).
        if ctx.input(|i| i.key_pressed(egui::Key::F11)) {
            let full = ctx.input(|i| i.viewport().fullscreen.unwrap_or(false));
            ctx.send_viewport_cmd(egui::ViewportCommand::Fullscreen(!full));
        }
        let state = self.session.state();
        ui::theme::follow(ctx, state.settings.appearance);
        self.audio.update(&nf_core::audio::cue(state), state.music_dir.as_deref());
        #[cfg(not(target_arch = "wasm32"))]
        if let Some(b) = &mut self.bridge {
            b.poll(ctx, &mut self.session, self.last_error.as_deref());
        }
        #[cfg(not(target_arch = "wasm32"))]
        let bridge = Some(self.bridge.as_ref().map(crate::bridge::Bridge::addr));
        #[cfg(target_arch = "wasm32")]
        let bridge: Option<Option<String>> = None;
        let mut shell = ui::Shell { bridge, no_tour: self.no_tour, store_note: self.store_note.clone(), ..Default::default() };
        for cmd in ui::show_with(root, &self.session, self.last_error.as_deref(), &mut shell) {
            self.run(cmd);
        }
        #[cfg(not(target_arch = "wasm32"))]
        if let Some(on) = shell.set_bridge {
            self.set_bridge(ctx, on);
        }
        #[cfg(not(target_arch = "wasm32"))]
        if let Some(dir) = shell.move_store.take() {
            self.store_note = Some(
                crate::store::move_to(&mut self.session, std::path::Path::new(dir.trim())).unwrap_or_else(|e| format!("Move failed: {e}")),
            );
        }
        self.platform_frame();
        ctx.request_repaint_after(REPAINT_INTERVAL);
    }
}

impl NeuroFeedApp {
    /// Android hooks: screen on while training, checkpoint when backgrounded.
    fn platform_frame(&mut self) {
        let Some(p) = crate::platform::get() else { return };
        let training = self.session.state().feedback.phase.active();
        if self.screen_on != training {
            self.screen_on = training;
            p.keep_screen_on(training);
        }
        if p.take_paused() {
            self.session.checkpoint_now();
        }
    }
}

fn wall_ms() -> Option<f64> {
    web_time::SystemTime::now().duration_since(web_time::UNIX_EPOCH).ok().map(|d| d.as_secs_f64() * 1000.0)
}
