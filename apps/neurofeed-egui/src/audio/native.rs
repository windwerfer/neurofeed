//! cpal output: the callback locks the mixer and renders; decoding runs on
//! worker threads and hands finished clips to the mixer.

use super::{audible, decode_asset, Audio};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use nf_core::nf_audio::{decode, Asset, Cue, Mixer, OneShot};
use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

type Shared = Arc<Mutex<Mixer>>;

#[derive(Default)]
pub struct Cpal {
    mixer: Option<Shared>,
    stream: Option<cpal::Stream>,
    failed: bool,
    requested: HashSet<Asset>,
    last: Option<Cue>,
    music_dir: Option<String>,
}

impl Cpal {
    fn ensure_open(&mut self) -> Option<Shared> {
        if self.mixer.is_none() && !self.failed {
            match open() {
                Ok((stream, mixer)) => {
                    self.stream = Some(stream);
                    self.mixer = Some(mixer);
                }
                Err(e) => {
                    log::warn!("audio disabled: {e}");
                    self.failed = true;
                }
            }
        }
        self.mixer.clone()
    }

    fn load_missing(&mut self, mixer: &Shared, cue: &Cue) {
        let missing = mixer.lock().map(|m| m.missing(cue)).unwrap_or_default();
        let new: Vec<Asset> = missing.into_iter().filter(|a| self.requested.insert(*a)).collect();
        if new.is_empty() {
            return;
        }
        let mixer = Arc::clone(mixer);
        std::thread::spawn(move || {
            for a in new {
                if let Some(p) = decode_asset(a) {
                    if let Ok(mut m) = mixer.lock() {
                        m.insert(a, Arc::new(p));
                    }
                }
            }
        });
    }

    fn load_music(&mut self, mixer: &Shared, dir: Option<&str>) {
        if self.music_dir.as_deref() == dir {
            return;
        }
        self.music_dir = dir.map(str::to_owned);
        let mixer = Arc::clone(mixer);
        let dir = dir.map(PathBuf::from);
        std::thread::spawn(move || {
            let tracks = dir.map(|d| music_tracks(&d)).unwrap_or_default();
            log::info!("music: {} tracks", tracks.len());
            if let Ok(mut m) = mixer.lock() {
                m.set_music(tracks);
            }
        });
    }
}

/// Decode every supported file in `dir` (sorted by name).
fn music_tracks(dir: &std::path::Path) -> Vec<Arc<nf_core::nf_audio::Pcm>> {
    let mut files: Vec<PathBuf> = std::fs::read_dir(dir).map(|r| r.filter_map(Result::ok).map(|e| e.path()).collect()).unwrap_or_default();
    files.sort();
    files
        .into_iter()
        .filter_map(|p| {
            let ext = p.extension()?.to_str()?.to_lowercase();
            if !decode::EXTENSIONS.contains(&ext.as_str()) {
                return None;
            }
            let bytes = std::fs::read(&p).ok()?;
            decode::decode(bytes, Some(&ext)).map_err(|e| log::warn!("{}: {e}", p.display())).ok().map(Arc::new)
        })
        .collect()
}

impl Audio for Cpal {
    fn update(&mut self, cue: &Cue, music_dir: Option<&str>) {
        if self.last.as_ref() == Some(cue) && self.music_dir.as_deref() == music_dir {
            return;
        }
        self.last = Some(*cue);
        let mixer = if audible(cue) { self.ensure_open() } else { self.mixer.clone() };
        let Some(mixer) = mixer else { return };
        self.load_missing(&mixer, cue);
        self.load_music(&mixer, music_dir);
        let locked = mixer.lock();
        if let Ok(mut m) = locked {
            m.set_cue(*cue);
        }
    }

    fn trigger(&mut self, shot: OneShot) {
        if let Some(m) = self.ensure_open() {
            if let Some(cue) = self.last {
                self.load_missing(&m, &cue);
            }
            if let Ok(mut m) = m.lock() {
                m.trigger(shot);
            }
        }
    }
}

fn open() -> Result<(cpal::Stream, Shared), String> {
    let device = cpal::default_host().default_output_device().ok_or("no output device")?;
    let cfg = device.default_output_config().map_err(|e| e.to_string())?;
    let channels = usize::from(cfg.channels());
    let mixer: Shared = Arc::new(Mutex::new(Mixer::new(cfg.sample_rate())));
    let err = |e| log::warn!("audio stream: {e}");
    let m = Arc::clone(&mixer);
    let stream = match cfg.sample_format() {
        cpal::SampleFormat::F32 => device.build_output_stream(
            cfg.into(),
            move |d: &mut [f32], _: &_| match m.lock() {
                Ok(mut m) => m.render(d, channels),
                Err(_) => d.fill(0.0),
            },
            err,
            None,
        ),
        cpal::SampleFormat::I16 => {
            let mut buf = Vec::new();
            device.build_output_stream(
                cfg.into(),
                move |d: &mut [i16], _: &_| {
                    buf.resize(d.len(), 0.0f32);
                    if let Ok(mut m) = m.lock() {
                        m.render(&mut buf, channels);
                    }
                    for (o, x) in d.iter_mut().zip(&buf) {
                        *o = (x * f32::from(i16::MAX)) as i16;
                    }
                },
                err,
                None,
            )
        }
        f => return Err(format!("unsupported sample format {f}")),
    }
    .map_err(|e| e.to_string())?;
    stream.play().map_err(|e| e.to_string())?;
    Ok((stream, mixer))
}
