//! Feedback audio: the reward chime only, behind a small trait.
//! Web: a short Web Audio sine tone. Desktop: the same tone through cpal
//! (feature `native-audio`, default), silent when no output device exists.

pub trait Audio {
    fn chime(&mut self);
}

/// Logs instead of playing.
pub struct Silent;

impl Audio for Silent {
    fn chime(&mut self) {
        log::debug!("chime");
    }
}

#[cfg(target_arch = "wasm32")]
pub struct WebAudio {
    ctx: Option<web_sys::AudioContext>,
}

#[cfg(target_arch = "wasm32")]
impl Audio for WebAudio {
    fn chime(&mut self) {
        if self.ctx.is_none() {
            self.ctx = web_sys::AudioContext::new().ok();
        }
        let Some(ctx) = &self.ctx else { return };
        let play = || -> Result<(), wasm_bindgen_futures::wasm_bindgen::JsValue> {
            let now = ctx.current_time();
            let osc = ctx.create_oscillator()?;
            let gain = ctx.create_gain()?;
            osc.frequency().set_value(660.0);
            gain.gain().set_value_at_time(0.0, now)?;
            gain.gain().linear_ramp_to_value_at_time(0.2, now + 0.02)?;
            gain.gain().exponential_ramp_to_value_at_time(0.001, now + 0.8)?;
            osc.connect_with_audio_node(&gain)?;
            gain.connect_with_audio_node(&ctx.destination())?;
            osc.start()?;
            osc.stop_with_when(now + 0.85)?;
            Ok(())
        };
        if let Err(e) = play() {
            log::warn!("chime: {e:?}");
        }
    }
}

/// Chime envelope shared by the backends: 660 Hz, 20 ms attack to 0.2,
/// exponential decay to 0.001 at 0.8 s, silent after 0.85 s.
pub const CHIME_HZ: f64 = 660.0;
pub const CHIME_S: f64 = 0.85;

/// Chime sample at `t` seconds after onset (matches the Web Audio ramps).
pub fn chime_sample(t: f64) -> f32 {
    let env = if !(0.0..CHIME_S).contains(&t) {
        0.0
    } else if t < 0.02 {
        0.2 * t / 0.02
    } else {
        // 0.2 -> 0.001 over 0.02..0.8 s.
        0.2 * (0.001f64 / 0.2).powf(((t - 0.02) / 0.78).min(1.0))
    };
    (env * (std::f64::consts::TAU * CHIME_HZ * t).sin()) as f32
}

#[cfg(all(not(target_arch = "wasm32"), feature = "native-audio"))]
mod native {
    use super::{chime_sample, Audio, CHIME_S};
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Arc;

    /// One output stream opened on the first chime and kept; each chime
    /// bumps a counter the callback watches (no allocation, no locks).
    pub struct Cpal {
        stream: Option<cpal::Stream>,
        failed: bool,
        triggers: Arc<AtomicU64>,
    }

    impl Cpal {
        pub fn new() -> Self {
            Self { stream: None, failed: false, triggers: Arc::new(AtomicU64::new(0)) }
        }

        fn open(&self) -> Result<cpal::Stream, String> {
            let device = cpal::default_host().default_output_device().ok_or("no output device")?;
            let cfg = device.default_output_config().map_err(|e| e.to_string())?;
            let rate = f64::from(cfg.sample_rate().0);
            let channels = usize::from(cfg.channels());
            let triggers = Arc::clone(&self.triggers);
            let (mut seen, mut pos) = (0u64, u64::MAX);
            let mut next = move || {
                let g = triggers.load(Ordering::Relaxed);
                if g != seen {
                    seen = g;
                    pos = 0;
                }
                let t = pos as f64 / rate;
                if t >= CHIME_S {
                    return 0.0;
                }
                pos += 1;
                chime_sample(t)
            };
            let err = |e| log::warn!("audio stream: {e}");
            let stream = match cfg.sample_format() {
                cpal::SampleFormat::F32 => device.build_output_stream(
                    &cfg.into(),
                    move |d: &mut [f32], _: &_| d.chunks_mut(channels).for_each(|f| f.fill(next())),
                    err,
                    None,
                ),
                cpal::SampleFormat::I16 => device.build_output_stream(
                    &cfg.into(),
                    move |d: &mut [i16], _: &_| d.chunks_mut(channels).for_each(|f| f.fill((next() * f32::from(i16::MAX)) as i16)),
                    err,
                    None,
                ),
                f => return Err(format!("unsupported sample format {f}")),
            }
            .map_err(|e| e.to_string())?;
            stream.play().map_err(|e| e.to_string())?;
            Ok(stream)
        }
    }

    impl Audio for Cpal {
        fn chime(&mut self) {
            if self.stream.is_none() && !self.failed {
                match self.open() {
                    Ok(s) => self.stream = Some(s),
                    Err(e) => {
                        log::warn!("chime disabled: {e}");
                        self.failed = true;
                    }
                }
            }
            self.triggers.fetch_add(1, Ordering::Relaxed);
        }
    }
}

/// The platform's audio backend.
pub fn platform() -> Box<dyn Audio> {
    #[cfg(target_arch = "wasm32")]
    return Box::new(WebAudio { ctx: None });
    #[cfg(all(not(target_arch = "wasm32"), feature = "native-audio"))]
    return Box::new(native::Cpal::new());
    #[cfg(all(not(target_arch = "wasm32"), not(feature = "native-audio")))]
    Box::new(Silent)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chime_envelope_rises_peaks_and_ends_silent() {
        let peak = |a: f64, b: f64| (0..2000).map(|i| chime_sample(a + (b - a) * f64::from(i) / 2000.0).abs()).fold(0.0f32, f32::max);
        assert!(peak(0.0, 0.005) < 0.06);
        assert!((peak(0.02, 0.03) - 0.2).abs() < 0.01);
        assert!(peak(0.7, 0.8) < 0.003);
        assert_eq!(chime_sample(0.9), 0.0);
        assert_eq!(chime_sample(-0.1), 0.0);
    }
}
