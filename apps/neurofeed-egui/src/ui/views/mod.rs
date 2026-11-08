//! One module per functional view.

mod ai;
pub(crate) mod bands;
mod devices;
mod feedback;
mod heart;
pub(crate) mod histogram;
mod history;
mod import;
/// egui temp-data key mirroring the gesture-markers setting.
pub const MARKS_ID: &str = "nf_gesture_markers";

mod about;
mod meta;
mod movement;
mod nerd;
mod plot;
mod protocol_builder;
mod psd;
mod raw;
mod settings;
mod sound;
mod spectrogram;
mod streaming;
mod trust;

use nf_core::{Command, Session, View};

pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>, shell: &mut super::Shell) {
    let state = session.state();
    match state.view {
        View::Feedback => feedback::show(ui, session, out),
        View::History => history::show(ui, session, out),
        View::Bands => bands::show(ui, state, out),
        View::RawEeg => raw::show(ui, session, out),
        View::Psd => psd::show(ui, session, out),
        View::HeartRate => heart::show(ui, session),
        View::Movement => movement::show(ui, session),
        View::Histogram => histogram::show(ui, session, out),
        View::Spectrogram => spectrogram::show(ui, session, out),
        View::Streaming => streaming::show(ui, session, out),
        View::Settings => settings::show(ui, session, out, shell),
    }
}

/// Follow smoothness: real data is drawn past the right edge so it slides
/// in (Bands lines, Spectrogram texture) instead of popping in at the edge.
#[cfg(test)]
mod follow_edge_tests {
    #![allow(clippy::unwrap_used, clippy::panic)]
    use egui::{Pos2, Rect, Vec2};
    use nf_core::{Command, Session};

    fn cmd(id: &str, p: serde_json::Value) -> Command {
        match nf_core::Request::parse(id, p) {
            Ok(nf_core::Request::Command(c)) => c,
            _ => panic!("{id}"),
        }
    }

    fn session(view: &str) -> Session {
        let mut s = Session::new();
        for (id, p) in [
            ("settings.set", serde_json::json!({ "onboarded": true, "layout": "regular" })),
            ("device.connect", serde_json::json!({ "id": "sim:muse" })),
            ("view.set", serde_json::json!({ "view": view })),
            ("clock.advance", serde_json::json!({ "seconds": 40.0 })),
            ("monitor.overview", serde_json::json!({ "monitor": view, "on": false })),
        ] {
            s.execute(cmd(id, p)).unwrap();
        }
        assert!(matches!(s.state().link, Some(nf_core::LinkState::Streaming)));
        s
    }

    /// Per frame: (rightmost geometry x, clip right) of the main plot's
    /// band lines (paths) or heatmap (textured mesh).
    fn edges(s: &mut Session, frames: &[(f64, f64)], mesh: bool) -> Vec<(f32, f32)> {
        let _lang = crate::i18n::lang_lock();
        let ctx = egui::Context::default();
        let mut t = 0.0;
        let mut out = Vec::new();
        for &(dt_ui, dt_data) in frames {
            if dt_data > 0.0 {
                s.execute(cmd("clock.advance", serde_json::json!({ "seconds": dt_data }))).unwrap();
            }
            t += dt_ui;
            let input = egui::RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, Vec2::new(1200.0, 800.0))),
                time: Some(t),
                ..Default::default()
            };
            let mut o = ctx.run_ui(input, |u| {
                crate::ui::show(u, s, None);
            });
            o.textures_delta.clear();
            let mut best: Option<(f32, f32)> = None;
            for c in &o.shapes {
                let x = match &c.shape {
                    egui::Shape::Path(p) if !mesh && p.points.len() > 8 => p.points.iter().map(|q| q.x).fold(f32::MIN, f32::max),
                    egui::Shape::Mesh(m) if mesh && m.texture_id != egui::TextureId::default() => {
                        m.vertices.iter().map(|v| v.pos.x).fold(f32::MIN, f32::max)
                    }
                    _ => continue,
                };
                // Main plot only (the widest clip).
                if best.is_none_or(|b| c.clip_rect.right() >= b.1) {
                    best = Some((x, c.clip_rect.right()));
                }
            }
            out.push(best.unwrap_or_else(|| panic!("no geometry in frame")));
        }
        out
    }

    fn frames() -> Vec<(f64, f64)> {
        // 30 repaints between data updates (60 Hz UI, 4 Hz data), then
        // a 1.5 s packet burst, then more intersample frames.
        let mut f: Vec<(f64, f64)> = (0..30).map(|i| (1.0 / 60.0, if i % 15 == 14 { 0.25 } else { 0.0 })).collect();
        f.push((1.0 / 60.0, 1.5));
        f.extend((0..20).map(|_| (1.0 / 60.0, 0.0)));
        f
    }

    #[test]
    fn bands_lines_extend_past_the_right_edge_every_follow_frame() {
        let mut s = session("bands");
        for (x, clip) in edges(&mut s, &frames(), false) {
            assert!(x > clip, "newest segment is prepared off-screen: line ends at {x}, edge {clip}");
        }
    }

    #[test]
    fn spectrogram_texture_extends_past_the_right_edge_every_follow_frame() {
        let mut s = session("spectrogram");
        let e = edges(&mut s, &frames(), true);
        for (x, clip) in &e {
            assert!(x > clip, "heatmap columns beyond the edge exist: quad ends at {x}, edge {clip}");
        }
        // The quad moves continuously (sub-column) between data updates.
        let xs: Vec<f32> = e.iter().take(14).map(|p| p.0).collect();
        assert!(xs.windows(2).all(|w| w[1] <= w[0] + 1e-3), "monotone leftward drift: {xs:?}");
        assert!(xs[0] - xs[13] > 0.5, "it actually moved: {xs:?}");
    }

    #[test]
    fn inspect_shows_no_data_past_its_end_and_needs_no_repaint() {
        let _lang = crate::i18n::lang_lock();
        let mut s = session("bands");
        s.execute(cmd("monitor.viewport", serde_json::json!({ "monitor": "bands", "mode": "inspect", "end_s": 30.0 }))).unwrap();
        let ctx = egui::Context::default();
        for i in 0..3 {
            let input = egui::RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, Vec2::new(1200.0, 800.0))),
                time: Some(f64::from(i)),
                ..Default::default()
            };
            let mut o = ctx.run_ui(input, |u| {
                crate::ui::show(u, &s, None);
            });
            o.textures_delta.clear();
            if i == 2 {
                let vp = o.viewport_output.values().next().unwrap();
                assert!(
                    vp.repaint_delay > std::time::Duration::from_millis(50),
                    "static Inspect: no continuous repaint ({:?})",
                    vp.repaint_delay
                );
            }
        }
    }
}
