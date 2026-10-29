#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use nf_dsp::*;
use std::f64::consts::TAU;

const FS: f64 = 256.0;

fn sine(hz: f64, amp: f64, secs: f64) -> Vec<f32> {
    (0..(FS * secs) as usize).map(|i| (amp * (TAU * hz * i as f64 / FS).sin()) as f32).collect()
}

#[test]
fn fft_of_impulse_is_flat() {
    let mut re = vec![0.0; 8];
    re[0] = 1.0;
    let mut im = vec![0.0; 8];
    assert!(fft_in_place(&mut re, &mut im));
    assert!(re.iter().all(|v| (v - 1.0).abs() < 1e-12) && im.iter().all(|v| v.abs() < 1e-12));
    assert!(!fft_in_place(&mut [0.0; 6], &mut [0.0; 6]));
}

#[test]
fn pure_sines_land_in_their_band() {
    for (hz, band) in [(2.0, 0), (6.0, 1), (10.0, 2), (20.0, 3), (38.0, 4)] {
        assert_eq!(dominant_band(&sine(hz, 10.0, 1.0), FS), Some(band), "{hz} Hz");
    }
    let bp = band_powers(&sine(10.0, 10.0, 1.0), FS).unwrap();
    let alpha = bp[2];
    assert!(bp.iter().enumerate().all(|(i, &b)| i == 2 || b < alpha - 1.0), "{bp:?}");
}

#[test]
fn psd_peak_and_parseval() {
    let x = sine(10.0, 10.0, 2.0);
    let p = psd(&x, FS).unwrap();
    assert!((p.df - 0.5).abs() < 1e-12);
    assert!((peak_frequency(&p, 1.0, 40.0).unwrap() - 10.0).abs() < 1e-9);
    // Integrated PSD ≈ variance of a sine (A²/2 = 50 µV²).
    let total: f64 = p.power.iter().sum::<f64>() * p.df;
    assert!((total - 50.0).abs() < 2.0, "{total}");
}

#[test]
fn filter_removes_dc_and_mains() {
    let mut f = EegFilter::new(FS, Mains::Hz50);
    assert!(f.gain_at(50.0) < 1e-3);
    assert!((f.gain_at(10.0) - 1.0).abs() < 0.05);
    assert!(f.gain_at(0.05) < 0.02);
    let hum = sine(50.0, 100.0, 4.0);
    let out: Vec<f32> = hum.iter().map(|&x| f.process(f64::from(x) + 500.0) as f32).collect();
    let tail = &out[out.len() - 256..];
    let rms = (tail.iter().map(|&v| f64::from(v).powi(2)).sum::<f64>() / 256.0).sqrt();
    assert!(rms < 2.0, "rms {rms}");
}

#[test]
fn mains_peak_ratio_flags_hum() {
    let mut x = sine(50.0, 20.0, 1.0);
    let mut s: u32 = 7;
    for v in &mut x {
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        *v += (f64::from(s) / f64::from(u32::MAX) - 0.5) as f32;
    }
    let p = psd(&x, FS).unwrap();
    assert!(mains_peak_ratio(&p, 50.0).unwrap() > 50.0);
    assert!(mains_peak_ratio(&p, 60.0).unwrap() < 5.0);
    assert!(line_noise_fraction(&p) > 0.9);
    assert_eq!(mains_vote(&x, FS), Some(50.0));
}

fn noisy(seed: u32, n: usize, amp: f64) -> Vec<f32> {
    let mut s = seed.max(1);
    (0..n)
        .map(|_| {
            s ^= s << 13;
            s ^= s >> 17;
            s ^= s << 5;
            ((f64::from(s) / f64::from(u32::MAX) - 0.5) * 2.0 * amp) as f32
        })
        .collect()
}

#[test]
fn mains_detector_locks_after_votes_and_is_final() {
    let hum: Vec<f32> = sine(60.0, 30.0, 8.0).iter().zip(noisy(3, 2048, 2.0)).map(|(a, b)| a + b).collect();
    let mut d = MainsDetector::new(FS, 1);
    let mut changed = Vec::new();
    for chunk in hum.chunks(12) {
        changed.extend(d.feed(0, chunk));
    }
    assert_eq!(changed, vec![Mains::Hz60]);
    // Final: 50 Hz afterwards changes nothing.
    for chunk in sine(50.0, 30.0, 8.0).chunks(12) {
        assert_eq!(d.feed(0, chunk), None);
    }
    // Clean signal decides None after LOCK_VOTES windows; a later hum switches after SWITCH_VOTES.
    let mut c = MainsDetector::new(FS, 1);
    for chunk in noisy(5, 256 * LOCK_VOTES as usize, 5.0).chunks(256) {
        c.feed(0, chunk);
    }
    assert_eq!(c.mains(), Mains::None);
    for chunk in sine(50.0, 30.0, f64::from(SWITCH_VOTES)).chunks(256) {
        c.feed(0, chunk);
    }
    assert_eq!(c.mains(), Mains::Hz50);
    assert!(!d.vote(None).is_some());
}

#[test]
fn pad_quality_known_answers() {
    assert_eq!(pad_quality(0.5, -1.0), 0.0);
    assert!((pad_quality(7.5, -1.0) - 90.0).abs() < 1e-9);
    assert!((pad_quality(15.0, -1.0) - 75.0).abs() < 1e-9);
    assert!((pad_quality(70.0, -1.0) - 20.0).abs() < 1e-9);
    assert!((pad_quality(7.5, 0.5) - 36.0).abs() < 1e-9, "full noise penalty = x0.4");
    assert!((sample_std(&[1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0]).unwrap() - 1.0).abs() < 1e-12);
    assert_eq!(sample_std(&[1.0; 5]), None);
}

#[test]
fn histogram_and_features() {
    let h = histogram(&[-150.0, -10.0, 10.0, 60.0, 90.0], 4, 100.0);
    // mean 0, -150 clamps to the first bin: bins [-100,-50) [-50,0) [0,50) [50,100)
    assert_eq!(h, vec![1, 1, 1, 2]);
    assert_eq!(h.iter().sum::<u32>(), 5);
    let lin = [1.0, 2.0, 4.0, 2.0, 1.0];
    assert_eq!(band_feature("band.atr", &lin), Some(2.0));
    assert_eq!(band_feature("band.tar", &lin), Some(0.5));
    assert_eq!(band_feature("band.btr", &lin), Some(1.0));
    assert_eq!(band_feature("band.alpha", &lin), Some(0.4));
    assert_eq!(band_feature("nope", &lin), None);
    assert_eq!(band_feature("band.atr", &[0.0; 5]), None);
    let p = psd(&sine(10.0, 10.0, 1.0), FS).unwrap();
    let a = band_feature("band.atr", &band_powers_linear(&p)).unwrap();
    assert!(a > 50.0, "{a}");
}
