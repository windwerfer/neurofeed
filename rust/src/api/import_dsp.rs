//! Import DSP: resample foreign EEG to the native 256 Hz and derive 1 s band
//! records with the same FFT the live forwarder uses.

use flutter_rust_bridge::frb;
use rubato::audioadapter_buffers::direct::InterleavedSlice;
use rubato::{Fft, FixedSync, Resampler};

/// Native EEG rate every recording is stored at.
pub(crate) const NATIVE_EEG_HZ: usize = 256;

/// Resample one channel from `from_hz` to `to_hz` with rubato's synchronous
/// FFT resampler (Blackman-Harris anti-alias low-pass below the lower
/// Nyquist). Startup delay is trimmed; output length ≈ `len * to / from`.
#[frb(sync)]
pub fn resample_eeg(samples: Vec<f64>, from_hz: u32, to_hz: u32) -> Result<Vec<f64>, String> {
    if from_hz == 0 || to_hz == 0 {
        return Err("sample rate must be > 0".into());
    }
    if from_hz == to_hz || samples.is_empty() {
        return Ok(samples);
    }
    let mut resampler =
        Fft::<f64>::new(from_hz as usize, to_hz as usize, 1024, 1, FixedSync::Input)
            .map_err(|e| e.to_string())?;
    let input = InterleavedSlice::new(&samples, 1, samples.len()).map_err(|e| e.to_string())?;
    let out = resampler
        .process_all(&input, samples.len(), None)
        .map_err(|e| e.to_string())?;
    Ok(out.take_data())
}

/// Band powers for each full 1 s chunk of 256 Hz EEG, 8 values per second:
/// `[delta, theta, alpha, beta, gamma, peak_alpha_hz, peak_alpha_power,
/// line_noise_ratio]` — identical to the live band records.
#[frb(sync)]
pub fn eeg_second_bands(samples: Vec<f64>) -> Vec<f64> {
    samples
        .chunks_exact(NATIVE_EEG_HZ)
        .flat_map(crate::api::muse::compute_fft_bands)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sine(hz: f64, rate: f64, secs: f64, amp: f64) -> Vec<f64> {
        let n = (rate * secs) as usize;
        (0..n)
            .map(|i| amp * (2.0 * std::f64::consts::PI * hz * i as f64 / rate).sin())
            .collect()
    }

    fn rms(v: &[f64]) -> f64 {
        (v.iter().map(|x| x * x).sum::<f64>() / v.len() as f64).sqrt()
    }

    #[test]
    fn resample_512_to_256_keeps_length_and_passband() {
        let x = sine(10.0, 512.0, 8.0, 50.0);
        let y = resample_eeg(x, 512, 256).unwrap();
        assert!((y.len() as i64 - 2048).abs() <= 2, "len {}", y.len());
        let mid = &y[256..1792];
        assert!((rms(mid) - 50.0 / 2f64.sqrt()).abs() < 1.0, "rms {}", rms(mid));
    }

    #[test]
    fn resample_attenuates_above_new_nyquist() {
        let x = sine(200.0, 512.0, 8.0, 50.0);
        let y = resample_eeg(x, 512, 256).unwrap();
        assert!(rms(&y[256..1792]) < 1.0, "alias rms {}", rms(&y[256..1792]));
    }

    #[test]
    fn resample_220_to_256_length() {
        let x = sine(10.0, 220.0, 10.0, 20.0);
        let y = resample_eeg(x, 220, 256).unwrap();
        assert!((y.len() as i64 - 2560).abs() <= 2, "len {}", y.len());
    }

    #[test]
    fn second_bands_one_record_per_full_second() {
        let x = sine(10.0, 256.0, 3.5, 20.0);
        let b = eeg_second_bands(x);
        assert_eq!(b.len(), 3 * 8);
        let alpha = b[2];
        assert!(alpha > b[0] && alpha > b[1] && alpha > b[3] && alpha > b[4]);
    }
}
