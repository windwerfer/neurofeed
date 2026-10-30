//! One-page PDF session report (`history.export` format `pdf`): title,
//! info line, totals, trust percentile plot with threshold, trust strip,
//! notes and recording context. Same colours as the trust pane.

use crate::trust::{Row, Trust};
use nf_format::pdf::{wrap, Page, Rgb, A4};
use nf_store::SessionMeta;

const GREEN: Rgb = (0.30, 0.69, 0.31);
const TEAL: Rgb = (0.20, 0.55, 0.55);
const AMBER: Rgb = (0.96, 0.65, 0.14);
const RED: Rgb = (0.90, 0.35, 0.35);
const GREY: Rgb = (0.75, 0.75, 0.75);
const INK: Rgb = (0.1, 0.1, 0.1);
const MUTED: Rgb = (0.45, 0.45, 0.45);
const M: f64 = 48.0;

fn strip_colour(r: &Row) -> Rgb {
    if r.calibrating || r.paused {
        GREY
    } else if r.dirty.is_some() {
        RED
    } else if !r.held_back.is_empty() {
        AMBER
    } else if r.in_target {
        GREEN
    } else {
        TEAL
    }
}

fn mmss(s: f64) -> String {
    let s = s.max(0.0).round() as u64;
    format!("{}:{:02}", s / 60, s % 60)
}

fn date(ms: Option<f64>) -> String {
    ms.map_or_else(
        || "unknown date".into(),
        |ms| {
            let (y, mo, d, h, mi, _) = crate::recording::civil_utc(ms);
            format!("{y}-{mo:02}-{d:02} {h:02}:{mi:02} UTC")
        },
    )
}

fn pct(v: Option<f64>) -> String {
    v.map_or_else(|| "-".into(), |v| format!("{v:.0} %"))
}

fn totals(p: &mut Page, y: f64, t: &Trust) -> f64 {
    let x = &t.totals;
    let items = [
        ("In zone", pct(x.pct_in_zone)),
        ("Clean", mmss(f64::from(x.clean_s))),
        ("Trained", mmss(f64::from(x.training_s))),
        ("Held back", pct(x.pct_held_back)),
        ("Rewards", x.reward_chimes.to_string()),
        ("Guard warn", pct(x.pct_warning)),
    ];
    let w = (A4.0 - 2.0 * M) / items.len() as f64;
    for (i, (k, v)) in items.iter().enumerate() {
        let cx = M + w * i as f64;
        p.fill(MUTED);
        p.text(cx, y, 8.0, false, k);
        p.fill(INK);
        p.text(cx, y + 16.0, 14.0, true, v);
    }
    let mut y = y + 32.0;
    if !x.dirty_s.is_empty() {
        let d: Vec<String> = x.dirty_s.iter().map(|(n, s)| format!("{n} {}", mmss(f64::from(*s)))).collect();
        p.fill(MUTED);
        p.text(M, y, 8.0, false, &format!("Dirty: {}", d.join(", ")));
        y += 12.0;
    }
    y
}

fn plot(p: &mut Page, y: f64, t: &Trust) -> f64 {
    let (w, h) = (A4.0 - 2.0 * M, 140.0);
    p.fill(MUTED);
    p.text(M, y, 7.0, false, "percentile (teal) vs threshold (orange), dirty seconds hold the last clean value");
    let y = y + 6.0;
    p.fill((0.96, 0.96, 0.96));
    p.rect(M, y, w, h);
    let n = t.rows.len().max(2) as f64 - 1.0;
    let at = |i: usize, v: f64| (M + w * i as f64 / n, y + h - h * v.clamp(0.0, 100.0) / 100.0);
    let segs = |f: &dyn Fn(&Row) -> Option<f64>| {
        let mut out: Vec<Vec<(f64, f64)>> = vec![Vec::new()];
        for (i, r) in t.rows.iter().enumerate() {
            match f(r) {
                Some(v) => out.last_mut().map_or((), |s| s.push(at(i, v))),
                None if out.last().is_some_and(|s| !s.is_empty()) => out.push(Vec::new()),
                None => {}
            }
        }
        out
    };
    p.stroke(TEAL, 0.8);
    for s in segs(&|r| if r.calibrating || r.paused { None } else { r.plot_pct }) {
        p.polyline(&s);
    }
    p.stroke(AMBER, 1.2);
    for s in segs(&|r| if r.calibrating { None } else { r.thr_pct }) {
        p.polyline(&s);
    }
    p.stroke((0.5, 0.2, 0.7), 0.8);
    for m in &t.marks {
        let x = at(t.rows.iter().position(|r| r.t >= m.t).unwrap_or(0), 0.0).0;
        p.polyline(&[(x, y), (x, y + h)]);
    }
    let sy = y + h + 4.0;
    let bw = w / t.rows.len().max(1) as f64;
    for (i, r) in t.rows.iter().enumerate() {
        p.fill(strip_colour(r));
        p.rect(M + bw * i as f64, sy, bw + 0.05, 10.0);
    }
    let ly = sy + 22.0;
    let mut lx = M;
    for (c, l) in [(GREEN, "in zone"), (TEAL, "below"), (AMBER, "held back"), (RED, "dirty"), (GREY, "calibrating / paused")] {
        p.fill(c);
        p.rect(lx, ly - 7.0, 7.0, 7.0);
        p.fill(MUTED);
        p.text(lx + 10.0, ly, 8.0, false, l);
        lx += 20.0 + l.len() as f64 * 4.4;
    }
    ly + 16.0
}

fn block(p: &mut Page, mut y: f64, title: &str, lines: &[String]) -> f64 {
    p.fill(INK);
    p.text(M, y, 11.0, true, title);
    y += 14.0;
    for l in lines {
        if y > A4.1 - M {
            p.text(M, y, 9.0, false, "...");
            return y + 12.0;
        }
        p.text(M, y, 9.0, false, l);
        y += 12.0;
    }
    y + 8.0
}

fn context_lines(ctx: Option<&serde_json::Value>) -> Vec<String> {
    let Some(obj) = ctx.and_then(|c| c.as_object()) else { return Vec::new() };
    obj.iter()
        .flat_map(|(k, v)| {
            let s = flat(v);
            wrap(&format!("{k}: {s}"), 9.0, A4.0 - 2.0 * M)
        })
        .collect()
}

fn flat(v: &serde_json::Value) -> String {
    match v {
        serde_json::Value::String(s) => s.clone(),
        serde_json::Value::Object(o) => o
            .iter()
            .filter(|(_, x)| !x.is_null() && !x.is_object() && !x.is_array())
            .map(|(k, x)| format!("{k}={}", flat(x)))
            .collect::<Vec<_>>()
            .join(", "),
        _ => v.to_string(),
    }
}

/// Render the report for a stored session.
pub fn pdf(meta: &SessionMeta, trust: &Trust) -> Vec<u8> {
    let mut p = Page::default();
    let named = meta.context.as_ref().and_then(|c| c["protocol"]["title"].as_str()).or(meta.protocol.as_deref());
    let title = named.map_or_else(|| "Recording".to_string(), |s| format!("{s} session"));
    p.fill(INK);
    p.text(M, M + 10.0, 20.0, true, &title);
    p.fill(MUTED);
    let info = format!("{} · {} · {} · #{}", date(meta.started_unix_ms), mmss(meta.duration_s), meta.device_name, meta.id);
    p.text(M, M + 28.0, 9.0, false, &info);
    let mut y = M + 56.0;
    if !trust.rows.is_empty() {
        y = totals(&mut p, y, trust);
        y = plot(&mut p, y + 6.0, trust);
    }
    if !meta.notes.trim().is_empty() {
        y = block(&mut p, y + 6.0, "Notes", &wrap(&meta.notes, 9.0, A4.0 - 2.0 * M));
    }
    let ctx = context_lines(meta.context.as_ref());
    if !ctx.is_empty() {
        block(&mut p, y + 6.0, "Recording context", &ctx);
    }
    nf_format::pdf::write(&[p], &format!("NeuroFeed - {title}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn report_contains_title_and_notes() {
        let meta = SessionMeta { protocol: Some("alpha".into()), notes: "calm (evening)".into(), ..Default::default() };
        let rows = (0..30)
            .map(|i| Row { t: f64::from(i), clean: true, pct: Some(50.0), thr_pct: Some(40.0), in_target: true, ..Default::default() })
            .collect();
        let b = pdf(&meta, &crate::trust::build(rows, Vec::new()));
        let s = String::from_utf8_lossy(&b);
        assert!(s.contains("(alpha session)") && s.contains("calm \\(evening\\)") && s.contains("100 %"));
    }
}
