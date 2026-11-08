//! Overview timeline toggles, Histogram pooling and Spectrogram history.
#![allow(clippy::panic, clippy::unwrap_used)]

use nf_core::monitor::MonitorId;
use nf_core::Session;
use nf_store::Store;
use serde_json::json;

fn live(dev: &str, seconds: f64) -> Session {
    let mut s = Session::new();
    s.call("device.connect", json!({ "id": dev })).unwrap();
    s.call("clock.advance", json!({ "seconds": seconds })).unwrap();
    s
}

fn reload(s: &Session) -> Session {
    let doc = s.store().get_doc(nf_core::settings::DOC_KEY).unwrap().unwrap();
    let mut store = nf_store::MemoryStore::default();
    store.put_doc(nf_core::settings::DOC_KEY, Some(&doc)).unwrap();
    Session::new().with_store(Box::new(store))
}

#[test]
fn overview_defaults_toggle_and_persist_per_view() {
    let mut s = Session::new();
    let m = s.call("monitor.get", json!({})).unwrap();
    assert_eq!(m["overview"], json!({ "bands": false, "raw_eeg": false, "histogram": true, "psd": true, "spectrogram": true }));
    s.call("monitor.overview", json!({ "monitor": "bands", "on": true })).unwrap();
    s.call("monitor.overview", json!({ "monitor": "psd", "on": false })).unwrap();
    assert!(s.call("monitor.overview", json!({ "monitor": "movement", "on": true })).is_err());
    assert!(s.call("monitor.overview", json!({ "monitor": "psd_strip", "on": true })).is_err());
    let s2 = reload(&s);
    let st = &s2.state().monitors;
    assert!(st.overview_on(MonitorId::Bands) && !st.overview_on(MonitorId::Psd));
    assert!(st.overview_on(MonitorId::Spectrogram) && !st.overview_on(MonitorId::RawEeg) && st.overview_on(MonitorId::Histogram));
}

/// Histogram's minimap is on by default (owner 2026-11-08), but a saved
/// explicit "off" survives restarts: only explicit toggles are persisted, so
/// files from before the change (no histogram entry) get the new default.
#[test]
fn histogram_overview_default_on_and_explicit_off_survives_restart() {
    let mut s = Session::new();
    assert!(s.state().monitors.overview_on(MonitorId::Histogram));
    s.call("monitor.overview", json!({ "monitor": "histogram", "on": false })).unwrap();
    let mut s2 = reload(&s);
    assert!(!s2.state().monitors.overview_on(MonitorId::Histogram));
    let s3 = reload(&reload(&s2));
    assert!(!s3.state().monitors.overview_on(MonitorId::Histogram), "no re-enable on every restart");
    s2.call("monitor.overview", json!({ "monitor": "histogram", "on": true })).unwrap();
    assert!(reload(&s2).state().monitors.overview_on(MonitorId::Histogram));
    // An older settings file with only other views toggled: new default.
    let mut old = Session::new();
    old.call("monitor.overview", json!({ "monitor": "bands", "on": true })).unwrap();
    assert!(reload(&old).state().monitors.overview_on(MonitorId::Histogram));
}

#[test]
fn overview_viewports_are_independent_of_each_other_and_of_their_host() {
    let mut s = live("sim:muse", 200.0);
    s.call("monitor.pan", json!({ "monitor": "bands_overview", "seconds": -30.0 })).unwrap();
    let m = s.call("monitor.get", json!({})).unwrap()["monitors"].clone();
    assert_eq!(m["bands_overview"]["mode"], "inspect");
    for other in ["bands", "raw_overview", "histogram_overview", "spectrogram_overview", "psd_strip"] {
        assert_eq!(m[other]["mode"], "follow", "{other}");
    }
    // Overview zoom is clamped like the strip (10 s .. 1 h) and to the data.
    s.call("monitor.zoom", json!({ "monitor": "raw_overview", "factor": 1000.0 })).unwrap();
    s.call("monitor.pan", json!({ "monitor": "raw_overview", "seconds": -1.0e6 })).unwrap();
    let r = &s.call("monitor.get", json!({})).unwrap()["monitors"]["raw_overview"];
    assert_eq!(r["window_s"], 10.0);
    assert!(r["start_s"].as_f64().unwrap() >= 0.0, "{r}");
}

#[test]
fn histogram_epoch_inspects_history_and_pools_eligible_pads() {
    let mut s = live("sim:muse", 60.0);
    let h = s.call("histogram.get", json!({ "seconds": 4.0, "end_s": 30.0 })).unwrap();
    let p = &h["pooled"];
    assert_eq!(p["end_s"], 30.0);
    assert_eq!(p["start_s"], 26.0);
    assert_eq!(p["channels"].as_array().unwrap().len(), 4);
    let n: u64 = p["counts"].as_array().unwrap().iter().map(|c| c.as_u64().unwrap()).sum();
    assert_eq!(n, p["samples"].as_u64().unwrap());
    // 4 pads × 4 s × 256 Hz, all pooled (not averaged into one waveform).
    assert!((4000..=4100).contains(&n), "{n}");
    s.call("analysis.exclude", json!({ "channel": "AF7", "confirm": true })).unwrap();
    let h = s.call("histogram.get", json!({ "seconds": 4.0, "end_s": 30.0 })).unwrap();
    assert_eq!(h["pooled"]["channels"], json!(["TP9", "AF8", "TP10"]));
    s.call("monitor.histogram", json!({ "electrodes": ["AF7"] })).unwrap();
    assert!(s.call("histogram.get", json!({})).unwrap()["pooled"].is_null(), "only an excluded pad: nothing");
    s.call("monitor.viewport", json!({ "monitor": "histogram", "window_s": 8.0, "mode": "inspect", "end_s": 20.0 })).unwrap();
    let v = &s.call("monitor.get", json!({})).unwrap()["monitors"]["histogram"];
    assert_eq!((v["start_s"].as_f64().unwrap(), v["end_s"].as_f64().unwrap()), (12.0, 20.0));
}

#[test]
fn pooled_histogram_does_not_cancel_opposite_phases() {
    // Two pads in anti-phase: an average waveform would be ~0 µV (σ≈0);
    // pooling keeps the real amplitude spread.
    let mut info = live("sim:muse", 0.5).state().device.clone().unwrap();
    info.channels = vec!["A".into(), "B".into()];
    info.sample_rate_hz = 256.0;
    let mut sig = nf_core::signal::Signal::new(&info, nf_core::signal::MainsMode::Off);
    for k in 0..(256 * 6 / 16u32) {
        for ch in 0..2u8 {
            let samples: Vec<f32> = (0..16)
                .map(|i| {
                    let t = f64::from(k * 16 + i) / 256.0;
                    let v = (2.0 * std::f64::consts::PI * 10.0 * t).sin() as f32 * 40.0;
                    if ch == 0 {
                        v
                    } else {
                        -v
                    }
                })
                .collect();
            let p = nf_types::EegPacket { electrode: u16::from(ch), time: f64::from(k * 16 + 15) / 256.0, samples };
            sig.push(&p);
        }
    }
    let p = nf_core::spectrum::histogram_pooled(&sig, &[0, 1], 2.0, 6.0, 64, 100.0).unwrap();
    assert!(p.std_uv > 20.0, "σ {}", p.std_uv);
}

#[test]
fn spectrogram_keeps_300_s_bounded_memory_and_averages_linear_power() {
    let mut s = live("sim:crown", 330.0);
    let (dev, sig) = s.live_signal().unwrap();
    let n = sig.spec_times.len();
    assert_eq!(n, nf_core::signal::SPEC_COLUMNS, "capped at 300 s");
    let span = sig.spec_times.back().unwrap() - sig.spec_times.front().unwrap();
    assert!((span - 299.75).abs() < 0.3, "{span}");
    let bytes = sig.spectrogram_bytes();
    println!("spectrogram history {} ch: {bytes} B", dev.channels.len());
    assert!(bytes < 2_800_000, "{bytes}");
    // Average of two channels == 10·log10(mean linear), per column and bin.
    let a = nf_core::spectrum::spectrogram_average(sig, &[0, 1], 0.0, 1e9, 60.0);
    let (k, bin) = (a.times.len() - 1, 10);
    let lin = |ch: usize| f64::from(sig.spectrogram[ch][n - 1][bin]);
    let want = 10.0 * ((lin(0) + lin(1)) / 2.0).log10();
    assert!((f64::from(a.cols[k][bin]) - want).abs() < 1e-3);
    // Excluded channels never contribute, old columns included.
    let first = dev.channels[0].clone();
    s.call("analysis.exclude", json!({ "channel": first, "confirm": true })).unwrap();
    let g = s.call("spectrogram.get", json!({ "seconds": 300.0, "max_hz": 60.0 })).unwrap();
    assert!(!g["channels"].as_array().unwrap().contains(&json!(first)));
    assert!(g["times"].as_array().unwrap().len() >= 1190);
    assert!(s.call("spectrogram.get", json!({ "seconds": 301.0 })).is_err());
    s.call("monitor.spectrogram", json!({ "electrodes": [first] })).unwrap();
    assert!(s.call("spectrogram.get", json!({})).unwrap()["columns"].as_array().unwrap().is_empty());
}

#[test]
fn muse_spectrogram_memory() {
    let s = live("sim:muse", 310.0);
    let (_, sig) = s.live_signal().unwrap();
    println!("muse spectrogram history: {} B", sig.spectrogram_bytes());
    assert!(sig.spectrogram_bytes() < 1_400_000);
}

#[test]
fn spectrogram_lock_validates_and_persists() {
    let mut s = Session::new();
    s.call("monitor.spectrogram", json!({ "db_min": -10.0, "db_max": 30.0 })).unwrap();
    assert!(s.call("monitor.spectrogram", json!({ "db_min": 30.0, "db_max": -10.0 })).is_err());
    assert!(s.call("monitor.spectrogram", json!({ "db_min": 5.0 })).is_err());
    assert_eq!(reload(&s).state().monitors.spectrogram.db_lock, Some((-10.0, 30.0)));
    s.call("monitor.spectrogram", json!({ "auto": true })).unwrap();
    assert_eq!(reload(&s).state().monitors.spectrogram.db_lock, None);
    s.call("monitor.histogram", json!({ "range": "50" })).unwrap();
    assert_eq!(reload(&s).state().monitors.histogram.range, nf_core::monitor::HistRange::Uv50);
}

#[test]
fn spectrogram_gap_leaves_missing_columns() {
    let mut s = live("sim:muse", 20.0);
    s.call("sim.fault.add", json!({ "kind": "disconnect", "duration_s": 3.0 })).unwrap();
    s.call("clock.advance", json!({ "seconds": 15.0 })).unwrap();
    let (_, sig) = s.live_signal().unwrap();
    let t: Vec<f64> = sig.spec_times.iter().copied().collect();
    let gap = t.windows(2).map(|w| w[1] - w[0]).fold(0.0, f64::max);
    assert!(gap > 2.0, "a dropout is a hole, not filled: max step {gap}");
    assert!(t.windows(2).all(|w| w[1] > w[0]));
}

fn view(s: &mut Session, id: &str) -> serde_json::Value {
    s.call("monitor.get", json!({})).unwrap()["monitors"][id].clone()
}

#[test]
fn host_follow_reengages_its_overview_only() {
    let mut s = live("sim:muse", 400.0);
    s.call("monitor.pan", json!({ "monitor": "bands_overview", "seconds": -120.0 })).unwrap();
    s.call("monitor.pan", json!({ "monitor": "psd_strip", "seconds": -120.0 })).unwrap();
    s.call("monitor.pan", json!({ "monitor": "bands", "seconds": -60.0 })).unwrap();
    assert_eq!(view(&mut s, "bands_overview")["mode"], "inspect", "overview pan alone stays independent");
    s.call("monitor.viewport", json!({ "monitor": "bands", "mode": "follow" })).unwrap();
    assert_eq!(view(&mut s, "bands")["mode"], "follow");
    assert_eq!(view(&mut s, "bands_overview")["mode"], "follow", "explicit Follow resets both");
    assert_eq!(view(&mut s, "psd_strip")["mode"], "inspect", "other views untouched");
}

#[test]
fn overview_never_narrower_than_its_host() {
    let mut s = live("sim:muse", 100.0);
    s.call("monitor.zoom", json!({ "monitor": "bands_overview", "factor": 100.0 })).unwrap();
    assert_eq!(view(&mut s, "bands_overview")["window_s"], 10.0);
    s.call("monitor.viewport", json!({ "monitor": "bands", "window_s": 120.0 })).unwrap();
    assert_eq!(view(&mut s, "bands_overview")["window_s"], 180.0);
    s.call("monitor.zoom", json!({ "monitor": "bands", "factor": 0.0001 })).unwrap();
    assert_eq!(view(&mut s, "bands_overview")["window_s"], 3600.0);
}

#[test]
fn bookmarks_add_go_dedupe_bound_expire_and_reset() {
    let mut s = live("sim:muse", 400.0);
    let id =
        s.call("monitor.bookmark_add", json!({ "monitor": "raw_eeg", "end_s": 380.0, "window_s": 4.0 })).unwrap()["id"].as_u64().unwrap();
    let dup =
        s.call("monitor.bookmark_add", json!({ "monitor": "raw_eeg", "end_s": 380.2, "window_s": 4.0 })).unwrap()["id"].as_u64().unwrap();
    assert_eq!(id, dup, "duplicate");
    s.call("monitor.bookmark_go", json!({ "monitor": "raw_eeg", "id": id })).unwrap();
    let r = view(&mut s, "raw_eeg");
    assert_eq!((r["mode"].as_str(), r["window_s"].as_f64(), r["end_s"].as_f64()), (Some("inspect"), Some(4.0), Some(380.0)));
    assert_eq!(view(&mut s, "bands")["mode"], "follow", "other views untouched");
    // Expired: older than the 5 min ring → kept, marked, not jumped to.
    s.call("clock.advance", json!({ "seconds": 400.0 })).unwrap();
    let b = &s.call("monitor.get", json!({})).unwrap()["bookmarks"]["raw_eeg"][0];
    assert_eq!(b["available"], false);
    assert!(s.call("monitor.bookmark_go", json!({ "monitor": "raw_eeg", "id": id })).is_err());
    // Bounded: oldest dropped.
    for k in 0..10 {
        s.call("monitor.bookmark_add", json!({ "monitor": "bands", "end_s": 100.0 + f64::from(k) * 10.0, "window_s": 30.0 })).unwrap();
    }
    let list = s.call("monitor.get", json!({})).unwrap()["bookmarks"]["bands"].clone();
    assert_eq!(list.as_array().unwrap().len(), nf_core::monitor::MAX_BOOKMARKS);
    assert_eq!(list[0]["end_s"], 120.0);
    assert!(s.call("monitor.bookmark_add", json!({ "monitor": "movement" })).is_err());
    assert!(s.call("monitor.bookmark_remove", json!({ "monitor": "bands", "id": 9999 })).is_err());
    let first = list[0]["id"].as_u64().unwrap();
    s.call("monitor.bookmark_remove", json!({ "monitor": "bands", "id": first })).unwrap();
    // New connection: all cleared; never persisted.
    s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
    let all = s.call("monitor.get", json!({})).unwrap()["bookmarks"].clone();
    assert!(all.as_object().unwrap().values().all(|v| v.as_array().unwrap().is_empty()), "{all}");
    assert!(reload(&s).state().monitors.bookmarks.is_empty());
}

#[test]
fn bookmark_default_is_the_shown_window_and_reveals_in_overview() {
    let mut s = live("sim:muse", 600.0);
    s.call("monitor.viewport", json!({ "monitor": "bands", "window_s": 60.0, "mode": "inspect", "end_s": 200.0 })).unwrap();
    let id = s.call("monitor.bookmark_add", json!({ "monitor": "bands" })).unwrap()["id"].as_u64().unwrap();
    s.call("monitor.viewport", json!({ "monitor": "bands", "mode": "follow" })).unwrap();
    s.call("monitor.bookmark_go", json!({ "monitor": "bands", "id": id })).unwrap();
    let o = view(&mut s, "bands_overview");
    assert!(o["start_s"].as_f64().unwrap() <= 140.0 && o["end_s"].as_f64().unwrap() >= 200.0, "{o}");
}
