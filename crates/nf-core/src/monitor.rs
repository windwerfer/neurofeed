//! Monitor graphs: per-monitor time viewport (Follow / Inspect, window
//! length, zoom and pan) and the Bands display choices (electrodes in the
//! average, hidden bands, log/% value math).
//!
//! The viewport is a small state machine owned by the core so the UI, CLI
//! and MCP drive it the same way (`monitor.*` commands). Window lengths are
//! persisted per monitor; Follow/Inspect and the inspect position are not.

use nf_types::{Band, BandSnapshot};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// Time-axis graphs that own a viewport.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum MonitorId {
    Bands,
    RawEeg,
    Spectrogram,
    HeartOverview,
    HeartDetail,
    Movement,
    /// PSD analysis epoch (2/4/8 s of raw EEG).
    Psd,
    /// Bands context strip under the PSD (the PSD view's overview).
    PsdStrip,
    /// Histogram analysis epoch (2/4/8 s of raw EEG).
    Histogram,
    /// Overview timelines (Bands history minimap) of the other views; each
    /// has its own pan/zoom, independent of every other view.
    BandsOverview,
    RawOverview,
    HistogramOverview,
    SpectrogramOverview,
}

/// Window presets and zoom limits of one monitor (seconds).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct WindowSpec {
    pub presets: &'static [f64],
    pub default_s: f64,
    pub min_s: f64,
    pub max_s: f64,
}

impl MonitorId {
    pub const ALL: [MonitorId; 13] = [
        MonitorId::Bands,
        MonitorId::RawEeg,
        MonitorId::Spectrogram,
        MonitorId::HeartOverview,
        MonitorId::HeartDetail,
        MonitorId::Movement,
        MonitorId::Psd,
        MonitorId::PsdStrip,
        MonitorId::Histogram,
        MonitorId::BandsOverview,
        MonitorId::RawOverview,
        MonitorId::HistogramOverview,
        MonitorId::SpectrogramOverview,
    ];

    /// Views that can show an overview timeline, with its viewport.
    pub const WITH_OVERVIEW: [MonitorId; 5] =
        [MonitorId::Bands, MonitorId::RawEeg, MonitorId::Histogram, MonitorId::Psd, MonitorId::Spectrogram];

    /// The overview timeline viewport of a view (`None`: no overview).
    pub fn overview(self) -> Option<MonitorId> {
        match self {
            MonitorId::Bands => Some(MonitorId::BandsOverview),
            MonitorId::RawEeg => Some(MonitorId::RawOverview),
            MonitorId::Histogram => Some(MonitorId::HistogramOverview),
            MonitorId::Psd => Some(MonitorId::PsdStrip),
            MonitorId::Spectrogram => Some(MonitorId::SpectrogramOverview),
            _ => None,
        }
    }

    /// The view an overview viewport belongs to.
    pub fn overview_host(self) -> Option<MonitorId> {
        Self::WITH_OVERVIEW.into_iter().find(|h| h.overview() == Some(self))
    }

    /// Overview shown by default: PSD and Spectrogram only (owner 2026-11-07).
    pub fn overview_default(self) -> bool {
        matches!(self, MonitorId::Psd | MonitorId::Spectrogram)
    }

    /// Presets and limits follow the legacy app (`viewport_controller.dart`).
    pub fn spec(self) -> WindowSpec {
        match self {
            MonitorId::Bands => WindowSpec { presets: &[15.0, 30.0, 60.0, 120.0], default_s: 30.0, min_s: 5.0, max_s: 3600.0 },
            MonitorId::RawEeg => WindowSpec { presets: &[2.0, 4.0, 8.0, 10.0], default_s: 8.0, min_s: 1.0, max_s: 10.0 },
            // Flutter spectrogram windows; 300 s of spectral history.
            MonitorId::Spectrogram => WindowSpec { presets: &[10.0, 20.0, 30.0, 120.0, 300.0], default_s: 30.0, min_s: 5.0, max_s: 300.0 },
            MonitorId::HeartOverview => WindowSpec { presets: &[15.0, 30.0, 60.0, 120.0], default_s: 30.0, min_s: 5.0, max_s: 120.0 },
            MonitorId::HeartDetail => WindowSpec { presets: &[2.0, 4.0, 8.0, 10.0], default_s: 10.0, min_s: 2.0, max_s: 120.0 },
            MonitorId::Movement => WindowSpec { presets: &[15.0, 30.0, 60.0], default_s: 30.0, min_s: 5.0, max_s: 60.0 },
            // Flutter `histogramPsdWindowOptions` / `psdDefaultWindowSeconds`.
            MonitorId::Psd => WindowSpec { presets: &[2.0, 4.0, 8.0], default_s: 4.0, min_s: 2.0, max_s: 8.0 },
            MonitorId::Histogram => WindowSpec { presets: &[2.0, 4.0, 8.0], default_s: 4.0, min_s: 2.0, max_s: 8.0 },
            MonitorId::PsdStrip
            | MonitorId::BandsOverview
            | MonitorId::RawOverview
            | MonitorId::HistogramOverview
            | MonitorId::SpectrogramOverview => WindowSpec {
                presets: &[30.0, 60.0, 90.0, 120.0, 300.0, 600.0, 1800.0, 3600.0],
                default_s: 90.0,
                min_s: 10.0,
                max_s: 3600.0,
            },
        }
    }

    /// Seconds of live history kept in memory for this monitor (recording
    /// or not; a recording saves from its start, it does not extend this).
    pub fn history_s(self) -> f64 {
        match self {
            MonitorId::Bands => crate::state::BandHistory::SECONDS,
            MonitorId::RawEeg => crate::signal::BUFFER_S,
            MonitorId::Spectrogram => crate::signal::SPEC_HOP_S * crate::signal::SPEC_COLUMNS as f64,
            MonitorId::HeartOverview => crate::optics::HISTORY_S,
            MonitorId::HeartDetail => crate::optics::PPG_BUFFER_S,
            MonitorId::Movement => crate::side::SIDE_S,
            MonitorId::Psd => crate::signal::BUFFER_S,
            MonitorId::Histogram => crate::signal::BUFFER_S,
            MonitorId::PsdStrip
            | MonitorId::BandsOverview
            | MonitorId::RawOverview
            | MonitorId::HistogramOverview
            | MonitorId::SpectrogramOverview => crate::state::BandHistory::SECONDS,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            MonitorId::Bands => "bands",
            MonitorId::RawEeg => "raw_eeg",
            MonitorId::Spectrogram => "spectrogram",
            MonitorId::HeartOverview => "heart_overview",
            MonitorId::HeartDetail => "heart_detail",
            MonitorId::Movement => "movement",
            MonitorId::Psd => "psd",
            MonitorId::PsdStrip => "psd_strip",
            MonitorId::Histogram => "histogram",
            MonitorId::BandsOverview => "bands_overview",
            MonitorId::RawOverview => "raw_overview",
            MonitorId::HistogramOverview => "histogram_overview",
            MonitorId::SpectrogramOverview => "spectrogram_overview",
        }
    }
}

/// `monitor.viewport` mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ViewportMode {
    /// Right edge sticks to the newest data.
    Follow,
    /// Frozen at `end_s` (default: now); drag/pan moves it.
    Inspect,
}

/// Follow (right edge = newest data) or Inspect (frozen at `end_s`).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct Viewport {
    pub window_s: f64,
    /// `None` = Follow; `Some(t)` = Inspect, window ends at session time `t`.
    pub end_s: Option<f64>,
}

/// Data range a viewport may show: oldest and newest session time.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Span {
    pub oldest_s: f64,
    pub newest_s: f64,
    /// Blank room right of the newest sample a frozen view may keep (0 for
    /// most monitors). Raw EEG in Sweep mode uses one window so Inspect can
    /// freeze on the current sweep slot: samples keep their x, the part
    /// right of the cursor is empty and fills as live data arrives.
    pub ahead_s: f64,
}

impl Span {
    pub fn new(oldest_s: f64, newest_s: f64) -> Self {
        Self { oldest_s, newest_s, ahead_s: 0.0 }
    }

    fn max_end(&self) -> f64 {
        self.newest_s + self.ahead_s.max(0.0)
    }
}

fn finite_or(v: f64, d: f64) -> f64 {
    if v.is_finite() {
        v
    } else {
        d
    }
}

impl Viewport {
    pub fn new(spec: WindowSpec) -> Self {
        Self { window_s: spec.default_s, end_s: None }
    }

    pub fn following(&self) -> bool {
        self.end_s.is_none()
    }

    /// Visible `(start, end)` in session seconds.
    pub fn range(&self, span: Span) -> (f64, f64) {
        let end = self.end_s.map_or(span.newest_s, |e| e.min(span.max_end()));
        (end - self.window_s, end)
    }

    /// Set the window length (clamped to the spec); keeps the right edge.
    pub fn set_window(&mut self, spec: WindowSpec, window_s: f64) {
        self.window_s = finite_or(window_s, spec.default_s).clamp(spec.min_s, spec.max_s);
    }

    pub fn follow(&mut self) {
        self.end_s = None;
    }

    /// Freeze at `end_s` (default: the newest data), clamped into the data.
    pub fn inspect(&mut self, span: Span, end_s: Option<f64>) {
        let end = end_s.map_or(span.newest_s, |e| finite_or(e, span.newest_s));
        self.end_s = Some(clamp_end(end, self.window_s, span));
    }

    /// Pan by `seconds` (positive = later); enters Inspect.
    pub fn pan(&mut self, span: Span, seconds: f64) {
        let (_, end) = self.range(span);
        self.end_s = Some(clamp_end(end + finite_or(seconds, 0.0), self.window_s, span));
    }

    /// Zoom by `factor` (> 1 = zoom in, shorter window) keeping the time
    /// under `focal` (0 = left edge, 1 = right edge) in place. Follow stays
    /// Follow when the focal point is the right edge; otherwise Inspect.
    pub fn zoom(&mut self, spec: WindowSpec, span: Span, factor: f64, focal: f64) {
        let factor = finite_or(factor, 1.0);
        if factor <= 0.0 {
            return;
        }
        let focal = finite_or(focal, 1.0).clamp(0.0, 1.0);
        let (start, _) = self.range(span);
        let anchor = start + focal * self.window_s;
        let following = self.following();
        self.set_window(spec, self.window_s / factor);
        if following && focal >= 0.999 {
            return;
        }
        let end = anchor + (1.0 - focal) * self.window_s;
        self.end_s = Some(clamp_end(end, self.window_s, span));
    }
}

/// Keep the right edge inside `[oldest + window, newest]` (or at newest
/// when there is less data than one window).
fn clamp_end(end: f64, window_s: f64, span: Span) -> f64 {
    let lo = (span.oldest_s + window_s).min(span.newest_s);
    end.clamp(lo, span.max_end())
}

/// One step of an elapsed-time axis: tick spacing for about `target` ticks.
pub fn tick_step_s(window_s: f64, target: usize) -> f64 {
    const STEPS: [f64; 14] = [0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0, 600.0, 900.0, 1800.0, 3600.0];
    let want = window_s / target.max(1) as f64;
    STEPS.into_iter().find(|s| *s >= want).unwrap_or(3600.0)
}

/// `m:ss` label for elapsed seconds (negative clamps to 0).
pub fn mmss(t: f64) -> String {
    let s = if t.is_finite() { t.max(0.0) as u64 } else { 0 };
    format!("{}:{:02}", s / 60, s % 60)
}

/// Raw EEG trace layout (`monitor.raw {"mode"}`, saved).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum RawMode {
    /// Oscilloscope: the trace is rewritten from the left, a cursor marks now.
    #[default]
    Sweep,
    /// The window slides; the newest sample is at the right edge.
    Scroll,
}

/// Raw EEG Y scale (`monitor.raw {"scale"}`, saved). `auto` is **shared**
/// by all panes (as in Flutter): half range = half the min..max span of the
/// visible OK samples of every shown channel + 15 %, clamped to 10..10 000 µV,
/// re-fitted at most every 250 ms. One scale keeps amplitudes comparable
/// across electrodes.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub enum RawScale {
    #[default]
    #[serde(rename = "auto")]
    Auto,
    #[serde(rename = "50")]
    Uv50,
    #[serde(rename = "100")]
    Uv100,
    #[serde(rename = "200")]
    Uv200,
}

impl RawScale {
    pub const ALL: [RawScale; 4] = [RawScale::Auto, RawScale::Uv50, RawScale::Uv100, RawScale::Uv200];

    /// Fixed half range in µV (`None` = auto).
    pub fn fixed_uv(self) -> Option<f32> {
        match self {
            RawScale::Auto => None,
            RawScale::Uv50 => Some(50.0),
            RawScale::Uv100 => Some(100.0),
            RawScale::Uv200 => Some(200.0),
        }
    }
}

/// PSD frequency axis (Flutter `PsdHzRange`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, JsonSchema)]
pub enum PsdRange {
    #[default]
    #[serde(rename = "60")]
    Hz60,
    #[serde(rename = "100")]
    Hz100,
}

impl PsdRange {
    pub fn max_hz(self) -> f64 {
        match self {
            PsdRange::Hz60 => 60.0,
            PsdRange::Hz100 => 100.0,
        }
    }
}

/// What the PSD shows: frequency range (saved) and the electrodes in the
/// average (by name, empty = all; saved).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct PsdDisplay {
    #[serde(default)]
    pub electrodes: Vec<String>,
    #[serde(default)]
    pub range: PsdRange,
}

impl PsdDisplay {
    pub fn selected(&self, channels: &[String]) -> Vec<usize> {
        select(&self.electrodes, channels)
    }
}

/// Indices of `names` in `channels` (all when none match: a new device).
/// Display choice only; analysis eligibility is applied on top.
pub fn select(names: &[String], channels: &[String]) -> Vec<usize> {
    let picked: Vec<usize> = channels.iter().enumerate().filter(|(_, n)| names.contains(n)).map(|(i, _)| i).collect();
    if picked.is_empty() {
        (0..channels.len()).collect()
    } else {
        picked
    }
}

/// What Raw EEG shows. `mode` and `scale` persist; the electrode choice
/// (by name, empty = all, like Bands) lasts for the session.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct RawDisplay {
    pub electrodes: Vec<String>,
    pub mode: RawMode,
    pub scale: RawScale,
}

impl RawDisplay {
    /// Indices of `channels` shown (all when none match: a new device).
    pub fn selected(&self, channels: &[String]) -> Vec<usize> {
        let picked: Vec<usize> = channels.iter().enumerate().filter(|(_, n)| self.electrodes.contains(n)).map(|(i, _)| i).collect();
        if picked.is_empty() {
            (0..channels.len()).collect()
        } else {
            picked
        }
    }
}

/// What the Bands monitor shows (also the electrode choice of later
/// averaged monitors).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct BandsDisplay {
    /// Electrodes in the average, by name; empty = all EEG channels.
    pub electrodes: Vec<String>,
    /// Bands hidden in the graph (their lines and their share).
    pub hidden_bands: Vec<Band>,
}

impl BandsDisplay {
    /// Channel indices averaged for `channels` (all when none match).
    pub fn selected(&self, channels: &[String]) -> Vec<usize> {
        let picked: Vec<usize> = channels.iter().enumerate().filter(|(_, n)| self.electrodes.contains(n)).map(|(i, _)| i).collect();
        if picked.is_empty() {
            (0..channels.len()).collect()
        } else {
            picked
        }
    }

    pub fn visible(&self, band: Band) -> bool {
        !self.hidden_bands.contains(&band)
    }
}

/// Monitor state kept in `AppState`.
/// Histogram amplitude range (± µV around each channel's mean).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, JsonSchema)]
pub enum HistRange {
    #[serde(rename = "50")]
    Uv50,
    #[default]
    #[serde(rename = "100")]
    Uv100,
    #[serde(rename = "200")]
    Uv200,
}

impl HistRange {
    pub const ALL: [HistRange; 3] = [HistRange::Uv50, HistRange::Uv100, HistRange::Uv200];

    pub fn half_uv(self) -> f64 {
        match self {
            HistRange::Uv50 => 50.0,
            HistRange::Uv100 => 100.0,
            HistRange::Uv200 => 200.0,
        }
    }
}

/// Histogram display: electrodes pooled (empty = all) and µV range.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct HistogramDisplay {
    #[serde(default)]
    pub electrodes: Vec<String>,
    #[serde(default)]
    pub range: HistRange,
}

impl HistogramDisplay {
    pub fn selected(&self, channels: &[String]) -> Vec<usize> {
        select(&self.electrodes, channels)
    }
}

/// Spectrogram display: electrodes averaged (empty = all) and the colour
/// range: `None` = auto (fitted to the visible data), `Some` = locked dB.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SpectrogramDisplay {
    #[serde(default)]
    pub electrodes: Vec<String>,
    #[serde(default)]
    pub db_lock: Option<(f32, f32)>,
}

impl SpectrogramDisplay {
    pub fn selected(&self, channels: &[String]) -> Vec<usize> {
        select(&self.electrodes, channels)
    }
}

/// Valid locked dB range (finite, min < max, within ±200 dB).
pub fn db_range_ok(lo: f32, hi: f32) -> bool {
    lo.is_finite() && hi.is_finite() && lo < hi && lo >= -200.0 && hi <= 200.0
}

/// Bookmarks kept per view (oldest dropped beyond this).
pub const MAX_BOOKMARKS: usize = 8;
/// Two bookmarks closer than this (same window) are the same bookmark.
pub const BOOKMARK_DUP_S: f64 = 0.5;

/// A saved host window (Overview long-press): session-local, cleared on a
/// new connection; never persisted (stream times mean nothing later).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct Bookmark {
    pub id: u32,
    /// Window end and length (session s): restoring both makes the
    /// comparison reproducible.
    pub end_s: f64,
    pub window_s: f64,
}

impl Bookmark {
    /// Is the bookmarked window still in the host's retained data?
    pub fn available(&self, span: Span) -> bool {
        self.end_s - self.window_s >= span.oldest_s - 1e-6 && self.end_s <= span.newest_s + span.ahead_s + 1e-6
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Monitors {
    viewports: BTreeMap<MonitorId, Viewport>,
    pub bands: BandsDisplay,
    pub raw: RawDisplay,
    pub psd: PsdDisplay,
    pub histogram: HistogramDisplay,
    pub spectrogram: SpectrogramDisplay,
    /// Overview shown per view; missing = [`MonitorId::overview_default`].
    pub overview: BTreeMap<MonitorId, bool>,
    /// Session-local bookmarks per host view, oldest first.
    pub bookmarks: BTreeMap<MonitorId, Vec<Bookmark>>,
    next_bookmark: u32,
}

impl Monitors {
    /// Add a bookmark (a duplicate returns the existing one; beyond
    /// [`MAX_BOOKMARKS`] the oldest is dropped). Returns its id.
    pub fn bookmark_add(&mut self, host: MonitorId, end_s: f64, window_s: f64) -> u32 {
        let list = self.bookmarks.entry(host).or_default();
        if let Some(b) = list.iter().find(|b| (b.end_s - end_s).abs() < BOOKMARK_DUP_S && (b.window_s - window_s).abs() < 1e-6) {
            return b.id;
        }
        self.next_bookmark += 1;
        let id = self.next_bookmark;
        list.push(Bookmark { id, end_s, window_s });
        if list.len() > MAX_BOOKMARKS {
            list.remove(0);
        }
        id
    }

    pub fn bookmark_remove(&mut self, host: MonitorId, id: u32) -> bool {
        let Some(list) = self.bookmarks.get_mut(&host) else { return false };
        let n = list.len();
        list.retain(|b| b.id != id);
        list.len() != n
    }

    pub fn bookmark(&self, host: MonitorId, id: u32) -> Option<Bookmark> {
        self.bookmarks.get(&host)?.iter().find(|b| b.id == id).copied()
    }

    pub fn bookmarks_of(&self, host: MonitorId) -> &[Bookmark] {
        self.bookmarks.get(&host).map_or(&[], Vec::as_slice)
    }

    /// New connection: stream times restart, old bookmarks are meaningless.
    pub fn clear_bookmarks(&mut self) {
        self.bookmarks.clear();
    }

    /// Is the overview timeline of view `id` on?
    pub fn overview_on(&self, id: MonitorId) -> bool {
        id.overview().is_some() && self.overview.get(&id).copied().unwrap_or_else(|| id.overview_default())
    }

    pub fn viewport(&self, id: MonitorId) -> Viewport {
        self.viewports.get(&id).copied().unwrap_or_else(|| Viewport::new(id.spec()))
    }

    pub fn set(&mut self, id: MonitorId, vp: Viewport) {
        self.viewports.insert(id, vp);
    }

    /// Persisted part: window length per monitor.
    pub fn windows(&self) -> BTreeMap<MonitorId, f64> {
        self.viewports.iter().map(|(k, v)| (*k, v.window_s)).collect()
    }

    /// Restore window lengths (clamped; Follow on start).
    pub fn restore_windows(&mut self, w: &BTreeMap<MonitorId, f64>) {
        for (id, s) in w {
            let mut vp = Viewport::new(id.spec());
            vp.set_window(id.spec(), *s);
            self.viewports.insert(*id, vp);
        }
    }

    /// Back to Follow everywhere (device change / disconnect).
    pub fn follow_all(&mut self) {
        self.viewports.values_mut().for_each(Viewport::follow);
    }
}

/// Bands value scale: log absolute (dB) or relative share.
///
/// Aggregation (documented in `docs/ui-port/monitors.md`): per band, the
/// **linear** power (µV²/Hz, `10^log10`) is averaged over the selected
/// electrodes (non-finite values skipped). Absolute = `10·log10(mean)` in dB.
/// Relative = `mean_band / Σ mean_visible_bands × 100` over the **visible**
/// bands only, so the shown lines sum to 100 %; hidden bands get `None`.
/// A zero, negative or non-finite total gives `None` for every band.
pub fn band_values(s: &BandSnapshot, channels: &[usize], visible: [bool; 5], relative: bool) -> [Option<f32>; 5] {
    let mut mean = [None; 5];
    for band in Band::ALL {
        let lin: Vec<f64> = channels
            .iter()
            .filter_map(|&ch| s.power(ch, band))
            .map(|l| 10f64.powf(f64::from(l)))
            .filter(|v| v.is_finite() && *v >= 0.0)
            .collect();
        if !lin.is_empty() {
            mean[band.index()] = Some(lin.iter().sum::<f64>() / lin.len() as f64);
        }
    }
    if !relative {
        return mean.map(|m| m.filter(|v| *v > 0.0).map(|v| (10.0 * v.log10()) as f32));
    }
    let total: f64 = Band::ALL.iter().filter(|b| visible[b.index()]).filter_map(|b| mean[b.index()]).sum();
    if !(total.is_finite() && total > 0.0) {
        return [None; 5];
    }
    let mut out = [None; 5];
    for band in Band::ALL.into_iter().filter(|b| visible[b.index()]) {
        out[band.index()] = mean[band.index()].map(|v| (v / total * 100.0) as f32);
    }
    out
}

/// Follow trails the newest data by this much (Flutter
/// `bandsFollowLeadSeconds`), so the right edge can glide at presentation
/// speed while snapshots arrive in ~0.1 s steps with jitter.
pub const FOLLOW_LEAD_S: f64 = 1.0;
/// Data-clock vs prediction error beyond which [`FollowClock`] re-anchors
/// (stream stalled and resumed, a new device, a clock jump).
pub const FOLLOW_RESYNC_S: f64 = 2.0;
/// Share of the data-clock error corrected per new snapshot.
const FOLLOW_SLEW: f64 = 0.1;

/// Smooth Follow right edge: maps monotonic presentation time (seconds, e.g.
/// egui `input.time`) onto session data time. Only moves the viewport; the
/// drawn points keep their true timestamps and nothing is interpolated.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct FollowClock {
    /// `(data_s, now_s)`: data time `data_s` corresponds to presentation `now_s`.
    anchor: Option<(f64, f64)>,
    newest: f64,
    last_end: Option<f64>,
}

impl FollowClock {
    /// Right edge at presentation time `now` with data up to `newest`:
    /// advances with `now`, never passes `newest`, never steps back (unless
    /// re-anchored).
    pub fn end(&mut self, newest: f64, now: f64, lead: f64) -> f64 {
        if !(newest.is_finite() && now.is_finite()) {
            return newest;
        }
        let lead = finite_or(lead, 0.0).max(0.0);
        let resync = match self.anchor {
            None => true,
            Some((d, w)) => {
                let predicted = d + (now - w);
                if now < w || (predicted - newest).abs() > FOLLOW_RESYNC_S + lead {
                    true
                } else {
                    if newest != self.newest {
                        // A new snapshot: slew toward the data clock.
                        self.anchor = Some((predicted + (newest - predicted) * FOLLOW_SLEW, now));
                    }
                    false
                }
            }
        };
        if resync {
            self.anchor = Some((newest, now));
            self.last_end = None;
        }
        self.newest = newest;
        let (d, w) = self.anchor.unwrap_or((newest, now));
        let mut end = (d + (now - w) - lead).min(newest);
        if let Some(last) = self.last_end {
            end = end.max(last).min(newest.max(last));
        }
        self.last_end = Some(end);
        end
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SPAN: Span = Span { oldest_s: 0.0, newest_s: 100.0, ahead_s: 0.0 };

    fn bands() -> WindowSpec {
        MonitorId::Bands.spec()
    }

    #[test]
    fn window_is_clamped_and_nan_safe() {
        let mut v = Viewport::new(bands());
        v.set_window(bands(), 1.0);
        assert_eq!(v.window_s, 5.0);
        v.set_window(bands(), 1e9);
        assert_eq!(v.window_s, 3600.0);
        v.set_window(bands(), f64::NAN);
        assert_eq!(v.window_s, 30.0);
    }

    #[test]
    fn zoom_keeps_the_time_under_the_focal_point() {
        let mut v = Viewport { window_s: 40.0, end_s: Some(80.0) };
        // window 40..80; focal 0.25 = t 50.
        v.zoom(bands(), SPAN, 2.0, 0.25);
        assert_eq!(v.window_s, 20.0);
        let (s, e) = v.range(SPAN);
        assert!((s + 0.25 * 20.0 - 50.0).abs() < 1e-9, "{s}..{e}");
        assert!(!v.following());
    }

    #[test]
    fn zoom_at_right_edge_keeps_follow_elsewhere_inspects() {
        let mut v = Viewport::new(bands());
        v.zoom(bands(), SPAN, 2.0, 1.0);
        assert!(v.following());
        assert_eq!(v.window_s, 15.0);
        v.zoom(bands(), SPAN, 0.5, 0.5);
        assert!(!v.following());
    }

    #[test]
    fn zoom_out_clamps_to_cap_and_data() {
        let mut v = Viewport { window_s: 60.0, end_s: Some(60.0) };
        v.zoom(bands(), SPAN, 0.001, 0.0);
        assert_eq!(v.window_s, 3600.0);
        // less data than the window: right edge sits at newest.
        assert_eq!(v.end_s, Some(100.0));
        v.zoom(bands(), SPAN, 0.0, 0.5);
        v.zoom(bands(), SPAN, f64::INFINITY, 0.5);
        assert_eq!(v.window_s, 3600.0);
    }

    #[test]
    fn pan_enters_inspect_and_clamps() {
        let mut v = Viewport { window_s: 30.0, end_s: None };
        v.pan(SPAN, -10.0);
        assert_eq!(v.end_s, Some(90.0));
        v.pan(SPAN, -1000.0);
        assert_eq!(v.end_s, Some(30.0));
        v.pan(SPAN, 1000.0);
        assert_eq!(v.end_s, Some(100.0));
        assert!(!v.following());
        v.follow();
        assert!(v.following());
        v.inspect(SPAN, Some(f64::NAN));
        assert_eq!(v.end_s, Some(100.0));
    }

    #[test]
    fn ticks_and_labels() {
        assert_eq!(tick_step_s(30.0, 6), 5.0);
        assert_eq!(tick_step_s(120.0, 6), 30.0);
        assert_eq!(tick_step_s(1800.0, 6), 300.0);
        assert_eq!(mmss(125.7), "2:05");
        assert_eq!(mmss(-3.0), "0:00");
        assert_eq!(mmss(f64::NAN), "0:00");
    }

    fn snap(rows: Vec<[f32; 5]>) -> BandSnapshot {
        BandSnapshot { time: 0.0, powers: rows }
    }

    #[test]
    fn relative_uses_linear_power_of_visible_bands() {
        // linear powers 1, 10, 100, 1000, 0.1 (log10 0,1,2,3,-1)
        let s = snap(vec![[0.0, 1.0, 2.0, 3.0, -1.0]]);
        let all = band_values(&s, &[0], [true; 5], true);
        let sum: f32 = all.iter().flatten().sum();
        assert!((sum - 100.0).abs() < 1e-3);
        assert!((all[3].unwrap() - 1000.0 / 1111.1 * 100.0).abs() < 1e-2);
        let some = band_values(&s, &[0], [true, true, false, false, false], true);
        assert!((some[0].unwrap() - 100.0 / 11.0).abs() < 1e-3);
        assert_eq!(some[2], None);
    }

    #[test]
    fn electrodes_average_in_linear_units() {
        let s = snap(vec![[0.0; 5], [2.0; 5]]);
        let abs = band_values(&s, &[0, 1], [true; 5], false);
        // mean(1, 100) = 50.5 -> 17.03 dB (not mean of logs = 10 dB).
        assert!((abs[0].unwrap() - 10.0 * 50.5f32.log10()).abs() < 1e-3);
    }

    #[test]
    fn invalid_totals_give_no_values() {
        let s = snap(vec![[f32::NAN; 5]]);
        assert_eq!(band_values(&s, &[0], [true; 5], true), [None; 5]);
        assert_eq!(band_values(&s, &[0], [true; 5], false), [None; 5]);
        let s = snap(vec![[1.0; 5]]);
        assert_eq!(band_values(&s, &[0], [false; 5], true), [None; 5]);
        assert_eq!(band_values(&s, &[7], [true; 5], true), [None; 5]);
    }

    #[test]
    fn selection_falls_back_to_all() {
        let ch: Vec<String> = ["TP9", "AF7", "AF8", "TP10"].map(String::from).to_vec();
        let mut d = BandsDisplay::default();
        assert_eq!(d.selected(&ch), vec![0, 1, 2, 3]);
        d.electrodes = vec!["AF8".into(), "X".into()];
        assert_eq!(d.selected(&ch), vec![2]);
    }

    #[test]
    fn windows_persist_round_trip() {
        let mut m = Monitors::default();
        let mut v = m.viewport(MonitorId::Bands);
        v.set_window(bands(), 60.0);
        v.end_s = Some(5.0);
        m.set(MonitorId::Bands, v);
        let j = serde_json::to_string(&m.windows()).unwrap();
        let mut back = Monitors::default();
        back.restore_windows(&serde_json::from_str(&j).unwrap());
        assert_eq!(back.viewport(MonitorId::Bands), Viewport { window_s: 60.0, end_s: None });
    }

    #[test]
    fn follow_clock_glides_between_snapshots() {
        let mut c = FollowClock::default();
        // Snapshots every 0.1 s, frames every 1/60 s.
        let mut prev = f64::NEG_INFINITY;
        let mut steps = Vec::new();
        for f in 0..600 {
            let now = f64::from(f) / 60.0;
            let newest = 100.0 + (now * 10.0).floor() / 10.0;
            let e = c.end(newest, now, FOLLOW_LEAD_S);
            assert!(e <= newest + 1e-9, "never past the data");
            if prev.is_finite() {
                assert!(e >= prev - 1e-12, "monotonic");
                steps.push(e - prev);
            }
            prev = e;
        }
        // After settling every frame advances ~1/60 s (no 0.1 s jumps).
        let tail = &steps[120..];
        assert!(tail.iter().all(|d| (d - 1.0 / 60.0).abs() < 0.004), "{tail:?}");
        assert!((prev - (100.0 + 9.9 - FOLLOW_LEAD_S)).abs() < 0.2, "{prev}");
    }

    #[test]
    fn follow_clock_stops_at_the_data_and_resyncs() {
        let mut c = FollowClock::default();
        for f in 0..60 {
            let now = f64::from(f) / 30.0;
            c.end(10.0 + now, now, 1.0);
        }
        // Stream stalls at 12.0: the edge reaches the newest data and stays.
        let mut e = 0.0;
        for f in 60..300 {
            e = c.end(12.0, f64::from(f) / 30.0, 1.0);
        }
        assert!((e - 12.0).abs() < 1e-9);
        // A new device starting at 0: re-anchor at once, not stuck at 12.
        let e = c.end(0.5, 10.1, 1.0);
        assert!((e - (0.5 - 1.0)).abs() < 1e-9, "{e}");
        assert!(c.end(f64::NAN, 10.2, 1.0).is_nan());
    }
}
