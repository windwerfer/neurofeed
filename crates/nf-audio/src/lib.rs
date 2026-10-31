//! L1: feedback audio.
//!
//! * [`cue`]: what should sound right now (pure data). `nf-core` computes a
//!   [`Cue`] from the session; MCP and tests can read it.
//! * [`outputs`]: the legacy output rules (rain stages, binaural swell,
//!   music filter, alarm ramp) as pure functions.
//! * [`mixer`]: renders a cue into stereo PCM. No device I/O: the host
//!   (cpal / Web Audio) pulls frames.
//! * [`decode`] (feature `decode`): Ogg Vorbis, MP3, FLAC, WAV into [`Pcm`].

pub mod cue;
#[cfg(feature = "decode")]
pub mod decode;
pub mod dsp;
pub mod mixer;
pub mod outputs;

pub use cue::{AudioSettings, Background, BinauralPreset, Cue, GuardSound, RewardOutput};
pub use dsp::Pcm;
pub use mixer::{Asset, Mixer, OneShot};
