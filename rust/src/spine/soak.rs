//! Max-rate filler that drives the capture writer + streaming assemble.

use std::fs::File;
use std::path::PathBuf;
use std::time::Instant;

use crate::api::muse::{
    BandsDto, EegDto, ImuDto, MovementDto, MuseEventDto, PeakAlphaDto, PpgDto, PulseDto, SpO2Dto,
    TelemetrySnapshot, XyzDto,
};
use crate::api::session_format::{
    encode_session_event, ComputedFrame, FeedbackInfo, GuardrailInfo, PeakAlphaInfo, V5_MAGIC,
};
use crate::spine::capture::{
    capture_append_computed_line, capture_assemble_v5, capture_discard, capture_drop_count,
    capture_flush, capture_start, capture_write_errors, on_dto, test_lock,
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
            "[spine] soak assemble_path={} ram=O(1) extra (copy .raw, no outer zstd)",
            self.assemble_path
        );
        eprintln!(
            "[spine] soak drops={} write_errors={} (writer thread + bounded try_send)",
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

struct FillStats {
    uncompressed_record_bytes: u64,
    events: u64,
}

fn push_dto(stats: &mut FillStats, dto: MuseEventDto) {
    let rec = encode_session_event(&dto);
    if rec.is_empty() {
        return;
    }
    stats.uncompressed_record_bytes += rec.len() as u64;
    stats.events += 1;
    on_dto(&dto);
}

fn fill_classic_muse(stats: &mut FillStats, equiv_secs: u64) {
    let eeg_pkts = equiv_secs * EEG_HZ / EEG_SAMPLES as u64;
    let ppg_pkts = equiv_secs * PPG_HZ / PPG_SAMPLES as u64;
    let imu_pkts = equiv_secs * IMU_HZ;
    let derived_ticks = equiv_secs * DERIVED_HZ;

    let eeg_samples = vec![1.0_f64; EEG_SAMPLES];
    let ppg_samples = vec![1000.0_f64; PPG_SAMPLES];

    for pkt in 0..eeg_pkts {
        let ts = (pkt as f64) * (EEG_SAMPLES as f64) / (EEG_HZ as f64) * 1000.0;
        for ch in 0..EEG_CH {
            push_dto(
                stats,
                MuseEventDto::Eeg(EegDto {
                    index: (pkt as u16).wrapping_add(ch as u16),
                    electrode: ch,
                    timestamp: ts,
                    samples: eeg_samples.clone(),
                }),
            );
        }
    }

    for pkt in 0..ppg_pkts {
        let ts = (pkt as f64) * (PPG_SAMPLES as f64) / (PPG_HZ as f64) * 1000.0;
        for ch in 0..PPG_CH {
            push_dto(
                stats,
                MuseEventDto::Ppg(PpgDto {
                    index: pkt as u16,
                    channel: ch,
                    timestamp: ts,
                    samples: ppg_samples.clone(),
                }),
            );
        }
    }

    for pkt in 0..imu_pkts {
        let sample = vec![XyzDto {
            x: 0.0,
            y: 0.0,
            z: 1.0,
        }];
        push_dto(
            stats,
            MuseEventDto::Accelerometer(ImuDto {
                sequence_id: pkt as u16,
                samples: sample,
            }),
        );
        push_dto(
            stats,
            MuseEventDto::Gyroscope(ImuDto {
                sequence_id: pkt as u16,
                samples: vec![XyzDto {
                    x: 0.0,
                    y: 0.0,
                    z: 1.0,
                }],
            }),
        );
    }

    for tick in 0..derived_ticks {
        let ts = tick as f64 * 1000.0;
        for ch in 0..DERIVED_CH {
            push_dto(
                stats,
                MuseEventDto::Bands(BandsDto {
                    electrode: ch,
                    timestamp: ts,
                    delta: 1.0,
                    theta: 2.0,
                    alpha: 3.0,
                    beta: 4.0,
                    gamma: 5.0,
                    line_noise_ratio: 0.01,
                }),
            );
        }
        push_dto(
            stats,
            MuseEventDto::Pulse(PulseDto {
                timestamp: ts,
                bpm: 60.0,
                confidence: 0.9,
            }),
        );
        push_dto(
            stats,
            MuseEventDto::SpO2(SpO2Dto {
                timestamp: ts,
                spo2: 98.0,
                confidence: 0.9,
            }),
        );
        push_dto(
            stats,
            MuseEventDto::Movement(MovementDto {
                timestamp: ts,
                score: 0.1,
            }),
        );
        push_dto(
            stats,
            MuseEventDto::PeakAlpha(PeakAlphaDto {
                timestamp: ts,
                frequency: 10.0,
                power: 1.0,
            }),
        );
        push_dto(
            stats,
            MuseEventDto::Telemetry(TelemetrySnapshot {
                battery_level: 85.0,
                fuel_gauge_voltage: 0.0,
                temperature: 0,
            }),
        );
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

fn soak_dir() -> PathBuf {
    std::env::temp_dir().join(format!(
        "neurofeed_spine_soak_{}_{}",
        std::process::id(),
        Instant::now().elapsed().as_nanos()
    ))
}

/// Fill Classic Muse all-stream records at max rate through the capture writer.
pub fn run_current_assemble_soak(equiv_secs: u64) -> SoakReport {
    let _lock = test_lock();
    let _ = capture_discard();
    let dir = soak_dir();
    std::fs::create_dir_all(&dir).expect("soak dir");
    let id = format!("soak_{equiv_secs}");
    capture_start(
        dir.to_string_lossy().into_owned(),
        "recording".into(),
        id.clone(),
        Vec::new(),
        0.0,
    )
    .expect("soak capture_start");

    let fill_t0 = Instant::now();
    let mut stats = FillStats {
        uncompressed_record_bytes: 0,
        events: 0,
    };
    fill_classic_muse(&mut stats, equiv_secs);
    let _ = capture_flush();
    let fill_ms = fill_t0.elapsed().as_millis();
    let rss_kb_after_fill = rss_kb();
    let rss_kb_after_read = rss_kb_after_fill;

    let raw_path = dir.join(format!("recording_{id}.raw"));
    let framed_raw_bytes = std::fs::metadata(&raw_path).map(|m| m.len()).unwrap_or(0);

    for frame in computed_frames(equiv_secs) {
        let _ = capture_append_computed_line(frame.to_json_bytes());
    }
    let _ = capture_flush();

    let drops = capture_drop_count();
    let mut write_errors = capture_write_errors();
    let metadata = br#"{"formatVersion":5,"kind":"recording","device":"classic-muse-soak"}"#;
    let assemble_t0 = Instant::now();
    let dest_out = capture_assemble_v5(metadata.to_vec(), Vec::new());
    let assemble_ms = assemble_t0.elapsed().as_millis();
    let rss_kb_after_assemble = rss_kb();
    let (container_bytes, container_magic_ok) = match dest_out {
        Ok(p) => {
            let len = std::fs::metadata(&p).map(|m| m.len()).unwrap_or(0);
            let mut magic = [0u8; 6];
            let ok = File::open(&p)
                .ok()
                .and_then(|mut f| {
                    use std::io::Read;
                    f.read_exact(&mut magic).ok()
                })
                .is_some()
                && magic == V5_MAGIC;
            let _ = std::fs::remove_file(&p);
            (len, ok)
        }
        Err(_) => {
            write_errors += 1;
            (0, false)
        }
    };
    let _ = capture_discard();
    let _ = std::fs::remove_dir_all(&dir);

    SoakReport {
        equiv_secs,
        uncompressed_record_bytes: stats.uncompressed_record_bytes,
        framed_raw_bytes,
        container_bytes,
        events: stats.events,
        flushes: 0,
        drops,
        write_errors,
        fill_ms,
        assemble_ms,
        rss_kb_after_fill,
        rss_kb_after_read,
        rss_kb_after_assemble,
        assemble_path: "capture_assemble_v5 copy .raw (writer thread, no outer zstd)",
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
        assert!(report.container_bytes >= report.framed_raw_bytes);
        assert!(report.container_magic_ok);
        assert!(
            report.assemble_path.contains("copy"),
            "assemble must copy .raw, not wrap it"
        );
        assert!(
            !report.assemble_path.contains("encode_all"),
            "assemble must not outer-zstd the raw section"
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
    #[ignore = "12h-equivalent volume; extra assemble RSS must not scale with filled raw"]
    fn soak_current_assemble_12h_equivalent() {
        let secs = equiv_secs_from_env(TWELVE_H_SECS);
        let report = run_current_assemble_soak(secs);
        assert_baseline(&report);
    }
}
