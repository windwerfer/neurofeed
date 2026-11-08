//! Top bar: sidebar toggle, device area (opens the Device dialog), analysis
//! exclusions / quality hint, record, pause. The notch is in Settings → Devices.

use super::layout::{Layout, TOUCH};
use super::{device_dialog, quality, theme};
use nf_core::{AppState, Command, LinkState, Session};

pub fn show(root: &mut egui::Ui, session: &Session, error: Option<&str>, layout: Layout, out: &mut Vec<Command>) {
    if layout.is_compact() {
        compact(root, session, error, out);
        return;
    }
    let state = session.state();
    egui::Panel::top("topbar").exact_size(theme::TOPBAR_HEIGHT).show(root, |ui| {
        ui.horizontal_centered(|ui| {
            if ui.button("☰").on_hover_text(t!("topbar-toggle-sidebar")).clicked() {
                out.push(Command::SidebarSet { open: !state.sidebar_open });
            }
            device(ui, session, out);
            if let Some(e) = error {
                ui.colored_label(ui.visuals().error_fg_color, e);
            }
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                stream_controls(ui, state, out);
                signal_controls(ui, session, out);
            });
        });
    });
}

/// Compact top bar: ☰ (navigation drawer), device area (tap opens the Device dialog), error
/// glyph, and icon-only record / pause. Notch lives in Settings → Devices.
fn compact(root: &mut egui::Ui, session: &Session, error: Option<&str>, out: &mut Vec<Command>) {
    let state = session.state();
    egui::Panel::top("topbar").exact_size(TOUCH).show(root, |ui| {
        ui.horizontal_centered(|ui| {
            if ui.add_sized([TOUCH, TOUCH - 8.0], egui::Button::new("☰")).on_hover_text(t!("topbar-menu")).clicked() {
                let open = super::sidebar::drawer_open(ui.ctx());
                super::sidebar::set_drawer(ui.ctx(), !open);
            }
            device(ui, session, out);
            if let Some(e) = error {
                ui.colored_label(ui.visuals().error_fg_color, "⚠").on_hover_text(e);
            }
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                analysis_chips(ui, session, out, true);
                record_controls(ui, state, out, true);
                if pause_visible(state) {
                    let (icon, cmd) = if state.paused { ("▶", Command::StreamResume) } else { ("⏸", Command::StreamPause) };
                    if ui.add_sized([TOUCH, TOUCH - 8.0], egui::Button::new(icon)).on_hover_text(t!("topbar-pause-resume")).clicked() {
                        out.push(cmd);
                    }
                }
            });
        });
    });
}

/// Device area: `[ Connect device ]` when disconnected; else
/// `Muse S · <name>`, pad quality glyphs, battery, and a green LSL/OSC dot
/// while a stream server runs. Any click opens the Device dialog.
fn device(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    let open = Command::DeviceDialog { open: true };
    let Some(d) = &state.device else {
        if ui.button(t!("topbar-connect-device")).clicked() {
            out.push(open);
        }
        return;
    };
    let area = ui.horizontal(|ui| {
        ui.label(device_dialog::label(d));
        match &state.link {
            Some(LinkState::Connecting) => {
                ui.spinner();
                ui.weak(t!("topbar-connecting"));
            }
            Some(LinkState::Lost { reason }) => {
                ui.colored_label(ui.visuals().error_fg_color, reason);
            }
            _ => {
                quality::row(ui, &device_dialog::scores(session), d.channels.len(), device_dialog::shown_aux(session, d));
            }
        }
        if let Some(b) = state.battery {
            ui.label(format!("{b:.0}%")).on_hover_text(t!("topbar-battery"));
        }
        if let Some(proto) = state.streaming.running() {
            let (r, _) = ui.allocate_exact_size(egui::vec2(10.0, 10.0), egui::Sense::hover());
            ui.painter().circle_filled(r.center(), 4.5, theme::STREAM_ON);
            ui.weak(proto);
        }
    });
    let r = ui.interact(area.response.rect, egui::Id::unique("device-area"), egui::Sense::click());
    if r.on_hover_cursor(egui::CursorIcon::PointingHand).on_hover_text(t!("topbar-device")).clicked() {
        out.push(open);
    }
}

/// Record (red dot) / stop, and Pause immediately left of it — shown only
/// while a recording runs (manual or feedback auto-recording) or while
/// paused (so Resume stays reachable). Pause keeps its meaning (`stream.pause`:
/// freezes the views' incoming band data; acquisition and the recording
/// continue). Right-to-left order. The session clock moved to the debug
/// overlay.
fn stream_controls(ui: &mut egui::Ui, state: &AppState, out: &mut Vec<Command>) {
    record_controls(ui, state, out, false);
    if pause_visible(state) {
        let label = if state.paused { t!("topbar-resume") } else { t!("topbar-pause") };
        if ui.button(label).on_hover_text(t!("topbar-pause-resume")).clicked() {
            out.push(if state.paused { Command::StreamResume } else { Command::StreamPause });
        }
    }
}

/// After Stop, Record and Discard ignore input this long (a double tap on
/// Stop must neither delete nor restart, whatever moved under the finger).
pub const STOP_GUARD_S: f64 = 0.8;

fn stop_id() -> egui::Id {
    egui::Id::unique("nf-recording-stopped-at")
}

pub fn discard_pending_id() -> egui::Id {
    egui::Id::unique("nf-discard-pending")
}

/// Stop / Record in one fixed slot (rightmost of the group), Discard
/// always to its LEFT (never where Stop was). Laid out right-to-left.
fn record_controls(ui: &mut egui::Ui, state: &AppState, out: &mut Vec<Command>, compact: bool) {
    let h = if compact { TOUCH - 8.0 } else { 22.0 };
    let now = ui.input(|i| i.time);
    let stopped_at = ui.ctx().data(|d| d.get_temp::<f64>(stop_id()));
    let press = ui.input(|i| i.pointer.press_start_time());
    // Armed only for presses that began after the guard window: a second
    // tap of a double tap (or a press held over the Stop) cannot act.
    let armed = stopped_at.is_none_or(|t| now - t >= STOP_GUARD_S && press.is_none_or(|p| p >= t + STOP_GUARD_S));
    if !armed {
        ui.ctx().request_repaint_after(std::time::Duration::from_millis(100));
    }
    if let Some(r) = state.recording.as_ref().filter(|r| r.active) {
        let label = if compact { format!("⏹ {:.0}s", r.duration) } else { t!("topbar-stop-recording", s = format!("{:.0}", r.duration)) };
        let b = ui.add(egui::Button::new(label).min_size(egui::vec2(if compact { TOUCH + 24.0 } else { 0.0 }, h)));
        ui.ctx().data_mut(|d| d.insert_temp(stop_id().with("rect"), b.rect));
        if b.clicked() {
            out.push(Command::RecordingStop);
            ui.ctx().data_mut(|d| d.insert_temp(stop_id(), now));
        }
        return;
    }
    let rec = ui.add_enabled_ui(armed, |ui| record_dot(ui, state.device.is_some(), h)).inner;
    if rec.clicked() && armed {
        out.push(Command::RecordingStart { wall_clock_unix_ms: None });
    }
    // The last recording is saved; Discard stays available (left of
    // Record) until the next recording.
    let saved = state.recording.as_ref().and_then(|r| r.saved_id).filter(|id| state.history.iter().any(|h| h.id == *id));
    if let Some(id) = saved {
        ui.add_space(if compact { 10.0 } else { 6.0 });
        let b = ui
            .add_enabled(armed, egui::Button::new(t!("topbar-discard-last-recording")).min_size(egui::vec2(0.0, h)))
            .on_hover_text(t!("topbar-it-was-saved-to-history"));
        ui.ctx().data_mut(|d| d.insert_temp(discard_pending_id().with("rect"), b.rect));
        if b.clicked() && armed {
            if state.settings.confirm_discard {
                ui.ctx().data_mut(|d| d.insert_temp(discard_pending_id(), (id, false)));
            } else {
                out.push(Command::HistoryDelete { id, confirm: true });
            }
        }
    }
}

/// "Discard this recording?" (Cancel is the default; Escape / outside
/// click cancel). Deletes exactly the recording that was asked about.
/// "Don't ask again" is saved only together with an explicit Discard.
pub fn confirm_discard(ctx: &egui::Context, state: &AppState, out: &mut Vec<Command>) {
    let Some((id, mut dont_ask)) = ctx.data(|d| d.get_temp::<(u64, bool)>(discard_pending_id())) else { return };
    let Some(meta) = state.history.iter().find(|h| h.id == id) else {
        ctx.data_mut(|d| d.remove::<(u64, bool)>(discard_pending_id()));
        return;
    };
    let mut done = false;
    let r = egui::Modal::new(egui::Id::unique("nf-discard-confirm")).show(ctx, |ui| {
        ui.set_max_width(360.0);
        ui.strong(t!("discard-title"));
        ui.label(t!("discard-body", device = meta.device_name.clone(), s = format!("{:.0}", meta.duration_s)));
        let cb = ui.checkbox(&mut dont_ask, t!("discard-dont-ask"));
        ui.ctx().data_mut(|d| d.insert_temp(discard_pending_id().with("dont_ask"), cb.rect));
        ui.add_space(6.0);
        ui.horizontal(|ui| {
            let cancel = ui.button(t!("discard-cancel"));
            ui.ctx().data_mut(|d| d.insert_temp(discard_pending_id().with("cancel"), cancel.rect));
            if !ui.memory(|m| m.focused().is_some()) {
                cancel.request_focus();
            }
            if cancel.clicked() {
                done = true;
            }
            let red = egui::RichText::new(t!("discard-confirm")).color(egui::Color32::WHITE);
            let confirm = ui.add(egui::Button::new(red).fill(theme::RECORD_RED));
            ui.ctx().data_mut(|d| d.insert_temp(discard_pending_id().with("confirm"), confirm.rect));
            if confirm.clicked() {
                out.push(Command::HistoryDelete { id, confirm: true });
                if dont_ask {
                    out.push(Command::SettingsSet(nf_core::settings::SettingsPatch { confirm_discard: Some(false), ..Default::default() }));
                }
                done = true;
            }
        });
    });
    if done || r.should_close() {
        ctx.data_mut(|d| d.remove::<(u64, bool)>(discard_pending_id()));
    } else {
        ctx.data_mut(|d| d.insert_temp(discard_pending_id(), (id, dont_ask)));
    }
}

/// Pause only while recording (or to Resume a pause).
pub fn pause_visible(state: &AppState) -> bool {
    state.paused || state.recording.as_ref().is_some_and(|r| r.active)
}

/// The Record button: a red dot, no text (tooltip names it).
/// "● Record": only the dot is red (painted, the font has no ● glyph); the
/// label keeps the normal text colour. `h` = button height (touch on mobile).
fn record_dot(ui: &mut egui::Ui, enabled: bool, h: f32) -> egui::Response {
    let label = format!("     {}", t!("topbar-record"));
    let r = ui.add_enabled(enabled, egui::Button::new(label).min_size(egui::vec2(28.0, h))).on_hover_text(t!("topbar-record-tip"));
    let col = if enabled { theme::RECORD_RED } else { theme::RECORD_RED.gamma_multiply(0.4) };
    ui.painter().circle_filled(egui::pos2(r.rect.left() + 13.0, r.rect.center().y), 5.5, col);
    r
}

/// Usable-pad count, analysis exclusions and the contact-quality hint.
/// (Notch moved to Settings → Devices only, owner 2026-11-07.)
fn signal_controls(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let Some((_, sig)) = session.live_signal() else { return };
    analysis_chips(ui, session, out, false);
    let good = (0..sig.quality.len()).filter(|&i| sig.usable(i)).count();
    ui.weak(t!("topbar-pads", good = good, total = sig.quality.len()));
}

/// `⊘ 1 excluded` (opens the Device dialog) and the dismissible hint.
fn analysis_chips(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>, compact: bool) {
    let a = &session.state().analysis;
    if let Some(ch) = &a.hint.active {
        if ui.small_button("×").on_hover_text(t!("analysis-hint-dismiss")).clicked() {
            out.push(Command::AnalysisHintDismiss);
        }
        let text = if compact { format!("⚠ {ch}") } else { t!("analysis-hint", channel = ch.clone()) };
        let b = ui.add(egui::Button::new(egui::RichText::new(text).color(ui.visuals().warn_fg_color)).small());
        if b.on_hover_text(t!("analysis-hint-tip", channel = ch.clone())).clicked() {
            device_dialog::highlight(ui.ctx(), ch);
            out.push(Command::DeviceDialog { open: true });
        }
    }
    if !a.excluded.is_empty() {
        let names: Vec<&str> = a.excluded.iter().map(String::as_str).collect();
        let text = if compact { t!("analysis-excluded-short", n = names.len()) } else { t!("analysis-excluded-count", n = names.len()) };
        if ui.small_button(text).on_hover_text(t!("analysis-excluded-tip", channels = names.join(", "))).clicked() {
            out.push(Command::DeviceDialog { open: true });
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use serde_json::json;

    #[test]
    fn pause_shows_only_while_recording_or_paused() {
        let mut s = Session::new();
        s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
        s.call("clock.advance", json!({ "seconds": 2.0 })).unwrap();
        assert!(!pause_visible(s.state()));
        s.call("recording.start", json!({})).unwrap();
        assert!(pause_visible(s.state()));
        s.call("stream.pause", json!({})).unwrap();
        s.call("recording.stop", json!({})).unwrap();
        assert!(pause_visible(s.state()), "Resume stays reachable");
        s.call("stream.resume", json!({})).unwrap();
        assert!(!pause_visible(s.state()));
    }

    // ---- Destructive Discard flow (owner 2026-11-08). Synthetic egui input
    // on an in-memory store only: no user recording is ever touched.

    struct Drive {
        ctx: egui::Context,
        t: f64,
        s: Session,
        size: egui::Vec2,
        all: Vec<Command>,
        _lang: std::sync::MutexGuard<'static, ()>,
    }

    impl Drive {
        fn new(compact: bool, confirm: bool) -> Self {
            let _lang = crate::i18n::lang_lock();
            let mut s = Session::new();
            let layout = if compact { "compact" } else { "regular" };
            s.call("settings.set", json!({ "onboarded": true, "layout": layout, "confirm_discard": confirm })).unwrap();
            s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
            s.call("clock.advance", json!({ "seconds": 2.0 })).unwrap();
            let size = if compact { egui::vec2(400.0, 850.0) } else { egui::vec2(1200.0, 800.0) };
            let mut d = Drive { ctx: egui::Context::default(), t: 0.0, s, size, all: Vec::new(), _lang };
            d.frame(vec![], 0.1);
            d
        }
        fn frame(&mut self, events: Vec<egui::Event>, dt: f64) {
            self.t += dt;
            let input = egui::RawInput {
                screen_rect: Some(egui::Rect::from_min_size(egui::Pos2::ZERO, self.size)),
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
        fn button(pos: egui::Pos2, pressed: bool) -> egui::Event {
            egui::Event::PointerButton { pos, button: egui::PointerButton::Primary, pressed, modifiers: egui::Modifiers::NONE }
        }
        /// A quick tap (press + release 1 frame apart), then a settle frame.
        fn tap(&mut self, pos: egui::Pos2) {
            self.frame(vec![egui::Event::PointerMoved(pos), Self::button(pos, true)], 1.0 / 60.0);
            self.frame(vec![Self::button(pos, false)], 1.0 / 60.0);
            self.frame(vec![], 1.0 / 60.0);
        }
        fn rect(&self, id: egui::Id) -> egui::Rect {
            self.ctx.data(|d| d.get_temp::<egui::Rect>(id)).unwrap_or_else(|| panic!("no rect {id:?}"))
        }
        fn pending(&self) -> bool {
            self.ctx.data(|d| d.get_temp::<(u64, bool)>(discard_pending_id())).is_some()
        }
        fn deletes(&self) -> Vec<u64> {
            self.all.iter().filter_map(|c| if let Command::HistoryDelete { id, .. } = c { Some(*id) } else { None }).collect()
        }
        fn starts(&self) -> usize {
            self.all.iter().filter(|c| matches!(c, Command::RecordingStart { .. })).count()
        }
        fn history(&self) -> Vec<u64> {
            self.s.state().history.iter().map(|h| h.id).collect()
        }
        fn saved(&self) -> u64 {
            self.s.state().recording.as_ref().and_then(|r| r.saved_id).unwrap()
        }
        /// Record ~3 s, tap Stop, then wait past the guard.
        fn record(&mut self) -> u64 {
            self.s.call("recording.start", json!({})).unwrap();
            self.s.call("clock.advance", json!({ "seconds": 3.0 })).unwrap();
            self.frame(vec![], 0.1);
            let stop = self.rect(stop_id().with("rect")).center();
            self.tap(stop);
            assert!(self.all.iter().any(|c| matches!(c, Command::RecordingStop)));
            self.frame(vec![], STOP_GUARD_S + 0.1);
            self.saved()
        }
        fn discard_rect(&self) -> egui::Rect {
            self.rect(discard_pending_id().with("rect"))
        }
    }

    fn double_tap_on_stop_cannot_discard(compact: bool, confirm: bool) {
        let mut d = Drive::new(compact, confirm);
        d.s.call("recording.start", json!({})).unwrap();
        d.s.call("clock.advance", json!({ "seconds": 3.0 })).unwrap();
        d.frame(vec![], 0.1);
        let stop = d.rect(stop_id().with("rect"));
        d.tap(stop.center());
        assert!(d.all.iter().any(|c| matches!(c, Command::RecordingStop)), "first tap stops");
        let id = d.saved();
        // Discard is left of Record, never over the old Stop hit region.
        let discard = d.discard_rect();
        assert!(!discard.intersects(stop), "discard {discard:?} vs stop {stop:?}");
        assert!(discard.right() <= stop.left() + 1.0, "discard is to the left");
        // Second (and third) tap at the same coordinates, then a tap right
        // on Discard, all within the guard.
        d.tap(stop.center());
        d.tap(stop.center());
        d.tap(discard.center());
        assert!(d.t < 1.0 + STOP_GUARD_S, "taps happened inside the guard");
        assert!(d.deletes().is_empty() && !d.pending(), "no delete, no dialog: {:?}", d.all);
        assert_eq!(d.starts(), 0, "no accidental new recording either");
        assert!(d.history().contains(&id));
    }

    #[test]
    fn stop_then_immediate_second_tap_cannot_discard_desktop() {
        double_tap_on_stop_cannot_discard(false, true);
    }

    #[test]
    fn stop_then_immediate_second_tap_cannot_discard_compact() {
        double_tap_on_stop_cannot_discard(true, true);
    }

    #[test]
    fn opted_out_confirmation_is_still_double_tap_protected() {
        double_tap_on_stop_cannot_discard(false, false);
        double_tap_on_stop_cannot_discard(true, false);
        // After the guard, opt-out deletes directly (only that recording).
        let mut d = Drive::new(true, false);
        let id = d.record();
        let r = d.discard_rect();
        d.tap(r.center());
        assert_eq!(d.deletes(), vec![id]);
        assert!(!d.pending() && !d.history().contains(&id));
    }

    #[test]
    fn cancel_and_escape_delete_nothing_and_keep_the_preference() {
        for escape in [false, true] {
            let mut d = Drive::new(false, true);
            let id = d.record();
            let r = d.discard_rect();
            d.tap(r.center());
            assert!(d.pending(), "dialog opens instead of deleting");
            assert!(d.deletes().is_empty());
            // Tick "Don't ask again", then back out.
            let cb = d.rect(discard_pending_id().with("dont_ask"));
            d.tap(cb.center());
            assert_eq!(d.ctx.data(|x| x.get_temp::<(u64, bool)>(discard_pending_id())), Some((id, true)));
            if escape {
                let key = |pressed| egui::Event::Key {
                    key: egui::Key::Escape,
                    physical_key: None,
                    pressed,
                    repeat: false,
                    modifiers: egui::Modifiers::NONE,
                };
                d.frame(vec![key(true)], 1.0 / 60.0);
                d.frame(vec![key(false)], 1.0 / 60.0);
                d.frame(vec![], 1.0 / 60.0);
            } else {
                let c = d.rect(discard_pending_id().with("cancel"));
                d.tap(c.center());
            }
            assert!(!d.pending(), "closed (escape={escape})");
            assert!(d.deletes().is_empty() && d.history().contains(&id));
            assert!(d.s.state().settings.confirm_discard, "preference unchanged (escape={escape})");
            assert!(!d.all.iter().any(|c| matches!(c, Command::SettingsSet(_))));
        }
    }

    #[test]
    fn cancel_is_the_default_focus() {
        let mut d = Drive::new(false, true);
        let id = d.record();
        let r = d.discard_rect();
        d.tap(r.center());
        let key = |pressed| egui::Event::Key {
            key: egui::Key::Enter,
            physical_key: None,
            pressed,
            repeat: false,
            modifiers: egui::Modifiers::NONE,
        };
        d.frame(vec![key(true)], 1.0 / 60.0);
        d.frame(vec![key(false)], 1.0 / 60.0);
        d.frame(vec![], 1.0 / 60.0);
        assert!(d.deletes().is_empty() && d.history().contains(&id), "Enter activates Cancel, never Discard");
    }

    #[test]
    fn confirm_discards_only_the_target_and_dont_ask_persists_only_on_confirm() {
        let mut d = Drive::new(false, true);
        let a = d.record();
        let b = d.record();
        assert_ne!(a, b);
        // Confirm without "Don't ask again": only B goes, preference stays.
        d.tap(d.discard_rect().center());
        d.tap(d.rect(discard_pending_id().with("confirm")).center());
        assert_eq!(d.deletes(), vec![b]);
        assert!(d.history().contains(&a) && !d.history().contains(&b));
        assert!(d.s.state().settings.confirm_discard);
        // C with "Don't ask again" ticked + Discard: C goes, opt-out saved.
        let c = d.record();
        d.tap(d.discard_rect().center());
        d.tap(d.rect(discard_pending_id().with("dont_ask")).center());
        d.tap(d.rect(discard_pending_id().with("confirm")).center());
        assert_eq!(d.deletes(), vec![b, c]);
        assert!(d.history().contains(&a));
        assert!(!d.s.state().settings.confirm_discard);
        let doc = d.s.store().get_doc(nf_core::settings::DOC_KEY).unwrap().unwrap();
        let mut store = nf_store::MemoryStore::default();
        nf_store::Store::put_doc(&mut store, nf_core::settings::DOC_KEY, Some(&doc)).unwrap();
        let again = Session::new().with_store(Box::new(store));
        assert!(!again.state().settings.confirm_discard, "opt-out persisted");
    }

    #[test]
    fn older_settings_without_the_field_default_to_asking() {
        let s = Session::new();
        assert!(s.state().settings.confirm_discard);
        let doc = s.store().get_doc(nf_core::settings::DOC_KEY).unwrap();
        let mut v: serde_json::Value = doc.map_or(json!({}), |d| serde_json::from_str(&d).unwrap());
        if let Some(u) = v.get_mut("user").and_then(|u| u.as_object_mut()) {
            u.remove("confirm_discard");
        }
        v["user"]["onboarded"] = json!(true);
        assert!(v["user"].get("confirm_discard").is_none());
        let mut store = nf_store::MemoryStore::default();
        nf_store::Store::put_doc(&mut store, nf_core::settings::DOC_KEY, Some(&v.to_string())).unwrap();
        let old = Session::new().with_store(Box::new(store));
        assert!(old.state().settings.onboarded, "old doc was actually loaded");
        assert!(old.state().settings.confirm_discard);
    }
}
