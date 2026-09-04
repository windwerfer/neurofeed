use crate::api::device_config::{DeviceConfig, DeviceKind};
use crate::api::muse::{EegDto, ImuDto, MuseEventDto, PpgDto, TelemetrySnapshot, XyzDto};
use anyhow::Result;
use flutter_rust_bridge::frb;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::mpsc;
use tokio::time::{interval, MissedTickBehavior};

/// Connected name and firmware for a `sim:*` catalog id.
/// Unknown ids fall back to Muse S / Crown from [kind].
pub fn simulated_identity(device_id: &str, kind: DeviceKind) -> (String, String) {
    match device_id {
        "sim:muse-2" => ("Muse 2 (Simulated)".to_string(), "Classic".to_string()),
        "sim:muse-s" => ("Muse S (Simulated)".to_string(), "Classic".to_string()),
        "sim:muse-s-athena" => (
            "Muse S Athena (Simulated)".to_string(),
            "Athena".to_string(),
        ),
        "sim:crown-osc" => (
            "Crown (Simulated)".to_string(),
            "Crown_sim_v1.0".to_string(),
        ),
        "sim:notion-osc" => (
            "Notion (Simulated)".to_string(),
            "Notion_sim_v1.0".to_string(),
        ),
        _ => match kind {
            DeviceKind::Muse => ("Muse S (Simulated)".to_string(), "Classic".to_string()),
            DeviceKind::Neurosity => (
                "Crown (Simulated)".to_string(),
                "Crown_sim_v1.0".to_string(),
            ),
        },
    }
}

fn now_ms() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock before Unix epoch")
        .as_secs_f64()
        * 1000.0
}

const EEG_SAMPLES_PER_PKT: usize = 12;
const PPG_HZ: f64 = 64.0;
const PPG_SAMPLES_PER_PKT: usize = 6;
const PPG_CHANNELS: usize = 3;
const HEART_HZ: f64 = 1.2;
const BATTERY_PERCENT: f32 = 85.0;

/// ~10 µV alpha + sub-µV hash noise. RMS stays in the Dart/Rust quality
/// band `1 < std < 15` so every pad scores ≥ 80.
fn eeg_sample(t: f64, ch: usize) -> f64 {
    let phi = ch as f64 * std::f64::consts::PI / 2.5;
    let alpha = 10.0 * (std::f64::consts::TAU * 10.0 * t + phi).sin();
    let nx = t * 1000.7 + ch as f64 * 137.508;
    let noise = ((nx.sin() * 9973.1).fract() - 0.5) * 0.8;
    alpha + noise
}

/// Classic-shaped PPG: ambient / infrared / red at 64 Hz.
fn ppg_sample(t: f64, ch: usize) -> f64 {
    let pulse = (std::f64::consts::TAU * HEART_HZ * t).sin();
    match ch {
        0 => 800.0 + 15.0 * pulse,
        1 => 200_000.0 + 8_000.0 * pulse,
        2 => 180_000.0 + 6_000.0 * pulse,
        _ => 0.0,
    }
}

/// Local headset-stream simulator. Emits the same DTO variants muse-rs maps
/// from BLE (`Eeg`, `Ppg`, `Telemetry`, `Accelerometer`, `Gyroscope`). Bands,
/// pulse, SpO2, features, and quality are derived by the event forwarder.
#[frb(ignore)]
pub struct DeviceSimulator {
    config: DeviceConfig,
    event_tx: mpsc::Sender<MuseEventDto>,
    running: Arc<AtomicBool>,
}

impl DeviceSimulator {
    pub fn new(config: DeviceConfig, event_tx: mpsc::Sender<MuseEventDto>) -> Self {
        Self {
            config,
            event_tx,
            running: Arc::new(AtomicBool::new(false)),
        }
    }

    pub async fn start(&self) -> Result<()> {
        self.running.store(true, Ordering::SeqCst);

        let config = self.config.clone();
        let tx = self.event_tx.clone();
        let running = self.running.clone();

        let eeg_task = tokio::spawn(Self::run_eeg(config.clone(), tx.clone(), running.clone()));
        let ppg_task = tokio::spawn(Self::run_ppg(config.clone(), tx.clone(), running.clone()));
        let imu_task = tokio::spawn(Self::run_imu(config.clone(), tx.clone(), running.clone()));
        let telemetry_task = tokio::spawn(Self::run_telemetry(tx, running));

        let _ = tokio::join!(eeg_task, ppg_task, imu_task, telemetry_task);
        Ok(())
    }

    pub async fn stop(&self) {
        self.running.store(false, Ordering::SeqCst);
    }

    async fn run_eeg(
        config: DeviceConfig,
        tx: mpsc::Sender<MuseEventDto>,
        running: Arc<AtomicBool>,
    ) {
        let sr = config.sampling_rate as f64;
        let period = Duration::from_secs_f64(EEG_SAMPLES_PER_PKT as f64 / sr);
        let mut ticker = interval(period);
        ticker.set_missed_tick_behavior(MissedTickBehavior::Delay);
        let mut idx: u16 = 0;
        let mut sample_n: u64 = 0;

        while running.load(Ordering::SeqCst) {
            ticker.tick().await;
            if !running.load(Ordering::SeqCst) {
                break;
            }
            let ts = now_ms();
            for ch in 0..config.channel_count {
                let mut samples = Vec::with_capacity(EEG_SAMPLES_PER_PKT);
                for i in 0..EEG_SAMPLES_PER_PKT {
                    let t = (sample_n + i as u64) as f64 / sr;
                    samples.push(eeg_sample(t, ch));
                }
                let event = MuseEventDto::Eeg(EegDto {
                    index: idx,
                    electrode: ch as i32,
                    timestamp: ts,
                    samples,
                });
                if tx.send(event).await.is_err() {
                    return;
                }
            }
            sample_n += EEG_SAMPLES_PER_PKT as u64;
            idx = idx.wrapping_add(1);
        }
    }

    async fn run_ppg(
        config: DeviceConfig,
        tx: mpsc::Sender<MuseEventDto>,
        running: Arc<AtomicBool>,
    ) {
        if !config.has_ppg {
            return;
        }
        let period = Duration::from_secs_f64(PPG_SAMPLES_PER_PKT as f64 / PPG_HZ);
        let mut ticker = interval(period);
        ticker.set_missed_tick_behavior(MissedTickBehavior::Delay);
        let mut idx: u16 = 0;
        let mut sample_n: u64 = 0;

        while running.load(Ordering::SeqCst) {
            ticker.tick().await;
            if !running.load(Ordering::SeqCst) {
                break;
            }
            let ts = now_ms();
            for ch in 0..PPG_CHANNELS {
                let mut samples = Vec::with_capacity(PPG_SAMPLES_PER_PKT);
                for i in 0..PPG_SAMPLES_PER_PKT {
                    let t = (sample_n + i as u64) as f64 / PPG_HZ;
                    samples.push(ppg_sample(t, ch));
                }
                let event = MuseEventDto::Ppg(PpgDto {
                    index: idx,
                    channel: ch as i32,
                    timestamp: ts,
                    samples,
                });
                if tx.send(event).await.is_err() {
                    return;
                }
            }
            sample_n += PPG_SAMPLES_PER_PKT as u64;
            idx = idx.wrapping_add(1);
        }
    }

    async fn run_imu(
        config: DeviceConfig,
        tx: mpsc::Sender<MuseEventDto>,
        running: Arc<AtomicBool>,
    ) {
        if !config.has_imu {
            return;
        }
        let mut ticker = interval(Duration::from_millis(20));
        ticker.set_missed_tick_behavior(MissedTickBehavior::Delay);
        let mut seq: u16 = 0;
        let start = std::time::Instant::now();

        while running.load(Ordering::SeqCst) {
            ticker.tick().await;
            if !running.load(Ordering::SeqCst) {
                break;
            }
            let t = start.elapsed().as_secs_f64();
            let accel = MuseEventDto::Accelerometer(ImuDto {
                sequence_id: seq,
                samples: vec![XyzDto {
                    x: (0.01 * (std::f64::consts::TAU * 0.3 * t).sin()) as f32,
                    y: (0.02 * (std::f64::consts::TAU * 0.5 * t).cos()) as f32,
                    z: (1.0 + 0.005 * (std::f64::consts::TAU * 0.1 * t).sin()) as f32,
                }],
            });
            if tx.send(accel).await.is_err() {
                return;
            }
            let gyro = MuseEventDto::Gyroscope(ImuDto {
                sequence_id: seq,
                samples: vec![XyzDto {
                    x: (0.02 * (std::f64::consts::TAU * 0.2 * t).sin()) as f32,
                    y: (0.015 * (std::f64::consts::TAU * 0.3 * t).cos()) as f32,
                    z: (0.01 * (std::f64::consts::TAU * 0.1 * t).sin()) as f32,
                }],
            });
            if tx.send(gyro).await.is_err() {
                return;
            }
            seq = seq.wrapping_add(1);
        }
    }

    async fn run_telemetry(tx: mpsc::Sender<MuseEventDto>, running: Arc<AtomicBool>) {
        let mut ticker = interval(Duration::from_secs(1));
        ticker.set_missed_tick_behavior(MissedTickBehavior::Delay);

        while running.load(Ordering::SeqCst) {
            ticker.tick().await;
            if !running.load(Ordering::SeqCst) {
                break;
            }
            let telemetry = MuseEventDto::Telemetry(TelemetrySnapshot {
                battery_level: BATTERY_PERCENT,
                fuel_gauge_voltage: 0.0,
                temperature: 0,
            });
            if tx.send(telemetry).await.is_err() {
                return;
            }
        }
    }
}

/// Spawn producer tasks on the current tokio runtime. Returns the handle used
/// to stop them. Does not join — connect must not block on the stream.
#[frb(ignore)]
pub fn spawn_simulator(
    config: DeviceConfig,
    tx: mpsc::Sender<MuseEventDto>,
) -> Arc<DeviceSimulator> {
    let sim = Arc::new(DeviceSimulator::new(config, tx));
    let run = sim.clone();
    tokio::spawn(async move {
        if let Err(e) = run.start().await {
            log::warn!("[muse] simulator exited: {e:#}");
        }
    });
    sim
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::device_config::DeviceConfig;

    #[test]
    fn simulated_identity_catalog_table() {
        assert_eq!(
            simulated_identity("sim:muse-2", DeviceKind::Muse),
            ("Muse 2 (Simulated)".into(), "Classic".into())
        );
        assert_eq!(
            simulated_identity("sim:muse-s", DeviceKind::Muse),
            ("Muse S (Simulated)".into(), "Classic".into())
        );
        assert_eq!(
            simulated_identity("sim:muse-s-athena", DeviceKind::Muse),
            ("Muse S Athena (Simulated)".into(), "Athena".into())
        );
        assert_eq!(
            simulated_identity("sim:crown-osc", DeviceKind::Neurosity),
            ("Crown (Simulated)".into(), "Crown_sim_v1.0".into())
        );
        assert_eq!(
            simulated_identity("sim:notion-osc", DeviceKind::Neurosity),
            ("Notion (Simulated)".into(), "Notion_sim_v1.0".into())
        );
    }

    #[test]
    fn simulated_identity_unknown_falls_back_by_kind() {
        assert_eq!(
            simulated_identity("sim:unknown", DeviceKind::Muse),
            ("Muse S (Simulated)".into(), "Classic".into())
        );
        assert_eq!(
            simulated_identity("sim:unknown", DeviceKind::Neurosity),
            ("Crown (Simulated)".into(), "Crown_sim_v1.0".into())
        );
    }

    fn sample_std(samples: &[f64]) -> f64 {
        let n = samples.len() as f64;
        let mean = samples.iter().sum::<f64>() / n;
        (samples.iter().map(|s| (s - mean).powi(2)).sum::<f64>() / n).sqrt()
    }

    async fn drain_for(rx: &mut mpsc::Receiver<MuseEventDto>, dur: Duration) -> Vec<MuseEventDto> {
        let deadline = tokio::time::Instant::now() + dur;
        let mut out = Vec::new();
        loop {
            match tokio::time::timeout_at(deadline, rx.recv()).await {
                Ok(Some(ev)) => out.push(ev),
                _ => break,
            }
        }
        out
    }

    #[tokio::test]
    async fn muse_simulator_emits_headset_stream() {
        let (tx, mut rx) = mpsc::channel(1024);
        let sim = spawn_simulator(DeviceConfig::muse(), tx);
        let events = drain_for(&mut rx, Duration::from_millis(350)).await;
        sim.stop().await;

        assert!(!events.is_empty(), "simulator produced no events");

        let mut eeg_ch = [0u32; 4];
        let mut ppg_ch = [0u32; 3];
        let mut telem = 0u32;
        let mut accel = 0u32;
        let mut gyro = 0u32;
        let mut derived = 0u32;
        let mut eeg_samples: Vec<f64> = Vec::new();

        for ev in &events {
            match ev {
                MuseEventDto::Eeg(e) => {
                    let i = e.electrode as usize;
                    if i < 4 {
                        eeg_ch[i] += 1;
                    }
                    assert_eq!(e.samples.len(), EEG_SAMPLES_PER_PKT);
                    assert!(e.timestamp > 0.0);
                    if e.electrode == 1 {
                        eeg_samples.extend_from_slice(&e.samples);
                    }
                }
                MuseEventDto::Ppg(p) => {
                    let i = p.channel as usize;
                    if i < 3 {
                        ppg_ch[i] += 1;
                    }
                    assert_eq!(p.samples.len(), PPG_SAMPLES_PER_PKT);
                }
                MuseEventDto::Telemetry(t) => {
                    telem += 1;
                    assert_eq!(t.battery_level, BATTERY_PERCENT);
                }
                MuseEventDto::Accelerometer(_) => accel += 1,
                MuseEventDto::Gyroscope(_) => gyro += 1,
                MuseEventDto::Bands(_)
                | MuseEventDto::Pulse(_)
                | MuseEventDto::SpO2(_)
                | MuseEventDto::PeakAlpha(_)
                | MuseEventDto::Gestures(_)
                | MuseEventDto::Movement(_)
                | MuseEventDto::Feature(_)
                | MuseEventDto::Reve(_) => derived += 1,
                _ => {}
            }
        }

        assert!(
            eeg_ch.iter().all(|&n| n > 0),
            "missing EEG on a Muse pad: {eeg_ch:?}"
        );
        assert!(
            ppg_ch.iter().all(|&n| n > 0),
            "missing PPG channel: {ppg_ch:?}"
        );
        assert!(telem >= 1, "expected an immediate telemetry packet");
        assert!(accel > 0 && gyro > 0, "expected IMU");
        assert_eq!(derived, 0, "simulator must not emit derived events");

        assert!(
            eeg_samples.len() >= 10,
            "not enough AF7 samples for quality std"
        );
        let std = sample_std(&eeg_samples);
        assert!(
            std > 1.0 && std < 15.0,
            "EEG std {std} is outside the ≥80 quality band"
        );
    }

    #[tokio::test]
    async fn crown_simulator_is_8ch_without_ppg() {
        let (tx, mut rx) = mpsc::channel(2048);
        let sim = spawn_simulator(DeviceConfig::neurosity_crown(), tx);
        let events = drain_for(&mut rx, Duration::from_millis(350)).await;
        sim.stop().await;

        let mut eeg_ch = [0u32; 8];
        let mut ppg = 0u32;
        for ev in &events {
            match ev {
                MuseEventDto::Eeg(e) => {
                    let i = e.electrode as usize;
                    if i < 8 {
                        eeg_ch[i] += 1;
                    }
                }
                MuseEventDto::Ppg(_) => ppg += 1,
                _ => {}
            }
        }
        assert!(
            eeg_ch.iter().all(|&n| n > 0),
            "missing EEG on a Crown pad: {eeg_ch:?}"
        );
        assert_eq!(ppg, 0, "Crown has no PPG");
    }
}
