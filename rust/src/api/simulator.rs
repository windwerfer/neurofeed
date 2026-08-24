use crate::api::device_config::{DeviceConfig, DeviceKind};
use crate::api::muse::{MuseEventDto, EegDto, BandsDto, ImuDto, XyzDto, TelemetrySnapshot, PulseDto, MovementDto, PeakAlphaDto};
use anyhow::Result;
use rand::Rng;
use std::sync::{mpsc, Arc};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::{Mutex, oneshot};
use tokio::time::interval;

fn now_ms() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock before Unix epoch")
        .as_secs_f64() * 1000.0
}

/// Simulator state for generating realistic EEG
struct SimulatorState {
    rng: rand::rngs::StdRng,
    // Per-electrode phase accumulators for alpha rhythm
    alpha_phase: Vec<f64>,
    // Per-electrode baseline power
    baseline_power: Vec<f32>,
    // Packet counters
    eeg_packet_idx: u16,
    bands_counter: u32,
    imu_counter: u32,
    telemetry_counter: u32,
}

impl SimulatorState {
    fn new(config: &DeviceConfig, seed: u64) -> Self {
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
                    rng.gen_range(8.0..15.0) // Higher alpha for target
                } else {
                    rng.gen_range(3.0..8.0)
                }
            })
            .collect();
        
        Self {
            rng,
            alpha_phase,
            baseline_power,
            eeg_packet_idx: 0,
            bands_counter: 0,
            imu_counter: 0,
            telemetry_counter: 0,
        }
    }
}

/// EEG simulator that produces MuseEventDto events matching the real pipeline
pub struct DeviceSimulator {
    config: DeviceConfig,
    state: Arc<Mutex<SimulatorState>>,
    event_tx: mpsc::Sender<MuseEventDto>,
    running: Arc<Mutex<bool>>,
    stop_tx: Option<oneshot::Sender<()>>,
}

impl DeviceSimulator {
    pub fn new(config: DeviceConfig, event_tx: mpsc::Sender<MuseEventDto>) -> Self {
        let seed = match config.kind {
            DeviceKind::SimulatedMuse => 0x4D555345, // "MUSE" in hex
            DeviceKind::SimulatedNeurosity => 0x43524F57, // "CROW" in hex
            _ => 0xDEADBEEF,
        };
        let state = Arc::new(Mutex::new(SimulatorState::new(&config, seed)));
        Self {
            config,
            state,
            event_tx,
            running: Arc::new(Mutex::new(false)),
            stop_tx: None,
        }
    }
    
    pub async fn start(&self) -> Result<()> {
        *self.running.lock().await = true;
        
        let (stop_tx, stop_rx) = oneshot::channel::<()>();
        // Store stop_tx for later use (we can't easily store it in &self, so we'll use a different approach)
        
        let config = self.config.clone();
        let state = self.state.clone();
        let tx = self.event_tx.clone();
        let running = self.running.clone();
        
        // EEG task: ~256 Hz / 12 samples per packet = ~21 packets/sec per electrode
        let eeg_task = tokio::spawn(Self::run_eeg(config.clone(), state.clone(), tx.clone(), running.clone(), stop_rx));
        
        // Bands task: ~10 Hz (every 100ms)
        let bands_task = tokio::spawn(Self::run_bands(config.clone(), state.clone(), tx.clone(), running.clone()));
        
        // IMU task: ~50 Hz
        let imu_task = tokio::spawn(Self::run_imu(config.clone(), state.clone(), tx.clone(), running.clone()));
        
        // Telemetry task: ~1 Hz
        let telemetry_task = tokio::spawn(Self::run_telemetry(config.clone(), state.clone(), tx.clone(), running.clone()));
        
        // Wait for all (they run until running=false)
        let _ = tokio::join!(eeg_task, bands_task, imu_task, telemetry_task);
        Ok(())
    }
    
    pub async fn stop(&self) {
        *self.running.lock().await = false;
    }
    
    async fn run_eeg(config: DeviceConfig, state: Arc<Mutex<SimulatorState>>, tx: mpsc::Sender<MuseEventDto>, running: Arc<Mutex<bool>>, mut stop_rx: oneshot::Receiver<()>) {
        let interval_ms = (1000 / config.sampling_rate * 12) as u64;
        let mut interval = interval(Duration::from_millis(interval_ms)); // ~12 samples per packet
        
        while *running.lock().await {
            interval.tick().await;
            
            let mut state_lock = state.lock().await;
            let ts = now_ms();
            
            // Generate EEG for each electrode
            for ch in 0..config.channel_count {
                let electrode = ch as i32;
                let mut samples = Vec::with_capacity(12);
                
                // Alpha rhythm (8-13 Hz) with some noise
                let alpha_freq = 10.0; // Hz
                let dt = 12.0 / config.sampling_rate as f64; // 12 samples
                state_lock.alpha_phase[ch] += alpha_freq * dt * std::f64::consts::TAU;
                
                for i in 0..12 {
                    let phase = state_lock.alpha_phase[ch] + (i as f64 / config.sampling_rate as f64) * alpha_freq * std::f64::consts::TAU;
                    // Alpha wave + noise + 1/f noise
                    let alpha = (phase.sin() * state_lock.baseline_power[ch] as f64) as f64;
                    let noise = state_lock.rng.gen_range(-2.0..2.0) as f64;
                    let pink = state_lock.rng.gen_range(-1.0..1.0) as f64 * 0.5;
                    samples.push(alpha + noise + pink);
                }
                
                let event = MuseEventDto::Eeg(EegDto {
                    index: state_lock.eeg_packet_idx,
                    electrode,
                    timestamp: ts,
                    samples,
                });
                
                if tx.send(event).is_err() {
                    return; // Channel closed
                }
            }
            
            state_lock.eeg_packet_idx = state_lock.eeg_packet_idx.wrapping_add(1);
        }
    }
    
    async fn run_bands(config: DeviceConfig, state: Arc<Mutex<SimulatorState>>, tx: mpsc::Sender<MuseEventDto>, running: Arc<Mutex<bool>>) {
        let mut interval = interval(Duration::from_millis(100)); // ~10 Hz
        
        while *running.lock().await {
            interval.tick().await;
            
            let mut state_lock = state.lock().await;
            let ts = now_ms();
            
            // Generate bands for each electrode
            for ch in 0..config.channel_count {
                let electrode = ch as i32;
                
                // Simulate realistic band powers
                let alpha_base = state_lock.baseline_power[ch];
                let alpha = alpha_base * state_lock.rng.gen_range(0.8..1.2);
                let theta = alpha_base * state_lock.rng.gen_range(0.3..0.6);
                let delta = alpha_base * state_lock.rng.gen_range(0.4..0.8);
                let beta = alpha_base * state_lock.rng.gen_range(0.2..0.5);
                let gamma = alpha_base * state_lock.rng.gen_range(0.1..0.3);
                let line_noise = state_lock.rng.gen_range(0.05..0.15);
                
                let event = MuseEventDto::Bands(BandsDto {
                    electrode,
                    timestamp: ts,
                    delta: delta as f64,
                    theta: theta as f64,
                    alpha: alpha as f64,
                    beta: beta as f64,
                    gamma: gamma as f64,
                    line_noise_ratio: line_noise as f64,
                });
                
                if tx.send(event).is_err() {
                    return;
                }
            }
            
            // Pulse (from PPG if available) - simulate ~60-80 BPM
            if config.has_ppg {
                let pulse = MuseEventDto::Pulse(PulseDto {
                    timestamp: ts,
                    bpm: state_lock.rng.gen_range(60.0..80.0),
                    confidence: state_lock.rng.gen_range(0.7..1.0),
                });
                tx.send(pulse).ok();
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
            
            state_lock.bands_counter += 1;
        }
    }
    
    async fn run_imu(config: DeviceConfig, state: Arc<Mutex<SimulatorState>>, tx: mpsc::Sender<MuseEventDto>, running: Arc<Mutex<bool>>) {
        if !config.has_imu {
            return;
        }
        
        let mut interval = interval(Duration::from_millis(20)); // ~50 Hz
        
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
                    z: state_lock.rng.gen_range(0.9..1.1), // gravity
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
        let mut interval = interval(Duration::from_secs(5)); // Every 5 seconds
        
        while *running.lock().await {
            interval.tick().await;
            
            let mut state_lock = state.lock().await;
            
            let _firmware = match config.kind {
                DeviceKind::SimulatedMuse => "MuseS_sim_v1.0".to_string(),
                DeviceKind::SimulatedNeurosity => "Crown_sim_v1.0".to_string(),
                _ => "Unknown_sim".to_string(),
            };
            
            let telemetry = MuseEventDto::Telemetry(TelemetrySnapshot {
                battery_level: 42.0, // Fixed 42% as requested
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
