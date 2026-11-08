//! Raw EEG trace geometry: which buffered samples a pane shows and where.
//! Pure (no UI, no clock); the egui view only scales and paints.
//!
//! - Sample `i` of a channel buffer of `n` samples ending at `end_t` has the
//!   time `end_t - (n - 1 - i) / rate` (the signal ring is gap-padded, so
//!   indices map to time).
//! - [`Mapping::Scroll`]: x = position of the time inside `[start, end]`.
//! - [`Mapping::Sweep`]: x = phase of the time inside its window-long slot
//!   (`floor(t / window)`), so a sample keeps its x until it is overwritten
//!   one window later. The trace is split where the slot changes, so no line
//!   crosses the wrap. A strip of [`SWEEP_BLANK`] after the cursor is empty.
//! - Lines also break at gap samples and non-finite values. Nothing is
//!   interpolated: each pixel column keeps its min and max sample (spikes
//!   survive decimation), at their true x.

use crate::signal::{FLAG_BAD, FLAG_GAP, FLAG_OK};

/// Share of the window left empty right of the sweep cursor.
pub const SWEEP_BLANK: f64 = 0.02;
/// Raw Follow trails the newest sample by this much (BLE packets arrive in
/// ~50–150 ms bursts); smaller than Bands' 1 s because raw data is dense.
pub const RAW_FOLLOW_LEAD_S: f64 = 0.25;
/// Auto Y scale limits and the value with no data (µV half range).
pub const AUTO_MIN_UV: f32 = 10.0;
pub const AUTO_MAX_UV: f32 = 10_000.0;
pub const AUTO_EMPTY_UV: f32 = 200.0;
/// Headroom above the largest visible |µV|.
pub const AUTO_PAD: f32 = 0.15;

/// Raw EEG data span ending at `newest`: the 300 s ring, plus one window of
/// blank room in Sweep mode (see [`Mapping::freeze_end`]).
pub fn raw_span(newest: f64, mode: crate::monitor::RawMode, window_s: f64) -> crate::monitor::Span {
    let mut s = crate::monitor::Span::new((newest - crate::signal::BUFFER_S).max(0.0), newest);
    if mode == crate::monitor::RawMode::Sweep {
        s.ahead_s = window_s.max(0.0);
    }
    s
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Mapping {
    /// Time-ordered window `[start, end]`.
    Scroll { start: f64, end: f64 },
    /// Oscilloscope sweep of `window` seconds with the cursor at `now`.
    Sweep { now: f64, window: f64 },
}

impl Mapping {
    /// Visible times `(lo, hi]`.
    pub fn visible(&self) -> (f64, f64) {
        match *self {
            Mapping::Scroll { start, end } => (start, end),
            Mapping::Sweep { now, window } => (now - window * (1.0 - SWEEP_BLANK), now),
        }
    }

    /// `(x in 0..=1, slot)` of time `t`; the slot changes at every sweep wrap.
    pub fn x(&self, t: f64) -> (f64, i64) {
        match *self {
            Mapping::Scroll { start, end } => ((t - start) / (end - start).max(1e-9), 0),
            Mapping::Sweep { window, .. } => {
                let w = window.max(1e-9);
                let k = (t / w).floor();
                ((t - k * w) / w, k as i64)
            }
        }
    }

    /// Right edge for freezing this view into Inspect without moving any
    /// sample: a sweep freezes on its current slot `[k·w, (k+1)·w]`, where
    /// the time-ordered x of every slot sample equals its sweep x. The
    /// previous slot's data right of the cursor is dropped (blank, filled
    /// only by real later samples). `None` when scrolling (freeze as drawn).
    pub fn freeze_end(&self) -> Option<f64> {
        match *self {
            Mapping::Scroll { .. } => None,
            Mapping::Sweep { now, window } => {
                let (_, k) = self.x(now);
                Some((k + 1) as f64 * window.max(1e-9))
            }
        }
    }

    /// Sweep cursor x (`None` when scrolling).
    pub fn cursor(&self) -> Option<f64> {
        match *self {
            Mapping::Scroll { .. } => None,
            Mapping::Sweep { now, .. } => Some(self.x(now).0),
        }
    }

    /// Time shown at `x` (0..=1): in a sweep, left of the cursor is the
    /// current slot and right of it the previous one.
    pub fn time_at(&self, x: f64) -> f64 {
        match *self {
            Mapping::Scroll { start, end } => start + x * (end - start),
            Mapping::Sweep { now, window } => {
                let (cx, k) = self.x(now);
                let base = k as f64 * window;
                if x <= cx {
                    base + x * window
                } else {
                    base - window + x * window
                }
            }
        }
    }
}

/// One channel's buffered samples (aligned values and flags).
#[derive(Debug, Clone, Copy)]
pub struct Channel<'a> {
    /// Time of the last sample.
    pub end_t: f64,
    pub rate: f64,
    pub values: &'a [f32],
    /// Same length as `values` (missing = OK).
    pub flags: &'a [u8],
}

impl Channel<'_> {
    /// Index range of samples with time in `(lo, hi]`.
    fn indices(&self, (lo, hi): (f64, f64)) -> std::ops::Range<usize> {
        let n = self.values.len();
        if n == 0 || !(self.rate > 0.0 && self.end_t.is_finite() && lo.is_finite() && hi.is_finite()) {
            return 0..0;
        }
        let last = (n - 1) as f64;
        let first = (last - (self.end_t - lo) * self.rate).floor() + 1.0;
        let end = (last - (self.end_t - hi) * self.rate + 1e-9).floor();
        let first = first.max(0.0);
        let end = end.min(last);
        if end < first {
            return 0..0;
        }
        first as usize..end as usize + 1
    }

    fn time(&self, i: usize) -> f64 {
        self.end_t - (self.values.len() - 1 - i) as f64 / self.rate
    }

    fn flag(&self, i: usize) -> u8 {
        self.flags.get(i).copied().unwrap_or(FLAG_OK)
    }
}

/// Polylines (x 0..1, µV) plus flagged spans `(x0, x1, flag)` for shading.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Trace {
    pub runs: Vec<Vec<[f32; 2]>>,
    pub spans: Vec<(f32, f32, u8)>,
}

impl Trace {
    pub fn points(&self) -> usize {
        self.runs.iter().map(Vec::len).sum()
    }
}

#[derive(Default)]
struct Bucket {
    col: Option<i64>,
    lo: Option<(usize, f32, f32)>,
    hi: Option<(usize, f32, f32)>,
}

impl Bucket {
    fn add(&mut self, i: usize, x: f32, v: f32) {
        if self.lo.is_none_or(|(_, _, m)| v < m) {
            self.lo = Some((i, x, v));
        }
        if self.hi.is_none_or(|(_, _, m)| v > m) {
            self.hi = Some((i, x, v));
        }
    }

    fn flush(&mut self, run: &mut Vec<[f32; 2]>) {
        match (self.lo.take(), self.hi.take()) {
            (Some(a), Some(b)) if a.0 == b.0 => run.push([a.1, a.2]),
            (Some(a), Some(b)) => {
                let (p, q) = if a.0 < b.0 { (a, b) } else { (b, a) };
                run.push([p.1, p.2]);
                run.push([q.1, q.2]);
            }
            _ => {}
        }
        self.col = None;
    }
}

struct Spans {
    open: Option<(f32, f32, u8, i64)>,
    out: Vec<(f32, f32, u8)>,
}

impl Spans {
    fn add(&mut self, flag: u8, x0: f32, x1: f32, slot: i64) {
        match &mut self.open {
            Some((_, end, f, s)) if *f == flag && *s == slot => *end = x1,
            _ => {
                self.close();
                if flag == FLAG_GAP || flag == FLAG_BAD {
                    self.open = Some((x0, x1, flag, slot));
                }
            }
        }
    }

    fn close(&mut self) {
        if let Some((a, b, f, _)) = self.open.take() {
            self.out.push((a, b, f));
        }
    }
}

/// The visible part of `ch` under `map`, decimated to about `columns`
/// pixel columns (min + max per column).
pub fn trace(ch: &Channel, map: Mapping, columns: usize) -> Trace {
    let items = ch.indices(map.visible()).map(|i| (ch.time(i), ch.values[i], ch.flag(i)));
    build(items, ch.rate, map, columns)
}

/// [`trace`] for time-stamped samples that are not one uniform ring (PPG
/// segments): `Some((t, v))` in time order, `None` = a gap (the line
/// breaks). Only samples inside `map.visible()` are used; the same sweep
/// / scroll geometry, wrap split and min/max decimation as Raw EEG.
pub fn trace_samples(samples: impl Iterator<Item = Option<(f64, f32)>>, rate: f64, map: Mapping, columns: usize) -> Trace {
    let (lo, hi) = map.visible();
    let mut last_t = lo;
    let items = samples.filter_map(move |s| match s {
        None => Some((last_t, f32::NAN, FLAG_GAP)),
        Some((t, v)) if t > lo && t <= hi + 1e-9 => {
            last_t = t;
            Some((t, v, FLAG_OK))
        }
        Some(_) => None,
    });
    build(items, rate, map, columns)
}

fn build(items: impl Iterator<Item = (f64, f32, u8)>, rate: f64, map: Mapping, columns: usize) -> Trace {
    let cols = columns.max(1) as f64;
    let dx = match map {
        Mapping::Scroll { start, end } => 1.0 / (rate * (end - start).max(1e-9)),
        Mapping::Sweep { window, .. } => 1.0 / (rate * window.max(1e-9)),
    };
    let mut runs = Vec::new();
    let mut run: Vec<[f32; 2]> = Vec::new();
    let mut bucket = Bucket::default();
    let mut spans = Spans { open: None, out: Vec::new() };
    let mut slot = None;
    for (i, (t, v, flag)) in items.enumerate() {
        let (x, k) = map.x(t);
        spans.add(flag, x as f32, (x + dx).min(1.0) as f32, k);
        let broken = flag == FLAG_GAP || !v.is_finite();
        if broken || slot != Some(k) {
            bucket.flush(&mut run);
            end_run(&mut runs, &mut run);
        }
        if broken {
            slot = None;
            continue;
        }
        slot = Some(k);
        let col = (x * cols).floor() as i64;
        if bucket.col != Some(col) {
            bucket.flush(&mut run);
            bucket.col = Some(col);
        }
        bucket.add(i, x as f32, v);
    }
    bucket.flush(&mut run);
    end_run(&mut runs, &mut run);
    spans.close();
    Trace { runs, spans: spans.out }
}

/// Close `run`; a lone sample (between gaps) stays as a zero-length stub.
fn end_run(runs: &mut Vec<Vec<[f32; 2]>>, run: &mut Vec<[f32; 2]>) {
    match run.len() {
        0 => {}
        1 => runs.push(vec![run[0], run[0]]),
        _ => runs.push(std::mem::take(run)),
    }
    run.clear();
}

/// Shared Auto half range (µV) for the visible OK samples of `chans`:
/// symmetric about 0 so every sample fits, plus [`AUTO_PAD`].
pub fn auto_half_range(chans: &[Channel], map: Mapping) -> f32 {
    let mut peak: Option<f32> = None;
    for ch in chans {
        for i in ch.indices(map.visible()) {
            let v = ch.values[i];
            if ch.flag(i) == FLAG_OK && v.is_finite() && v.abs() < 1e6 {
                peak = Some(peak.map_or(v.abs(), |p| p.max(v.abs())));
            }
        }
    }
    peak.map_or(AUTO_EMPTY_UV, |p| (p * (1.0 + AUTO_PAD)).clamp(AUTO_MIN_UV, AUTO_MAX_UV))
}

/// Elapsed label: `m:ss`, with tenths when ticks are under a second apart.
pub fn elapsed_label(t: f64, step_s: f64) -> String {
    let t = if t.is_finite() { t.max(0.0) } else { 0.0 };
    if step_s < 1.0 {
        let tenths = (t * 10.0).round() as u64;
        format!("{}:{:02}.{}", tenths / 600, (tenths / 10) % 60, tenths % 10)
    } else {
        let s = t.round() as u64;
        format!("{}:{:02}", s / 60, s % 60)
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::float_cmp)]
    use super::*;

    #[test]
    fn freezing_a_sweep_keeps_every_x_and_blanks_right_of_cursor() {
        let rate = 256.0;
        let w = 8.0;
        // Cursor near the slot start, middle and end; slot k = 5.
        for frac in [0.01, 0.5, 0.995] {
            let now = 5.0 * w + frac * w;
            let n = (40.0 * rate) as usize;
            let values: Vec<f32> = (0..n).map(|i| ((i as f32) * 0.37).sin() * 30.0 + if i % 97 == 0 { 150.0 } else { 0.0 }).collect();
            let flags = vec![0u8; n];
            let ch = Channel { end_t: now, rate, values: &values, flags: &flags };
            let sweep = Mapping::Sweep { now, window: w };
            let end = sweep.freeze_end().unwrap();
            assert!((end - 6.0 * w).abs() < 1e-9, "{frac}: slot end");
            let frozen = Mapping::Scroll { start: end - w, end };
            // Same sample, same x. (The one sample exactly on the slot start
            // belongs to the slot in a sweep and to the left edge, excluded,
            // when frozen; it sits at x = 0 either way.)
            for t in [5.0 * w + 1e-6, 5.0 * w + frac * w * 0.5, now] {
                assert!((sweep.x(t).0 - frozen.x(t).0).abs() < 1e-9, "{frac} t={t}");
            }
            let cx = sweep.cursor().unwrap();
            let cols = 2000;
            let a = trace(&ch, sweep, cols);
            let b = trace(&ch, frozen, cols);
            // Near the slot end the sweep's blank gap also hides the slot start;
            // frozen, those real samples appear at the left edge (nothing moves).
            let lo = if sweep.visible().0 > end - w { sweep.x(sweep.visible().0).0 + 2.0 / cols as f64 } else { 0.0 };
            let left = |tr: &Trace| -> Vec<[f32; 2]> {
                let mut v: Vec<[f32; 2]> = tr
                    .runs
                    .iter()
                    .flatten()
                    .copied()
                    .filter(|p| f64::from(p[0]) > lo && f64::from(p[0]) <= cx - 2.0 / cols as f64)
                    .collect();
                v.sort_by(|p, q| p[0].total_cmp(&q[0]).then(p[1].total_cmp(&q[1])));
                v
            };
            assert_eq!(left(&a), left(&b), "{frac}: traces left of the cursor are identical");
            // Old sweep data right of the cursor is gone (no fabricated data).
            let tol = 1.5 / cols as f64;
            assert!(b.runs.iter().flatten().all(|p| f64::from(p[0]) <= cx + tol), "{frac}: blank right of cursor");
            if (0.4..0.9).contains(&frac) {
                assert!(a.runs.iter().flatten().any(|p| f64::from(p[0]) > cx + 0.05), "sweep did show the previous slot");
            }
        }
    }

    #[test]
    fn scroll_mapping_has_no_freeze_override() {
        assert_eq!(Mapping::Scroll { start: 0.0, end: 8.0 }.freeze_end(), None);
    }

    fn ch<'a>(end_t: f64, values: &'a [f32], flags: &'a [u8]) -> Channel<'a> {
        Channel { end_t, rate: 10.0, values, flags }
    }

    #[test]
    fn scroll_maps_true_timestamps() {
        let v: Vec<f32> = (0..100).map(|i| i as f32).collect(); // t = 0.1 .. 10.0
        let c = ch(10.0, &v, &[]);
        let t = trace(&c, Mapping::Scroll { start: 8.0, end: 10.0 }, 1000);
        assert_eq!(t.runs.len(), 1);
        let r = &t.runs[0];
        assert_eq!(r.len(), 20, "samples in (8, 10]");
        assert!((r[0][0] - 0.05).abs() < 1e-5 && r[0][1] == 80.0);
        assert!((r[19][0] - 1.0).abs() < 1e-5 && r[19][1] == 99.0);
    }

    #[test]
    fn sweep_splits_at_the_wrap_and_blanks_after_the_cursor() {
        let v: Vec<f32> = (0..100).map(|i| i as f32).collect();
        let c = ch(10.0, &v, &[]);
        // Window 4 s, now 9.0: slot 2 = [8, 12), cursor at 0.25.
        let m = Mapping::Sweep { now: 9.0, window: 4.0 };
        assert!((m.cursor().unwrap() - 0.25).abs() < 1e-9);
        let t = trace(&c, m, 1000);
        assert_eq!(t.runs.len(), 2, "old slot right of the cursor, new slot left");
        let old = &t.runs[0];
        let new = &t.runs[1];
        assert!(old.iter().all(|p| f64::from(p[0]) > 0.25 + SWEEP_BLANK - 1e-6), "blank strip after the cursor");
        assert!(new.iter().all(|p| f64::from(p[0]) <= 0.25 + 1e-6));
        assert_eq!(new.last().unwrap()[1], 89.0, "nothing newer than `now` (t = 9.0)");
        // No segment joins x≈1 to x≈0.
        for r in &t.runs {
            assert!(r.windows(2).all(|w| w[1][0] >= w[0][0]));
        }
        assert!((m.time_at(0.1) - 8.4).abs() < 1e-9 && (m.time_at(0.5) - 6.0).abs() < 1e-9);
    }

    #[test]
    fn gaps_break_lines_and_are_shaded() {
        let v = [1.0_f32; 30];
        let mut f = [FLAG_OK; 30];
        f[10..15].fill(FLAG_GAP);
        f[20..22].fill(FLAG_BAD);
        let c = ch(3.0, &v, &f);
        let t = trace(&c, Mapping::Scroll { start: 0.0, end: 3.0 }, 1000);
        assert_eq!(t.runs.len(), 2, "split at the gap");
        assert_eq!(t.spans.len(), 2);
        assert_eq!(t.spans[0].2, FLAG_GAP);
        assert_eq!(t.spans[1].2, FLAG_BAD, "bad data is drawn, shaded red");
        let nan = [1.0, f32::NAN, 1.0, 1.0];
        assert_eq!(trace(&ch(0.4, &nan, &[]), Mapping::Scroll { start: 0.0, end: 0.4 }, 100).runs.len(), 2);
    }

    #[test]
    fn decimation_keeps_spikes_and_bounds_points() {
        let mut v = vec![0.0_f32; 2560];
        v[1234] = 500.0;
        v[2000] = -400.0;
        let c = Channel { end_t: 10.0, rate: 256.0, values: &v, flags: &[] };
        let t = trace(&c, Mapping::Scroll { start: 0.0, end: 10.0 }, 300);
        assert!(t.points() <= 2 * 300 + 2, "{}", t.points());
        let ys: Vec<f32> = t.runs.iter().flatten().map(|p| p[1]).collect();
        assert!(ys.contains(&500.0) && ys.contains(&-400.0), "spikes survive");
    }

    #[test]
    fn auto_scale_is_shared_symmetric_and_ignores_flagged() {
        let a = [10.0_f32, -40.0, 5.0];
        let b = [20.0_f32, 1000.0, 0.0];
        let fb = [FLAG_OK, FLAG_BAD, FLAG_OK];
        let m = Mapping::Scroll { start: 0.0, end: 0.3 };
        let h = auto_half_range(&[ch(0.3, &a, &[]), ch(0.3, &b, &fb)], m);
        assert!((h - 46.0).abs() < 1e-4, "{h}");
        assert_eq!(auto_half_range(&[], m), AUTO_EMPTY_UV);
        assert_eq!(auto_half_range(&[ch(0.3, &[0.1, 0.0, 0.2], &[])], m), AUTO_MIN_UV);
    }

    #[test]
    fn labels() {
        assert_eq!(elapsed_label(75.0, 5.0), "1:15");
        assert_eq!(elapsed_label(75.5, 0.5), "1:15.5");
        assert_eq!(elapsed_label(f64::NAN, 1.0), "0:00");
    }

    #[test]
    fn empty_and_invalid() {
        assert!(trace(&ch(1.0, &[], &[]), Mapping::Scroll { start: 0.0, end: 1.0 }, 10).runs.is_empty());
        let c = Channel { end_t: f64::NAN, rate: 0.0, values: &[1.0, 2.0], flags: &[] };
        assert!(trace(&c, Mapping::Sweep { now: 1.0, window: 1.0 }, 10).runs.is_empty());
    }

    #[test]
    fn samples_trace_breaks_at_gaps_and_sweep_wraps() {
        // 64 Hz, 0..12 s with a gap 5..6 s; sweep window 10 s at now = 12.
        let mut v: Vec<Option<(f64, f32)>> = Vec::new();
        for i in 0..(12 * 64) {
            let t = f64::from(i) / 64.0;
            if (5.0..6.0).contains(&t) {
                if v.last().is_some_and(Option::is_some) {
                    v.push(None);
                }
                continue;
            }
            v.push(Some((t, 1.0)));
        }
        let map = Mapping::Sweep { now: 12.0, window: 10.0 };
        let tr = trace_samples(v.iter().copied(), 64.0, map, 10_000);
        // Visible (2.2, 12]: [2.2..5) | gap | [6..10) | wrap | [10..12].
        assert_eq!(tr.runs.len(), 3, "{:?}", tr.runs.iter().map(|r| (r[0][0], r[r.len() - 1][0])).collect::<Vec<_>>());
        assert!(tr.runs.iter().all(|r| r.windows(2).all(|p| p[1][0] >= p[0][0])), "no line crosses the wrap");
        assert!(tr.runs[2][0][0] < 0.01 && tr.runs[1][0][0] > 0.59);
    }
}
