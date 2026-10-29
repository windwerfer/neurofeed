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
fn line_noise_ratio_flags_hum() {
    let mut x = sine(50.0, 20.0, 1.0);
    let mut s: u32 = 7;
    for v in &mut x {
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        *v += (f64::from(s) / f64::from(u32::MAX) - 0.5) as f32;
    }
    let p = psd(&x, FS).unwrap();
    assert!(line_noise_ratio(&p, 50.0).unwrap() > 50.0);
    assert!(line_noise_ratio(&p, 60.0).unwrap() < 5.0);
}
