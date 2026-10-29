//! L1 EEG signal processing. Pure functions and small streaming state, no
//! allocation-heavy deps, no clock, no I/O: safe for WASM and for tests with
//! known answers.
//!
//! Ported from `rust/src/analysis/eeg_filter.rs` (biquads, generalised to any
//! sample rate) plus a self-contained radix-2 FFT, Hamming single-window
//! PSD, mains detection, pad quality, band features, and the five-band power math the Bands view and features use.

mod bands;
mod features;
mod fft;
mod filter;
mod mains;
mod quality;

pub use bands::{
    band_powers, band_powers_linear, dominant_band, histogram, line_noise_fraction, mains_peak_ratio, peak_frequency, psd, psd_db, Psd,
    BANDS_HZ, MAX_PSD_HZ,
};
pub use features::{band_feature, FEATURE_IDS};
pub use fft::fft_in_place;
pub use filter::{notch_frequencies, Biquad, EegFilter, Mains, HIGHPASS_HZ, NOTCH_Q};
pub use mains::{mains_vote, MainsDetector, DETECT_WINDOW, LOCK_VOTES, PEAK_RATIO, SWITCH_VOTES};
pub use quality::{pad_quality, sample_std, MIN_QUALITY_SAMPLES, USABLE_QUALITY};
