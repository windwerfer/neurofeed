//! PSD monitor (Flutter `psd_view.dart`): one averaged spectrum of the
//! selected, analysis-eligible electrodes over the epoch (2/4/8 s, Follow /
//! Inspect), and the shared overview timeline below it (7:3, on by
//! default) with the epoch shaded (`ui::overview`). Spectra exist only for
//! the raw ring (last 5 min); older overview time is shaded.

use crate::ui::{monitor, overview, spectrum};
use egui::{Pos2, Rect, Sense, Ui};
use nf_core::monitor::{MonitorId, PsdRange, Span};
use nf_core::rawtrace as rt;
use nf_core::{Command, Session};

#[derive(Clone)]
struct Cached {
    key: (Vec<usize>, i64, i64),
    avg: Option<nf_core::spectrum::Averaged>,
}

/// Recompute at most every 1/8 s of epoch movement (Welch on ≤ 8 s × 8 ch).
fn cached(ui: &Ui, sig: &nf_core::signal::Signal, chans: &[usize], epoch: (f64, f64)) -> Option<nf_core::spectrum::Averaged> {
    let id = egui::Id::unique("nf-psd-cache");
    let key = (chans.to_vec(), (epoch.1 * 8.0).round() as i64, ((epoch.1 - epoch.0) * 8.0).round() as i64);
    if let Some(c) = ui.data(|d| d.get_temp::<Cached>(id)).filter(|c| c.key == key) {
        return c.avg;
    }
    let avg = nf_core::spectrum::average(sig, chans, epoch.0, epoch.1);
    ui.data_mut(|d| d.insert_temp(id, Cached { key, avg: avg.clone() }));
    avg
}

pub fn show(ui: &mut Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    let id = MonitorId::Psd;
    let vp = state.monitors.viewport(id);
    let live = session.live_signal();
    let channels: Vec<String> = live.map(|(d, _)| d.channels.clone()).unwrap_or_default();
    let span = live.and_then(|(_, s)| s.time).map(|t| Span::new((t - nf_core::signal::BUFFER_S).max(0.0), t));
    monitor::toolbar(ui, state, id, out, |ui, out| {
        if let Some(span) = span {
            monitor::inspect_label(ui, vp, span);
        }
        range_menu(ui, state.monitors.psd.range, out);
        ui.add_space(8.0);
        overview::toggle(ui, state, id, out);
        ui.add_space(8.0);
        let sel = state.monitors.psd.selected(&channels);
        monitor::channel_selector(ui, &channels, &sel, &state.analysis, true, out, |names| Command::MonitorPsd {
            range: None,
            electrodes: Some(names),
        });
    });
    let (Some((dev, sig)), Some(span)) = (live, span) else {
        ui.label(if live.is_none() { t!("plot-no-device-connected-use-connect") } else { t!("raw-waiting-for-data") });
        return;
    };
    let epoch = monitor::presented_range_lead(ui, state, id, vp, span, rt::RAW_FOLLOW_LEAD_S);
    let chans = state.analysis.eligible_of(&dev.channels, &state.monitors.psd.selected(&dev.channels));
    let max_hz = state.monitors.psd.range.max_hz();
    let full = ui.available_rect_before_wrap();
    let ov_h = overview::height(ui, state, id, full.height());
    let top = Rect::from_min_max(full.min, Pos2::new(full.right(), full.bottom() - ov_h));
    let avg = if chans.is_empty() { None } else { cached(ui, sig, &chans, epoch) };
    let db = avg.as_ref().map(nf_core::spectrum::Averaged::db);
    let curve = avg.as_ref().zip(db.as_ref()).map(|(a, db)| spectrum::Curve { db, df: a.df, peak_hz: a.peak(8.0, 13.0) });
    let empty = if chans.is_empty() { t!("channels-none-eligible") } else { t!("psd-no-segment") };
    let hid = egui::Id::unique("nf-psd-hairline");
    let hair = ui.data(|d| d.get_temp::<f64>(hid));
    if let Some(h) = spectrum::plot(ui, top, max_hz, curve.as_ref(), hair, &empty) {
        ui.data_mut(|d| d.insert_temp(hid, h));
    }
    ui.allocate_rect(top, Sense::hover());
    if ov_h > 0.0 {
        let host = overview::Host { id, range: epoch, detail_oldest: span.oldest_s, no_detail: t!("psd-strip-no-raw") };
        overview::show(ui, state, &chans, &host, ov_h, out);
    }
}

fn range_menu(ui: &mut Ui, cur: PsdRange, out: &mut Vec<Command>) {
    let label = |r: PsdRange| if r == PsdRange::Hz60 { "0–60 Hz" } else { "0–100 Hz" };
    egui::ComboBox::from_id_salt("nf-psd-range").selected_text(label(cur)).show_ui(ui, |ui| {
        for r in [PsdRange::Hz60, PsdRange::Hz100] {
            if ui.selectable_label(cur == r, label(r)).clicked() && cur != r {
                out.push(Command::MonitorPsd { range: Some(r), electrodes: None });
            }
        }
    });
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::panic)]
    use super::*;
    use egui::Vec2;

    fn cmd(id: &str, p: serde_json::Value) -> Command {
        match nf_core::Request::parse(id, p) {
            Ok(nf_core::Request::Command(c)) => c,
            _ => panic!("{id}"),
        }
    }

    fn frame(s: &mut Session, size: Vec2, layout: &str) -> Vec<Command> {
        let _lang = crate::i18n::lang_lock();
        let ctx = egui::Context::default();
        s.execute(cmd("settings.set", serde_json::json!({ "onboarded": true, "layout": layout }))).unwrap();
        let mut cmds = Vec::new();
        for i in 0..3 {
            let input = egui::RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, size)),
                time: Some(f64::from(i) / 60.0),
                ..Default::default()
            };
            ctx.run_ui(input, |u| cmds = crate::ui::show(u, s, None)).textures_delta.clear();
        }
        cmds
    }

    #[test]
    fn psd_renders_for_4_and_8_channels_all_layouts_and_no_eligible() {
        for dev in ["sim:muse", "sim:crown"] {
            let mut s = Session::new();
            for c in [
                cmd("device.connect", serde_json::json!({ "id": dev })),
                cmd("view.set", serde_json::json!({ "view": "psd" })),
                cmd("clock.advance", serde_json::json!({ "seconds": 20.0 })),
            ] {
                s.execute(c).unwrap();
            }
            for (size, layout) in
                [(Vec2::new(1200.0, 800.0), "regular"), (Vec2::new(400.0, 860.0), "compact"), (Vec2::new(860.0, 400.0), "compact")]
            {
                let out = frame(&mut s, size, layout);
                assert!(!out.iter().any(|c| matches!(c, Command::AnalysisExclude { .. })), "rendering never excludes");
            }
            let first = s.live_signal().unwrap().0.channels[0].clone();
            s.execute(cmd("monitor.psd", serde_json::json!({ "electrodes": [first] }))).unwrap();
            s.execute(cmd("analysis.exclude", serde_json::json!({ "channel": first, "confirm": true }))).unwrap();
            frame(&mut s, Vec2::new(1200.0, 800.0), "regular");
            // Display selection did not change the analysis state, and vice versa.
            assert_eq!(s.state().monitors.psd.electrodes, vec![first.clone()]);
            assert_eq!(s.state().analysis.excluded.len(), 1);
        }
    }
}
