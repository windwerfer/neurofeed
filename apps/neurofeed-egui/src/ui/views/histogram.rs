//! Histogram monitor (Flutter `histogram_view.dart`): one pane of the
//! **pooled** amplitude distribution of the selected, analysis-eligible
//! electrodes over the epoch (2/4/8 s, Follow / Inspect over the 5 min raw
//! ring), µV range menu (±50/100/200), tap / cursor hairline readout, and
//! the shared overview timeline (off by default).
//!
//! Pooling (`nf_core::spectrum::histogram_pooled`): every valid sample of
//! every selected pad, each pad's window mean removed. Waveforms are not
//! averaged first (that would cancel opposite-phase signals silently).

use crate::ui::{monitor, overview, theme};
use egui::{Align2, FontId, Pos2, Rect, Sense, Stroke, Ui};
use nf_core::monitor::{HistRange, MonitorId, Span};
use nf_core::rawtrace as rt;
use nf_core::spectrum::Pooled;
use nf_core::{Command, Session};

pub const BINS: usize = 64;

#[derive(Clone)]
struct Cached {
    key: (Vec<usize>, i64, i64, i64),
    pooled: Option<Pooled>,
}

/// Recompute at most every 1/8 s of epoch movement.
fn cached(ui: &Ui, sig: &nf_core::signal::Signal, chans: &[usize], epoch: (f64, f64), half: f64) -> Option<Pooled> {
    let id = egui::Id::unique("nf-hist-cache");
    let key = (chans.to_vec(), (epoch.1 * 8.0).round() as i64, ((epoch.1 - epoch.0) * 8.0).round() as i64, half as i64);
    if let Some(c) = ui.data(|d| d.get_temp::<Cached>(id)).filter(|c| c.key == key) {
        return c.pooled;
    }
    let pooled = nf_core::spectrum::histogram_pooled(sig, chans, epoch.0, epoch.1, BINS, half);
    ui.data_mut(|d| d.insert_temp(id, Cached { key, pooled: pooled.clone() }));
    pooled
}

pub fn show(ui: &mut Ui, session: &Session, out: &mut Vec<Command>) {
    let state = session.state();
    let id = MonitorId::Histogram;
    let vp = state.monitors.viewport(id);
    let live = session.live_signal();
    let channels: Vec<String> = live.map(|(d, _)| d.channels.clone()).unwrap_or_default();
    let span = live.and_then(|(_, s)| s.time).map(|t| Span::new((t - nf_core::signal::BUFFER_S).max(0.0), t));
    monitor::toolbar(ui, state, id, out, |ui, out| {
        if let Some(span) = span {
            monitor::inspect_label(ui, vp, span);
        }
        range_menu(ui, state.monitors.histogram.range, out);
        ui.add_space(8.0);
        let sel = state.monitors.histogram.selected(&channels);
        monitor::channel_selector(ui, &channels, &sel, &state.analysis, true, out, |names| Command::MonitorHistogram {
            range: None,
            electrodes: Some(names),
        });
        ui.add_space(8.0);
        overview::toggle(ui, state, id, out);
    });
    let (Some((dev, sig)), Some(span)) = (live, span) else {
        ui.label(if live.is_none() { t!("plot-no-device-connected-use-connect") } else { t!("raw-waiting-for-data") });
        return;
    };
    let epoch = monitor::presented_range_lead(ui, state, id, vp, span, rt::RAW_FOLLOW_LEAD_S);
    let chans = state.analysis.eligible_of(&dev.channels, &state.monitors.histogram.selected(&dev.channels));
    let half = state.monitors.histogram.range.half_uv();
    let full = ui.available_rect_before_wrap();
    let ov_h = overview::height(ui, state, id, full.height());
    let top = Rect::from_min_max(full.min, Pos2::new(full.right(), full.bottom() - ov_h));
    let pooled = if chans.is_empty() { None } else { cached(ui, sig, &chans, epoch, half) };
    let empty = if chans.is_empty() { t!("channels-none-eligible") } else { t!("histogram-no-samples") };
    plot(ui, top, half, pooled.as_ref(), &empty);
    if ov_h > 0.0 {
        let host = overview::Host { id, range: epoch, detail_oldest: span.oldest_s, no_detail: t!("overview-no-raw") };
        overview::show(ui, state, &chans, &host, ov_h, out);
    }
}

fn range_menu(ui: &mut Ui, cur: HistRange, out: &mut Vec<Command>) {
    let label = |r: HistRange| format!("±{:.0} µV", r.half_uv());
    egui::ComboBox::from_id_salt("nf-hist-range").selected_text(label(cur)).show_ui(ui, |ui| {
        for r in HistRange::ALL {
            if ui.selectable_label(cur == r, label(r)).clicked() && cur != r {
                out.push(Command::MonitorHistogram { range: Some(r), electrodes: None });
            }
        }
    });
}

/// Share of samples (%) per bin; the Y axis is fitted in 5 % steps.
pub fn shares(p: &Pooled) -> Vec<f64> {
    let n = p.samples.max(1) as f64;
    p.counts.iter().map(|&c| f64::from(c) * 100.0 / n).collect()
}

fn plot(ui: &mut Ui, rect: Rect, half: f64, pooled: Option<&Pooled>, empty: &str) {
    let resp = ui.allocate_rect(rect, Sense::click_and_drag());
    let plot = Rect::from_min_max(rect.left_top() + egui::vec2(40.0, 16.0), rect.right_bottom() - egui::vec2(8.0, 18.0));
    let v = ui.visuals().clone();
    let p = ui.painter_at(rect);
    let x_of = |uv: f64| plot.left() + (((uv + half) / (2.0 * half)).clamp(0.0, 1.0) as f32) * plot.width();
    for k in -2..=2 {
        let uv = half * f64::from(k) / 2.0;
        let x = x_of(uv);
        p.line_segment([Pos2::new(x, plot.top()), Pos2::new(x, plot.bottom())], theme::grid(&v));
        p.text(Pos2::new(x, plot.bottom() + 2.0), Align2::CENTER_TOP, format!("{uv:.0}"), FontId::proportional(10.0), theme::axis_text(&v));
    }
    p.text(
        Pos2::new(plot.right() - 2.0, plot.bottom() - 2.0),
        Align2::RIGHT_BOTTOM,
        "µV",
        FontId::proportional(10.0),
        theme::axis_text(&v),
    );
    let Some(pl) = pooled else {
        p.text(plot.center(), Align2::CENTER_CENTER, empty, FontId::proportional(14.0), v.weak_text_color());
        return;
    };
    let sh = shares(pl);
    let top = (sh.iter().copied().fold(0.0, f64::max) / 5.0).ceil().max(1.0) * 5.0;
    let y_of = |s: f64| plot.bottom() - ((s / top).clamp(0.0, 1.0) as f32) * plot.height();
    let step = if top > 20.0 { 10.0 } else { 5.0 };
    let mut y = 0.0;
    while y <= top + 1e-9 {
        let sy = y_of(y);
        p.line_segment([Pos2::new(plot.left(), sy), Pos2::new(plot.right(), sy)], theme::grid(&v));
        p.text(Pos2::new(plot.left() - 6.0, sy), Align2::RIGHT_CENTER, format!("{y:.0}"), FontId::proportional(10.0), theme::axis_text(&v));
        y += step;
    }
    p.text(
        Pos2::new(plot.left() - 36.0, plot.top() - 14.0),
        Align2::LEFT_TOP,
        t!("histogram-y-unit"),
        FontId::proportional(10.0),
        theme::axis_text(&v),
    );
    let bw = plot.width() / BINS as f32;
    let fill = theme::band_color(nf_core::Band::Alpha);
    for (i, s) in sh.iter().enumerate() {
        let x = plot.left() + i as f32 * bw;
        p.rect_filled(Rect::from_min_max(Pos2::new(x + 0.5, y_of(*s)), Pos2::new(x + bw - 0.5, plot.bottom())), 0.0, fill);
    }
    let info = t!("histogram-info", std = format!("{:.1}", pl.std_uv), n = pl.channels.len(), samples = pl.samples);
    p.text(Pos2::new(plot.right() - 4.0, plot.top() + 4.0), Align2::RIGHT_TOP, info, FontId::proportional(11.0), v.text_color());
    // Hairline: tap / drag / hover sets it; kept until the next tap.
    let hid = egui::Id::unique("nf-hist-hairline");
    if let Some(q) = resp.interact_pointer_pos().or_else(|| resp.hover_pos()).filter(|q| plot.contains(*q)) {
        let uv = f64::from((q.x - plot.left()) / plot.width()) * 2.0 * half - half;
        ui.data_mut(|d| d.insert_temp(hid, uv));
    }
    if let Some(uv) = ui.data(|d| d.get_temp::<f64>(hid)).filter(|u| u.abs() <= half) {
        let b = (((uv + half) / (2.0 * half) * BINS as f64).floor() as usize).min(BINS - 1);
        let lo = -half + b as f64 * 2.0 * half / BINS as f64;
        let hi = lo + 2.0 * half / BINS as f64;
        let x = x_of(uv);
        p.line_segment([Pos2::new(x, plot.top()), Pos2::new(x, plot.bottom())], Stroke::new(1.0, v.strong_text_color()));
        let text = t!("histogram-readout", lo = format!("{lo:.1}"), hi = format!("{hi:.1}"), share = format!("{:.1}", sh[b]));
        let al = if x > plot.center().x { Align2::RIGHT_TOP } else { Align2::LEFT_TOP };
        let dx = if x > plot.center().x { -6.0 } else { 6.0 };
        p.text(Pos2::new(x + dx, plot.top() + 22.0), al, text, FontId::proportional(11.0), v.strong_text_color());
    }
}

#[cfg(test)]
pub(crate) mod tests {
    #![allow(clippy::unwrap_used)]
    use nf_core::Session;
    use serde_json::json;

    /// All painted text of one frame of `view`.
    pub(crate) fn texts(s: &Session, view: impl Fn(&mut egui::Ui, &Session)) -> Vec<String> {
        let ctx = egui::Context::default();
        let mut t = Vec::new();
        for i in 0..2 {
            let input = egui::RawInput {
                screen_rect: Some(egui::Rect::from_min_size(egui::Pos2::ZERO, egui::vec2(1000.0, 800.0))),
                time: Some(f64::from(i) / 60.0),
                ..Default::default()
            };
            let mut out = ctx.run_ui(input, |u| view(u, s));
            out.textures_delta.clear();
            t.clear();
            for c in out.shapes {
                if let egui::Shape::Text(x) = c.shape {
                    t.push(x.galley.text().to_owned());
                }
            }
        }
        t
    }

    fn show(u: &mut egui::Ui, s: &Session) {
        super::show(u, s, &mut Vec::new());
    }

    #[test]
    fn pooled_pane_no_eligible_and_range() {
        let _lang = crate::i18n::lang_lock();
        let mut s = Session::new();
        s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
        s.call("clock.advance", json!({ "seconds": 10.0 })).unwrap();
        let t = texts(&s, show);
        assert!(t.iter().any(|x| x.contains("σ")), "{t:?}");
        assert!(t.iter().any(|x| x == "-100") && t.iter().any(|x| x == "100"), "{t:?}");
        s.call("monitor.histogram", json!({ "range": "200" })).unwrap();
        assert!(texts(&s, show).iter().any(|x| x == "200"));
        for c in ["TP9", "AF7", "AF8", "TP10"] {
            s.call("analysis.exclude", json!({ "channel": c, "confirm": true })).unwrap();
        }
        let t = texts(&s, show);
        assert!(t.contains(&t!("channels-none-eligible")) && !t.iter().any(|x| x.contains("σ")), "{t:?}");
    }
}
