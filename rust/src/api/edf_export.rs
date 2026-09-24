//! EDF+ export of raw EEG from a recorded session body.
//!
//! The byte layout itself is owned by the `edf_export` crate
//! (`third_party/edf_export`); this module is the thin FFI surface that
//! turns a parsed `SessionData` (raw EEG packets in µV, electrode-tagged)
//! plus recording metadata into per-electrode continuous signals and a
//! sorted annotation list, then delegates to the writer.

use flutter_rust_bridge::frb;

use crate::api::session_format::session_parse_body;

#[frb(dart_metadata = ("freezed",))]
pub struct EdfExportAnnotation {
    /// Seconds from recording start (session-relative, same clock as
    /// gesture markers).
    pub onset_seconds: f64,
    pub text: String,
}

#[frb(dart_metadata = ("freezed",))]
pub struct EdfExportParams {
    pub patient_id: String,
    pub recording_id: String,
    pub year: u16,
    pub month: u16,
    pub day: u16,
    pub hour: u16,
    pub minute: u16,
    pub second: u16,
    /// Annotations, sorted ascending by onset (e.g. calibration
    /// boundaries, gesture markers).
    pub annotations: Vec<EdfExportAnnotation>,
}

/// Nominal Muse EEG sample rate used when the recorded packet stream is
/// too short to estimate a rate from the data.
const NOMINAL_EEG_RATE: usize = 256;

/// Encodes the raw EEG of a session raw body as a complete EDF+ file.
///
/// `channel_labels` maps the i16 electrode index to a channel label (e.g.
/// `["TP9", "AF7", "AF8", "TP10"]`); an empty string or out-of-range
/// index means "no data for that electrode". Only electrodes with data
/// are written. Returns an error string when the body has no EEG or the
/// writer rejects the inputs.
#[frb(sync)]
pub fn encode_edf_export(
    body: &[u8],
    channel_labels: Vec<String>,
    params: &EdfExportParams,
) -> Result<Vec<u8>, String> {
    let data = session_parse_body(body)?;

    // Sample rate estimate: total samples across all electrodes over the
    // covered wall-clock span, clamped to a sane range.
    let mut total_samples: u64 = 0;
    let (mut t_min, mut t_max) = (f64::INFINITY, f64::NEG_INFINITY);
    for rec in &data.eeg {
        if rec.samples.is_empty() {
            continue;
        }
        total_samples += rec.samples.len() as u64;
        t_min = t_min.min(rec.timestamp);
        t_max = t_max.max(
            rec.timestamp + rec.samples.len() as f64 * 1000.0 / NOMINAL_EEG_RATE as f64,
        );
    }
    let span_secs = (t_max - t_min) / 1000.0;
    let rate = if span_secs > 1.0 {
        (total_samples as f64 / span_secs).round().clamp(1.0, 1024.0) as usize
    } else {
        NOMINAL_EEG_RATE
    };

    if data.eeg.is_empty() || total_samples == 0 {
        return Err("no raw EEG recorded in this session".to_string());
    }

    let sample_count = ((span_secs.max(0.0)) * rate as f64).ceil() as usize + rate;
    let mut signals: Vec<edf_export::EdfSignal> = Vec::new();
    let mut electrodes: Vec<i16> = data.eeg.iter().map(|r| r.electrode).collect();
    electrodes.sort_unstable();
    electrodes.dedup();
    for electrode in electrodes {
        let label = match channel_labels.get(electrode as usize) {
            Some(l) if !l.is_empty() => l.clone(),
            _ => continue,
        };
        let mut buf = vec![0.0f32; sample_count];
        // Place samples and fill inter-packet gaps by holding the last
        // valid sample (leading positions stay 0 until the first sample).
        let mut last: Option<f32> = None;
        let mut last_idx: i64 = -1;
        for rec in &data.eeg {
            if rec.electrode != electrode {
                continue;
            }
            for (i, &s) in rec.samples.iter().enumerate() {
                let idx = ((rec.timestamp - t_min) / 1000.0 * rate as f64).round() as i64
                    + i as i64;
                if idx <= last_idx {
                    continue;
                }
                if let Some(hold) = last {
                    for j in (last_idx + 1)..idx {
                        if j >= 0 && (j as usize) < buf.len() {
                            buf[j as usize] = hold;
                        }
                    }
                }
                let ui = idx as usize;
                if ui < buf.len() {
                    buf[ui] = s;
                }
                last = Some(s);
                last_idx = idx;
            }
        }
        signals.push(edf_export::EdfSignal::eeg(label, rate, buf));
    }
    if signals.is_empty() {
        return Err("no EEG electrodes with labels provided".to_string());
    }

    let annotations: Vec<edf_export::EdfAnnotation> = params
        .annotations
        .iter()
        .map(|a| edf_export::EdfAnnotation {
            onset_seconds: a.onset_seconds,
            // TAL duration not yet on EdfExportAnnotation (needs FRB regen).
            duration_seconds: 0.0,
            text: a.text.clone(),
        })
        .collect();
    let spec = edf_export::EdfFileSpec {
        patient_id: &params.patient_id,
        recording_id: &params.recording_id,
        start: (params.year, params.month, params.day, params.hour, params.minute, params.second),
        physical_dimension: "uV",
        annotations: &annotations,
    };
    edf_export::encode_edf_plus(&signals, &spec).map_err(|e| e.to_string())
}


/// One decoded continuous signal (EEG or other).
#[frb(dart_metadata = ("freezed",))]
pub struct EdfDecodedSignal {
    pub label: String,
    /// Samples per 1-second data record (== nominal Hz for EDF+C).
    pub samples_per_record: u32,
    pub physical_min: f64,
    pub physical_max: f64,
    /// Physical-domain samples (µV for EEG).
    pub data: Vec<f32>,
}

/// Result of decoding an EDF / EDF+ file for import.
#[frb(dart_metadata = ("freezed",))]
pub struct EdfImportResult {
    pub patient_id: String,
    pub recording_id: String,
    pub year: u16,
    pub month: u16,
    pub day: u16,
    pub hour: u16,
    pub minute: u16,
    pub second: u16,
    /// Header reserved field (`EDF+C` / `EDF+D` / empty for plain EDF).
    pub reserved: String,
    pub signals: Vec<EdfDecodedSignal>,
    pub annotations: Vec<EdfExportAnnotation>,
}

/// Decode an EDF / EDF+ file into signals + TAL annotations.
///
/// Mirrors [`edf_export::decode_edf_plus`]. Returns an error string when the
/// bytes are truncated or not a version-0 EDF header.
#[frb(sync)]
pub fn decode_edf_import(bytes: &[u8]) -> Result<EdfImportResult, String> {
    let dec = edf_export::decode_edf_plus(bytes).map_err(|e| e.to_string())?;
    let (year, month, day, hour, minute, second) = dec.start;
    Ok(EdfImportResult {
        patient_id: dec.patient_id,
        recording_id: dec.recording_id,
        year,
        month,
        day,
        hour,
        minute,
        second,
        reserved: dec.reserved,
        signals: dec
            .signals
            .into_iter()
            .map(|s| EdfDecodedSignal {
                label: s.label,
                samples_per_record: s.samples_per_record as u32,
                physical_min: s.physical_min,
                physical_max: s.physical_max,
                data: s.data,
            })
            .collect(),
        annotations: dec
            .annotations
            .into_iter()
            .map(|a| EdfExportAnnotation {
                onset_seconds: a.onset_seconds,
                text: a.text,
            })
            .collect(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::muse::{EegDto, MuseEventDto};
    use crate::api::session_format::{encode_session_event, session_frame_bytes, session_header_bytes};

    fn body_with_eeg() -> Vec<u8> {
        let mk = |ts: f64, electrode: i32, samples: Vec<f64>| {
            MuseEventDto::Eeg(EegDto {
                index: 0,
                electrode,
                timestamp: ts,
                samples,
            })
        };
        let events = vec![
            mk(1000.0, 0, vec![1.0; 26]),
            mk(1100.0, 0, vec![2.0; 26]),
            mk(1200.0, 1, vec![3.0; 26]),
        ];
        let mut body = session_header_bytes();
        let records: Vec<u8> = events.iter().flat_map(|e| encode_session_event(e)).collect();
        body.extend_from_slice(&session_frame_bytes(&records));
        body
    }

    fn params() -> EdfExportParams {
        EdfExportParams {
            patient_id: "NeuroFeed".to_string(),
            recording_id: "session-test".to_string(),
            year: 2026,
            month: 8,
            day: 19,
            hour: 10,
            minute: 30,
            second: 5,
            annotations: vec![EdfExportAnnotation {
                onset_seconds: 0.25,
                text: "Double blink".to_string(),
            }],
        }
    }

    #[test]
    fn wrapper_builds_edf_from_body() {
        let body = body_with_eeg();
        let out = encode_edf_export(
            &body,
            vec!["TP9".to_string(), "AF7".to_string(), String::new(), String::new()],
            &params(),
        )
        .unwrap();
        // 2 signals + annotation channel → 1024-byte header; 2 data records
        // (334 samples @ 256 Hz → ceil 334/256).
        let header = &out[..1024];
        assert_eq!(&header[8..88], format!("{:<80}", "NeuroFeed").as_bytes());
        assert_eq!(&header[192..236], format!("{:<44}", "EDF+C").as_bytes());
        assert_eq!(&header[236..244], b"       2");
        // First TP9 sample = 1.0 µV on ±2000 range → ~16 digital LSB.
        let first = i16::from_le_bytes([out[1024], out[1025]]);
        assert_eq!(first, 16);
        // The "+0.25 s" annotation TAL must land in record 0.
        assert!(
            out.windows(20).any(|w| w == b"+0.25\x14Double blink\x14\x00".as_slice()),
            "annotation TAL missing from output"
        );
    }

    #[test]
    fn wrapper_rejects_unlabeled_or_empty_bodies() {
        let body = body_with_eeg();
        assert!(encode_edf_export(&body, vec![String::new(); 4], &params())
            .unwrap_err()
            .contains("no EEG electrodes"));
        assert!(encode_edf_export(&session_header_bytes(), vec!["TP9".to_string()], &params())
            .unwrap_err()
            .contains("no raw EEG"));
    }
}


#[cfg(test)]
mod decode_tests {
    use super::*;

    #[test]
    fn ffi_decode_round_trip_via_encode() {
        use crate::api::muse::{EegDto, MuseEventDto};
        use crate::api::session_format::{
            encode_session_event, session_frame_bytes, session_header_bytes,
        };
        let mk = |ts: f64, electrode: i32, samples: Vec<f64>| {
            MuseEventDto::Eeg(EegDto {
                index: 0,
                electrode,
                timestamp: ts,
                samples,
            })
        };
        let events = vec![
            mk(1000.0, 0, vec![10.0; 12]),
            mk(1000.0 + 12.0 * 1000.0 / 256.0, 0, vec![10.0; 12]),
            mk(1000.0, 1, vec![-10.0; 12]),
            mk(1000.0 + 12.0 * 1000.0 / 256.0, 1, vec![-10.0; 12]),
        ];
        let mut body = session_header_bytes();
        let records: Vec<u8> = events.iter().flat_map(|e| encode_session_event(e)).collect();
        body.extend_from_slice(&session_frame_bytes(&records));
        let edf = encode_edf_export(
            &body,
            vec!["TP9".to_string(), "AF7".to_string()],
            &EdfExportParams {
                patient_id: "subj1 X X X".to_string(),
                recording_id: "rec-test".to_string(),
                year: 2026,
                month: 9,
                day: 25,
                hour: 3,
                minute: 50,
                second: 0,
                annotations: vec![EdfExportAnnotation {
                    onset_seconds: 0.1,
                    text: "double_blink".to_string(),
                }],
            },
        )
        .unwrap();
        let imported = decode_edf_import(&edf).unwrap();
        assert_eq!(imported.patient_id.trim(), "subj1 X X X");
        assert_eq!(imported.year, 2026);
        assert_eq!(imported.signals.len(), 2);
        assert_eq!(imported.signals[0].label, "TP9");
        assert_eq!(imported.signals[1].label, "AF7");
        assert!(imported.signals[0].data.len() >= 12);
        assert!(
            imported
                .annotations
                .iter()
                .any(|a| a.text == "double_blink"),
            "missing annotation"
        );
    }
}
