use crate::api::device_config::{DeviceConfig, DeviceKind};
use crate::api::muse::{MuseEventDto, EegDto, BandsDto, ImuDto, XyzDto, TelemetrySnapshot, PulseDto, MovementDto, PeakAlphaDto, GestureDto, SpO2Dto};
use anyhow::Result;
use flutter_rust_bridge::frb;
use rand::Rng;
use std::sync::{mpsc, Arc};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::Mutex;
use tokio::time::interval;

/// Connected name and firmware for a `sim:*` catalog id.
/// Unknown ids fall back to Muse S / Crown from [kind].
pub fn simulated_identity(device_id: &str, kind: DeviceKind) -> (String, String) {
    match device_id {
        "sim:muse-2" => ("Muse 2 (Simulated)".to_string(), "Classic".to_string()),
        "sim:muse-s" => ("Muse S (Simulated)".to_string(), "Classic".to_string()),
        "sim:muse-s-athena" => ("Muse S Athena (Simulated)".to_string(), "Athena".to_string()),
        "sim:crown-osc" => ("Crown (Simulated)".to_string(), "Crown_sim_v1.0".to_string()),
        "sim:notion-osc" => ("Notion (Simulated)".to_string(), "Notion_sim_v1.0".to_string()),
        _ => match kind {
            DeviceKind::Muse => ("Muse S (Simulated)".to_string(), "Classic".to_string()),
            DeviceKind::Neurosity => ("Crown (Simulated)".to_string(), "Crown_sim_v1.0".to_string()),
        },
    }
}

fn now_ms() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock before Unix epoch")
        .as_secs_f64() * 1000.0
}

/// Configuration for simulator behavior
#[derive(Debug, Clone)]
pub struct SimulatorConfig {
    /// Base noise level (0.0 = clean, 1.0 = very noisy)
    pub noise_level: f64,
    /// Signal quality variation amplitude (0.0 = stable, 1.0 = highly variable)
    pub quality_variation: f64,
    /// Enable blink simulation (Muse only)
    pub enable_blink: bool,
    /// Enable jaw clench simulation (Muse only)
    pub enable_clench: bool,
    /// Blink interval range (min, max) in seconds
    pub blink_interval_range: (f64, f64),
    /// Clench interval range (min, max) in seconds
    pub clench_interval_range: (f64, f64),
    /// SpO2 simulation (Muse only, requires PPG)
    pub enable_spo2: bool,
    /// SpO2 base value (95-99%)
    pub spo2_base: f64,
    /// SpO2 variation range
    pub spo2_variation: f64,
}

impl Default for SimulatorConfig {
    fn default() -> Self {
        Self {
            noise_level: 0.3,
            quality_variation: 0.2,
            enable_blink: true,
            enable_clench: true,
            blink_interval_range: (3.0, 8.0),
            clench_interval_range: (10.0, 30.0),
            enable_spo2: true,
            spo2_base: 97.0,
            spo2_variation: 1.5,
        }
    }
}

/// Simulator state for generating realistic EEG
struct SimulatorState {
    rng: rand::rngs::StdRng,
    config: SimulatorConfig,
    // Per-electrode phase accumulators for alpha rhythm
    alpha_phase: Vec<f64>,
    // Per-electrode baseline power
    baseline_power: Vec<f32>,
    // Signal quality per electrode (0-100)
    signal_quality: Vec<f64>,
    // Quality variation phase
    quality_phase: f64,
    // Packet counters
    eeg_packet_idx: u16,
    bands_counter: u32,
    imu_counter: u32,
    telemetry_counter: u32,
    // Gesture timing
    next_blink_at: f64,
    next_clench_at: f64,
    // SpO2 simulation
    spo2_phase: f64,
    spo2_window: Vec<f64>,
}

impl SimulatorState {
    fn new(config: &DeviceConfig, sim_config: SimulatorConfig, seed: u64) -> Self {
        use rand::SeedableRng;
        let mut rng = rand::rngs::StdRng::seed_from_u64(seed);
        
        // Initialize alpha phases randomly
        let alpha_phase: Vec<f64> = (0..config.channel_count)
            .map(|_| rng.gen_range(0.0..std::f64::consts::TAU))
            .collect();
        
        // Baseline power: higher alpha for target electrodes
        let baseline_power: Vec<f32> = (0..config.channel_count)
            .map(|i| {
                if config.target_electrodes.contains(&i) {
                    rng.gen_range(8.0..15.0)
                } else {
                    rng.gen_range(3.0..8.0)
                }
            })
            .collect();
        
        // Initial signal quality: good for target electrodes, variable for others
        let signal_quality: Vec<f64> = (0..config.channel_count)
            .map(|i| {
                if config.target_electrodes.contains(&i) {
                    rng.gen_range(85.0..95.0)
                } else if config.needed_electrodes.contains(&i) {
                    rng.gen_range(70.0..90.0)
                } else {
                    rng.gen_range(60.0..85.0)
                }
            })
            .collect();
        
        let now = now_ms();
        let next_blink_at = now + rng.gen_range(sim_config.blink_interval_range.0 * 1000.0 .. sim_config.blink_interval_range.1 * 1000.0);
        let next_clench_at = now + rng.gen_range(sim_config.clench_interval_range.0 * 1000.0 .. sim_config.clench_interval_range.1 * 1000.0);
        
        Self {
            rng,
            config: sim_config,
            alpha_phase,
            baseline_power,
            signal_quality,
            quality_phase: 0.0,
            eeg_packet_idx: 0,
            bands_counter: 0,
            imu_counter: 0,
            telemetry_counter: 0,
            next_blink_at,
            next_clench_at,
            spo2_phase: 0.0,
            spo2_window: Vec::new(),
        }
    }
}

/// EEG simulator that produces MuseEventDto events matching the real pipeline
#[allow(dead_code)]
pub struct DeviceSimulator {
    config: DeviceConfig,
    sim_config: SimulatorConfig,
    state: Arc<Mutex<SimulatorState>>,
    event_tx: mpsc::Sender<MuseEventDto>,
    running: Arc<Mutex<bool>>,
}

impl DeviceSimulator {
    pub fn new(config: DeviceConfig, event_tx: mpsc::Sender<MuseEventDto>) -> Self {
        Self::with_config(config, event_tx, SimulatorConfig::default())
    }
    
    #[frb(ignore)]
    pub fn with_config(config: DeviceConfig, event_tx: mpsc::Sender<MuseEventDto>, sim_config: SimulatorConfig) -> Self {
        let seed = match config.kind {
            DeviceKind::Muse => 0x4D555345,
            DeviceKind::Neurosity => 0x43524F57,
        };
        let state = Arc::new(Mutex::new(SimulatorState::new(&config, sim_config.clone(), seed)));
        Self {
            config,
            sim_config,
            state,
            event_tx,
            running: Arc::new(Mutex::new(false)),
        }
    }
    
    pub async fn start(&self) -> Result<()> {
        *self.running.lock().await = true;
        
        let config = self.config.clone();
        let state = self.state.clone();
        let tx = self.event_tx.clone();
        let running = self.running.clone();
        
        // EEG task: ~256 Hz / 12 samples per packet = ~21 packets/sec per electrode
        let eeg_task = tokio::spawn(Self::run_eeg(config.clone(), state.clone(), tx.clone(), running.clone()));
        
        // Bands task: ~10 Hz (every 100ms)
        let bands_task = tokio::spawn(Self::run_bands(config.clone(), state.clone(), tx.clone(), running.clone()));
        
        // IMU task: ~50 Hz
        let imu_task = tokio::spawn(Self::run_imu(config.clone(), state.clone(), tx.clone(), running.clone()));
        
        // Telemetry task: ~1 Hz (every 5s)
        let telemetry_task = tokio::spawn(Self::run_telemetry(config.clone(), state.clone(), tx.clone(), running.clone()));
        
        // Wait for all (they run until running=false)
        let _ = tokio::join!(eeg_task, bands_task, imu_task, telemetry_task);
        Ok(())
    }
    
    pub async fn stop(&self) {
        *self.running.lock().await = false;
    }
    
    async fn run_eeg(config: DeviceConfig, state: Arc<Mutex<SimulatorState>>, tx: mpsc::Sender<MuseEventDto>, running: Arc<Mutex<bool>>) {
        let interval_ms = (1000 / config.sampling_rate * 12) as u64;
        let mut interval = interval(Duration::from_millis(interval_ms));
        
        while *running.lock().await {
            interval.tick().await;
            
            let mut state_lock = state.lock().await;
            let ts = now_ms();
            
            // Generate EEG for each electrode
            for ch in 0..config.channel_count {
                let electrode = ch as i32;
                let mut samples = Vec::with_capacity(12);
                
                // Alpha rhythm (8-13 Hz) with some noise
                let alpha_freq = 10.0;
                let dt = 12.0 / config.sampling_rate as f64;
                state_lock.alpha_phase[ch] += alpha_freq * dt * std::f64::consts::TAU;
                
                // Get current signal quality for this electrode (affects noise)
                let quality = state_lock.signal_quality[ch].clamp(0.0, 100.0);
                let quality_factor = 1.0 - (quality / 100.0); // 0 = perfect, 1 = terrible
                let noise_mult = 1.0 + quality_factor * state_lock.config.noise_level * 3.0;
                
                for i in 0..12 {
                    let phase = state_lock.alpha_phase[ch] + (i as f64 / config.sampling_rate as f64) * alpha_freq * std::f64::consts::TAU;
                    // Alpha wave + noise scaled by signal quality + pink noise
                    let alpha = (phase.sin() * state_lock.baseline_power[ch] as f64) as f64;
                    let noise = state_lock.rng.gen_range(-2.0..2.0) as f64 * noise_mult;
                    let pink = state_lock.rng.gen_range(-1.0..1.0) as f64 * 0.5 * noise_mult;
                    samples.push(alpha + noise + pink);
                }
                
                let event = MuseEventDto::Eeg(EegDto {
                    index: state_lock.eeg_packet_idx,
                    electrode,
                    timestamp: ts,
                    samples,
                });
                
                if tx.send(event).is_err() {
                    return;
                }
            }
            
            state_lock.eeg_packet_idx = state_lock.eeg_packet_idx.wrapping_add(1);
        }
    }
    
    async fn run_bands(config: DeviceConfig, state: Arc<Mutex<SimulatorState>>, tx: mpsc::Sender<MuseEventDto>, running: Arc<Mutex<bool>>) {
        let mut interval = interval(Duration::from_millis(100));
        
        while *running.lock().await {
            interval.tick().await;
            
            let mut state_lock = state.lock().await;
            let ts = now_ms();
            
            // Update signal quality with slow variation
            state_lock.quality_phase += 0.05; // Slow cycle ~20s
            for ch in 0..config.channel_count {
                let base_quality = state_lock.signal_quality[ch];
                let variation = (state_lock.quality_phase + ch as f64 * 0.7).sin() * state_lock.config.quality_variation * 20.0;
                state_lock.signal_quality[ch] = (base_quality + variation).clamp(10.0, 100.0);
            }
            
            // Generate bands for each electrode
            for ch in 0..config.channel_count {
                let electrode = ch as i32;
                let quality = state_lock.signal_quality[ch] / 100.0;
                
                // Simulate realistic band powers - quality affects line noise ratio
                let alpha_base = state_lock.baseline_power[ch];
                let alpha = alpha_base * state_lock.rng.gen_range(0.8..1.2);
                let theta = alpha_base * state_lock.rng.gen_range(0.3..0.6);
                let delta = alpha_base * state_lock.rng.gen_range(0.4..0.8);
                let beta = alpha_base * state_lock.rng.gen_range(0.2..0.5);
                let gamma = alpha_base * state_lock.rng.gen_range(0.1..0.3);
                
                // Line noise increases as signal quality decreases
                let line_noise = 0.05 + (1.0 - quality) * 0.3 + state_lock.rng.gen_range(0.0..0.1);
                
                let event = MuseEventDto::Bands(BandsDto {
                    electrode,
                    timestamp: ts,
                    delta: delta as f64,
                    theta: theta as f64,
                    alpha: alpha as f64,
                    beta: beta as f64,
                    gamma: gamma as f64,
                    line_noise_ratio: line_noise.clamp(0.0, 1.0) as f64,
                });
                
                if tx.send(event).is_err() {
                    return;
                }
            }
            
            // Pulse (from PPG if available) - simulate ~60-80 BPM
            if config.has_ppg {
                let bpm = state_lock.rng.gen_range(60.0..80.0);
                let pulse = MuseEventDto::Pulse(PulseDto {
                    timestamp: ts,
                    bpm,
                    confidence: state_lock.rng.gen_range(0.7..1.0),
                });
                tx.send(pulse).ok();
            }
            
            // SpO2 simulation (Muse only, requires PPG)
            if config.has_ppg && state_lock.config.enable_spo2 {
                state_lock.spo2_phase += 0.02;
                let spo2_val = state_lock.config.spo2_base 
                    + (state_lock.spo2_phase.sin() * state_lock.config.spo2_variation)
                    + state_lock.rng.gen_range(-0.3..0.3);
                
                // Maintain rolling window for confidence calculation
                state_lock.spo2_window.push(spo2_val);
                if state_lock.spo2_window.len() > 30 { // 30 samples @ ~10Hz = 3s window
                    state_lock.spo2_window.remove(0);
                }
                
                // Confidence based on window stability
                let mean = state_lock.spo2_window.iter().sum::<f64>() / state_lock.spo2_window.len() as f64;
                let variance = state_lock.spo2_window.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / state_lock.spo2_window.len() as f64;
                let confidence = (1.0 - variance / 10.0).clamp(0.3, 1.0);
                
                if confidence >= 0.3 {
                    let spo2 = MuseEventDto::SpO2(SpO2Dto {
                        timestamp: ts,
                        spo2: spo2_val.clamp(85.0, 100.0),
                        confidence,
                    });
                    tx.send(spo2).ok();
                }
            }
            
            // Movement (from accel magnitude)
            let movement = MuseEventDto::Movement(MovementDto {
                timestamp: ts,
                score: state_lock.rng.gen_range(0.0..0.3),
            });
            tx.send(movement).ok();
            
            // Peak alpha (for target electrodes)
            for &ch in &config.target_electrodes {
                if ch < config.channel_count {
                    let peak_alpha = MuseEventDto::PeakAlpha(PeakAlphaDto {
                        timestamp: ts,
                        frequency: 10.0 + state_lock.rng.gen_range(-0.5..0.5),
                        power: (state_lock.baseline_power[ch] * state_lock.rng.gen_range(0.9..1.1)) as f64,
                    });
                    tx.send(peak_alpha).ok();
                }
            }
            
            // Gesture simulation (Muse only - 4 channel)
            if config.channel_count == 4 {
                // Extract config values to avoid borrow checker issues
                let blink_enabled = state_lock.config.enable_blink;
                let blink_interval = state_lock.config.blink_interval_range;
                let clench_enabled = state_lock.config.enable_clench;
                let clench_interval = state_lock.config.clench_interval_range;
                
                // Blink simulation
                if blink_enabled && ts >= state_lock.next_blink_at {
                    let gesture = MuseEventDto::Gestures(GestureDto {
                        timestamp: ts,
                        blink_count: 1,
                        clench: false,
                        eye: 0,
                    });
                    tx.send(gesture).ok();
                    
                    // Schedule next blink
                    state_lock.next_blink_at = ts + state_lock.rng.gen_range(
                        blink_interval.0 * 1000.0 .. 
                        blink_interval.1 * 1000.0
                    );
                    
                    // Occasionally double blink (two blinks in quick succession)
                    if state_lock.rng.gen_bool(0.15) {
                        state_lock.next_blink_at = ts + state_lock.rng.gen_range(100.0..300.0);
                    }
                }
                
                // Clench simulation
                if clench_enabled && ts >= state_lock.next_clench_at {
                    let gesture = MuseEventDto::Gestures(GestureDto {
                        timestamp: ts,
                        blink_count: 0,
                        clench: true,
                        eye: 0,
                    });
                    tx.send(gesture).ok();
                    
                    // Schedule next clench
                    state_lock.next_clench_at = ts + state_lock.rng.gen_range(
                        clench_interval.0 * 1000.0 .. 
                        clench_interval.1 * 1000.0
                    );
                    
                    // Occasionally double clench
                    if state_lock.rng.gen_bool(0.1) {
                        state_lock.next_clench_at = ts + state_lock.rng.gen_range(500.0..1500.0);
                    }
                }
            }
            
            state_lock.bands_counter += 1;
        }
    }
    
    async fn run_imu(config: DeviceConfig, state: Arc<Mutex<SimulatorState>>, tx: mpsc::Sender<MuseEventDto>, running: Arc<Mutex<bool>>) {
        if !config.has_imu {
            return;
        }
        
        let mut interval = interval(Duration::from_millis(20));
        
        while *running.lock().await {
            interval.tick().await;
            
            let mut state_lock = state.lock().await;
            let _ts = now_ms();
            
            // Accelerometer - simulate slight head movement
            let accel = MuseEventDto::Accelerometer(ImuDto {
                sequence_id: state_lock.imu_counter as u16,
                samples: vec![XyzDto {
                    x: state_lock.rng.gen_range(-0.1..0.1),
                    y: state_lock.rng.gen_range(-0.1..0.1),
                    z: state_lock.rng.gen_range(0.9..1.1),
                }],
            });
            tx.send(accel).ok();
            
            // Gyroscope - simulate slow rotation
            let gyro = MuseEventDto::Gyroscope(ImuDto {
                sequence_id: state_lock.imu_counter as u16,
                samples: vec![XyzDto {
                    x: state_lock.rng.gen_range(-0.02..0.02),
                    y: state_lock.rng.gen_range(-0.02..0.02),
                    z: state_lock.rng.gen_range(-0.02..0.02),
                }],
            });
            tx.send(gyro).ok();
            
            state_lock.imu_counter += 1;
        }
    }
    
    async fn run_telemetry(config: DeviceConfig, state: Arc<Mutex<SimulatorState>>, tx: mpsc::Sender<MuseEventDto>, running: Arc<Mutex<bool>>) {
        let mut interval = interval(Duration::from_secs(5));
        
        while *running.lock().await {
            interval.tick().await;
            
            let mut state_lock = state.lock().await;
            
            let _firmware = match config.kind {
                DeviceKind::Muse => "MuseS_sim_v1.0".to_string(),
                DeviceKind::Neurosity => "Crown_sim_v1.0".to_string(),
            };
            
            let telemetry = MuseEventDto::Telemetry(TelemetrySnapshot {
                battery_level: 42.0,
                fuel_gauge_voltage: 0.0,
                temperature: 0,
            });
            
            if tx.send(telemetry).is_err() {
                return;
            }
            
            state_lock.telemetry_counter += 1;
        }
    }
}

/// Spawn a simulator task and return the handle + stop signal
#[frb(ignore)]
pub async fn spawn_simulator(
    config: DeviceConfig,
    tx: mpsc::Sender<MuseEventDto>,
    sim_config: Option<SimulatorConfig>,
) -> Result<tokio::task::JoinHandle<()>> {
    let sim = DeviceSimulator::with_config(config, tx, sim_config.unwrap_or_default());
    let handle = tokio::spawn(async move {
        let _ = sim.start().await;
    });
    Ok(handle)
}

#[cfg(test)]
mod tests {
    use super::*;

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
}