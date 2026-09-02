use crate::api::device_config::DeviceConfig;
use crate::api::features::{self, FeatureDto};
use crate::api::muse::{MuseEventDto, EegDto, BandsDto, TelemetrySnapshot};
use anyhow::Result;
use flutter_rust_bridge::frb;
use rosc::{OscPacket, OscMessage, OscType};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::net::UdpSocket;
use tokio::sync::{mpsc, Mutex};
use tokio::time::interval;

fn now_ms() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64() * 1000.0
}

/// Crown electrode order matches `DeviceConfig::neurosity_crown()`:
/// 0=CP3, 1=C3, 2=F5, 3=PO3, 4=PO4, 5=F6, 6=C4, 7=CP4.
/// OSC `/raw` and `/brainwaves/*` packs 8 floats in this index order.
const CROWN_ELECTRODE_COUNT: usize = 8;

/// Per-electrode band power accumulator for merging /brainwaves/{band} messages
#[frb(ignore)]
#[derive(Default)]
struct BandAccumulator {
    timestamp: f64,
    delta: [f32; 8],
    theta: [f32; 8],
    alpha: [f32; 8],
    beta: [f32; 8],
    gamma: [f32; 8],
    received: [bool; 5],
}

/// Crown OSC connection handle for the connection manager
#[frb(ignore)]
pub struct CrownOscHandle {
    stop_tx: tokio::sync::oneshot::Sender<()>,
    task_handle: tokio::task::JoinHandle<()>,
}

impl CrownOscHandle {
    pub async fn disconnect(self) {
        let _ = self.stop_tx.send(());
        let _ = self.task_handle.await;
    }
}

/// Start the Crown/Notion OSC receiver.
/// Returns a handle that can be used to stop the receiver.
#[frb(ignore)]
pub async fn start_crown_osc_receiver(
    device_id: String,
    tx: mpsc::Sender<MuseEventDto>,
    port: u16, // default 9000
) -> Result<CrownOscHandle> {
    let socket = UdpSocket::bind(("0.0.0.0", port)).await?;
    log::info!("[crown_osc] Listening on 0.0.0.0:{port} for device {device_id}");

    let (stop_tx, mut stop_rx) = tokio::sync::oneshot::channel::<()>();

    // DeviceConfig for Crown (used for electrode mapping)
    let config = DeviceConfig::neurosity_crown();
    
    // Band accumulator protected by mutex for concurrent access from OSC handler
    let band_accumulator = Arc::new(Mutex::new(BandAccumulator::default()));
    
    // Signal quality per electrode (from /signalQuality)
    let signal_quality = Arc::new(Mutex::new([0.5f32; CROWN_ELECTRODE_COUNT]));
    
    // Latest battery level
    let battery_level = Arc::new(Mutex::new(0.0f32));
    
    // Track if we've seen data from this device_id (filter by serial in address)
    let device_id_filter = device_id.clone();

    let task_handle = tokio::spawn(async move {
        let mut buf = [0u8; 8192];
        let mut band_emit_interval = interval(Duration::from_millis(100)); // ~10Hz bands emit
        let mut telemetry_emit_interval = interval(Duration::from_secs(5));
        let mut first_packet = true;

        loop {
            tokio::select! {
                _ = &mut stop_rx => {
                    log::info!("[crown_osc] Stop signal received, shutting down");
                    break;
                }
                result = socket.recv_from(&mut buf) => {
                    match result {
                        Ok((len, src_addr)) => {
                            if first_packet {
                                log::info!("[crown_osc] First packet received from {src_addr} ({len} bytes)");
                                first_packet = false;
                            }
                            if let Err(e) = handle_osc_packet(
                                &buf[..len],
                                src_addr,
                                &device_id_filter,
                                &tx,
                                &band_accumulator,
                                &signal_quality,
                                &battery_level,
                                &config,
                            ).await {
                                log::warn!("[crown_osc] Failed to handle OSC packet: {e}");
                            }
                        }
                        Err(e) => {
                            log::error!("[crown_osc] UDP recv error: {e}");
                        }
                    }
                }
                _ = band_emit_interval.tick() => {
                    // Emit merged bands at ~10Hz
                    let mut acc = band_accumulator.lock().await;
                    if acc.received.iter().any(|&r| r) {
                        let ts = acc.timestamp;
                        let sq = signal_quality.lock().await;
                        
                        for ch in 0..CROWN_ELECTRODE_COUNT {
                            let electrode = ch as i32;
                            let event = MuseEventDto::Bands(BandsDto {
                                electrode,
                                timestamp: ts,
                                delta: acc.delta[ch] as f64,
                                theta: acc.theta[ch] as f64,
                                alpha: acc.alpha[ch] as f64,
                                beta: acc.beta[ch] as f64,
                                gamma: acc.gamma[ch] as f64,
                                line_noise_ratio: sq[ch] as f64,
                            });
                            if tx.send(event).await.is_err() {
                                return; // Channel closed
                            }
                        }
                        // Reset received flags
                        acc.received = [false; 5];
                    }
                }
                _ = telemetry_emit_interval.tick() => {
                    // Emit battery telemetry every 5s
                    let bat = *battery_level.lock().await;
                    if bat > 0.0 {
                        let event = MuseEventDto::Telemetry(TelemetrySnapshot {
                            battery_level: bat,
                            fuel_gauge_voltage: 0.0,
                            temperature: 0,
                        });
                        if tx.send(event).await.is_err() {
                            return;
                        }
                    }
                }
            }
        }
    });

    Ok(CrownOscHandle { stop_tx, task_handle })
}

async fn handle_osc_packet(
    data: &[u8],
    _src_addr: SocketAddr,
    device_id_filter: &str,
    tx: &mpsc::Sender<MuseEventDto>,
    band_accumulator: &Arc<Mutex<BandAccumulator>>,
    signal_quality: &Arc<Mutex<[f32; CROWN_ELECTRODE_COUNT]>>,
    battery_level: &Arc<Mutex<f32>>,
    _config: &DeviceConfig,
) -> Result<()> {
    // rosc::decoder::decode_udp returns (&[u8], OscPacket) - we want the packet
    let (_remaining, packet) = rosc::decoder::decode_udp(data)?;
    
    match packet {
        OscPacket::Message(msg) => {
            handle_osc_message(
                msg,
                device_id_filter,
                tx,
                band_accumulator,
                signal_quality,
                battery_level,
            ).await?;
        }
        OscPacket::Bundle(bundle) => {
            for packet in bundle.content {
                if let OscPacket::Message(msg) = packet {
                    handle_osc_message(
                        msg,
                        device_id_filter,
                        tx,
                        band_accumulator,
                        signal_quality,
                        battery_level,
                    ).await?;
                }
            }
        }
    }
    Ok(())
}

async fn handle_osc_message(
    msg: OscMessage,
    device_id_filter: &str,
    tx: &mpsc::Sender<MuseEventDto>,
    band_accumulator: &Arc<Mutex<BandAccumulator>>,
    signal_quality: &Arc<Mutex<[f32; CROWN_ELECTRODE_COUNT]>>,
    battery_level: &Arc<Mutex<f32>>,
) -> Result<()> {
    let addr = msg.addr.clone(); // Clone to avoid partial move
    
    // Filter by device ID in address (format: /neurosity/notion/{deviceId}/...)
    if !addr.contains(device_id_filter) {
        return Ok(()); // Ignore packets for other devices
    }

    // Parse address pattern
    if addr.ends_with("/raw") {
        handle_raw_eeg(msg, tx).await?;
    } else if addr.ends_with("/brainwaves/delta") {
        handle_band(msg, band_accumulator, 0).await?;
    } else if addr.ends_with("/brainwaves/theta") {
        handle_band(msg, band_accumulator, 1).await?;
    } else if addr.ends_with("/brainwaves/alpha") {
        handle_band(msg, band_accumulator, 2).await?;
    } else if addr.ends_with("/brainwaves/beta") {
        handle_band(msg, band_accumulator, 3).await?;
    } else if addr.ends_with("/brainwaves/gamma") {
        handle_band(msg, band_accumulator, 4).await?;
    } else if addr.ends_with("/signalQuality") {
        handle_signal_quality(msg, signal_quality).await?;
    } else if addr.ends_with("/battery") {
        handle_battery(msg, battery_level).await?;
    } else if addr.ends_with("/focus") {
        if let Some(OscType::Float(f)) = msg.args.first() {
            if features::is_enabled(features::ID_FOCUS) {
                let event = MuseEventDto::Feature(FeatureDto {
                    id: features::ID_FOCUS.to_string(),
                    timestamp: now_ms(),
                    value: *f as f64,
                });
                if tx.send(event).await.is_err() {
                    return Err(anyhow::anyhow!("Channel closed"));
                }
            }
        }
    } else if addr.ends_with("/calm") {
        if let Some(OscType::Float(f)) = msg.args.first() {
            if features::is_enabled(features::ID_CALM) {
                let event = MuseEventDto::Feature(FeatureDto {
                    id: features::ID_CALM.to_string(),
                    timestamp: now_ms(),
                    value: *f as f64,
                });
                if tx.send(event).await.is_err() {
                    return Err(anyhow::anyhow!("Channel closed"));
                }
            }
        }
    } else {
        log::trace!("[crown_osc] Unhandled OSC address: {addr}");
    }
    Ok(())
}

async fn handle_raw_eeg(
    msg: OscMessage,
    tx: &mpsc::Sender<MuseEventDto>,
) -> Result<()> {
    // /neurosity/notion/{deviceId}/raw
    // Args: float32 EEG samples (µV), then timestamp (string?), then package_num (int)
    // Neurosity SDK: "Streams raw 256Hz 8-channel EEG microvolt samples"
    // "Raw EEG = 16-sample binary epochs @ 256Hz" from handoff.
    // Each packet = 1 epoch = 16 samples × 8 channels = 128 float32 values.
    
    let float_args: Vec<f32> = msg.args.iter()
        .filter_map(|arg| match arg {
            OscType::Float(f) => Some(*f),
            OscType::Double(d) => Some(*d as f32),
            _ => None,
        })
        .collect();
    
    if float_args.is_empty() {
        return Ok(());
    }
    
    let ts = now_ms();
    let samples_per_channel = float_args.len() / CROWN_ELECTRODE_COUNT;
    
    if samples_per_channel == 0 || float_args.len() % CROWN_ELECTRODE_COUNT != 0 {
        log::warn!("[crown_osc] Unexpected /raw arg count: {} (expected multiple of 8)", float_args.len());
        return Ok(());
    }
    
    // Emit one EegDto per electrode with its samples
    for ch in 0..CROWN_ELECTRODE_COUNT {
        let electrode = ch as i32;
        let mut samples = Vec::with_capacity(samples_per_channel);
        
        for s in 0..samples_per_channel {
            let idx = ch + s * CROWN_ELECTRODE_COUNT; // Interleaved: ch0_s0, ch1_s0, ch2_s0... ch0_s1, ch1_s1...
            if idx < float_args.len() {
                samples.push(float_args[idx] as f64);
            }
        }
        
        if samples.is_empty() {
            continue;
        }
        
        let event = MuseEventDto::Eeg(EegDto {
            index: 0,
            electrode,
            timestamp: ts,
            samples,
        });
        
        if tx.send(event).await.is_err() {
            return Err(anyhow::anyhow!("Channel closed"));
        }
    }
    
    Ok(())
}

async fn handle_band(
    msg: OscMessage,
    band_accumulator: &Arc<Mutex<BandAccumulator>>,
    band_idx: usize, // 0=delta, 1=theta, 2=alpha, 3=beta, 4=gamma
) -> Result<()> {
    // /neurosity/notion/{deviceId}/brainwaves/{band}
    // Args: 8 float32 values (one per electrode)
    
    let float_args: Vec<f32> = msg.args.iter()
        .filter_map(|arg| match arg {
            OscType::Float(f) => Some(*f),
            OscType::Double(d) => Some(*d as f32),
            _ => None,
        })
        .collect();
    
    if float_args.len() != CROWN_ELECTRODE_COUNT {
        log::warn!("[crown_osc] Unexpected band arg count: {} (expected 8)", float_args.len());
        return Ok(());
    }
    
    let mut acc = band_accumulator.lock().await;
    acc.timestamp = now_ms();
    
    for ch in 0..CROWN_ELECTRODE_COUNT {
        match band_idx {
            0 => acc.delta[ch] = float_args[ch],
            1 => acc.theta[ch] = float_args[ch],
            2 => acc.alpha[ch] = float_args[ch],
            3 => acc.beta[ch] = float_args[ch],
            4 => acc.gamma[ch] = float_args[ch],
            _ => {}
        }
    }
    acc.received[band_idx] = true;
    
    Ok(())
}

async fn handle_signal_quality(
    msg: OscMessage,
    signal_quality: &Arc<Mutex<[f32; CROWN_ELECTRODE_COUNT]>>,
) -> Result<()> {
    // /neurosity/notion/{deviceId}/signalQuality
    // Args: 8 float32 values (0-1 per electrode)
    
    let float_args: Vec<f32> = msg.args.iter()
        .filter_map(|arg| match arg {
            OscType::Float(f) => Some(*f),
            OscType::Double(d) => Some(*d as f32),
            _ => None,
        })
        .collect();
    
    if float_args.len() != CROWN_ELECTRODE_COUNT {
        log::warn!("[crown_osc] Unexpected signalQuality arg count: {}", float_args.len());
        return Ok(());
    }
    
    let mut sq = signal_quality.lock().await;
    for ch in 0..CROWN_ELECTRODE_COUNT {
        sq[ch] = float_args[ch].clamp(0.0, 1.0);
        features::set_crown_quality(ch, sq[ch]);
    }
    
    Ok(())
}

async fn handle_battery(
    msg: OscMessage,
    battery_level: &Arc<Mutex<f32>>,
) -> Result<()> {
    // /neurosity/notion/{deviceId}/battery
    // Args: float32 percentage (0-100)
    
    if let Some(OscType::Float(f)) = msg.args.first() {
        *battery_level.lock().await = f.clamp(0.0, 100.0);
    } else if let Some(OscType::Double(d)) = msg.args.first() {
        *battery_level.lock().await = (*d as f32).clamp(0.0, 100.0);
    }
    Ok(())
}

/// Connect to a Crown/Notion device via OSC.
/// This is called from `connect_with_options` when kind=Neurosity and simulate=false.
#[frb(ignore)]
pub async fn connect_crown_osc(
    device_id: String,
    tx: mpsc::Sender<MuseEventDto>,
) -> anyhow::Result<crate::api::muse::ConnectionStatus> {
    // Start OSC receiver on default port 9000
    let _handle = start_crown_osc_receiver(device_id.clone(), tx, 9000).await?;
    
    // For OSC, we don't have a traditional "connected" event from the device.
    // We'll emit a Connected event immediately and the forwarder will start.
    // The actual data flow begins when OSC packets arrive.
    
    Ok(crate::api::muse::ConnectionStatus {
        connected: true,
        name: format!("Crown ({device_id})"),
        id: device_id,
        firmware: "Crown_OSC".to_string(),
    })
}