#![allow(clippy::unwrap_used, clippy::panic)]
//! Band snapshot cadence: at most 4 Hz on a source-time grid
//! (`signal::BAND_INTERVAL_S`). The simulator delivers packets per 0.1 s
//! session tick; real devices deliver their own packet sizes, so the grid is
//! also tested with direct packets (12-sample Muse-like, bursts).
//! A snapshot's time is its true window end (the packet that crossed the
//! tick), so single intervals vary by up to one packet (12 / 256 s) around
//! 0.25 s while the rate stays locked to 4 Hz.
use nf_core::signal::{Signal, BAND_INTERVAL_S};
use nf_core::{EegPacket, MainsMode};
use serde_json::json;

fn deltas(t: &[f64]) -> Vec<f64> {
    t.windows(2).map(|w| w[1] - w[0]).collect()
}

#[test]
fn simulator_bands_are_4_hz() {
    for id in ["sim:muse_s", "sim:crown"] {
        let mut s = nf_core::Session::new();
        s.call("device.connect", json!({ "id": id })).unwrap();
        s.call("clock.advance", json!({ "seconds": 20.0 })).unwrap();
        let t: Vec<f64> = s.state().bands.iter().map(|x| x.time).collect();
        let d = deltas(&t);
        assert!(d.iter().all(|x| *x > BAND_INTERVAL_S - 0.05), "{id}: one snapshot per tick: {d:?}");
        let span = t.last().unwrap() - t[0];
        assert!(t.len() as f64 <= span / BAND_INTERVAL_S + 1.0 + 1e-9, "{id}: never above 4 Hz");
        let mean = d.iter().sum::<f64>() / d.len() as f64;
        assert!((mean - 0.25).abs() < 0.02, "{id}: {mean}");
    }
}

fn info(n: usize) -> nf_core::DeviceInfo {
    let mut i = nf_sim::sim_info(if n == 8 { nf_core::DeviceKind::Crown } else { nf_core::DeviceKind::Muse });
    i.channels.truncate(n);
    i
}

/// Feed `seconds` of 256 Hz data in packets of `per` samples per channel;
/// returns the snapshot times.
fn feed(sig: &mut Signal, n: usize, t0: f64, seconds: f64, per: usize) -> Vec<f64> {
    let rate = 256.0;
    let total = (seconds * rate) as usize;
    let mut out = Vec::new();
    let mut i = 0;
    while i < total {
        let k = per.min(total - i);
        let time = t0 + (i + k) as f64 / rate;
        for ch in 0..n {
            let samples: Vec<f32> = (0..k).map(|j| ((i + j) as f32 * 0.245).sin() * 20.0).collect();
            let p = EegPacket { electrode: u16::try_from(ch).unwrap(), time, samples };
            if let Some(s) = sig.push(&p) {
                out.push(s.time);
            }
        }
        i += k;
    }
    out
}

#[test]
fn source_time_grid_with_real_packet_sizes() {
    for n in [4usize, 8] {
        let mut sig = Signal::new(&info(n), MainsMode::Auto);
        // Muse-like 12-sample packets (~21 Hz per channel).
        let t = feed(&mut sig, n, 0.0, 10.0, 12);
        let d = deltas(&t);
        let pkt = 12.0 / 256.0;
        assert!(d.iter().all(|x| (0.25 - pkt - 1e-9..=0.25 + pkt + 1e-9).contains(x)), "{n} ch: {d:?}");
        assert!((34..=38).contains(&t.len()), "{n} ch: {} snapshots in 10 s", t.len());
    }
}

#[test]
fn bursts_give_one_snapshot_not_a_backlog() {
    let mut sig = Signal::new(&info(4), MainsMode::Auto);
    feed(&mut sig, 4, 0.0, 2.0, 12);
    // 2 s arrive at once (BLE stall flushed): one snapshot, on the newest window.
    let t = feed(&mut sig, 4, 2.0, 2.0, 512);
    assert_eq!(t.len(), 1, "{t:?}");
    assert!((t[0] - 4.0).abs() < 1e-9);
    // Then the grid continues at 4 Hz.
    let t = feed(&mut sig, 4, 4.0, 1.0, 12);
    assert!(deltas(&t).iter().all(|x| *x > 0.25 - 0.05), "{t:?}");
}

#[test]
fn device_change_starts_a_new_grid() {
    let mut s = nf_core::Session::new();
    s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
    s.call("clock.advance", json!({ "seconds": 5.0 })).unwrap();
    s.call("device.connect", json!({ "id": "sim:crown" })).unwrap();
    s.call("clock.advance", json!({ "seconds": 5.0 })).unwrap();
    let t: Vec<f64> = s.state().bands.iter().map(|x| x.time).collect();
    assert!(!t.is_empty());
    assert!(deltas(&t).iter().all(|x| *x > 0.25 - 0.05), "{t:?}");
}

#[test]
fn one_hz_is_supported_by_the_same_scheduler() {
    let mut sig = Signal::new(&info(8), MainsMode::Auto).with_band_interval(1.0);
    assert_eq!(sig.band_interval_s(), 1.0);
    let t = feed(&mut sig, 8, 0.0, 10.0, 12);
    assert!((9..=10).contains(&t.len()), "{t:?}");
    assert!(deltas(&t).iter().all(|x| (x - 1.0).abs() <= 12.0 / 256.0 + 1e-9), "{t:?}");
    // Out-of-range values clamp; faster than 4 Hz is not possible.
    assert_eq!(Signal::new(&info(4), MainsMode::Auto).with_band_interval(0.01).band_interval_s(), BAND_INTERVAL_S);
}
