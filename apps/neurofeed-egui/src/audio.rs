//! Feedback audio: the reward chime only, behind a small trait.
//! Web: a short Web Audio sine tone. Desktop: silent stub for now (a native
//! backend such as cpal can implement `Audio` later).

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

/// The platform's audio backend.
pub fn platform() -> Box<dyn Audio> {
    #[cfg(target_arch = "wasm32")]
    return Box::new(WebAudio { ctx: None });
    #[cfg(not(target_arch = "wasm32"))]
    Box::new(Silent)
}
