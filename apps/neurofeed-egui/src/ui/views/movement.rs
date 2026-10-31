//! Movement (IMU) view: accelerometer x/y/z and dynamic |a| − 1 g with a
//! Follow/Inspect viewport over the 30 s side buffer.

use super::plot;
use egui::{Align2, Color32};
use nf_core::Session;

const WINDOWS: [f64; 4] = [5.0, 10.0, 20.0, 30.0];
const BUFFER_S: f64 = 30.0;
const RANGE_G: f32 = 1.5;
const COLORS: [Color32; 4] = [
    Color32::from_rgb(0xEF, 0x53, 0x50),
    Color32::from_rgb(0x66, 0xBB, 0x6A),
    Color32::from_rgb(0x4F, 0xC3, 0xF7),
    Color32::from_rgb(0xFF, 0xCA, 0x28),
];

/// Longer than this without a sample is a dropout (IMU runs at ≥ 50 Hz).
const GAP_S: f64 = 0.25;
const GAP_FILL: Color32 = Color32::from_rgba_premultiplied(0x16, 0x16, 0x16, 40);

/// Time spans inside `[t0, t1]` with no samples, including a trailing one
/// from the newest sample to `now` while data is not arriving.
fn gaps(times: impl Iterator<Item = f64>, t0: f64, t1: f64, newest: f64, now: f64) -> Vec<(f64, f64)> {
    let mut out = Vec::new();
    let mut prev: Option<f64> = None;
    for t in times {
        if let Some(p) = prev.filter(|p| t - p > GAP_S && t >= t0 && *p <= t1) {
            out.push((p.max(t0), t.min(t1)));
        }
        prev = Some(t);
    }
    if now - newest > GAP_S && newest < t1 {
        out.push((newest.max(t0), t1));
    }
    out
}

pub fn show(ui: &mut egui::Ui, session: &Session) {
    ui.horizontal(|ui| {
        ui.heading("Movement");
        ui.weak("accelerometer, g (x, y, z) and |a| − 1 g");
    });
    ui.separator();
    let Some(side) = session.side().filter(|s| !s.accel.is_empty()) else {
        ui.label(if session.live_signal().is_some() {
            "This device sends no accelerometer data."
        } else {
            "No device connected. Use Connect device in the top bar."
        });
        return;
    };
    let now = session.state().time;
    let vp = plot::viewport(ui, "movement", &WINDOWS, now);
    let max_back = BUFFER_S - vp.window_s;
    let back = vp.back_s(now, max_back);
    // Anchor on session time so an ongoing dropout shows as a trailing gap.
    let newest = side.accel.back().map_or(now, |a| a.0);
    let anchor = if now - newest > GAP_S { now } else { newest };
    let (t1, t0) = (anchor - back, anchor - back - vp.window_s);
    let gaps = gaps(side.accel.iter().map(|a| a.0), t0, t1, newest, anchor);
    let names: Vec<String> = ["x", "y", "z", "|a| − 1 g"].iter().map(|s| (*s).to_owned()).collect();
    let resp = plot::cards_resp(ui, &names, |p, r, k| {
        let x = |t: f64| plot::to_screen(r, (t0 as f32, t1 as f32), (0.0, 1.0), t as f32, 0.0).x;
        for &(a, b) in &gaps {
            p.rect_filled(egui::Rect::from_x_y_ranges(x(a)..=x(b), r.y_range()), 0.0, GAP_FILL);
        }
        p.line_segment([r.left_center(), r.right_center()], (0.5_f32, Color32::DARK_GRAY));
        let (mut run, mut prev) = (Vec::new(), f64::NEG_INFINITY);
        for (t, a) in side.accel.iter().filter(|(t, _)| (t0..=t1).contains(t)) {
            if t - prev > GAP_S {
                plot::trace(p, std::mem::take(&mut run), COLORS[k]);
            }
            prev = *t;
            let y = if k < 3 { a[k] } else { (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt() - 1.0 };
            run.push(plot::to_screen(r, (t0 as f32, t1 as f32), (-RANGE_G, RANGE_G), *t as f32, y.clamp(-RANGE_G, RANGE_G)));
        }
        plot::trace(p, run, COLORS[k]);
        plot::label(p, r.left_top(), Align2::RIGHT_TOP, format!("{RANGE_G} "));
        plot::label(p, r.left_bottom(), Align2::RIGHT_BOTTOM, format!("-{RANGE_G} "));
        plot::label(p, r.right_bottom(), Align2::RIGHT_TOP, if back > 0.05 { format!("-{back:.1} s") } else { "now".into() });
    });
    if let Some(resp) = resp {
        plot::drag(ui, "movement", &resp, now, max_back);
    }
}
