//! Feedback audio host. Core computes a [`Cue`] (what should sound);
//! `nf_audio::Mixer` renders it; this module only owns the device stream
//! and decodes clips off the audio thread.
//! Desktop: cpal (feature `native-audio`, default), silent without a device.
//! Web: a Web Audio ScriptProcessorNode pulling from the mixer.

use nf_core::nf_audio::{Asset, Cue, OneShot, Pcm};

pub trait Audio {
    /// Apply the current cue (cheap when unchanged); `music_dir` is the
    /// desktop music folder.
    fn update(&mut self, cue: &Cue, music_dir: Option<&str>);
    fn trigger(&mut self, shot: OneShot);
}

/// Logs instead of playing.
pub struct Silent;

impl Audio for Silent {
    fn update(&mut self, _: &Cue, _: Option<&str>) {}
    fn trigger(&mut self, shot: OneShot) {
        log::debug!("{shot:?}");
    }
}

/// Bundled clip bytes (Ogg Vorbis, see assets/audio/README.md).
pub fn asset_bytes(a: Asset) -> &'static [u8] {
    match a {
        Asset::Rain => include_bytes!("../../../assets/audio/ogg/rain.ogg"),
        Asset::Drone => include_bytes!("../../../assets/audio/ogg/drone.ogg"),
        Asset::DroneLoop => include_bytes!("../../../assets/audio/ogg/drone-loop.ogg"),
        Asset::BowlLow => include_bytes!("../../../assets/audio/ogg/bowl-low.ogg"),
        Asset::BowlHigh => include_bytes!("../../../assets/audio/ogg/bowl-high.ogg"),
        Asset::Bell => include_bytes!("../../../assets/audio/ogg/bell.ogg"),
        Asset::Cough1 => include_bytes!("../../../assets/audio/ogg/guard-cough-01.ogg"),
        Asset::Cough2 => include_bytes!("../../../assets/audio/ogg/guard-cough-02.ogg"),
        Asset::Cough3 => include_bytes!("../../../assets/audio/ogg/guard-cough-03.ogg"),
        Asset::Alarm => include_bytes!("../../../assets/audio/ogg/guard-alarm.ogg"),
    }
}

pub fn decode_asset(a: Asset) -> Option<Pcm> {
    match nf_core::nf_audio::decode::decode(asset_bytes(a).to_vec(), Some("ogg")) {
        Ok(p) => Some(p),
        Err(e) => {
            log::warn!("{}: {e}", a.file());
            None
        }
    }
}

/// A cue worth opening the device for.
fn audible(cue: &Cue) -> bool {
    !cue.settings.muted && (cue.background_on || cue.reward_on)
}

#[cfg(all(not(target_arch = "wasm32"), feature = "native-audio"))]
mod native;

#[cfg(target_arch = "wasm32")]
mod web;

/// The platform's audio backend.
pub fn platform() -> Box<dyn Audio> {
    #[cfg(target_arch = "wasm32")]
    return Box::new(web::WebAudio::default());
    #[cfg(all(not(target_arch = "wasm32"), feature = "native-audio"))]
    return Box::new(native::Cpal::default());
    #[cfg(all(not(target_arch = "wasm32"), not(feature = "native-audio")))]
    Box::new(Silent)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_bundled_clip_decodes() {
        for a in Asset::ALL {
            let p = decode_asset(a).unwrap_or_else(|| panic!("{}", a.file()));
            assert!(p.seconds() > 0.5, "{}", a.file());
        }
    }
}
