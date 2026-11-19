//! The two feedback-session guards (`.ai/contracts/feedback-disconnect.md`):
//!
//! - **Disconnect during a session**: a confirmation that the session will
//!   end. Only Confirm sends `device.disconnect {end_session: true}`, which
//!   ends the session normally and then disconnects. Cancel (the default)
//!   changes nothing.
//! - **Reconnect prompt**: after a link loss of `RECONNECT_PROMPT_S` the core
//!   sets `reconnect_prompt`; this asks "keep waiting or end the session?".
//!   It cannot be dismissed without a choice, and never ends anything itself.

use super::theme;
use nf_core::{Command, Session};

/// Pending "end the session and disconnect?" confirmation (a `bool` marker).
pub(crate) fn disconnect_pending_id() -> egui::Id {
    egui::Id::unique("nf-disconnect-pending")
}

/// Widget rects for tests (`prompt_id().with("wait" | "end")`).
pub(crate) fn prompt_id() -> egui::Id {
    egui::Id::unique("nf-reconnect-prompt")
}

/// The Device dialog's Disconnect button: ask first while a session runs.
pub fn request_disconnect(ctx: &egui::Context, session: &Session, out: &mut Vec<Command>) {
    if session.trainer().phase.active() {
        ctx.data_mut(|d| d.insert_temp(disconnect_pending_id(), true));
    } else {
        out.push(Command::DeviceDisconnect { end_session: false });
    }
}

pub fn show(ctx: &egui::Context, session: &Session, out: &mut Vec<Command>) {
    confirm_disconnect(ctx, session, out);
    reconnect_prompt(ctx, session, out);
}

fn device_name(session: &Session) -> String {
    session.state().device.as_ref().map_or_else(|| t!("session-guard-this-device").to_owned(), super::device_dialog::label)
}

fn confirm_disconnect(ctx: &egui::Context, session: &Session, out: &mut Vec<Command>) {
    if ctx.data(|d| d.get_temp::<bool>(disconnect_pending_id())).is_none() {
        return;
    }
    // The session ended some other way meanwhile: nothing left to confirm.
    if !session.trainer().phase.active() || session.state().device.is_none() {
        ctx.data_mut(|d| d.remove::<bool>(disconnect_pending_id()));
        return;
    }
    let id = disconnect_pending_id();
    let mut done = false;
    let r = egui::Modal::new(egui::Id::unique("nf-disconnect-confirm")).show(ctx, |ui| {
        ui.set_max_width(360.0);
        ui.strong(t!("session-guard-disconnect-title"));
        ui.label(t!("session-guard-disconnect-body", device = device_name(session)));
        ui.add_space(6.0);
        ui.horizontal(|ui| {
            let cancel = ui.button(t!("session-guard-cancel"));
            ui.ctx().data_mut(|d| d.insert_temp(id.with("cancel"), cancel.rect));
            if !ui.memory(|m| m.focused().is_some()) {
                cancel.request_focus();
            }
            done |= cancel.clicked();
            let red = egui::RichText::new(t!("session-guard-disconnect-confirm")).color(egui::Color32::WHITE);
            let confirm = ui.add(egui::Button::new(red).fill(theme::RECORD_RED));
            ui.ctx().data_mut(|d| d.insert_temp(id.with("confirm"), confirm.rect));
            if confirm.clicked() {
                out.push(Command::DeviceDisconnect { end_session: true });
                done = true;
            }
        });
    });
    if done || r.should_close() {
        ctx.data_mut(|d| d.remove::<bool>(id));
    }
}

fn reconnect_prompt(ctx: &egui::Context, session: &Session, out: &mut Vec<Command>) {
    let t = session.trainer();
    if !t.reconnect_prompt || !t.phase.active() {
        return;
    }
    let lost = t.link_lost_s(session.state().time).unwrap_or(0.0);
    let id = prompt_id();
    // No close on Escape / outside click: the user must choose.
    egui::Modal::new(egui::Id::unique("nf-reconnect-modal")).show(ctx, |ui| {
        ui.set_max_width(380.0);
        ui.strong(t!("session-guard-lost-title"));
        ui.label(t!("session-guard-lost-body", device = device_name(session), s = format!("{lost:.0}")));
        ui.add_space(6.0);
        ui.horizontal(|ui| {
            let wait = ui.button(t!("session-guard-keep-waiting"));
            ui.ctx().data_mut(|d| d.insert_temp(id.with("wait"), wait.rect));
            if !ui.memory(|m| m.focused().is_some()) {
                wait.request_focus();
            }
            if wait.clicked() {
                out.push(Command::FeedbackKeepWaiting);
            }
            let end = ui.button(t!("feedback-end-session"));
            ui.ctx().data_mut(|d| d.insert_temp(id.with("end"), end.rect));
            if end.clicked() {
                out.push(Command::FeedbackStop);
            }
        });
    });
    // The lost-time counter in the text ticks.
    ctx.request_repaint_after(std::time::Duration::from_millis(500));
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
    use super::*;
    use serde_json::json;

    /// Synthetic egui frames over a simulated session (manual clock).
    struct Drive {
        ctx: egui::Context,
        t: f64,
        s: Session,
        all: Vec<Command>,
        _lang: std::sync::MutexGuard<'static, ()>,
    }

    impl Drive {
        fn training() -> Self {
            let _lang = crate::i18n::lang_lock();
            let mut s = Session::new();
            s.call("settings.set", json!({ "onboarded": true, "layout": "regular" })).unwrap();
            s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
            s.call("clock.advance", json!({ "seconds": 3.0 })).unwrap();
            s.call("feedback.start", json!({ "minutes": 5 })).unwrap();
            s.call("calibration.start", json!({ "anyway": true })).unwrap();
            s.call("calibration.skip", json!({})).ok();
            s.call("clock.advance", json!({ "seconds": 12.0 })).unwrap();
            s.call("calibration.skip", json!({})).ok();
            let mut d = Drive { ctx: egui::Context::default(), t: 0.0, s, all: Vec::new(), _lang };
            d.frame(vec![]);
            d
        }
        fn frame(&mut self, events: Vec<egui::Event>) {
            self.t += 1.0 / 60.0;
            let input = egui::RawInput {
                screen_rect: Some(egui::Rect::from_min_size(egui::Pos2::ZERO, egui::vec2(1200.0, 800.0))),
                time: Some(self.t),
                events,
                ..Default::default()
            };
            let mut cmds = Vec::new();
            let s = &self.s;
            self.ctx.run_ui(input, |u| cmds = crate::ui::show(u, s, None)).textures_delta.clear();
            for c in cmds {
                self.s.execute(c.clone()).ok();
                self.all.push(c);
            }
        }
        fn tap(&mut self, id: egui::Id) {
            let pos = self.ctx.data(|d| d.get_temp::<egui::Rect>(id)).unwrap_or_else(|| panic!("no rect {id:?}")).center();
            let b = |pressed| egui::Event::PointerButton {
                pos,
                button: egui::PointerButton::Primary,
                pressed,
                modifiers: egui::Modifiers::NONE,
            };
            self.frame(vec![egui::Event::PointerMoved(pos), b(true)]);
            self.frame(vec![b(false)]);
            self.frame(vec![]);
        }
        fn phase(&self) -> nf_core::feedback::Phase {
            self.s.trainer().phase
        }
        fn open_device_dialog(&mut self) {
            self.s.call("device.dialog", json!({ "open": true })).unwrap();
            self.frame(vec![]);
            self.frame(vec![]);
        }
    }

    #[test]
    fn disconnect_during_a_session_asks_and_cancel_keeps_it() {
        let mut d = Drive::training();
        assert!(d.phase().active());
        d.open_device_dialog();
        d.tap(disconnect_pending_id().with("button"));
        assert!(d.s.state().device.is_some(), "the button only asks");
        assert!(!d.all.iter().any(|c| matches!(c, Command::DeviceDisconnect { .. })));
        d.tap(disconnect_pending_id().with("cancel"));
        assert!(d.phase().active() && d.s.state().device.is_some(), "Cancel changes nothing");
    }

    #[test]
    fn confirmed_disconnect_ends_the_session_then_disconnects() {
        let mut d = Drive::training();
        d.open_device_dialog();
        d.tap(disconnect_pending_id().with("button"));
        d.tap(disconnect_pending_id().with("confirm"));
        assert!(d.all.contains(&Command::DeviceDisconnect { end_session: true }));
        assert_eq!(d.phase(), nf_core::feedback::Phase::Ended);
        assert_eq!(d.s.trainer().summary.as_ref().map(|s| s.ended_by.as_str()), Some("device disconnected by the user"));
        assert!(d.s.state().device.is_none());
    }

    #[test]
    fn reconnect_prompt_offers_wait_or_end_and_never_ends_by_itself() {
        let mut d = Drive::training();
        d.s.call("sim.fault", json!({ "bad_pads": [], "dropout": true })).unwrap();
        d.s.call("clock.advance", json!({ "seconds": 20.0 })).unwrap();
        d.frame(vec![]);
        d.frame(vec![]);
        assert!(d.s.trainer().reconnect_prompt);
        d.tap(prompt_id().with("wait"));
        assert!(d.all.contains(&Command::FeedbackKeepWaiting));
        assert!(!d.s.trainer().reconnect_prompt && d.phase().active());
        // A later loss asks again; End session ends it.
        d.s.call("sim.fault", json!({ "bad_pads": [], "dropout": false })).unwrap();
        d.s.call("clock.advance", json!({ "seconds": 3.0 })).unwrap();
        d.s.call("sim.fault", json!({ "bad_pads": [], "dropout": true })).unwrap();
        d.s.call("clock.advance", json!({ "seconds": 20.0 })).unwrap();
        d.frame(vec![]);
        d.frame(vec![]);
        assert!(d.s.trainer().reconnect_prompt);
        d.tap(prompt_id().with("end"));
        assert_eq!(d.phase(), nf_core::feedback::Phase::Ended);
        assert!(d.s.state().device.is_some(), "ending the session does not disconnect");
    }
}
