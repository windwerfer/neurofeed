//! Bands view: band power over the last minute (legacy layout: average of
//! the chosen electrodes, one line per visible band), or per-channel bars.

use crate::ui::theme;
use egui::{Align2, Color32, FontId, Pos2, Rect, Sense, Stroke, Vec2};
use std::cell::RefCell;

/// View-local chips (not app state, like legacy): over-time vs bars,
/// electrodes in the average (bit mask) and visible bands.
#[derive(Clone, Copy)]
struct Chips {
    over_time: bool,
    electrodes: u32,
    bands: [bool; 5],
}

thread_local! {
    static CHIPS: RefCell<Chips> = const { RefCell::new(Chips { over_time: true, electrodes: u32::MAX, bands: [true; 5] }) };
}
use nf_core::{AppState, Band, BandHistory, BandScale, BandSnapshot, Command};

/// Display range for absolute log10 band power (µV²).
const ABS_MIN: f32 = -1.0;
const ABS_MAX: f32 = 3.0;

pub fn show(ui: &mut egui::Ui, state: &AppState, out: &mut Vec<Command>) {
    ui.horizontal(|ui| {
        ui.heading(t!("bands-band-powers"));
        if state.device.as_ref().is_some_and(|d| d.simulated) {
            ui.weak(t!("bands-simulated-data"));
        }
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            for (scale, label) in [(BandScale::Relative, t!("bands-relative")), (BandScale::Absolute, t!("bands-absolute-log"))] {
                if ui.selectable_label(state.band_scale == scale, label).clicked() {
                    out.push(Command::ScaleSet { scale });
                }
            }
        });
    });
    let mut chips = CHIPS.with(|c| *c.borrow());
    ui.horizontal(|ui| {
        for (v, label) in [(true, t!("bands-over-time")), (false, t!("bands-bars"))] {
            if ui.selectable_label(chips.over_time == v, label).clicked() {
                chips.over_time = v;
            }
        }
        ui.separator();
        if chips.over_time {
            if let Some(d) = &state.device {
                ui.weak(t!("bands-average-of"));
                for (i, name) in d.channels.iter().enumerate().take(32) {
                    let on = chips.electrodes & (1 << i) != 0;
                    let others = chips.electrodes & !(1 << i) & ((1u32 << d.channels.len().min(31)) - 1);
                    if ui.selectable_label(on, name).clicked() && (!on || others != 0) {
                        chips.electrodes ^= 1 << i;
                    }
                }
            }
        }
    });
    legend(ui, chips.over_time.then_some(&mut chips.bands));
    CHIPS.with(|c| *c.borrow_mut() = chips);
    ui.separator();

    let Some(device) = &state.device else {
        ui.label(t!("bands-no-device-connected-use-connect"));
        return;
    };
    let Some(snapshot) = state.bands.latest() else {
        ui.label(t!("bands-waiting-for-data"));
        return;
    };

    if chips.over_time {
        over_time(ui, state, device.channels.len(), chips);
        return;
    }
    let n = device.channels.len().max(1);
    let avail = ui.available_size();
    let cols = if avail.x > 700.0 { n.min(4) } else { n.min(2) };
    let rows = n.div_ceil(cols);
    let gap = 12.0;
    let cell =
        Vec2::new((avail.x - gap * (cols as f32 - 1.0)) / cols as f32, ((avail.y - gap * (rows as f32 - 1.0)) / rows as f32).max(120.0));

    egui::Grid::new("bands_grid").spacing([gap, gap]).show(ui, |ui| {
        for (ch, name) in device.channels.iter().enumerate() {
            channel_card(ui, cell, name, ch, snapshot, state.band_scale);
            if (ch + 1) % cols == 0 {
                ui.end_row();
            }
        }
    });
}

/// Band legend; with `toggles`, each entry shows/hides its line.
fn legend(ui: &mut egui::Ui, mut toggles: Option<&mut [bool; 5]>) {
    ui.horizontal_wrapped(|ui| {
        for band in Band::ALL {
            let (lo, hi) = band.range_hz();
            let on = toggles.as_ref().is_none_or(|t| t[band.index()]);
            let col = if on { theme::band_color(band) } else { ui.visuals().weak_text_color() };
            ui.colored_label(col, "■");
            let text = format!("{} {lo:.0}–{hi:.0} Hz", band.name());
            match toggles.as_deref_mut() {
                Some(t) => {
                    if ui.selectable_label(on, text).on_hover_text(t!("bands-show-hide-this-band")).clicked() {
                        t[band.index()] = !on;
                    }
                }
                None => {
                    ui.label(text);
                }
            }
            ui.add_space(8.0);
        }
    });
}

/// Mean over the chosen electrodes of one band in the current scale.
fn value(s: &BandSnapshot, n: usize, mask: u32, band: Band, scale: BandScale) -> Option<f32> {
    let vals: Vec<f32> = (0..n)
        .filter(|ch| mask & (1 << ch) != 0)
        .filter_map(|ch| match scale {
            BandScale::Absolute => s.power(ch, band),
            BandScale::Relative => s.relative(ch, band).map(|r| r * 100.0),
        })
        .filter(|v| v.is_finite())
        .collect();
    (!vals.is_empty()).then(|| vals.iter().sum::<f32>() / vals.len() as f32)
}

fn over_time(ui: &mut egui::Ui, state: &AppState, n: usize, chips: Chips) {
    let latest = state.bands.latest().map_or(0.0, |s| s.time);
    let vp = super::plot::viewport(ui, "bands", &[15.0, 30.0, 60.0, 120.0], latest);
    let max_back = BandHistory::SECONDS - vp.window_s;
    let back = vp.back_s(latest, max_back);
    let (rect, resp) = ui.allocate_exact_size(ui.available_size().max(Vec2::new(200.0, 160.0)), Sense::drag());
    super::plot::drag(ui, "bands", &resp, latest, max_back);
    let p = ui.painter_at(rect);
    let vis = ui.visuals();
    p.rect_filled(rect, 6.0, vis.extreme_bg_color);
    let plot = Rect::from_min_max(rect.left_top() + Vec2::new(44.0, 12.0), rect.right_bottom() - Vec2::new(12.0, 24.0));
    let (y0, y1, unit) = match state.band_scale {
        BandScale::Absolute => (ABS_MIN, ABS_MAX, "log10 µV²"),
        BandScale::Relative => (0.0, 100.0, "%"),
    };
    let span = vp.window_s as f32;
    let now = (latest - back) as f32;
    let grid = Stroke::new(0.5_f32, vis.weak_text_color().gamma_multiply(0.4));
    for k in 0..=4 {
        let y = y0 + (y1 - y0) * k as f32 / 4.0;
        let a = super::plot::to_screen(plot, (-span, 0.0), (y0, y1), -span, y);
        p.line_segment([a, Pos2::new(plot.right(), a.y)], grid);
        super::plot::label(&p, Pos2::new(plot.left() - 4.0, a.y), Align2::RIGHT_CENTER, format!("{y:.0}"));
    }
    super::plot::label(&p, plot.left_bottom() + Vec2::new(0.0, 4.0), Align2::LEFT_TOP, format!("-{:.0} s", vp.window_s + back));
    let end = if back > 0.05 { format!("-{back:.1} s") } else { "now".into() };
    super::plot::label(&p, plot.right_bottom() + Vec2::new(0.0, 4.0), Align2::RIGHT_TOP, end);
    super::plot::label(&p, plot.left_top() + Vec2::new(4.0, 0.0), Align2::LEFT_TOP, unit);
    for band in Band::ALL.into_iter().filter(|b| chips.bands[b.index()]) {
        // Break the line where snapshots stop (disconnect, dropped data);
        // values off the axis are clipped and marked red at the edge.
        let (mut run, mut prev) = (Vec::new(), f64::NEG_INFINITY);
        for s in state.bands.iter() {
            let x = s.time as f32 - now;
            let Some(v) = value(s, n, chips.electrodes, band, state.band_scale) else { continue };
            if !(x >= -span && x <= 0.0) {
                continue;
            }
            if s.time - prev > GAP_S {
                super::plot::trace(&p, std::mem::take(&mut run), theme::band_color(band));
            }
            prev = s.time;
            let pt = super::plot::to_screen(plot, (-span, 0.0), (y0, y1), x, v.clamp(y0, y1));
            if !(y0..=y1).contains(&v) {
                p.circle_filled(pt, 1.6, Color32::from_rgb(0xEF, 0x53, 0x50));
            }
            run.push(pt);
        }
        super::plot::trace(&p, run, theme::band_color(band));
    }
}

/// Snapshots come at 10 Hz; a longer silence is a gap.
const GAP_S: f64 = 0.5;

fn channel_card(ui: &mut egui::Ui, size: Vec2, name: &str, ch: usize, snapshot: &BandSnapshot, scale: BandScale) {
    let (rect, _) = ui.allocate_exact_size(size, Sense::hover());
    let painter = ui.painter_at(rect);
    let visuals = ui.visuals();
    painter.rect_filled(rect, 6.0, visuals.extreme_bg_color);
    painter.text(rect.left_top() + Vec2::new(10.0, 8.0), Align2::LEFT_TOP, name, FontId::proportional(16.0), visuals.strong_text_color());

    let plot = Rect::from_min_max(rect.left_top() + Vec2::new(10.0, 34.0), rect.right_bottom() - Vec2::new(10.0, 26.0));
    let slot = plot.width() / Band::ALL.len() as f32;
    let baseline = plot.bottom();
    painter.line_segment([plot.left_bottom(), plot.right_bottom()], Stroke::new(1.0_f32, visuals.weak_text_color()));

    for (i, band) in Band::ALL.iter().enumerate() {
        let (fraction, text) = match scale {
            BandScale::Absolute => {
                let v = snapshot.power(ch, *band).unwrap_or(ABS_MIN);
                (((v - ABS_MIN) / (ABS_MAX - ABS_MIN)).clamp(0.0, 1.0), format!("{v:.2}"))
            }
            BandScale::Relative => {
                let r = snapshot.relative(ch, *band).unwrap_or(0.0);
                (r.clamp(0.0, 1.0), format!("{:.0}%", r * 100.0))
            }
        };
        let x0 = plot.left() + slot * i as f32 + slot * 0.15;
        let x1 = x0 + slot * 0.7;
        let top = baseline - (plot.height() - 16.0).max(0.0) * fraction;
        painter.rect_filled(Rect::from_min_max(egui::pos2(x0, top), egui::pos2(x1, baseline)), 3.0, theme::band_color(*band));
        let cx = (x0 + x1) / 2.0;
        painter.text(egui::pos2(cx, top - 2.0), Align2::CENTER_BOTTOM, text, FontId::monospace(11.0), visuals.text_color());
        painter.text(
            egui::pos2(cx, baseline + 4.0),
            Align2::CENTER_TOP,
            &band.name()[..1],
            FontId::proportional(12.0),
            visuals.weak_text_color(),
        );
    }
}
