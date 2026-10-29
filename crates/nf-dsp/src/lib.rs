//! L1 EEG signal processing. Pure functions and small streaming state, no
//! allocation-heavy deps, no clock, no I/O: safe for WASM and for tests with
//! known answers.
//!
//! Ported from `rust/src/analysis/eeg_filter.rs` (biquads, generalised to any
//! sample rate) plus a self-contained radix-2 FFT, Welch-free single-window
//! PSD and the five-band power math the Bands view and features use.

mod bands;
mod fft;
mod filter;

pub use bands::{band_powers, dominant_band, line_noise_ratio, peak_frequency, psd, Psd, BANDS_HZ, MAX_PSD_HZ};
pub use fft::fft_in_place;
pub use filter::{notch_frequencies, Biquad, EegFilter, Mains, HIGHPASS_HZ, NOTCH_Q};
