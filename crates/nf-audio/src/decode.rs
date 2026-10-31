//! Decode Ogg Vorbis / MP3 / FLAC / WAV bytes into [`Pcm`] (symphonia).

use crate::dsp::Pcm;
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::errors::Error;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

/// Extensions the decoder accepts (music folder filter).
pub const EXTENSIONS: [&str; 5] = ["ogg", "mp3", "flac", "wav", "oga"];

/// Decode a whole file; at most 2 channels are kept.
pub fn decode(bytes: Vec<u8>, ext: Option<&str>) -> Result<Pcm, String> {
    let mss = MediaSourceStream::new(Box::new(std::io::Cursor::new(bytes)), Default::default());
    let mut hint = Hint::new();
    if let Some(e) = ext {
        hint.with_extension(e);
    }
    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .map_err(|e| e.to_string())?;
    let mut format = probed.format;
    let track = format.default_track().ok_or("no audio track")?;
    let id = track.id;
    let mut dec = symphonia::default::get_codecs().make(&track.codec_params, &DecoderOptions::default()).map_err(|e| e.to_string())?;
    let mut pcm = Pcm { rate: track.codec_params.sample_rate.unwrap_or(44_100), channels: 0, data: Vec::new() };
    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(Error::IoError(_)) => break,
            Err(e) => return Err(e.to_string()),
        };
        if packet.track_id() != id {
            continue;
        }
        match dec.decode(&packet) {
            Ok(buf) => append(&mut pcm, buf),
            Err(Error::DecodeError(_)) => continue,
            Err(e) => return Err(e.to_string()),
        }
    }
    if pcm.data.is_empty() {
        return Err("no audio decoded".into());
    }
    Ok(pcm)
}

fn append(pcm: &mut Pcm, buf: symphonia::core::audio::AudioBufferRef<'_>) {
    let spec = *buf.spec();
    let ch = spec.channels.count().max(1);
    pcm.rate = spec.rate;
    let mut sb = SampleBuffer::<f32>::new(buf.capacity() as u64, spec);
    sb.copy_interleaved_ref(buf);
    let keep = ch.min(2);
    pcm.channels = keep as u16;
    for frame in sb.samples().chunks_exact(ch) {
        pcm.data.extend_from_slice(&frame[..keep]);
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]

    #[test]
    fn decodes_bundled_vorbis_and_rejects_garbage() {
        let bytes = include_bytes!("../../../assets/audio/ogg/guard-cough-01.ogg").to_vec();
        let pcm = super::decode(bytes, Some("ogg")).unwrap();
        assert_eq!((pcm.rate, pcm.channels), (44_100, 2));
        assert!((pcm.seconds() - 1.12).abs() < 0.05, "{}", pcm.seconds());
        assert!(super::decode(vec![1, 2, 3], None).is_err());
    }
}
