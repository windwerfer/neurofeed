//! Settings: Band Stability (and devices, see `devices`).

use egui::RichText;
use nf_core::{Command, Session};
use nf_feedback_consts::{DEFAULT_DIFFICULTY, DEFAULT_WINDOW, MAX_DIFFICULTY, MAX_WINDOW, MIN_WINDOW};

/// Values shown while dragging (sent on release so a drag is one command).
#[derive(Default)]
pub struct SettingsUi {
    window: Option<u32>,
    difficulty: Option<f64>,
}

thread_local! {
    static UI: std::cell::RefCell<SettingsUi> = std::cell::RefCell::new(SettingsUi::default());
}

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>, shell: &mut crate::ui::Shell) {
    ui.add_space(6.0);
    ui.heading(RichText::new("Settings").size(24.0));
    ui.add_space(8.0);
    super::devices::show(ui, session, out);
    ui.add_space(12.0);
    stability(ui, session, out);
    if let Some(bridge) = &shell.bridge {
        ui.add_space(12.0);
        ui.group(|ui| {
            ui.label(RichText::new("Agents").strong().size(17.0));
            let mut on = bridge.is_some();
            if ui.checkbox(&mut on, "Allow AI agents to control this app (MCP bridge)").changed() {
                shell.set_bridge = Some(on);
            }
            match bridge {
                Some(addr) => ui.weak(format!("Listening on {addr} (local only, token in bridge.json). Run: neurofeed-mcp --bridge")),
                None => ui.weak("Off. Also enabled by starting with NF_BRIDGE=1."),
            };
        });
    }
}

fn stability(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let cur = session.state().feedback.stability;
    let enabled = session.enabled("stability.set");
    ui.group(|ui| {
        ui.label(RichText::new("Band Stability").strong().size(17.0));
        ui.weak("Rewards steadier alpha than in calibration. Window = clean seconds in the rolling fluctuation; difficulty = how much steadier than baseline you must be (in target when r ≤ 1 − difficulty).");
        if let Err(why) = &enabled {
            ui.colored_label(egui::Color32::from_rgb(230, 170, 60), why);
        }
        ui.add_enabled_ui(enabled.is_ok(), |ui| {
            UI.with(|st| {
                let mut st = st.borrow_mut();
                let mut w = st.window.unwrap_or(cur.window);
                let r = ui.add(egui::Slider::new(&mut w, MIN_WINDOW..=MAX_WINDOW).text("window (s)"));
                st.window = (r.dragged() || r.has_focus()).then_some(w);
                if r.drag_stopped() || (r.changed() && !r.dragged()) {
                    out.push(Command::StabilitySet { window: Some(w), difficulty: None, reset: false });
                }
                let mut d = st.difficulty.unwrap_or(cur.difficulty);
                let r = ui.add(egui::Slider::new(&mut d, 0.0..=MAX_DIFFICULTY).step_by(0.01).fixed_decimals(2).text("difficulty"));
                st.difficulty = (r.dragged() || r.has_focus()).then_some(d);
                if r.drag_stopped() || (r.changed() && !r.dragged()) {
                    out.push(Command::StabilitySet { window: None, difficulty: Some(d), reset: false });
                }
            });
            let is_default = cur.window == DEFAULT_WINDOW && (cur.difficulty - DEFAULT_DIFFICULTY).abs() < 1e-9;
            if ui.add_enabled(!is_default, egui::Button::new(format!("Reset to defaults ({DEFAULT_WINDOW} s, {DEFAULT_DIFFICULTY:.2})"))).clicked() {
                out.push(Command::StabilitySet { window: None, difficulty: None, reset: true });
            }
        });
    });
}

/// Re-exported bounds (nf-feedback is reached through nf-core).
mod nf_feedback_consts {
    use nf_core::StabilityConfig as S;
    pub const DEFAULT_WINDOW: u32 = S::DEFAULT_WINDOW;
    pub const MIN_WINDOW: u32 = S::MIN_WINDOW;
    pub const MAX_WINDOW: u32 = S::MAX_WINDOW;
    pub const DEFAULT_DIFFICULTY: f64 = S::DEFAULT_DIFFICULTY;
    pub const MAX_DIFFICULTY: f64 = S::MAX_DIFFICULTY;
}
