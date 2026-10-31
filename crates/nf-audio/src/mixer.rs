//! Renders a [`Cue`] to stereo frames. Lives on the audio thread; the host
//! calls [`Mixer::set_cue`] / [`Mixer::trigger`] and pulls [`Mixer::render`].
//! Clips are decoded by the host ([`Mixer::missing`] lists what is needed).

use crate::cue::{Background, Cue, GuardSound, RewardOutput};
use crate::dsp::{Binaural, Pcm, Slew, Voice};
use crate::outputs::{self as o, RAIN_INITIAL_STAGE};
use std::sync::Arc;

/// Bundled clips.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Asset {
    Rain,
    Drone,
    DroneLoop,
    /// Reward chime.
    BowlLow,
    /// Guard "soft bowl".
    BowlHigh,
    /// Guard "chime".
    Bell,
    Cough1,
    Cough2,
    Cough3,
    Alarm,
}

impl Asset {
    pub const ALL: [Asset; 10] = [
        Asset::Rain,
        Asset::Drone,
        Asset::DroneLoop,
        Asset::BowlLow,
        Asset::BowlHigh,
        Asset::Bell,
        Asset::Cough1,
        Asset::Cough2,
        Asset::Cough3,
        Asset::Alarm,
    ];

    /// File name under `assets/audio/ogg/`.
    pub fn file(self) -> &'static str {
        match self {
            Asset::Rain => "rain.ogg",
            Asset::Drone => "drone.ogg",
            Asset::DroneLoop => "drone-loop.ogg",
            Asset::BowlLow => "bowl-low.ogg",
            Asset::BowlHigh => "bowl-high.ogg",
            Asset::Bell => "bell.ogg",
            Asset::Cough1 => "guard-cough-01.ogg",
            Asset::Cough2 => "guard-cough-02.ogg",
            Asset::Cough3 => "guard-cough-03.ogg",
            Asset::Alarm => "guard-alarm.ogg",
        }
    }

    fn index(self) -> usize {
        Asset::ALL.iter().position(|a| *a == self).unwrap_or(0)
    }
}

/// Event-driven one-shots.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OneShot {
    /// Rising edge into target (reward output `chime`).
    Reward,
    /// Guard warning (rate-limited by the engine).
    Guard,
}

const MAX_SHOTS: usize = 8;

pub struct Mixer {
    rate: f64,
    cue: Cue,
    bank: [Option<Arc<Pcm>>; 10],
    background: Voice,
    reward: Voice,
    alarm: Voice,
    binaural: Binaural,
    bg_binaural: Binaural,
    shots: Vec<Voice>,
    music: Vec<Arc<Pcm>>,
    track: usize,
    rain_stage: usize,
    cough: usize,
    alarm_s: f64,
    master: Slew,
    scratch: Vec<f32>,
}

impl Mixer {
    pub fn new(rate: u32) -> Self {
        let rate = f64::from(rate.max(8000));
        let cue = Cue::silent(Default::default());
        Self {
            rate,
            cue,
            bank: Default::default(),
            background: Voice::new(rate, 16_000.0, 0.5),
            reward: Voice::new(rate, o::RAIN_CUTOFFS[RAIN_INITIAL_STAGE], o::RAIN_SLEW_S),
            alarm: Voice::new(rate, 16_000.0, 0.5),
            binaural: Binaural::new(rate),
            bg_binaural: Binaural::new(rate),
            shots: Vec::new(),
            music: Vec::new(),
            track: 0,
            rain_stage: RAIN_INITIAL_STAGE,
            cough: 0,
            alarm_s: 0.0,
            master: Slew::new(0.0, 0.05, rate),
            scratch: Vec::new(),
        }
    }

    pub fn rate(&self) -> u32 {
        self.rate as u32
    }

    pub fn insert(&mut self, asset: Asset, pcm: Arc<Pcm>) {
        self.bank[asset.index()] = Some(pcm);
        let cue = self.cue;
        self.set_cue(cue);
    }

    /// Music tracks for the `music` output (played in order, looping list).
    pub fn set_music(&mut self, tracks: Vec<Arc<Pcm>>) {
        self.music = tracks;
        self.track = 0;
        let cue = self.cue;
        self.set_cue(cue);
    }

    pub fn has_music(&self) -> bool {
        !self.music.is_empty()
    }

    /// Current rain stage 1..=5 (debug / MCP).
    pub fn rain_stage(&self) -> usize {
        self.rain_stage + 1
    }

    /// Clips this cue can use that are not loaded yet.
    pub fn missing(&self, cue: &Cue) -> Vec<Asset> {
        let s = cue.settings;
        let mut want = vec![Asset::BowlLow];
        want.extend(bg_asset(s.background));
        if s.reward == RewardOutput::Rain {
            want.push(Asset::Rain);
        }
        want.extend(match s.guard {
            GuardSound::SoftBowl => vec![Asset::BowlHigh],
            GuardSound::Chime => vec![Asset::Bell],
            GuardSound::Cough => vec![Asset::Cough1, Asset::Cough2, Asset::Cough3],
            GuardSound::Alarm => vec![Asset::Alarm],
            GuardSound::None => vec![],
        });
        want.retain(|a| self.bank[a.index()].is_none());
        want
    }

    fn clip(&self, a: Asset) -> Option<Arc<Pcm>> {
        self.bank[a.index()].clone()
    }

    pub fn set_cue(&mut self, cue: Cue) {
        self.cue = cue;
        let s = cue.settings;
        self.master.target = if s.muted { 0.0 } else { s.master };
        self.set_background(&cue);
        self.set_reward(&cue);
        let alarm_on = cue.reward_on && cue.warning && s.guard == GuardSound::Alarm;
        self.alarm.set_pcm(self.clip(Asset::Alarm));
        if !alarm_on {
            self.alarm_s = 0.0;
        }
        self.alarm.gain.target = if alarm_on { s.guard_volume * o::alarm_ramp(self.alarm_s) } else { 0.0 };
    }

    fn set_background(&mut self, cue: &Cue) {
        let s = cue.settings;
        let clash = s.background == Background::Rain && s.reward == RewardOutput::Rain
            || s.background == Background::Binaural && s.reward == RewardOutput::Binaural;
        let on = cue.background_on && !clash;
        self.background.set_pcm(bg_asset(s.background).and_then(|a| self.clip(a)));
        self.background.gain.target = if on && s.background != Background::Binaural { s.background_volume } else { 0.0 };
        let (_, _, beat, carrier) = s.binaural.spec();
        self.bg_binaural.set_preset(beat, carrier);
        let muffle = if cue.muffle { o::BINAURAL_MUFFLE } else { 1.0 };
        self.bg_binaural.gain.target = if on && s.background == Background::Binaural { s.background_volume * muffle } else { 0.0 };
    }

    fn set_reward(&mut self, cue: &Cue) {
        let s = cue.settings;
        let on = cue.reward_on;
        let pct = cue.pct;
        self.binaural.gain.target = 0.0;
        match s.reward {
            RewardOutput::Rain => {
                if let Some(p) = pct {
                    self.rain_stage = o::rain_stage(self.rain_stage, p);
                }
                self.reward.set_pcm(self.clip(Asset::Rain));
                self.reward.filtered = true;
                self.reward.cutoff.set_tau(o::RAIN_SLEW_S, self.rate);
                let (vol, cut) = if cue.muffle {
                    (o::RAIN_MUFFLE_VOLUME, o::RAIN_MUFFLE_CUTOFF)
                } else {
                    (o::RAIN_VOLUMES[self.rain_stage], o::RAIN_CUTOFFS[self.rain_stage])
                };
                self.reward.cutoff.target = cut;
                self.reward.gain.target = if on { vol * s.feedback } else { 0.0 };
            }
            RewardOutput::Music => {
                let track = self.music.get(self.track).cloned();
                self.reward.set_pcm(track);
                self.reward.filtered = true;
                self.reward.cutoff.set_tau(o::MUSIC_SLEW_S, self.rate);
                let cut = if cue.muffle {
                    s.music_min_hz
                } else {
                    o::music_cutoff(pct.unwrap_or(50.0), s.music_min_hz, s.music_max_hz, s.music_invert)
                };
                self.reward.cutoff.target = cut;
                self.reward.gain.target = if on { s.feedback } else { 0.0 };
            }
            RewardOutput::Binaural => {
                let (_, _, beat, carrier) = s.binaural.spec();
                self.binaural.set_preset(beat, carrier);
                self.reward.gain.target = 0.0;
                self.binaural.gain.target = if on { s.feedback * o::binaural_volume(pct.unwrap_or(0.0), cue.muffle) } else { 0.0 };
            }
            RewardOutput::Chime | RewardOutput::None => self.reward.gain.target = 0.0,
        }
    }

    pub fn trigger(&mut self, shot: OneShot) {
        let s = self.cue.settings;
        let (asset, gain) = match shot {
            OneShot::Reward if s.reward == RewardOutput::Chime && !self.cue.muffle => (Some(Asset::BowlLow), s.feedback),
            OneShot::Guard => (self.guard_asset(), s.guard_volume),
            OneShot::Reward => (None, 0.0),
        };
        let Some(pcm) = asset.and_then(|a| self.clip(a)) else { return };
        let mut v = Voice::new(self.rate, 16_000.0, 0.5);
        v.looping = false;
        v.set_pcm(Some(pcm));
        v.gain = Slew::new(gain, 0.01, self.rate);
        if self.shots.len() >= MAX_SHOTS {
            self.shots.remove(0);
        }
        self.shots.push(v);
    }

    fn guard_asset(&mut self) -> Option<Asset> {
        match self.cue.settings.guard {
            GuardSound::SoftBowl => Some(Asset::BowlHigh),
            GuardSound::Chime => Some(Asset::Bell),
            GuardSound::Cough => {
                self.cough = (self.cough + 1) % 3;
                Some([Asset::Cough1, Asset::Cough2, Asset::Cough3][self.cough])
            }
            GuardSound::Alarm | GuardSound::None => None,
        }
    }

    /// Fill `out` (interleaved, `channels` per frame) with the mix.
    pub fn render(&mut self, out: &mut [f32], channels: usize) {
        let channels = channels.max(1);
        let frames = out.len() / channels;
        self.scratch.clear();
        self.scratch.resize(frames * 2, 0.0);
        let mut buf = std::mem::take(&mut self.scratch);
        self.render_stereo(&mut buf);
        for (f, frame) in out.chunks_exact_mut(channels).enumerate() {
            let (l, r) = (buf[2 * f], buf[2 * f + 1]);
            match frame {
                [m] => *m = (l + r) * 0.5,
                [a, b, rest @ ..] => {
                    *a = l;
                    *b = r;
                    rest.fill(0.0);
                }
                [] => {}
            }
        }
        self.scratch = buf;
    }

    fn render_stereo(&mut self, buf: &mut [f32]) {
        self.background.render(buf);
        self.bg_binaural.render(buf);
        self.reward.render(buf);
        self.binaural.render(buf);
        self.render_alarm(buf);
        for s in &mut self.shots {
            s.render(buf);
        }
        self.shots.retain(|s| !s.finished());
        self.next_track_if_done();
        for frame in buf.as_chunks_mut::<2>().0 {
            let g = self.master.step() as f32;
            for v in frame {
                *v = soft_clip(*v * g);
            }
        }
    }

    fn render_alarm(&mut self, buf: &mut [f32]) {
        if self.alarm.gain.target > 0.0 {
            self.alarm_s += (buf.len() / 2) as f64 / self.rate;
            self.alarm.gain.target = self.cue.settings.guard_volume * o::alarm_ramp(self.alarm_s);
        }
        self.alarm.render(buf);
    }

    fn next_track_if_done(&mut self) {
        if self.cue.settings.reward != RewardOutput::Music || self.music.len() < 2 {
            return;
        }
        self.reward.looping = false;
        if self.reward.finished() {
            self.track = (self.track + 1) % self.music.len();
            let cue = self.cue;
            self.set_cue(cue);
        }
    }
}

fn bg_asset(b: Background) -> Option<Asset> {
    match b {
        Background::Drone => Some(Asset::Drone),
        Background::DroneLoop => Some(Asset::DroneLoop),
        Background::Rain => Some(Asset::Rain),
        Background::Binaural | Background::None => None,
    }
}

/// Gentle limiter: linear below 0.8, tanh knee above.
fn soft_clip(x: f32) -> f32 {
    if x.abs() <= 0.8 {
        x
    } else {
        x.signum() * (0.8 + 0.2 * ((x.abs() - 0.8) / 0.2).tanh())
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use crate::cue::AudioSettings;

    const RATE: u32 = 48_000;

    fn noise(secs: f64) -> Arc<Pcm> {
        let mut x: u32 = 1;
        let data = (0..(f64::from(RATE) * secs) as usize)
            .map(|_| {
                x ^= x << 13;
                x ^= x >> 17;
                x ^= x << 5;
                (f64::from(x) / f64::from(u32::MAX) * 2.0 - 1.0) as f32 * 0.5
            })
            .collect();
        Arc::new(Pcm { rate: RATE, channels: 1, data })
    }

    fn rms_after(m: &mut Mixer, secs: f64) -> f64 {
        let mut out = vec![0.0; 2 * (f64::from(RATE) * secs) as usize];
        m.render(&mut out, 2);
        let tail = &out[out.len() / 2..];
        (tail.iter().map(|v| f64::from(*v).powi(2)).sum::<f64>() / tail.len() as f64).sqrt()
    }

    fn cue(reward: RewardOutput, pct: f64, muffle: bool) -> Cue {
        let settings = AudioSettings { reward, background: Background::None, master: 1.0, ..AudioSettings::default() };
        Cue { background_on: true, reward_on: true, pct: Some(pct), muffle, warning: muffle, settings }
    }

    #[test]
    fn rain_gets_quieter_as_the_percentile_rises() {
        let mut m = Mixer::new(RATE);
        m.insert(Asset::Rain, noise(2.0));
        let mut levels = Vec::new();
        for pct in [5.0, 30.0, 50.0, 70.0, 95.0] {
            m.set_cue(cue(RewardOutput::Rain, pct, false));
            levels.push(rms_after(&mut m, 2.0));
        }
        assert_eq!(m.rain_stage(), 5);
        assert!(levels.windows(2).all(|w| w[0] > w[1]), "{levels:?}");
        m.set_cue(cue(RewardOutput::Rain, 5.0, true));
        assert!(rms_after(&mut m, 2.0) < levels[1], "muffle ducks heavy rain");
    }

    #[test]
    fn binaural_swells_with_percentile_and_fades_off_target() {
        let mut m = Mixer::new(RATE);
        m.set_cue(cue(RewardOutput::Binaural, 90.0, false));
        let high = rms_after(&mut m, 2.0);
        m.set_cue(cue(RewardOutput::Binaural, 20.0, false));
        let low = rms_after(&mut m, 2.0);
        m.set_cue(cue(RewardOutput::Binaural, 90.0, true));
        let muffled = rms_after(&mut m, 2.0);
        assert!(high > 2.0 * low && low > muffled && muffled > 0.0, "{high} {low} {muffled}");
    }

    #[test]
    fn music_filter_opens_with_percentile() {
        let mut m = Mixer::new(RATE);
        m.set_music(vec![noise(3.0)]);
        m.set_cue(cue(RewardOutput::Music, 0.0, false));
        let closed = rms_after(&mut m, 3.0);
        m.set_cue(cue(RewardOutput::Music, 100.0, false));
        let open = rms_after(&mut m, 3.0);
        assert!(open > 2.0 * closed, "{open} {closed}");
    }

    #[test]
    fn one_shots_alarm_and_silence() {
        let mut m = Mixer::new(RATE);
        assert!(m.missing(&cue(RewardOutput::Chime, 50.0, false)).contains(&Asset::BowlLow));
        m.insert(Asset::BowlLow, noise(0.5));
        m.set_cue(cue(RewardOutput::Chime, 50.0, false));
        assert_eq!(rms_after(&mut m, 0.2), 0.0);
        m.trigger(OneShot::Reward);
        assert!(rms_after(&mut m, 0.2) > 0.05);
        assert_eq!(rms_after(&mut m, 1.0), 0.0, "one-shot ends");
        let mut c = cue(RewardOutput::Chime, 50.0, true);
        c.settings.guard = GuardSound::Alarm;
        m.insert(Asset::Alarm, noise(1.0));
        m.set_cue(c);
        let early = rms_after(&mut m, 2.0);
        for _ in 0..30 {
            rms_after(&mut m, 2.0);
        }
        let late = rms_after(&mut m, 2.0);
        assert!(late > 3.0 * early && early > 0.0, "alarm ramps {early} {late}");
        c.settings.muted = true;
        m.set_cue(c);
        assert!(rms_after(&mut m, 1.0) < 1e-4);
    }

    #[test]
    fn mono_and_multichannel_outputs() {
        let mut m = Mixer::new(RATE);
        m.set_cue(cue(RewardOutput::Binaural, 100.0, false));
        let mut out = vec![1.0; 4 * 4800];
        m.render(&mut out, 4);
        assert!(out.as_chunks::<4>().0.iter().all(|f| f[2] == 0.0 && f[3] == 0.0));
        let mut mono = vec![0.0; 4800];
        m.render(&mut mono, 1);
        assert!(mono.iter().any(|v| v.abs() > 0.01));
    }
}
