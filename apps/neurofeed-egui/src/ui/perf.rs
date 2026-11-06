//! Debug overlay (Settings → Debug → "Show frame rate overlay"): frames per
//! second, the frame interval and the CPU time of the previous frame.
//!
//! - **Frame interval**: presentation time between two drawn frames
//!   (`input.time` deltas, smoothed). The app repaints on demand, so on a
//!   still screen this is long; it does not request extra frames itself.
//! - **CPU**: eframe's `cpu_usage` of the previous frame (ui + tessellation +
//!   paint submission on the CPU), not GPU time.

use super::theme;

/// Smoothing of the frame interval (share of the newest sample).
const EMA: f64 = 0.1;
/// Intervals beyond this (idle, app in the background) reset the average.
const IDLE_S: f64 = 1.0;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Stats {
    last: Option<f64>,
    /// Smoothed frame interval, seconds.
    pub interval_s: Option<f64>,
}

impl Stats {
    /// One frame at presentation time `now`.
    #[must_use]
    pub fn frame(self, now: f64) -> Self {
        let interval_s = match self.last {
            Some(t) if now > t => {
                let dt = now - t;
                Some(match self.interval_s {
                    Some(avg) if dt <= IDLE_S => avg + (dt - avg) * EMA,
                    _ => dt,
                })
            }
            _ => self.interval_s,
        };
        Self { last: Some(now), interval_s }
    }

    pub fn fps(&self) -> Option<f64> {
        self.interval_s.filter(|s| *s > 0.0).map(|s| 1.0 / s)
    }
}

/// Small label in the bottom-left corner of the safe area.
pub fn show(ctx: &egui::Context, cpu_s: Option<f32>) {
    let id = egui::Id::unique("nf_perf_stats");
    let now = ctx.input(|i| i.time);
    let stats = ctx.data(|d| d.get_temp::<Stats>(id)).unwrap_or_default().frame(now);
    ctx.data_mut(|d| d.insert_temp(id, stats));
    let text = t!(
        "perf-overlay",
        fps = stats.fps().map_or_else(|| "–".to_owned(), |f| format!("{f:.0}")),
        interval = stats.interval_s.map_or_else(|| "–".to_owned(), |s| format!("{:.1}", s * 1e3)),
        cpu = cpu_s.map_or_else(|| "–".to_owned(), |s| format!("{:.1}", f64::from(s) * 1e3))
    );
    let corner = ctx.content_rect().left_bottom() + egui::vec2(6.0, -6.0);
    egui::Area::new(id.with("area"))
        .order(egui::Order::Tooltip)
        .interactable(false)
        .pivot(egui::Align2::LEFT_BOTTOM)
        .fixed_pos(corner)
        .show(ctx, |ui| {
            egui::Frame::new().fill(theme::overlay_bg(ui.visuals())).corner_radius(4.0).inner_margin(egui::Margin::symmetric(6, 2)).show(
                ui,
                |ui| {
                    ui.add(
                        egui::Label::new(egui::RichText::new(text).monospace().size(11.0).color(theme::axis_text(ui.visuals()))).extend(),
                    );
                },
            );
        });
}

#[cfg(test)]
mod tests {
    use super::Stats;

    #[test]
    fn interval_and_fps() {
        let mut s = Stats::default().frame(0.0);
        assert_eq!(s.interval_s, None);
        for f in 1..=120 {
            s = s.frame(f64::from(f) / 60.0);
        }
        assert!((s.fps().unwrap_or(0.0) - 60.0).abs() < 0.5);
        // Idle gap: restart from the measured interval instead of averaging.
        s = s.frame(10.0);
        assert!((s.interval_s.unwrap_or(0.0) - (10.0 - 2.0)).abs() < 1e-9);
        // Clock not advancing: unchanged.
        assert_eq!(s.frame(10.0).interval_s, s.interval_s);
    }
}
