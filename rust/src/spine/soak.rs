//! Max-rate filler that drives **today's** assemble: read whole framed `.raw`,
//! then [`container_encode_v5`](crate::api::session_format::container_encode_v5)
//! (`zstd::encode_all` of the entire raw body).
//!
//! This is the PR 2 baseline. Extra RSS during assemble is **O(n)** in filled
//! volume (whole-file compress). That report is PASS, not a reason to change
//! encode in this module. PR 3 kills the outer wrap.

use std::fs::File;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::time::Instant;

use crate::api::muse::{
    BandsDto, EegDto, ImuDto, MovementDto, MuseEventDto, PeakAlphaDto, PpgDto, PulseDto, SpO2Dto,
    TelemetrySnapshot, XyzDto,
};
use crate::api::session_format::{
    container_encode_v5, encode_session_event, session_frame_bytes, session_header_bytes,
    ComputedFrame, FeedbackInfo, GuardrailInfo, PeakAlphaInfo, V5_MAGIC,
};

const EEG_HZ: u64 = 256;
const EEG_CH: i32 = 4;
const EEG_SAMPLES: usize = 12;
const PPG_HZ: u64 = 64;
const PPG_CH: i32 = 3;
const PPG_SAMPLES: usize = 6;
const IMU_HZ: u64 = 52;
const DERIVED_HZ: u64 = 1;
const DERIVED_CH: i32 = 4;
const FLUSH_BYTES: usize = 64 * 1024;
const DEFAULT_EQUIV_SECS: u64 = 60;
const TWELVE_H_SECS: u64 = 12 * 3600;

#[derive(Debug, Clone)]
pub struct SoakReport {
    pub equiv_secs: u64,
    pub uncompressed_record_bytes: u64,
    pub framed_raw_bytes: u64,
    pub container_bytes: u64,
    pub events: u64,
    pub flushes: u64,
    pub drops: u64,
    pub write_errors: u64,
    pub fill_ms: u128,
    pub assemble_ms: u128,
    pub rss_kb_after_fill: Option<u64>,
    pub rss_kb_after_read: Option<u64>,
    pub rss_kb_after_assemble: Option<u64>,
    pub assemble_path: &'static str,
    pub container_magic_ok: bool,
}

impl SoakReport {
    pub fn print(&self) {
        let un_gb = self.uncompressed_record_bytes as f64 / 1e9;
        let raw_gb = self.framed_raw_bytes as f64 / 1e9;
        let out_gb = self.container_bytes as f64 / 1e9;
        let extra_read = extra_kb(self.rss_kb_after_fill, self.rss_kb_after_read);
        let extra_assemble = extra_kb(self.rss_kb_after_fill, self.rss_kb_after_assemble);
        eprintln!(
            "[spine] soak equiv_s={} device=classic-muse streams=all max_rate=true",
            self.equiv_secs
        );
        eprintln!(
            "[spine] soak fill events={} flushes={} uncompressed_gb={:.6} framed_raw_gb={:.6} fill_ms={}",
            self.events, self.flushes, un_gb, raw_gb, self.fill_ms
        );
        eprintln!(
            "[spine] soak assemble container_gb={:.6} assemble_ms={} rss_fill_kb={:?} rss_read_kb={:?} rss_assemble_kb={:?} extra_read_kb={:?} extra_assemble_kb={:?}",
            out_gb,
            self.assemble_ms,
            self.rss_kb_after_fill,
            self.rss_kb_after_read,
            self.rss_kb_after_assemble,
            extra_read,
            extra_assemble
        );
        eprintln!(
            "[spine] soak assemble_path={} ram=O(n) (whole-file encode_all; PR 2 baseline, not a fail)",
            self.assemble_path
        );
        eprintln!(
            "[spine] soak drops={} write_errors={} (no capture writer yet; drops stay 0 until PR 4)",
            self.drops, self.write_errors
        );
    }
}

fn extra_kb(before: Option<u64>, after: Option<u64>) -> Option<i64> {
    Some(after? as i64 - before? as i64)
}

fn rss_kb() -> Option<u64> {
    let text = std::fs::read_to_string("/proc/self/status").ok()?;
    for line in text.lines() {
        if let Some(rest) = line.strip_prefix("VmRSS:") {
            return rest.split_whitespace().next()?.parse().ok();
        }
    }
    None
}

fn equiv_secs_from_env(default: u64) -> u64 {
    std::env::var("NEUROFEED_SOAK_EQUIV_SECS")
        .ok()
        .and_then(|s| s.parse().ok())
        .filter(|n| *n > 0)
        .unwrap_or(default)
}

struct RawSink {
    file: File,
    pending: Vec<u8>,
    uncompressed_record_bytes: u64,
    framed_raw_bytes: u64,
    events: u64,
    flushes: u64,
    write_errors: u64,
}

impl RawSink {
    fn create(path: &std::path::Path) -> std::io::Result<Self> {
        let mut file = File::create(path)?;
        let header = session_header_bytes();
        file.write_all(&header)?;
        Ok(Self {
            file,
            pending: Vec::with_capacity(FLUSH_BYTES + 4096),
            uncompressed_record_bytes: 0,
            framed_raw_bytes: header.len() as u64,
            events: 0,
            flushes: 0,
            write_errors: 0,
        })
    }

    fn push(&mut self, rec: &[u8]) {
        if rec.is_empty() || self.write_errors > 0 {
            return;
        }
        self.uncompressed_record_bytes += rec.len() as u64;
        self.events += 1;
        self.pending.extend_from_slice(rec);
        if self.pending.len() >= FLUSH_BYTES {
            self.flush();
        }
    }

    fn flush(&mut self) {
        if self.pending.is_empty() || self.write_errors > 0 {
            return;
        }
        let frame = session_frame_bytes(&self.pending);
        self.pending.clear();
        match self.file.write_all(&frame) {
            Ok(()) => {
                self.flushes += 1;
                self.framed_raw_bytes += frame.len() as u64;
            }
            Err(_) => {
                self.write_errors += 1;
            }
        }
    }

    fn finish(mut self) -> Self {
        self.flush();
        if self.write_errors == 0 {
            if self.file.flush().is_err() {
                self.write_errors += 1;
            }
        }
        self
    }
}

fn fill_classic_muse(sink: &mut RawSink, equiv_secs: u64) {
    let eeg_pkts = equiv_secs * EEG_HZ / EEG_SAMPLES as u64;
    let ppg_pkts = equiv_secs * PPG_HZ / PPG_SAMPLES as u64;
    let imu_pkts = equiv_secs * IMU_HZ;
    let derived_ticks = equiv_secs * DERIVED_HZ;

    let eeg_samples = vec![1.0_f64; EEG_SAMPLES];
    let ppg_samples = vec![1000.0_f64; PPG_SAMPLES];

    for pkt in 0..eeg_pkts {
        let ts = (pkt as f64) * (EEG_SAMPLES as f64) / (EEG_HZ as f64) * 1000.0;
        for ch in 0..EEG_CH {
            let rec = encode_session_event(&MuseEventDto::Eeg(EegDto {
                index: (pkt as u16).wrapping_add(ch as u16),
                electrode: ch,
                timestamp: ts,
                samples: eeg_samples.clone(),
            }));
            sink.push(&rec);
        }
    }

    for pkt in 0..ppg_pkts {
        let ts = (pkt as f64) * (PPG_SAMPLES as f64) / (PPG_HZ as f64) * 1000.0;
        for ch in 0..PPG_CH {
            let rec = encode_session_event(&MuseEventDto::Ppg(PpgDto {
                index: pkt as u16,
                channel: ch,
                timestamp: ts,
                samples: ppg_samples.clone(),
            }));
            sink.push(&rec);
        }
    }

    for pkt in 0..imu_pkts {
        let sample = vec![XyzDto {
            x: 0.0,
            y: 0.0,
            z: 1.0,
        }];
        let rec_a = encode_session_event(&MuseEventDto::Accelerometer(ImuDto {
            sequence_id: pkt as u16,
            samples: sample,
        }));
        sink.push(&rec_a);
        let rec_g = encode_session_event(&MuseEventDto::Gyroscope(ImuDto {
            sequence_id: pkt as u16,
            samples: vec![XyzDto {
                x: 0.0,
                y: 0.0,
                z: 1.0,
            }],
        }));
        sink.push(&rec_g);
    }

    for tick in 0..derived_ticks {
        let ts = tick as f64 * 1000.0;
        for ch in 0..DERIVED_CH {
            let rec = encode_session_event(&MuseEventDto::Bands(BandsDto {
                electrode: ch,
                timestamp: ts,
                delta: 1.0,
                theta: 2.0,
                alpha: 3.0,
                beta: 4.0,
                gamma: 5.0,
                line_noise_ratio: 0.01,
            }));
            sink.push(&rec);
        }
        sink.push(&encode_session_event(&MuseEventDto::Pulse(PulseDto {
            timestamp: ts,
            bpm: 60.0,
            confidence: 0.9,
        })));
        sink.push(&encode_session_event(&MuseEventDto::SpO2(SpO2Dto {
            timestamp: ts,
            spo2: 98.0,
            confidence: 0.9,
        })));
        sink.push(&encode_session_event(&MuseEventDto::Movement(
            MovementDto {
                timestamp: ts,
                score: 0.1,
            },
        )));
        sink.push(&encode_session_event(&MuseEventDto::PeakAlpha(
            PeakAlphaDto {
                timestamp: ts,
                frequency: 10.0,
                power: 1.0,
            },
        )));
        sink.push(&encode_session_event(&MuseEventDto::Telemetry(
            TelemetrySnapshot {
                battery_level: 85.0,
                fuel_gauge_voltage: 0.0,
                temperature: 0,
            },
        )));
    }
}

fn computed_frames(equiv_secs: u64) -> Vec<ComputedFrame> {
    (0..equiv_secs)
        .map(|t| ComputedFrame {
            t: t as f64,
            bands: vec![vec![1.0, 2.0, 3.0, 4.0, 5.0]; 4],
            pulse: Some(60.0),
            movement: Some(0.1),
            peak_alpha: Some(PeakAlphaInfo {
                freq: 10.0,
                power: 1.0,
            }),
            spo2: Some(98.0),
            line_noise: vec![0.01; 4],
            signal_quality: vec![90; 4],
            guardrail: GuardrailInfo {
                sleep_dir: 0.0,
                clarity: 1.0,
                warning: false,
                delta: 0.0,
            },
            feedback: FeedbackInfo {
                ratio: 1.0,
                threshold: 1.0,
                in_target: true,
                pct: 0.5,
            },
            gestures: Vec::new(),
        })
        .collect()
}

fn soak_raw_path() -> PathBuf {
    std::env::temp_dir().join(format!(
        "neurofeed_spine_soak_{}_{}.raw",
        std::process::id(),
        Instant::now().elapsed().as_nanos()
    ))
}

/// Fill Classic Muse all-stream records at max rate, `read_to_end` the framed
/// `.raw`, and assemble with today's `container_encode_v5`.
pub fn run_current_assemble_soak(equiv_secs: u64) -> SoakReport {
    let path = soak_raw_path();
    let fill_t0 = Instant::now();
    let mut sink = RawSink::create(&path).expect("soak create raw temp");
    fill_classic_muse(&mut sink, equiv_secs);
    let sink = sink.finish();
    let fill_ms = fill_t0.elapsed().as_millis();
    let rss_kb_after_fill = rss_kb();

    let mut raw_body = Vec::new();
    let mut write_errors = sink.write_errors;
    match File::open(&path).and_then(|mut f| f.read_to_end(&mut raw_body)) {
        Ok(_) => {}
        Err(_) => write_errors += 1,
    }
    let rss_kb_after_read = rss_kb();

    let metadata = br#"{"formatVersion":5,"kind":"recording","device":"classic-muse-soak"}"#;
    let computed = computed_frames(equiv_secs);
    let assemble_t0 = Instant::now();
    let container = container_encode_v5(&[], metadata, &computed, &raw_body);
    let assemble_ms = assemble_t0.elapsed().as_millis();
    let rss_kb_after_assemble = rss_kb();
    let container_bytes = container.len() as u64;
    let container_magic_ok = container.len() >= 6 && container[..6] == V5_MAGIC;
    let _ = std::fs::remove_file(&path);

    SoakReport {
        equiv_secs,
        uncompressed_record_bytes: sink.uncompressed_record_bytes,
        framed_raw_bytes: raw_body.len() as u64,
        container_bytes,
        events: sink.events,
        flushes: sink.flushes,
        drops: 0,
        write_errors,
        fill_ms,
        assemble_ms,
        rss_kb_after_fill,
        rss_kb_after_read,
        rss_kb_after_assemble,
        assemble_path: "container_encode_v5 zstd::encode_all(whole raw_body) + read_to_end(.raw)",
        container_magic_ok,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn assert_baseline(report: &SoakReport) {
        report.print();
        assert_eq!(report.drops, 0);
        assert_eq!(report.write_errors, 0);
        assert!(report.events > 0);
        assert!(report.uncompressed_record_bytes > 0);
        assert!(report.framed_raw_bytes >= 12);
        assert!(report.container_bytes > report.framed_raw_bytes / 4);
        assert!(report.container_magic_ok);
        assert!(
            report.assemble_path.contains("encode_all"),
            "PR 2 must document today's whole-file compress"
        );
        assert!(
            report.assemble_path.contains("read_to_end"),
            "PR 2 must drive today's whole-raw read"
        );
    }

    #[test]
    fn soak_current_assemble_max_rate() {
        let secs = equiv_secs_from_env(DEFAULT_EQUIV_SECS);
        let report = run_current_assemble_soak(secs);
        assert_baseline(&report);
        assert!(
            report.fill_ms < (secs as u128) * 1000,
            "filler must run faster than wall-clock equivalent (max rate)"
        );
    }

    #[test]
    #[ignore = "12h-equivalent volume; extra RSS is O(n) (PR 2 baseline, not a fail)"]
    fn soak_current_assemble_12h_equivalent() {
        let secs = equiv_secs_from_env(TWELVE_H_SECS);
        let report = run_current_assemble_soak(secs);
        assert_baseline(&report);
    }
}
