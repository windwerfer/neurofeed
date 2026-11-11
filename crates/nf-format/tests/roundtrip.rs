#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use nf_format::edf::{decode_edf_plus, records_to_edf, EdfRequest};
use nf_format::*;

fn all_records() -> Vec<Record> {
    vec![
        Record::Eeg { ts: 1.5, electrode: 3, samples: vec![1.0, -2.5, 3.25] },
        Record::Telemetry { ts: 2.0, battery: 85.0, fuel: 3.7, temp: 31 },
        Record::Accelerometer { ts: 2.1, seq: 7, xyz: vec![[0.1, 0.2, 0.3], [1.0, 2.0, 3.0]] },
        Record::Gyroscope { ts: 2.2, seq: 8, xyz: vec![[4.0, 5.0, 6.0]] },
        Record::Ppg { ts: 2.3, channel: 1, samples: vec![200_000.0; 6] },
        Record::Optics { ts: 2.35, lane: 1, samples: vec![210_000.0; 6] },
        Record::Bands { ts: 2.4, electrode: 0, bands: [1.0, 0.5, 0.75, 0.25, -0.1] },
        Record::Pulse { ts: 2.5, bpm: 72.0, confidence: 0.9 },
        Record::Movement { ts: 2.6, score: 0.1 },
        Record::PeakAlpha { ts: 2.7, frequency: 10.0, power: 1.2 },
        Record::SpO2 { ts: 2.8, spo2: 97.0, confidence: 0.8 },
        Record::Feedback { ts: 2.9, value: 1.25, threshold: 1.1, flags: feedback_flags::COUNTED | feedback_flags::IN_TARGET },
        Record::Trust { ts: 2.9, native: 0.5, pct: 61.0, thr_pct: 50.0, bits: nf_format::trust_bits::HAS_GUARD | 2 },
        Record::Guard { ts: 2.9, value: 82.5, line: 75.0 },
    ]
}

#[test]
fn eeg_record_bytes_match_legacy_layout() {
    let mut b = Vec::new();
    Record::Eeg { ts: 1.0, electrode: 2, samples: vec![0.5] }.encode(&mut b);
    let mut want = vec![1u8];
    want.extend_from_slice(&1.0f64.to_le_bytes());
    want.extend_from_slice(&2i16.to_le_bytes());
    want.extend_from_slice(&1u16.to_le_bytes());
    want.extend_from_slice(&0.5f32.to_le_bytes());
    assert_eq!(b, want);
}

#[test]
fn body_roundtrip_all_tags_multiple_frames() {
    let recs = all_records();
    let mut w = BodyWriter::new();
    for (i, r) in recs.iter().enumerate() {
        w.push(r);
        if i % 3 == 0 {
            w.flush_frame();
        }
    }
    let body = w.finish();
    assert_eq!(&body[..8], b"\nNIBDEFN");
    assert_eq!(parse_body(&body).unwrap(), recs);
    // Truncated tail frame is dropped, earlier frames survive.
    let cut = parse_body(&body[..body.len() - 3]).unwrap();
    assert!(!cut.is_empty() && cut.len() < recs.len());
    assert!(parse_body(b"nope").is_err());
}

#[test]
fn container_roundtrip_and_crc() {
    let mut w = BodyWriter::new();
    all_records().iter().for_each(|r| w.push(r));
    let c = Container {
        thumbnail: vec![1, 2, 3],
        metadata_json: br#"{"device":"sim:muse"}"#.to_vec(),
        computed_jsonl: b"{\"t\":0}\n{\"t\":1}\n".to_vec(),
        raw_body: w.finish(),
    };
    let bytes = encode_container(&c);
    assert_eq!(&bytes[..6], b"NFED6\0");
    assert_eq!(decode_container(&bytes).unwrap(), c);
    let mut bad = bytes.clone();
    bad[10] ^= 1;
    assert!(decode_container(&bad).unwrap_err().0.contains("CRC32"));
}

#[test]
fn edf_roundtrip() {
    let labels = vec!["TP9".to_string(), "AF7".to_string()];
    let recs: Vec<Record> = (0..4)
        .flat_map(|e| {
            (0..2).map(move |ch| Record::Eeg { ts: f64::from(e), electrode: ch, samples: (0..128).map(|i| (i % 50) as f32).collect() })
        })
        .collect();
    let req = EdfRequest {
        labels: &labels,
        sample_rate_hz: 256,
        start: (2026, 10, 29, 12, 0, 0),
        recording_id: "Startdate 29-OCT-2026 X X neurofeed",
        prefiltering: "",
        annotations: &[],
    };
    let bytes = records_to_edf(&recs, &req).unwrap();
    let d = decode_edf_plus(&bytes).unwrap();
    println!("{d:?}");
    let dbg = format!("{d:?}");
    assert!(dbg.contains("TP9") && dbg.contains("AF7"));
}

#[test]
fn feedback_record_layout_and_unknown_tag_stops_reader() {
    let mut b = Vec::new();
    Record::Feedback { ts: 1.0, value: f32::NAN, threshold: 2.0, flags: 5 }.encode(&mut b);
    assert_eq!(b.len(), 1 + 8 + 4 + 4 + 2);
    assert_eq!(b[0], TAG_FEEDBACK);
    let r = nf_format::record::decode_records(&b);
    assert!(matches!(r[..], [Record::Feedback { value, threshold, flags: 5, .. }] if value.is_nan() && threshold == 2.0));
    // Legacy behaviour: an unknown tag stops decoding; records before it survive.
    let mut body = Vec::new();
    Record::Pulse { ts: 1.0, bpm: 60.0, confidence: 1.0 }.encode(&mut body);
    body.push(99);
    body.extend_from_slice(&[0; 20]);
    Record::Pulse { ts: 2.0, bpm: 61.0, confidence: 1.0 }.encode(&mut body);
    assert_eq!(nf_format::record::decode_records(&body).len(), 1);
}
