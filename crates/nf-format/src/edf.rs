//! EEG records → EDF+ (continuous, 1-second data records) via
//! the `edf_export` crate. Packets are concatenated per electrode in
//! order; the shortest channel bounds the length so all signals align.

use crate::record::Record;
use crate::FormatError;
pub use edf_export::{decode_edf_plus, encode_edf_plus, EdfAnnotation, EdfDecoded, EdfFileSpec, EdfSignal};

pub struct EdfRequest<'a> {
    pub labels: &'a [String],
    pub sample_rate_hz: usize,
    /// (year, month, day, hour, minute, second); year 1985–2084.
    pub start: (u16, u16, u16, u16, u16, u16),
    pub recording_id: &'a str,
    pub prefiltering: &'a str,
    pub annotations: &'a [EdfAnnotation],
}

pub fn records_to_edf(records: &[Record], req: &EdfRequest<'_>) -> Result<Vec<u8>, FormatError> {
    let mut data: Vec<Vec<f32>> = vec![Vec::new(); req.labels.len()];
    for r in records {
        if let Record::Eeg { electrode, samples, .. } = r {
            if let Some(ch) = usize::try_from(*electrode).ok().and_then(|e| data.get_mut(e)) {
                ch.extend_from_slice(samples);
            }
        }
    }
    let len = data.iter().map(Vec::len).min().unwrap_or(0);
    let signals: Vec<_> = req
        .labels
        .iter()
        .zip(data)
        .map(|(l, mut d)| {
            d.truncate(len);
            let mut s = edf_export::EdfSignal::eeg(l.clone(), req.sample_rate_hz, d);
            s.prefiltering = req.prefiltering.to_string();
            s
        })
        .collect();
    let spec = edf_export::EdfFileSpec {
        patient_id: "X X X X",
        recording_id: req.recording_id,
        start: req.start,
        physical_dimension: "uV",
        annotations: req.annotations,
        discontinuous_starts: None,
    };
    edf_export::encode_edf_plus(&signals, &spec).map_err(|e| FormatError(format!("EDF: {e:?}")))
}
