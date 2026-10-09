use crate::api::device_config::{DeviceConfig, DeviceKind, QualitySource};
use crate::api::features::{self, FeatureDto};
use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
use muse_rs::prelude::*;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::analysis::eeg_filter::{self, EegConditioner};
use crate::analysis::gesture::GestureDetector;
use crate::analysis::{cbramod, guardrail, reve};
use crate::connection::{state, ActiveConnection, ConnectionHandle};

fn now_ms() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
        * 1000.0
}

// ── Guardrail window helpers ─────────────────────────────────────────────────

/// Max samples kept per electrode in the rolling guardrail window buffer.
/// 5.5 s @ 256 Hz covers a 5 s epoch (1280 samples) with headroom.
const GUARDRAIL_WINDOW: usize = 1408;

/// Frontal and temporal pads of the active device (device config): Muse
/// AF7/AF8 + TP9/TP10, Crown F5/F6 + CP3/CP4.
fn device_pads(kind: DeviceKind) -> ([i32; 2], [i32; 2]) {
    let c = DeviceConfig::for_kind(kind);
    let pair = |v: &[usize]| [v[0] as i32, v[1] as i32];
    (pair(&c.frontal_electrodes), pair(&c.temporal_electrodes))
}

/// App electrode indices in model row order (AF7, AF8, TP9, TP10 rows): the
/// device's frontal pair, then its temporal pair.
fn model_rows(kind: DeviceKind) -> [i32; 4] {
    let (f, t) = device_pads(kind);
    [f[0], f[1], t[0], t[1]]
}

/// AF7/AF8/TP9/TP10 approximate EEG coordinates (mm), used by REVE
/// (`positions_xyz`). CBraMod Spur A ignores positions (channel-order only).
const MODEL_POSITIONS: [f32; 12] = [
    -36.0, 30.0, 90.0, // AF7
    36.0, 30.0, 90.0, // AF8
    -75.0, -18.0, -15.0, // TP9
    75.0, -18.0, -15.0, // TP10
];

/// Window length for [kind]: CBraMod Spur A uses 2 s (512 @ 256 Hz),
/// REVE on 4 s (1024 @ 256 Hz).
fn score_window_len(kind: &str) -> Option<usize> {
    match kind {
        cbramod::KIND_CBRAMOD_A_VIG => Some(cbramod::WINDOW_SAMPLES),
        reve::KIND_REVE_BASE => Some(1024),
        _ => None,
    }
}

/// Build a time-aligned model window from the per-electrode rolling buffers,
/// arranged in model row order ([model_rows]). Returns
/// `(signal, positions, n_channels, n_times)` or None when any of the four
/// electrodes has fewer than [n_times] buffered samples yet.
fn build_score_window(
    bufs: &std::collections::HashMap<i32, Vec<f64>>,
    n_times: usize,
    rows: [i32; 4],
) -> Option<(Vec<f32>, Vec<f32>, usize, usize)> {
    let mut signal = Vec::with_capacity(4 * n_times);
    for app_el in rows {
        let buf = bufs.get(&app_el)?;
        if buf.len() < n_times {
            return None;
        }
        let start = buf.len() - n_times;
        signal.extend(buf[start..].iter().map(|s| *s as f32));
    }
    Some((signal, MODEL_POSITIONS.to_vec(), 4, n_times))
}

/// Average of the most recent delta band powers of the device's frontal
/// pair (Muse AF7/AF8, Crown F5/F6), µV²/Hz. Used as the permanent
/// hard-rail companion to the embedding.
fn frontal_delta_average(deltas: &std::collections::HashMap<i32, f64>, frontal: [i32; 2]) -> f64 {
    let mut sum = 0f64;
    let mut n = 0u32;
    for el in frontal {
        if let Some(d) = deltas.get(&el) {
            sum += d;
            n += 1;
        }
    }
    if n == 0 {
        0.0
    } else {
        sum / n as f64
    }
}

// ── DTOs (serializable across the bridge) ──────────────────────────────────────

/// A Muse device discovered during a scan.
#[frb(dart_metadata = ("freezed",))]
pub struct DeviceInfo {
    pub name: String,
    pub id: String,
    pub kind: DeviceKind,
}

/// Connection / link status reported to the UI.
#[frb(dart_metadata = ("freezed",))]
pub struct ConnectionStatus {
    pub connected: bool,
    pub name: String,
    pub id: String,
    pub firmware: String,
    /// Muse AUX inputs streamed on this connection (electrodes 4.. = AUX1..).
    pub aux_channels: u32,
}

impl Default for ConnectionStatus {
    fn default() -> Self {
        Self {
            connected: false,
            name: String::new(),
            id: String::new(),
            firmware: String::new(),
            aux_channels: 0,
        }
    }
}

/// Muse on-head EEG electrodes (TP9, AF7, AF8, TP10); AUX inputs follow.
pub(crate) const MUSE_HEAD_ELECTRODES: u32 = 4;

/// AUX inputs a real Muse streams on every connect. Classic exposes one
/// AUX characteristic (electrode 4). Athena delivers electrodes 4..7.
/// Devices → Muse Aux channels filters the UI; it does not change this.
pub(crate) fn muse_aux_channels(is_athena: bool) -> u32 {
    if is_athena {
        4
    } else {
        1
    }
}

/// AUX count a simulator reports. Classic is 1, Athena is 4, Crown is 0.
/// The Devices switch shows or hides them; the sim already emits them.
pub(crate) fn simulated_aux_channels(kind: DeviceKind, firmware: &str) -> u32 {
    if !kind.is_muse() {
        return 0;
    }
    muse_aux_channels(firmware == "Athena")
}

/// Telemetry snapshot (battery etc.) surfaced in the status bar.
#[frb(dart_metadata = ("freezed",))]
pub struct TelemetrySnapshot {
    pub battery_level: f32,
    pub fuel_gauge_voltage: f32,
    pub temperature: u16,
}

impl Default for TelemetrySnapshot {
    fn default() -> Self {
        Self {
            battery_level: 0.0,
            fuel_gauge_voltage: 0.0,
            temperature: 0,
        }
    }
}

/// An EEG sample batch for a single electrode channel.
#[frb(dart_metadata = ("freezed",))]
pub struct EegDto {
    pub index: u16,
    pub electrode: i32,
    pub timestamp: f64,
    pub samples: Vec<f64>,
}

/// A PPG (optical) reading for one channel.
#[frb(dart_metadata = ("freezed",))]
pub struct PpgDto {
    pub index: u16,
    pub channel: i32,
    pub timestamp: f64,
    pub samples: Vec<f64>,
}

/// A 3-axis inertial measurement.
#[frb(dart_metadata = ("freezed",))]
pub struct XyzDto {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

/// A batch of inertial measurements.
#[frb(dart_metadata = ("freezed",))]
pub struct ImuDto {
    pub sequence_id: u16,
    pub samples: Vec<XyzDto>,
}

/// A parsed control/status JSON response from the headset.
#[frb(dart_metadata = ("freezed",))]
pub struct ControlDto {
    pub raw: String,
    pub fields: std::collections::HashMap<String, String>,
}

/// Band power estimates for a single electrode.
/// Bands: [delta, theta, alpha, beta, gamma] in µV²/Hz.
///
/// `signal_quality` is the score of this FFT window (0–100). The live dash
/// and the playing-session sampler stamp it. The raw record does not store it.
#[frb(dart_metadata = ("freezed",))]
pub struct BandsDto {
    pub electrode: i32,
    pub timestamp: f64,
    pub delta: f64,
    pub theta: f64,
    pub alpha: f64,
    pub beta: f64,
    pub gamma: f64,
    /// Fraction of total spectral power landing in the 50/60 Hz mains bins.
    /// A high ratio (vs the electrode's rolling baseline) indicates line-noise
    /// / high skin impedance — a per-pad "fit" proxy.
    pub line_noise_ratio: f64,
    /// Score of this FFT window. Not written by `encode_session_event`.
    pub signal_quality: f64,
}

/// Heart-rate pulse estimate from PPG infrared channel.
#[frb(dart_metadata = ("freezed",))]
pub struct PulseDto {
    pub timestamp: f64,
    pub bpm: f64,
    pub confidence: f64,
}

/// Blood oxygen saturation estimate from PPG IR + Red channels.
#[frb(dart_metadata = ("freezed",))]
pub struct SpO2Dto {
    pub timestamp: f64,
    pub spo2: f64,
    pub confidence: f64,
}

/// Movement score derived from accelerometer magnitude variance.
#[frb(dart_metadata = ("freezed",))]
pub struct MovementDto {
    pub timestamp: f64,
    pub score: f64,
}

/// Peak alpha frequency and power (parabolic interpolation over FFT bins).
#[frb(dart_metadata = ("freezed",))]
pub struct PeakAlphaDto {
    pub timestamp: f64,
    pub frequency: f64,
    pub power: f64,
}

/// One second of gesture detection (blink / jaw clench / eye position).
#[frb(dart_metadata = ("freezed",))]
pub struct GestureDto {
    pub timestamp: f64,
    /// Number of blinks detected in the last second.
    pub blink_count: u32,
    /// Jaw-clench muscle activity present in the last second.
    pub clench: bool,
    /// Vertical eye position: 0 = neutral, 1 = up, 2 = down (experimental).
    pub eye: u8,
}

/// Per-second sleep-guardrail score from the loaded foundation model (Sleep-Edge
/// Rest protocol). The full pooled latent stays Rust-side; only the reduced
/// readings cross the bridge.
#[frb(dart_metadata = ("freezed",))]
pub struct ReveDto {
    pub timestamp: f64,
    /// Model kind that produced this score (`cbramod_a_vig` | `reve_base`);
    /// matches `ModelKind.ffId`.
    pub kind: String,
    /// Cosine of the live pooled embedding against the awake `V_clear` anchor
    /// captured during calibration (1.0 = exactly the awake reference).
    pub clarity: f32,
    /// Sleep-direction index: cosine against `V_sleep` once that anchor exists,
    /// otherwise `1 - clarity`. Higher = pointing toward sleep.
    pub sleep_dir: f32,
    /// Classical frontal (AF7/AF8 average) delta band power, µV²/Hz — the
    /// permanent hard rail companion to the embedding.
    pub delta: f64,
    /// Latent embedding dim (informational, from the loaded model).
    pub dim: u32,
}

/// Pad signal quality for one second. The single source for the UI pads
/// and the recording sampler.
///
/// Muse: in-app scores, [source] is [QualitySource::App], [crown] is None.
/// Dart does not record [source] on a Muse computed frame.
/// Neurosity: [source] is the resolved `crown_quality_source`, and [crown]
/// holds the headset's 0..1 means when that source won.
#[frb(dart_metadata = ("freezed",))]
pub struct PadQualityDto {
    /// Per pad, 0–100 (usable >= 80). Index is the electrode.
    pub values: Vec<f64>,
    pub source: QualitySource,
    /// Crown per-pad means (0..1) for this second when [source] is Crown.
    pub crown: Option<Vec<f64>>,
}

/// All events streamed from the headset to the UI.
#[frb(dart_metadata = ("freezed",))]
pub enum MuseEventDto {
    Connected(String),
    Disconnected,
    Eeg(EegDto),
    Bands(BandsDto),
    Ppg(PpgDto),
    Telemetry(TelemetrySnapshot),
    Accelerometer(ImuDto),
    Gyroscope(ImuDto),
    Control(ControlDto),
    Pulse(PulseDto),
    SpO2(SpO2Dto),
    Movement(MovementDto),
    PeakAlpha(PeakAlphaDto),
    Gestures(GestureDto),
    Reve(ReveDto),
    Feature(FeatureDto),
    PadQuality(PadQualityDto),
}

// ── Bridge API ─────────────────────────────────────────────────────────────────

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    #[cfg(target_os = "android")]
    {
        android_logger::init_once(
            android_logger::Config::default()
                .with_max_level(log::LevelFilter::Debug)
                .with_tag("neurofeed"),
        );
        // Ensure the max level takes effect even if android_logger was
        // already initialized (e.g. by flutter_rust_bridge). Without this,
        // jni::trace!() spam floods logcat at verbose priority.
        log::set_max_level(log::LevelFilter::Debug);
    }
    #[cfg(not(target_os = "android"))]
    {
        env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    }
}

/// Called from Kotlin `MainActivity.configureFlutterEngine`/`onCreate` with the
/// JNI environment and Android Context so that btleplug's global Android adapter
/// can be registered. On Android, btleplug requires `btleplug::platform::init(env)`
/// to be called from a JNI context before any BLE scan/connect; otherwise it panics
/// with "Droidplug has not been initialized".
#[cfg(target_os = "android")]
#[no_mangle]
pub extern "C" fn Java_org_windwerfer_neurofeed_MainActivity_museAndroidInit(
    env: *mut jni::sys::JNIEnv,
    _class: *mut jni::sys::jobject,
    _context: *mut jni::sys::jobject,
) {
    let mut env = unsafe { jni::EnvUnowned::from_raw(env) };
    match env
        .with_env(|env| btleplug::platform::init(env))
        .into_outcome()
    {
        jni::Outcome::Ok(()) => log::info!("[muse] btleplug initialized"),
        jni::Outcome::Err(e) => log::error!("[muse] btleplug init failed: {e:?}"),
        jni::Outcome::Panic(_) => log::error!("[muse] btleplug init panicked"),
    }
}

/// Scan for nearby Muse devices for `timeout_secs` seconds and return what was
/// found. Results are **merged** into the existing device cache so that the UI
/// can call `scan` repeatedly in short chunks without losing previously
/// discovered peripherals (which `connect` needs via `MuseDevice`).
pub async fn scan(timeout_secs: Option<u64>) -> anyhow::Result<Vec<DeviceInfo>> {
    let timeout = timeout_secs.unwrap_or(15);
    let client = MuseClient::new(MuseClientConfig {
        scan_timeout_secs: timeout,
        enable_ppg: true,
        ..Default::default()
    });

    let devices = client.scan_all().await.map_err(|e| {
        log::error!("[muse] scan_all failed: {e:?}");
        e
    })?;

    let infos: Vec<DeviceInfo> = devices
        .iter()
        .filter(|d| d.rssi.is_some()) // Only include devices actually advertising (have RSSI)
        .map(|d| DeviceInfo {
            name: d.name.clone(),
            id: d.id.clone(),
            kind: DeviceKind::Muse,
        })
        .collect();

    {
        let mut guard = state().inner.lock().unwrap();
        for d in devices {
            guard.devices.insert(d.id.clone(), d);
        }
    }

    Ok(infos)
}

/// Connect to a previously discovered device by its BLE id and begin streaming.
/// Returns the connection status on success.
///
/// The entire operation is guarded by an overall timeout so the caller never
/// waits more than ≈18 s.  Inside, each BLE step already has its own shorter
/// timeout (10 s connect, 15 s discover services, 8 s startup commands).
pub async fn connect(device_id: String) -> anyhow::Result<ConnectionStatus> {
    // Tear down any existing connection first so the BLE link is released
    // before we attempt a new one.  Without this the device may still think
    // it is connected and reject (or ignore) the new connection attempt.
    {
        let old = state().inner.lock().unwrap().active.take();
        if let Some(old) = old {
            let _ = old.handle.disconnect().await;
        }
    }

    let device = {
        let guard = state().inner.lock().unwrap();
        guard
            .devices
            .get(&device_id)
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("Device {device_id} not found; scan first"))?
    };

    let name = device.name.clone();
    let client = MuseClient::new(MuseClientConfig {
        enable_ppg: true,
        ..Default::default()
    });

    tokio::time::timeout(std::time::Duration::from_secs(18), async {
        let (rx, handle) = client.connect_to(device).await?;
        let firmware = if handle.is_athena {
            "Athena"
        } else {
            "Classic"
        }
        .to_string();

        log::info!("[muse] connected to {name} ({firmware} firmware)");

        // Start streaming via muse-rs's own startup (pause → s → preset →
        // resume). The previous hand-rolled Classic sequence inserted
        // inter-command delays because Android was dropping rapid-fire
        // WriteWithoutResponse; that was actually the JNI notification
        // death spiral (fixed in the btleplug fork), so the delays are
        // unnecessary. enable_ppg = true → Classic preset p50 (5th EEG
        // channel on, and PPG). This path does not subscribe to 273e0007.
        let start_result =
            tokio::time::timeout(std::time::Duration::from_secs(8), handle.start(true, false))
                .await;
        match start_result {
            Ok(Err(e)) => log::warn!("[muse] start commands failed: {e:#}"),
            Err(_) => log::warn!("[muse] start commands timed out after 8 s"),
            _ => {}
        }

        // Request device info once so the control JSON with bp (battery
        // percentage) arrives.  The forwarder extracts bp from Control events
        // and emits a Telemetry event with the correct 0-100 value.
        let _ = handle.send_command("v1").await;

        let (dto_tx, dto_rx) = tokio::sync::mpsc::channel(256);

        let conv_tx = dto_tx.clone();
        tokio::spawn(async move {
            let mut rx = rx;
            while let Some(ev) = rx.recv().await {
                let dto = map_event(ev);
                if conv_tx.send(dto).await.is_err() {
                    break;
                }
            }
        });

        {
            let mut guard = state().inner.lock().unwrap();
            guard.connection_epoch += 1;
            guard.active = Some(ActiveConnection {
                handle: ConnectionHandle::Muse(handle),
                name: name.clone(),
                id: device_id.clone(),
                firmware: firmware.clone(),
                aux_channels: 0,
            });
            guard.events = Some(dto_rx);
            guard.eeg_electrode_limit = Some(MUSE_HEAD_ELECTRODES as i32);
        }
        features::set_active_kind(DeviceKind::Muse);

        spawn_event_forwarder();

        Ok(ConnectionStatus {
            connected: true,
            name,
            id: device_id,
            firmware,
            aux_channels: 0,
        })
    })
    .await
    .map_err(|_| anyhow::anyhow!("connect timed out after 18 s"))?
}

/// Disconnect from the active device, if any.
///
/// Takes the active connection and immediately clears `guard.events` so the
/// event forwarder stops waiting.  Then sends the BLE disconnect command and
/// fires `Disconnected` through the Dart sink directly — the UI updates
/// straight away instead of waiting for the disconnect-watcher event (which
/// can be delayed on some BLE stacks).
pub async fn disconnect() -> anyhow::Result<()> {
    let conn = {
        let mut guard = state().inner.lock().unwrap();
        guard.active.take()
    };
    if let Some(conn) = conn {
        let _ = conn.handle.disconnect().await;
    }
    // Immediately report disconnected to the UI.  We do NOT rely on the
    // disconnect watcher inside muse-rs because its event travels through
    // the channel → forwarder → sink, and that path can be delayed or lost
    // if the forwarder's rx channel closes before the event is consumed.
    {
        let mut guard = state().inner.lock().unwrap();
        guard.events = None;
        if let Some(sink) = &guard.sink {
            let _ = sink.add(MuseEventDto::Disconnected);
        }
    }
    features::clear_active_kind();
    Ok(())
}

/// Current connection status (used on app launch to restore UI state).
pub fn get_status() -> ConnectionStatus {
    let guard = state().inner.lock().unwrap();
    match &guard.active {
        Some(conn) => ConnectionStatus {
            connected: true,
            name: conn.name.clone(),
            id: conn.id.clone(),
            firmware: conn.firmware.clone(),
            aux_channels: conn.aux_channels,
        },
        None => ConnectionStatus::default(),
    }
}

/// Connect to a device with explicit kind and simulation flag.
/// - `kind`: DeviceKind::Muse (BLE id from `scan`) or DeviceKind::Neurosity
///   (Crown device id from `discovered_crowns`, streamed over OSC on the LAN)
/// - `simulate`: if true, runs the built-in simulator instead of a headset
/// - `record_aux`: ignored. A real Muse always streams AUX (Classic `p50`
///   plus the RIGHTAUX subscribe, Athena `p1045` electrodes 4..7). The
///   Devices setting filters the status bar and monitors. Record AUX
///   filters the file.
/// - `quality_source`: Neurosity only — pad quality from the Crown or the app.
#[frb]
pub async fn connect_with_options(
    device_id: String,
    kind: DeviceKind,
    simulate: bool,
    record_aux: bool,
    quality_source: QualitySource,
) -> anyhow::Result<ConnectionStatus> {
    features::set_quality_source(quality_source);
    {
        let old = state().inner.lock().unwrap().active.take();
        if let Some(old) = old {
            let _ = old.handle.disconnect().await;
        }
    }

    if simulate {
        let (name, firmware) = crate::api::simulator::simulated_identity(&device_id, kind);
        let aux_channels = simulated_aux_channels(kind, &firmware);
        let mut config = crate::api::device_config::DeviceConfig::for_kind(kind);
        if kind.is_muse() {
            config.channel_count = (MUSE_HEAD_ELECTRODES + aux_channels) as usize;
        }
        let (dto_tx, dto_rx) = tokio::sync::mpsc::channel(1024);
        let simulator = crate::api::simulator::spawn_simulator(config, dto_tx);
        log::info!("[muse] simulator started for {name} ({device_id}, aux={aux_channels})");

        {
            let mut guard = state().inner.lock().unwrap();
            guard.connection_epoch += 1;
            guard.active = Some(ActiveConnection {
                handle: ConnectionHandle::Simulator(simulator),
                name: name.clone(),
                id: device_id.clone(),
                firmware: firmware.clone(),
                aux_channels,
            });
            guard.events = Some(dto_rx);
            guard.eeg_electrode_limit = if kind.is_muse() {
                Some((MUSE_HEAD_ELECTRODES + aux_channels) as i32)
            } else {
                None
            };
        }
        features::set_active_kind(kind);

        spawn_event_forwarder();

        return Ok(ConnectionStatus {
            connected: true,
            name,
            id: device_id,
            firmware,
            aux_channels,
        });
    }

    if kind.is_neurosity() {
        let (dto_tx, dto_rx) = tokio::sync::mpsc::channel(256);
        let (handle, status) =
            crate::api::neurosity_osc::connect_crown_osc(device_id.clone(), dto_tx).await?;

        {
            let mut guard = state().inner.lock().unwrap();
            guard.connection_epoch += 1;
            guard.active = Some(ActiveConnection {
                handle: ConnectionHandle::Crown(handle),
                name: status.name.clone(),
                id: device_id.clone(),
                firmware: status.firmware.clone(),
                aux_channels: 0,
            });
            guard.events = Some(dto_rx);
            guard.eeg_electrode_limit = None;
        }
        features::set_active_kind(kind);

        spawn_event_forwarder();

        return Ok(status);
    }

    let device = {
        let guard = state().inner.lock().unwrap();
        guard
            .devices
            .get(&device_id)
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("Device {device_id} not found; scan first"))?
    };

    let name = device.name.clone();
    let _ = record_aux;
    let client = MuseClient::new(MuseClientConfig {
        enable_ppg: true,
        enable_aux: true,
        ..Default::default()
    });

    tokio::time::timeout(std::time::Duration::from_secs(18), async {
        let (rx, handle) = client.connect_to(device).await?;
        let firmware = if handle.is_athena {
            "Athena"
        } else {
            "Classic"
        }
        .to_string();
        let aux_channels = muse_aux_channels(handle.is_athena);

        log::info!("[muse] connected to {name} ({firmware} firmware, aux={aux_channels})");

        let start_result =
            tokio::time::timeout(std::time::Duration::from_secs(8), handle.start(true, true)).await;
        match start_result {
            Ok(Err(e)) => log::warn!("[muse] start commands failed: {e:#}"),
            Err(_) => log::warn!("[muse] start commands timed out after 8 s"),
            _ => {}
        }

        let _ = handle.send_command("v1").await;

        let (dto_tx, dto_rx) = tokio::sync::mpsc::channel(256);

        let conv_tx = dto_tx.clone();
        tokio::spawn(async move {
            let mut rx = rx;
            while let Some(ev) = rx.recv().await {
                let dto = map_event(ev);
                if conv_tx.send(dto).await.is_err() {
                    break;
                }
            }
        });

        {
            let mut guard = state().inner.lock().unwrap();
            guard.connection_epoch += 1;
            guard.active = Some(ActiveConnection {
                handle: ConnectionHandle::Muse(handle),
                name: name.clone(),
                id: device_id.clone(),
                firmware: firmware.clone(),
                aux_channels,
            });
            guard.events = Some(dto_rx);
            guard.eeg_electrode_limit = Some((MUSE_HEAD_ELECTRODES + aux_channels) as i32);
        }
        features::set_active_kind(kind);

        spawn_event_forwarder();

        Ok(ConnectionStatus {
            connected: true,
            name,
            id: device_id,
            firmware,
            aux_channels,
        })
    })
    .await
    .map_err(|_| anyhow::anyhow!("connect timed out after 18 s"))?
}

/// Returns `true` if a connection is currently active. The Rust side clears
/// this as soon as muse-rs reports a disconnect, so it tracks the real link
/// state closely enough for the UI.
pub fn is_connected() -> bool {
    state().inner.lock().unwrap().active.is_some()
}

/// Subscribe to the live event stream from the connected headset.
///
/// Call this once at startup. It returns a Dart `Stream<MuseEventDto>` that
/// receives every event emitted by muse-rs for the active (or future)
/// connection. The Rust side forwards events into the provided `StreamSink`.
pub fn subscribe_events(sink: StreamSink<MuseEventDto>) {
    let mut guard = state().inner.lock().unwrap();
    guard.sink = Some(sink);
}

/// Guard that ensures forwarder state is cleaned up when the task exits,
/// whether normally or via panic. Drop runs even during stack unwinding.
struct ForwarderGuard {
    epoch: u64,
}

impl Drop for ForwarderGuard {
    fn drop(&mut self) {
        let panicking = std::thread::panicking();
        {
            let mut guard = state().inner.lock().unwrap_or_else(|e| e.into_inner());
            if guard.connection_epoch == self.epoch {
                guard.active = None;
                guard.events = None;
                if let Some(sink) = &guard.sink {
                    let _ = sink.add(MuseEventDto::Disconnected);
                }
                features::clear_active_kind();
            }
            guard.forwarder_running = false;
        }
        if panicking {
            log::error!("[muse] forwarder panicked (epoch={})", self.epoch);
        } else {
            log::info!("[muse] forwarder exited (epoch={})", self.epoch);
        }
    }
}

fn spawn_event_forwarder() {
    let epoch = {
        let mut guard = state().inner.lock().unwrap_or_else(|e| e.into_inner());
        if guard.forwarder_running {
            return;
        }
        guard.forwarder_running = true;
        guard.connection_epoch
    };
    log::info!("[muse] forwarder started (epoch={epoch})");
    tokio::spawn(async move {
        let _guard = ForwarderGuard { epoch };
        #[derive(Default)]
        struct PktCounts {
            eeg: u64,
            bands: u64,
            ppg: u64,
            telemetry: u64,
            accelerometer: u64,
            gyroscope: u64,
            control: u64,
            connected: u64,
            other: u64,
        }
        let mut counts = PktCounts::default();
        let mut last_print = tokio::time::Instant::now();
        let mut accums: std::collections::HashMap<i32, Vec<f64>> = std::collections::HashMap::new();
        let mut bp_override: Option<f32> = None;

        // PPG and accelerometer buffers for derived metrics
        let mut ppg_ir_buffer: Vec<f64> = Vec::new();
        let mut ppg_red_buffer: Vec<f64> = Vec::new();
        let mut accel_mag_buffer: Vec<f64> = Vec::new();
        let mut last_metrics = tokio::time::Instant::now();
        let mut last_optical = tokio::time::Instant::now();

        // Guardrail (Sleep-Edge Rest): rolling per-electrode EEG window + the
        // most recent frontal delta, fed to the loaded foundation model once/second.
        let mut window_bufs: std::collections::HashMap<i32, Vec<f64>> =
            std::collections::HashMap::new();
        let mut frontal_delta: std::collections::HashMap<i32, f64> =
            std::collections::HashMap::new();
        let mut last_guardrail_attempt = tokio::time::Instant::now();

        // Blink / clench / eye-position detector: conditioned EEG for blinks,
        // RAW for the slow eye level, plus gamma.
        let mut gesture = GestureDetector::default();

        // Per-electrode virtual timestamp tracking for Athena firmware.
        // muse-rs emits timestamp=0.0 for Athena packets because they lack
        // per-channel sequence indices.  We synthesise wall-clock timestamps
        // by anchoring to the first packet arrival and advancing at 256 Hz.
        let mut eeg_ts_base: std::collections::HashMap<i32, f64> = std::collections::HashMap::new(); // ms epoch
        let mut eeg_ts_count: std::collections::HashMap<i32, u64> =
            std::collections::HashMap::new(); // total samples

        let mut quality_rings: std::collections::HashMap<i32, features::EegRing> =
            std::collections::HashMap::new();
        let mut latest_bands: std::collections::HashMap<i32, features::ChannelBands> =
            std::collections::HashMap::new();

        // EEG conditioning (per connection, every device). RAW is recorded
        // as received; quality, bands, features, gestures and the UI get
        // the conditioned signal.
        let mut conditioner: EegConditioner;
        let mut published_mains: eeg_filter::Mains;
        let mut pads_kind: Option<DeviceKind> = None;

        const FFT_N: usize = 256;
        loop {
            let (rx, eeg_limit) = {
                let mut guard = state().inner.lock().unwrap_or_else(|e| e.into_inner());
                (guard.events.take(), guard.eeg_electrode_limit)
            };
            let Some(mut rx) = rx else {
                tokio::time::sleep(std::time::Duration::from_millis(200)).await;
                continue;
            };
            quality_rings.clear();
            latest_bands.clear();
            conditioner = EegConditioner::new(eeg_filter::NotchMode::Live);
            published_mains = eeg_filter::Mains::Unknown;
            eeg_filter::publish_live_mains(published_mains);
            // Poll the event channel once a second. This serves two purposes:
            // 1. A reconnect stores a fresh channel in `events`; pick it up
            //    here instead of draining a stale one forever.
            // 2. A connected Muse streams continuously. If we see no events
            //    for this many consecutive windows, the BLE link is dead
            //    without a proper disconnect notification — report it so the
            //    app can reconnect instead of silently sitting on a dead link.
            const RECV_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(1);
            const SILENT_WINDOWS: u32 = 30;
            let mut silent_windows = 0u32;
            loop {
                let ev = match tokio::time::timeout(RECV_TIMEOUT, rx.recv()).await {
                    Ok(Some(ev)) => {
                        silent_windows = 0;
                        ev
                    }
                    Ok(None) => {
                        log::info!("[muse] forwarder: event channel closed (epoch={epoch})");
                        break;
                    }
                    Err(_) => {
                        let newer_channel = {
                            let guard = state().inner.lock().unwrap_or_else(|e| e.into_inner());
                            guard.events.is_some()
                        };
                        if newer_channel {
                            log::info!(
                                "[muse] forwarder: newer connection (epoch={epoch}), switching channels"
                            );
                            break;
                        }
                        silent_windows += 1;
                        if silent_windows >= SILENT_WINDOWS {
                            log::error!(
                                "[muse] forwarder: no events for {} s (epoch={epoch}), link assumed dead",
                                SILENT_WINDOWS as u64 * RECV_TIMEOUT.as_secs()
                            );
                            let guard = state().inner.lock().unwrap_or_else(|e| e.into_inner());
                            if let Some(sink) = &guard.sink {
                                let _ = sink.add(MuseEventDto::Disconnected);
                            }
                            break;
                        }
                        if silent_windows % 5 == 0 {
                            log::info!(
                                "[muse] forwarder: alive (epoch={epoch}, no events for 5s, eeg={} telem={} accel={} gyro={})",
                                counts.eeg, counts.telemetry,
                                counts.accelerometer, counts.gyroscope,
                            );
                            counts = PktCounts::default();
                            last_print = tokio::time::Instant::now();
                        }
                        continue;
                    }
                };
                match &ev {
                    MuseEventDto::Eeg(_) => counts.eeg += 1,
                    MuseEventDto::Ppg(_) => counts.ppg += 1,
                    MuseEventDto::Telemetry(_) => counts.telemetry += 1,
                    MuseEventDto::Accelerometer(_) => counts.accelerometer += 1,
                    MuseEventDto::Gyroscope(_) => counts.gyroscope += 1,
                    MuseEventDto::Control(_) => counts.control += 1,
                    MuseEventDto::Connected(_) => counts.connected += 1,
                    _ => counts.other += 1,
                }
                if last_print.elapsed() >= std::time::Duration::from_secs(1) {
                    log::info!(
                        "[muse] pkt/s: eeg={} bands={} ppg={} telem={} accel={} gyro={} ctrl={} conn={} other={}",
                        counts.eeg, counts.bands, counts.ppg, counts.telemetry,
                        counts.accelerometer, counts.gyroscope, counts.control,
                        counts.connected, counts.other,
                    );
                    counts = PktCounts::default();
                    last_print = tokio::time::Instant::now();
                }
                let mut dto = ev;
                match &dto {
                    MuseEventDto::Bands(_) => continue,
                    MuseEventDto::Eeg(e) if eeg_limit.is_some_and(|l| e.electrode >= l) => continue,
                    _ => {}
                }
                // Patch Athena EEG timestamps (0.0) with virtual wall-clock
                // timestamps derived from total sample count @ 256 Hz.
                if let MuseEventDto::Eeg(ref mut e) = dto {
                    if e.timestamp == 0.0 {
                        let count = eeg_ts_count.entry(e.electrode).or_insert(0);
                        let base = eeg_ts_base.entry(e.electrode).or_insert_with(now_ms);
                        e.timestamp = *base + (*count as f64) * 1000.0 / 256.0;
                        *count += e.samples.len() as u64;
                    } else {
                        // Non-zero (Classic): keep tracker aligned so that
                        // switching between Classic/Athena is seamless.
                        eeg_ts_count.insert(e.electrode, 0);
                        eeg_ts_base.insert(e.electrode, e.timestamp);
                    }
                }
                if let MuseEventDto::Control(ref c) = dto {
                    if let Some(bp) = c.fields.get("bp").and_then(|s| s.parse::<f32>().ok()) {
                        bp_override = Some(bp);
                    }
                }
                if let MuseEventDto::Telemetry(ref mut t) = dto {
                    if let Some(bp) = bp_override {
                        t.battery_level = bp;
                    }
                }

                // Extract PPG IR (channel 1) and Red (channel 2) samples for pulse / SpO2
                if let MuseEventDto::Ppg(ref ppg) = dto {
                    match ppg.channel {
                        1 => {
                            ppg_ir_buffer.extend(ppg.samples.iter().copied());
                            if ppg_ir_buffer.len() > 1920 {
                                let drain_to = ppg_ir_buffer.len() - 1920;
                                ppg_ir_buffer.drain(..drain_to);
                            }
                        }
                        2 => {
                            ppg_red_buffer.extend(ppg.samples.iter().copied());
                            if ppg_red_buffer.len() > 1920 {
                                let drain_to = ppg_red_buffer.len() - 1920;
                                ppg_red_buffer.drain(..drain_to);
                            }
                        }
                        _ => {}
                    }
                }

                // Extract accelerometer magnitude for movement score
                if let MuseEventDto::Accelerometer(ref imu) = dto {
                    for s in &imu.samples {
                        let mag = ((s.x * s.x + s.y * s.y + s.z * s.z) as f64).sqrt();
                        accel_mag_buffer.push(mag);
                    }
                    if accel_mag_buffer.len() > 1040 {
                        let drain_to = accel_mag_buffer.len() - 1040;
                        accel_mag_buffer.drain(..drain_to);
                    }
                }

                // Pulse and SpO2 follow the optical packets. EEG pad quality is
                // not an input, and this tick does not wait for an EEG packet.
                if last_optical.elapsed() >= std::time::Duration::from_secs(1) {
                    last_optical = tokio::time::Instant::now();
                    let now_ms = now_ms();
                    let (bpm, confidence) = compute_pulse(&ppg_ir_buffer);
                    if bpm > 0.0 {
                        let dto = MuseEventDto::Pulse(PulseDto {
                            timestamp: now_ms,
                            bpm,
                            confidence,
                        });
                        crate::spine::capture::on_dto(&dto);
                        let mut guard = state().inner.lock().unwrap_or_else(|e| e.into_inner());
                        if let Some(sink) = &guard.sink {
                            if sink.add(dto).is_err() {
                                guard.sink = None;
                            }
                        }
                    }
                    let (spo2, spo2_conf) = compute_spo2(&ppg_ir_buffer, &ppg_red_buffer);
                    if spo2 > 0.0 {
                        let dto = MuseEventDto::SpO2(SpO2Dto {
                            timestamp: now_ms,
                            spo2,
                            confidence: spo2_conf,
                        });
                        crate::spine::capture::on_dto(&dto);
                        let mut guard = state().inner.lock().unwrap_or_else(|e| e.into_inner());
                        if let Some(sink) = &guard.sink {
                            if sink.add(dto).is_err() {
                                guard.sink = None;
                            }
                        }
                    }
                }

                // Capture records `dto` (RAW as received); analysis and the UI
                // use the conditioned samples.
                let (eeg_samples, outgoing) = match &dto {
                    MuseEventDto::Eeg(e) => {
                        let (samples, events) = condition_eeg_packet(&mut conditioner, e);
                        (Some((e.electrode, e.timestamp, samples)), Some(events))
                    }
                    _ => (None, None),
                };
                if conditioner.mains() != published_mains {
                    published_mains = conditioner.mains();
                    eeg_filter::publish_live_mains(published_mains);
                }
                let kind = features::active_kind().unwrap_or(DeviceKind::Muse);
                if pads_kind != Some(kind) {
                    pads_kind = Some(kind);
                    let (frontal, temporal) = device_pads(kind);
                    gesture.set_electrodes(frontal, temporal);
                }
                if let (Some((electrode, _, samples)), MuseEventDto::Eeg(e)) = (&eeg_samples, &dto)
                {
                    quality_rings.entry(*electrode).or_default().extend(samples);
                    gesture.feed_eeg(*electrode, samples, &e.samples);
                }
                crate::spine::capture::on_dto(&dto);
                let outgoing = outgoing.unwrap_or_else(|| vec![dto]);
                let should_stop = {
                    let mut guard = state().inner.lock().unwrap_or_else(|e| e.into_inner());
                    let mut failed = false;
                    if let Some(sink) = guard.sink.as_ref() {
                        for ev in outgoing {
                            if sink.add(ev).is_err() {
                                failed = true;
                                break;
                            }
                        }
                    }
                    if failed {
                        guard.sink = None;
                    }
                    failed
                };
                if should_stop {
                    break;
                }
                if let Some((electrode, timestamp, samples)) = eeg_samples {
                    // Keep the rolling guardrail window (all electrodes, capped
                    // at ~5.5 s) fed from the same conditioned EEG.
                    {
                        let buf = window_bufs.entry(electrode).or_default();
                        buf.extend_from_slice(&samples);
                        if buf.len() > GUARDRAIL_WINDOW {
                            let drain_to = buf.len() - GUARDRAIL_WINDOW;
                            buf.drain(..drain_to);
                        }
                    }
                    let trimmed = {
                        let buf = accums.entry(electrode).or_default();
                        for s in &samples {
                            buf.push(*s);
                        }
                        if buf.len() >= FFT_N {
                            Some(buf.drain(..FFT_N).collect::<Vec<f64>>())
                        } else {
                            None
                        }
                    };
                    if let Some(trimmed) = trimmed {
                        let window_std = features::sample_std(&trimmed);
                        let result =
                            match tokio::task::spawn_blocking(move || compute_fft_bands(&trimmed))
                                .await
                            {
                                Ok(r) => r,
                                Err(e) => {
                                    log::error!("[muse] FFT blocking task panicked: {e}");
                                    continue;
                                }
                            };
                        // result: [delta, theta, alpha, beta, gamma, peak_alpha_freq, peak_alpha_power, line_noise_ratio]
                        counts.bands += 1;
                        gesture.feed_gamma(electrode, result[4]);
                        frontal_delta.insert(electrode, result[0]);
                        latest_bands.insert(
                            electrode,
                            features::ChannelBands {
                                delta: result[0],
                                theta: result[1],
                                alpha: result[2],
                                beta: result[3],
                                gamma: result[4],
                                line_noise_ratio: result[7],
                            },
                        );
                        let bands_dto = MuseEventDto::Bands(BandsDto {
                            electrode,
                            timestamp,
                            delta: result[0],
                            theta: result[1],
                            alpha: result[2],
                            beta: result[3],
                            gamma: result[4],
                            line_noise_ratio: result[7],
                            signal_quality: features::score_band_window(
                                kind, electrode, window_std, result[7],
                            ),
                        });
                        crate::spine::capture::on_dto(&bands_dto);
                        let peak_dto = if result[5] > 0.0 {
                            let dto = MuseEventDto::PeakAlpha(PeakAlphaDto {
                                timestamp,
                                frequency: result[5],
                                power: result[6],
                            });
                            crate::spine::capture::on_dto(&dto);
                            Some(dto)
                        } else {
                            None
                        };
                        let should_stop = {
                            let mut guard = state().inner.lock().unwrap_or_else(|e| e.into_inner());
                            let sink_ok = match guard.sink.as_ref() {
                                Some(sink) => sink.add(bands_dto).is_ok(),
                                None => false,
                            };
                            if !sink_ok {
                                guard.sink = None;
                                true
                            } else {
                                if let Some(dto) = peak_dto {
                                    let _ = guard.sink.as_ref().map(|s| s.add(dto));
                                }
                                false
                            }
                        };
                        if should_stop {
                            break;
                        }
                    }

                    // Emit 1 Hz derived metrics (pulse, movement)
                    if last_metrics.elapsed() >= std::time::Duration::from_secs(1) {
                        let now_ms = now_ms();
                        last_metrics = tokio::time::Instant::now();
                        emit_pad_quality(&latest_bands, &quality_rings, eeg_limit);
                        emit_enabled_band_features(now_ms, &latest_bands, &quality_rings);

                        let movement_score = compute_movement(&accel_mag_buffer);
                        {
                            let dto = MuseEventDto::Movement(MovementDto {
                                timestamp: now_ms,
                                score: movement_score,
                            });
                            crate::spine::capture::on_dto(&dto);
                            let mut guard = state().inner.lock().unwrap_or_else(|e| e.into_inner());
                            if let Some(sink) = &guard.sink {
                                if sink.add(dto).is_err() {
                                    guard.sink = None;
                                }
                            }
                        }

                        let g = gesture.tick(now_ms);
                        {
                            let mut guard = state().inner.lock().unwrap_or_else(|e| e.into_inner());
                            if let Some(sink) = &guard.sink {
                                if sink
                                    .add(MuseEventDto::Gestures(GestureDto {
                                        timestamp: now_ms,
                                        blink_count: g.blink_count,
                                        clench: g.clench,
                                        eye: g.eye,
                                    }))
                                    .is_err()
                                {
                                    guard.sink = None;
                                }
                            }
                        }

                        // CBraMod/REVE sleep-guardrail scoring. Runs once per second
                        // while enabled, on a blocking thread so a slow inference
                        // never stalls the event loop. Ticks during an in-flight
                        // run are coalesced away.
                        if last_guardrail_attempt.elapsed() >= std::time::Duration::from_secs(1)
                            && guardrail::is_enabled()
                            && guardrail::try_begin_score()
                        {
                            last_guardrail_attempt = tokio::time::Instant::now();
                            let kind = match guardrail::active_kind() {
                                Some(k) => k,
                                None => {
                                    guardrail::finish_score();
                                    continue;
                                }
                            };
                            let Some(n_times) = score_window_len(&kind) else {
                                guardrail::finish_score();
                                continue;
                            };
                            let device = features::active_kind().unwrap_or(DeviceKind::Muse);
                            let window =
                                build_score_window(&window_bufs, n_times, model_rows(device));
                            let Some((signal, positions, n_channels, n_times)) = window else {
                                // Not enough buffered samples yet — first window
                                // lands after ~5 s of streaming.
                                guardrail::finish_score();
                                continue;
                            };
                            let ts = now_ms;
                            let delta =
                                frontal_delta_average(&frontal_delta, device_pads(device).0);
                            tokio::spawn(async move {
                                let infer_kind = kind.clone();
                                let embedding = tokio::task::spawn_blocking(move || {
                                    if infer_kind == reve::KIND_REVE_BASE {
                                        reve::score_window(signal, positions, n_channels, n_times)
                                    } else if infer_kind == cbramod::KIND_CBRAMOD_A_VIG {
                                        cbramod::score_window(
                                            signal, positions, n_channels, n_times,
                                        )
                                    } else {
                                        Err(anyhow::anyhow!("unknown guardrail kind: {infer_kind}"))
                                    }
                                })
                                .await;
                                let embedding = match embedding {
                                    Ok(Ok(v)) => v,
                                    Ok(Err(e)) => {
                                        log::warn!("[guardrail] inference failed: {e}");
                                        guardrail::finish_score();
                                        return;
                                    }
                                    Err(e) => {
                                        log::warn!("[guardrail] inference task panicked: {e}");
                                        guardrail::finish_score();
                                        return;
                                    }
                                };
                                guardrail::set_live_embedding(kind.clone(), embedding.clone());
                                let dim = guardrail::live_dim();
                                // Emit per-feature-ID head scores when packs are loaded for this
                                // embedding dim (CBraMod 200-d / REVE 512-d). Encoder gaps still
                                // fail earlier in score_window; head-linear path runs when emb exists.
                                // Emit FeatureDto only for heads whose pack matches this
                                // embedding dim (CBraMod 200-d / REVE 512-d). Value is
                                // P(class 1) — P(hypnagogic) or P(light) — not argmax.
                                let head_scores =
                                    crate::analysis::ai_heads::score_matching_heads(&embedding);
                                {
                                    let mut guard =
                                        state().inner.lock().unwrap_or_else(|e| e.into_inner());
                                    let mut kill_sink = false;
                                    if let Some(sink) = guard.sink.as_ref() {
                                        for (fid, score) in &head_scores {
                                            let enabled = features::is_enabled(fid)
                                                || (*fid == features::ID_A_VIG
                                                    && features::is_enabled(
                                                        features::ID_DROWSINESS,
                                                    ));
                                            if !enabled {
                                                continue;
                                            }
                                            if sink
                                                .add(MuseEventDto::Feature(FeatureDto {
                                                    id: fid.clone(),
                                                    timestamp: ts,
                                                    value: *score as f64,
                                                }))
                                                .is_err()
                                            {
                                                kill_sink = true;
                                                break;
                                            }
                                            // Protocol alias: same CBraMod A-vig scalar.
                                            if *fid == features::ID_A_VIG
                                                && features::is_enabled(features::ID_DROWSINESS)
                                                && sink
                                                    .add(MuseEventDto::Feature(FeatureDto {
                                                        id: features::ID_DROWSINESS.to_string(),
                                                        timestamp: ts,
                                                        value: *score as f64,
                                                    }))
                                                    .is_err()
                                            {
                                                kill_sink = true;
                                                break;
                                            }
                                        }
                                    }
                                    if kill_sink {
                                        guard.sink = None;
                                    }
                                }

                                if let Some((clarity, sd)) = guardrail::clarity_and_sleep_dir() {
                                    let sleep_dir = sd.unwrap_or(1.0 - clarity);
                                    let dto = MuseEventDto::Reve(ReveDto {
                                        timestamp: ts,
                                        kind,
                                        clarity,
                                        sleep_dir,
                                        delta,
                                        dim,
                                    });
                                    let mut guard =
                                        state().inner.lock().unwrap_or_else(|e| e.into_inner());
                                    let mut kill_sink = false;
                                    if let Some(sink) = &guard.sink {
                                        // FeatureDto for AI IDs comes only from that ID's own
                                        // pack/encoder head (score_matching_heads above). Never
                                        // map REVE cosine sleep_dir onto ai.a_vig / aliases.
                                        if sink.add(dto).is_err() {
                                            kill_sink = true;
                                        }
                                    }
                                    if kill_sink {
                                        guard.sink = None;
                                    }
                                }
                                guardrail::finish_score();
                            });
                        }
                    }
                }
            }
        }
    });
}

/// One RAW EEG packet through the conditioner: the conditioned samples for
/// quality / bands / features / gestures, and the conditioned EEG events
/// for the UI (none while a segment's first samples are held).
fn condition_eeg_packet(
    conditioner: &mut EegConditioner,
    e: &EegDto,
) -> (Vec<f64>, Vec<MuseEventDto>) {
    let chunks = conditioner.process(e.electrode, e.timestamp, &e.samples);
    let samples = chunks.iter().flat_map(|(_, s)| s.iter().copied()).collect();
    let events = chunks
        .into_iter()
        .map(|(timestamp, samples)| {
            MuseEventDto::Eeg(EegDto {
                index: e.index,
                electrode: e.electrode,
                timestamp,
                samples,
            })
        })
        .collect();
    (samples, events)
}

/// Radix-2 FFT of `samples` (length a power of two) into thread-local
/// scratch buffers; `f` sees the real and imaginary parts.
fn with_spectrum<R>(samples: &[f64], f: impl FnOnce(&[f64], &[f64]) -> R) -> R {
    let n = samples.len();
    // Reuse scratch buffers across calls via a small thread-local pool to
    // avoid repeated allocations.  Each electrode does one FFT per second,
    // and one blocking task runs at a time, so 2 buffers × n is enough.
    thread_local! {
        static RE: std::cell::RefCell<Vec<f64>> = const { std::cell::RefCell::new(Vec::new()) };
        static IM: std::cell::RefCell<Vec<f64>> = const { std::cell::RefCell::new(Vec::new()) };
    }

    RE.with(|re_buf| {
        IM.with(|im_buf| {
            let mut re = re_buf.borrow_mut();
            let mut im = im_buf.borrow_mut();
            re.resize(n, 0.0);
            im.resize(n, 0.0);

            // Cooley–Tukey radix-2 DIT FFT, in-place, O(n log n).
            // n = 256 (power of two) guaranteed by the caller.
            re.copy_from_slice(samples);
            im.fill(0.0);
            let mut j = 0;
            for i in 1..n {
                let mut bit = n >> 1;
                while j & bit != 0 {
                    j ^= bit;
                    bit >>= 1;
                }
                j ^= bit;
                if i < j {
                    re.swap(i, j);
                    im.swap(i, j);
                }
            }
            let mut len = 2;
            while len <= n {
                let angle = -2.0 * std::f64::consts::PI / len as f64;
                let wlen_re = angle.cos();
                let wlen_im = angle.sin();
                for i in (0..n).step_by(len) {
                    let half = len / 2;
                    let mut w_re = 1.0;
                    let mut w_im = 0.0;
                    for j in 0..half {
                        let k = i + j;
                        let u_re = re[k];
                        let u_im = im[k];
                        let v_re = w_re * re[k + half] - w_im * im[k + half];
                        let v_im = w_re * im[k + half] + w_im * re[k + half];
                        re[k] = u_re + v_re;
                        im[k] = u_im + v_im;
                        re[k + half] = u_re - v_re;
                        im[k + half] = u_im - v_im;
                        let t_re = w_re * wlen_re - w_im * wlen_im;
                        let t_im = w_re * wlen_im + w_im * wlen_re;
                        w_re = t_re;
                        w_im = t_im;
                    }
                }
                len <<= 1;
            }
            f(&re, &im)
        })
    })
}

/// Power in the mains bin for `hz`, summed over a ±1 bin window to tolerate
/// slight mains drift. hz_per_bin = 1.0 at FFT_N=256 @ 256 Hz, so the mains
/// spike lands directly on bins 50/60.
fn mains_bin_power(re: &[f64], im: &[f64], hz: f64) -> f64 {
    let n = re.len();
    let half_n = n / 2;
    let k = (hz / (256.0 / n as f64)).round() as usize;
    let lo = k.saturating_sub(1).max(1);
    let hi = (k + 1).min(half_n);
    (lo..=hi).map(|kk| re[kk] * re[kk] + im[kk] * im[kk]).sum()
}

/// How far the 50 Hz and 60 Hz mains peaks stand out in one 256 Hz window:
/// mean power of each mains window (±1 bin, as in the line-noise ratio) over
/// the median bin power within ±8 Hz, excluding bins within 2 Hz of either
/// mains frequency. Infinite when a peak sits on a zero floor.
pub(crate) fn mains_peak_ratios(samples: &[f64]) -> (f64, f64) {
    if samples.len() != 256 {
        return (0.0, 0.0);
    }
    with_spectrum(samples, |re, im| {
        let power = |k: usize| re[k] * re[k] + im[k] * im[k];
        let ratio = |hz: f64| {
            let k = hz as usize;
            let mut floor: Vec<f64> = (k - 8..=k + 8)
                .filter(|&b| (b as f64 - 50.0).abs() > 2.0 && (b as f64 - 60.0).abs() > 2.0)
                .map(power)
                .collect();
            floor.sort_by(f64::total_cmp);
            let median = floor[floor.len() / 2];
            let peak = mains_bin_power(re, im, hz) / 3.0;
            if median > 0.0 {
                peak / median
            } else if peak > 0.0 {
                f64::INFINITY
            } else {
                0.0
            }
        };
        (ratio(50.0), ratio(60.0))
    })
}

/// EEG bands `[lo, hi)` in Hz: delta, theta, alpha, beta, gamma. Every 1 Hz
/// bin belongs to exactly one band; gamma stops below the mains notch.
pub(crate) const BANDS_HZ: [(f64, f64); 5] = [
    (1.0, 4.0),
    (4.0, 8.0),
    (8.0, 13.0),
    (13.0, 30.0),
    (30.0, 45.0),
];

/// Periodic Hamming window `0.54 − 0.46·cos(2πi/n)`.
fn hamming(n: usize) -> Vec<f64> {
    (0..n)
        .map(|i| 0.54 - 0.46 * (2.0 * std::f64::consts::PI * i as f64 / n as f64).cos())
        .collect()
}

/// Bands, peak alpha and line noise of one window (256 samples at 256 Hz):
/// Hamming-windowed FFT, one-sided PSD `2|X_k|² / (fs·Σw²)` in µV²/Hz.
/// Band power = PSD summed over the band's bins (× 1 Hz bin width).
/// Returns `[delta, theta, alpha, beta, gamma, peak_alpha_hz,
/// peak_alpha_psd, line_noise_ratio]`.
pub(crate) fn compute_fft_bands(samples: &[f64]) -> [f64; 8] {
    let n = samples.len();
    if n < 2 {
        return [0.0; 8];
    }
    let sample_rate = 256.0;
    let hz_per_bin = sample_rate / n as f64;
    let w = hamming(n);
    let windowed: Vec<f64> = samples.iter().zip(&w).map(|(x, w)| x * w).collect();
    let psd_scale = 2.0 / (sample_rate * w.iter().map(|v| v * v).sum::<f64>());

    with_spectrum(&windowed, |re, im| {
        let half_n = n / 2;
        let psd = |k: usize| (re[k] * re[k] + im[k] * im[k]) * psd_scale;
        let band = |(lo, hi): (f64, f64)| {
            (1..half_n)
                .filter(|&k| {
                    let f = k as f64 * hz_per_bin;
                    f >= lo && f < hi
                })
                .map(psd)
                .sum::<f64>()
                * hz_per_bin
        };
        let powers = BANDS_HZ.map(band);

        let (peak_freq, peak_power) = compute_peak_alpha(re, im, hz_per_bin);

        // Line-noise / impedance proxy: fraction of total power in the
        // 50/60 Hz mains bins.
        let total: f64 = (1..=half_n).map(|k| re[k] * re[k] + im[k] * im[k]).sum();
        let mains_power = mains_bin_power(re, im, 50.0).max(mains_bin_power(re, im, 60.0));
        let line_noise_ratio = if total > 0.0 {
            mains_power / total
        } else {
            0.0
        };

        [
            powers[0],
            powers[1],
            powers[2],
            powers[3],
            powers[4],
            peak_freq,
            peak_power * psd_scale,
            line_noise_ratio,
        ]
    })
}

fn compute_pulse(ir_samples: &[f64]) -> (f64, f64) {
    const MIN_SAMPLES: usize = 128; // 2 s @ 64 Hz
    const WINDOW: usize = 8 * 64;
    if ir_samples.len() < MIN_SAMPLES {
        return (0.0, 0.0);
    }
    let start = ir_samples.len().saturating_sub(WINDOW);
    let ac = pulse_ac(&ir_samples[start..]);
    if ac.len() < 64 {
        return (0.0, 0.0);
    }

    let mut mags: Vec<f64> = ac.iter().map(|s| s.abs()).collect();
    let mid = mags.len() / 2;
    mags.select_nth_unstable_by(mid, |a, b| {
        a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal)
    });
    let median = mags[mid];
    if median < 1.0 {
        return (0.0, 0.0);
    }
    let threshold = median;

    let mut peaks = Vec::new();
    for i in 1..ac.len() - 1 {
        if ac[i] > threshold && ac[i] > ac[i - 1] && ac[i] > ac[i + 1] {
            peaks.push(i);
        }
    }
    if peaks.len() < 2 {
        return (0.0, 0.0);
    }

    let mut ibis = Vec::new();
    for pair in peaks.windows(2) {
        let ibi = (pair[1] - pair[0]) as f64 / 64.0;
        if ibi > 0.3 && ibi < 1.5 {
            ibis.push(ibi);
        }
    }
    if ibis.len() < 2 {
        return (0.0, 0.0);
    }

    let avg_ibi = ibis.iter().copied().sum::<f64>() / ibis.len() as f64;
    let bpm = 60.0 / avg_ibi;
    let variance = ibis.iter().map(|i| (i - avg_ibi).powi(2)).sum::<f64>() / ibis.len() as f64;
    let cv = variance.sqrt() / avg_ibi;
    let confidence = (1.0 - cv).max(0.0);
    (bpm, confidence)
}

/// SpO2 from PPG IR + Red (ratio-of-ratios). Returns (percent, confidence).
/// A=110, B=25 are a best-guess, not Muse-calibrated. Needs 4 s of both
/// channels and uses the last 8 s. AC is the pulse after a 0.5 Hz high-pass,
/// so a contact step does not move the ratio. Outside 50–100 returns (0, 0)
/// instead of pinning the trace to the rail. Flat light also returns (0, 0).
fn compute_spo2(ir_samples: &[f64], red_samples: &[f64]) -> (f64, f64) {
    const MIN_SAMPLES: usize = 256; // 4 s @ 64 Hz
    const MAX_SAMPLES: usize = 8 * 64;
    if ir_samples.len() < MIN_SAMPLES || red_samples.len() < MIN_SAMPLES {
        return (0.0, 0.0);
    }
    let window_size = ir_samples.len().min(red_samples.len()).min(MAX_SAMPLES);
    let ir_window = &ir_samples[ir_samples.len() - window_size..];
    let red_window = &red_samples[red_samples.len() - window_size..];

    let ir_dc = ir_window.iter().copied().sum::<f64>() / ir_window.len() as f64;
    let red_dc = red_window.iter().copied().sum::<f64>() / red_window.len() as f64;
    let ir_ac_sig = pulse_ac(ir_window);
    let red_ac_sig = pulse_ac(red_window);
    if ir_ac_sig.is_empty() || red_ac_sig.is_empty() {
        return (0.0, 0.0);
    }
    let ir_ac = (ir_ac_sig.iter().map(|s| s * s).sum::<f64>() / ir_ac_sig.len() as f64).sqrt();
    let red_ac = (red_ac_sig.iter().map(|s| s * s).sum::<f64>() / red_ac_sig.len() as f64).sqrt();

    if ir_dc < 100.0 || red_dc < 100.0 || ir_ac < 1.0 || red_ac < 1.0 {
        return (0.0, 0.0);
    }

    let r = (red_ac / red_dc) / (ir_ac / ir_dc);
    if !r.is_finite() {
        return (0.0, 0.0);
    }

    const A: f64 = 110.0;
    const B: f64 = 25.0;
    let spo2 = A - B * r;
    if !(50.0..=100.0).contains(&spo2) {
        return (0.0, 0.0);
    }

    let ir_quality = (ir_ac / ir_dc * 20.0).min(1.0);
    let red_quality = (red_ac / red_dc * 20.0).min(1.0);
    let confidence = (ir_quality * red_quality).sqrt().clamp(0.0, 1.0);
    (spo2, confidence)
}

/// High-pass at 0.5 Hz, then drop the filter settle. A headset-on step dies
/// in about a second; heart rate sits above that.
fn pulse_ac(samples: &[f64]) -> Vec<f64> {
    const FS: f64 = 64.0;
    const CUTOFF: f64 = 0.5;
    let dt = 1.0 / FS;
    let rc = 1.0 / (2.0 * std::f64::consts::PI * CUTOFF);
    let a = rc / (rc + dt);
    let mut hp = vec![0.0; samples.len()];
    for i in 1..samples.len() {
        hp[i] = a * (hp[i - 1] + samples[i] - samples[i - 1]);
    }
    let settle = 32.min(hp.len());
    hp.split_off(settle)
}

/// Movement score from accelerometer magnitude variance.
/// Higher score = more movement.
fn compute_movement(magnitudes: &[f64]) -> f64 {
    if magnitudes.len() < 10 {
        return 0.0;
    }
    // Use the last 2 seconds of data
    let window_size = (2.0 * 52.0) as usize;
    let start = magnitudes.len().saturating_sub(window_size);
    let window = &magnitudes[start..];

    let mean = window.iter().copied().sum::<f64>() / window.len() as f64;
    let variance = window.iter().map(|m| (m - mean).powi(2)).sum::<f64>() / window.len() as f64;
    variance.sqrt()
}

/// Peak alpha frequency via parabolic interpolation over FFT bins.
/// `re` and `im` are the full FFT output (half_n + 1 usable bins).
/// Returns (frequency_hz, power).
fn compute_peak_alpha(re: &[f64], im: &[f64], hz_per_bin: f64) -> (f64, f64) {
    let (lo, hi) = BANDS_HZ[2];
    let bin_start = (lo / hz_per_bin).ceil() as usize;
    let bin_end = (hi / hz_per_bin).ceil() as usize;
    let bin_end = bin_end.min(re.len());

    let mut max_power = 0.0f64;
    let mut max_bin = bin_start;
    for k in bin_start..bin_end {
        let power = re[k] * re[k] + im[k] * im[k];
        if power > max_power {
            max_power = power;
            max_bin = k;
        }
    }
    if max_power < 1e-12 {
        return (0.0, 0.0);
    }

    let prev_power = if max_bin > bin_start {
        re[max_bin - 1] * re[max_bin - 1] + im[max_bin - 1] * im[max_bin - 1]
    } else {
        0.0
    };
    let next_power = if max_bin + 1 < bin_end {
        re[max_bin + 1] * re[max_bin + 1] + im[max_bin + 1] * im[max_bin + 1]
    } else {
        0.0
    };

    let offset = (next_power - prev_power) / (2.0 * (2.0 * max_power - prev_power - next_power));
    let frequency = (max_bin as f64 + offset) * hz_per_bin;
    (frequency, max_power)
}

/// Montage width for a Muse `PadQuality` vector: 4 head electrodes, plus AUX
/// when the connection is streaming them. A missing limit is the head only.
fn muse_quality_width(eeg_limit: Option<i32>) -> usize {
    let n = eeg_limit.unwrap_or(MUSE_HEAD_ELECTRODES as i32);
    if n < MUSE_HEAD_ELECTRODES as i32 {
        MUSE_HEAD_ELECTRODES as usize
    } else {
        n as usize
    }
}

fn emit_pad_quality(
    latest_bands: &std::collections::HashMap<i32, features::ChannelBands>,
    rings: &std::collections::HashMap<i32, features::EegRing>,
    eeg_limit: Option<i32>,
) {
    match features::active_kind() {
        Some(kind) if kind.is_neurosity() => emit_neurosity_pad_quality(latest_bands, rings),
        Some(kind) if kind.is_muse() => {
            emit_muse_pad_quality(latest_bands, rings, eeg_limit);
        }
        _ => {}
    }
}

fn emit_muse_pad_quality(
    latest_bands: &std::collections::HashMap<i32, features::ChannelBands>,
    rings: &std::collections::HashMap<i32, features::EegRing>,
    eeg_limit: Option<i32>,
) {
    let width = muse_quality_width(eeg_limit);
    let ready = rings
        .iter()
        .any(|(&el, ring)| usize::try_from(el).is_ok_and(|i| i < width && ring.has_window()));
    if !ready {
        return;
    }
    let values = features::muse_pad_scores(rings, latest_bands, width);
    push_pad_quality(PadQualityDto {
        values,
        source: QualitySource::App,
        crown: None,
    });
}

fn emit_neurosity_pad_quality(
    latest_bands: &std::collections::HashMap<i32, features::ChannelBands>,
    rings: &std::collections::HashMap<i32, features::EegRing>,
) {
    let app: [Option<f64>; crate::analysis::crown_quality::CROWN_PADS] =
        std::array::from_fn(|pad| {
            let el = pad as i32;
            let noise = latest_bands.get(&el).map_or(-1.0, |b| b.line_noise_ratio);
            rings.get(&el).and_then(|r| r.quality(noise))
        });
    let resolved = features::resolve_neurosity_second(&app);
    push_pad_quality(PadQualityDto {
        values: resolved.scores.iter().map(|q| q.unwrap_or(0.0)).collect(),
        source: resolved.source,
        crown: resolved.crown.map(|c| c.to_vec()),
    });
}

fn push_pad_quality(dto: PadQualityDto) {
    let dto = MuseEventDto::PadQuality(dto);
    let mut guard = state().inner.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(sink) = &guard.sink {
        if sink.add(dto).is_err() {
            guard.sink = None;
        }
    }
}

fn emit_enabled_band_features(
    timestamp: f64,
    latest_bands: &std::collections::HashMap<i32, features::ChannelBands>,
    rings: &std::collections::HashMap<i32, features::EegRing>,
) {
    let Some(kind) = features::active_kind() else {
        return;
    };
    for id in features::enabled_ids() {
        if !id.starts_with("band.") {
            continue;
        }
        let Ok(indices) = features::resolved_electrode_indices(kind, &id) else {
            continue;
        };
        let pads = features::collect_usable_pads(kind, &indices, latest_bands, rings);
        let Some(value) = features::aggregate_band_feature(&id, &pads) else {
            continue;
        };
        let mut guard = state().inner.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(sink) = &guard.sink {
            if sink
                .add(MuseEventDto::Feature(FeatureDto {
                    id,
                    timestamp,
                    value,
                }))
                .is_err()
            {
                guard.sink = None;
            }
        }
    }
}

fn map_event(ev: MuseEvent) -> MuseEventDto {
    match ev {
        MuseEvent::Connected(name) => MuseEventDto::Connected(name),
        MuseEvent::Disconnected => MuseEventDto::Disconnected,
        MuseEvent::Eeg(r) => MuseEventDto::Eeg(EegDto {
            index: r.index,
            electrode: r.electrode as i32,
            timestamp: r.timestamp,
            samples: r.samples,
        }),
        MuseEvent::Ppg(r) => MuseEventDto::Ppg(PpgDto {
            index: r.index,
            channel: r.ppg_channel as i32,
            timestamp: r.timestamp,
            samples: r.samples.into_iter().map(|s| s as f64).collect(),
        }),
        MuseEvent::Telemetry(t) => MuseEventDto::Telemetry(TelemetrySnapshot {
            battery_level: t.battery_level,
            fuel_gauge_voltage: t.fuel_gauge_voltage,
            temperature: t.temperature,
        }),
        MuseEvent::Accelerometer(imu) => MuseEventDto::Accelerometer(map_imu(imu)),
        MuseEvent::Gyroscope(imu) => MuseEventDto::Gyroscope(map_imu(imu)),
        MuseEvent::Control(c) => MuseEventDto::Control(ControlDto {
            raw: c.raw,
            fields: c
                .fields
                .into_iter()
                .map(|(k, v)| (k, v.to_string()))
                .collect(),
        }),
    }
}

fn map_imu(imu: ImuData) -> ImuDto {
    ImuDto {
        sequence_id: imu.sequence_id,
        samples: imu
            .samples
            .iter()
            .map(|s| XyzDto {
                x: s.x,
                y: s.y,
                z: s.z,
            })
            .collect(),
    }
}

#[cfg(test)]
mod aux_tests {
    use super::*;

    #[test]
    fn aux_channel_count_by_firmware() {
        assert_eq!(muse_aux_channels(false), 1);
        assert_eq!(muse_aux_channels(true), 4);
    }

    #[test]
    fn simulated_aux_follows_catalog_firmware() {
        assert_eq!(simulated_aux_channels(DeviceKind::Muse, "Classic"), 1);
        assert_eq!(simulated_aux_channels(DeviceKind::Muse, "Athena"), 4);
        assert_eq!(
            simulated_aux_channels(DeviceKind::Neurosity, "Crown_sim_v1.0"),
            0
        );
    }

    #[test]
    fn muse_quality_width_follows_the_connection_limit() {
        assert_eq!(muse_quality_width(None), 4);
        assert_eq!(muse_quality_width(Some(4)), 4);
        assert_eq!(muse_quality_width(Some(5)), 5);
        assert_eq!(muse_quality_width(Some(8)), 8);
        assert_eq!(muse_quality_width(Some(0)), 4);
    }
}

#[cfg(test)]
mod conditioning_tests {
    use super::*;
    use crate::api::features::pad_quality_from_std_and_noise;
    use std::f64::consts::PI;

    /// Muse Classic-style packet: 12 samples, ~800 µV offset, 10 µV alpha,
    /// 60 µV 50 Hz hum.
    fn muse_packet(n0: usize, electrode: i32) -> EegDto {
        EegDto {
            index: (n0 / 12) as u16,
            electrode,
            timestamp: 1.0e12 + n0 as f64 * 1000.0 / 256.0,
            samples: (n0..n0 + 12)
                .map(|n| {
                    let t = n as f64 / 256.0;
                    800.0
                        + electrode as f64 * 37.0
                        + 10.0 * (2.0 * PI * 10.0 * t).sin()
                        + 60.0 * (2.0 * PI * 50.0 * t).sin()
                })
                .collect(),
        }
    }

    fn std(v: &[f64]) -> f64 {
        let m = v.iter().sum::<f64>() / v.len() as f64;
        (v.iter().map(|x| (x - m).powi(2)).sum::<f64>() / v.len() as f64).sqrt()
    }

    #[test]
    fn muse_quality_and_bands_use_the_conditioned_signal() {
        let mut c = EegConditioner::default();
        let mut raw = vec![Vec::new(); 4];
        let mut conditioned = vec![Vec::new(); 4];
        let mut n = 0;
        while n < 256 * 6 {
            for el in 0..4 {
                let p = muse_packet(n, el);
                let before = p.samples.clone();
                let (samples, events) = condition_eeg_packet(&mut c, &p);
                // The packet capture records is RAW as received.
                assert_eq!(p.samples, before);
                assert_eq!(
                    samples.len(),
                    events
                        .iter()
                        .map(|e| match e {
                            MuseEventDto::Eeg(e) => e.samples.len(),
                            _ => 0,
                        })
                        .sum::<usize>()
                );
                raw[el as usize].extend(before);
                conditioned[el as usize].extend(samples);
            }
            n += 12;
        }
        assert_eq!(c.mains(), eeg_filter::Mains::Hz(50.0));
        for el in 0..4 {
            let last_raw = &raw[el][256 * 5..256 * 6];
            let last = &conditioned[el][256 * 5..256 * 6];
            let raw_bands = compute_fft_bands(last_raw);
            let bands = compute_fft_bands(last);
            // Unfiltered: hum dominates spread and line noise → unusable.
            let raw_q = pad_quality_from_std_and_noise(std(last_raw), raw_bands[7]);
            // Conditioned: 10 µV alpha, no residual hum → usable.
            let q = pad_quality_from_std_and_noise(std(last), bands[7]);
            assert!(raw_q < 80.0 && q >= 80.0, "raw {raw_q} conditioned {q}");
            assert!(bands[7] < 1e-4, "line noise {}", bands[7]);
            let rel_alpha = bands[2] / bands[..5].iter().sum::<f64>();
            assert!(rel_alpha > 0.99, "relative alpha {rel_alpha}");
        }
    }

    #[test]
    fn crown_packet_is_conditioned_and_raw_untouched() {
        let mut c = EegConditioner::default();
        let mut out = Vec::new();
        for k in 0..64usize {
            let p = EegDto {
                index: k as u16,
                electrode: 3,
                timestamp: k as f64 * 62.5,
                samples: (k * 16..k * 16 + 16)
                    .map(|n| -2.0e5 + 10.0 * (2.0 * PI * 10.0 * n as f64 / 256.0).sin())
                    .collect(),
            };
            let before = p.samples.clone();
            let (samples, _) = condition_eeg_packet(&mut c, &p);
            assert_eq!(p.samples, before);
            out.extend(samples);
        }
        assert_eq!(out.len(), 64 * 16);
        assert!(out.iter().all(|v| v.abs() < 15.0));
    }

    /// A 10 µV sine carries 50 µV² (A²/2): the alpha band gets it all when
    /// the sine sits inside alpha, on or between bins.
    #[test]
    fn known_alpha_sine_band_power() {
        for hz in [10.0, 10.5, 11.3] {
            let x: Vec<f64> = (0..256)
                .map(|n| 10.0 * (2.0 * PI * hz * n as f64 / 256.0).sin())
                .collect();
            let b = compute_fft_bands(&x);
            let total: f64 = b[..5].iter().sum();
            eprintln!(
                "{hz} Hz: bands {:?} peak {:.2} Hz {:.2} µV²/Hz",
                &b[..5],
                b[5],
                b[6]
            );
            assert!((b[2] - 50.0).abs() < 2.0, "{hz} Hz alpha {}", b[2]);
            assert!(b[2] / total > 0.97, "{hz} Hz rel alpha {}", b[2] / total);
            assert!((b[5] - hz).abs() < 0.3, "{hz} Hz peak {}", b[5]);
        }
        // Every 1 Hz bin in exactly one band: 1..=44 Hz tones each land in
        // one band only, and 45..=50 Hz in none.
        for f in 1..=50usize {
            let x: Vec<f64> = (0..256)
                .map(|n| (2.0 * PI * f as f64 * n as f64 / 256.0).cos())
                .collect();
            let b = compute_fft_bands(&x);
            let hit = BANDS_HZ
                .iter()
                .position(|&(lo, hi)| (f as f64) >= lo && (f as f64) < hi);
            if let Some(i) = hit {
                assert!(b[i] > 0.3, "{f} Hz band {i} {}", b[i]);
            } else {
                assert!(b[4] < 0.2, "{f} Hz leaks into gamma {}", b[4]);
            }
        }
    }

    /// Direct DFT reference for the band / line-noise math.
    #[test]
    fn fft_bands_match_direct_dft() {
        let x: Vec<f64> = (0..256)
            .map(|n| {
                let t = n as f64 / 256.0;
                20.0 * (2.0 * PI * 10.0 * t).sin()
                    + 5.0 * (2.0 * PI * 3.0 * t).cos()
                    + 4.0 * (2.0 * PI * 50.0 * t).sin()
                    + 2.0 * (2.0 * PI * 21.0 * t).sin()
            })
            .collect();
        let w: Vec<f64> = (0..256)
            .map(|n| 0.54 - 0.46 * (2.0 * PI * n as f64 / 256.0).cos())
            .collect();
        let sum_w2: f64 = w.iter().map(|v| v * v).sum();
        let p = |k: usize| {
            let (mut re, mut im) = (0.0, 0.0);
            for (n, v) in x.iter().enumerate() {
                let a = 2.0 * PI * (k * n) as f64 / 256.0;
                re += v * w[n] * a.cos();
                im -= v * w[n] * a.sin();
            }
            re * re + im * im
        };
        // Half-open bins [lo, hi), one-sided PSD, 1 Hz bins.
        let band = |lo: usize, hi: usize| (lo..hi).map(p).sum::<f64>() * 2.0 / (256.0 * sum_w2);
        let got = compute_fft_bands(&x);
        let want = [
            band(1, 4),
            band(4, 8),
            band(8, 13),
            band(13, 30),
            band(30, 45),
        ];
        for i in 0..5 {
            assert!(
                (got[i] - want[i]).abs() <= 1e-9 * want[i].max(1.0),
                "band {i}: {} vs {}",
                got[i],
                want[i]
            );
        }
        let total: f64 = (1..=128).map(p).sum();
        let mains = (49..=51).map(p).sum::<f64>().max((59..=61).map(p).sum());
        assert!((got[7] - mains / total).abs() < 1e-12);
        let (r50, _) = mains_peak_ratios(&x);
        assert!(r50 > eeg_filter::PEAK_RATIO, "{r50}");
    }
}

#[cfg(test)]
mod spo2_tests {
    use super::compute_spo2;

    fn tone(n: usize, dc: f64, amp: f64) -> Vec<f64> {
        (0..n)
            .map(|i| {
                let t = i as f64 / 64.0;
                dc + amp * (2.0 * std::f64::consts::PI * 1.2 * t).sin()
            })
            .collect()
    }

    #[test]
    fn spo2_waits_for_four_seconds_then_estimates() {
        let short = tone(255, 200_000.0, 8_000.0);
        assert_eq!(compute_spo2(&short, &tone(255, 180_000.0, 6_000.0)).0, 0.0);

        let ir = tone(256, 200_000.0, 8_000.0);
        let red = tone(256, 180_000.0, 6_000.0);
        let (spo2, confidence) = compute_spo2(&ir, &red);
        assert!(
            (70.0..=100.0).contains(&spo2),
            "spo2 {spo2} confidence {confidence}"
        );
        assert!(confidence > 0.0 && confidence <= 1.0);
    }

    #[test]
    fn spo2_flat_or_tiny_signal_stays_absent() {
        let flat = vec![200_000.0; 256];
        assert_eq!(compute_spo2(&flat, &vec![180_000.0; 256]).0, 0.0);
        let quiet = tone(256, 50.0, 30.0);
        assert_eq!(compute_spo2(&quiet, &tone(256, 40.0, 30.0)).0, 0.0);
    }

    #[test]
    fn spo2_keeps_a_value_when_the_ratio_leaves_the_old_band() {
        // R ≈ 1.3 still yields ~77%. A ratio this high used to be dropped.
        let (mid, _) = compute_spo2(
            &tone(256, 200_000.0, 8_000.0),
            &tone(256, 180_000.0, 9_360.0),
        );
        assert!((mid - 77.5).abs() < 2.0, "{mid}");

        // Far below 50% is a gap, not a pinned 50% rail.
        let (low, _) = compute_spo2(
            &tone(256, 200_000.0, 2_000.0),
            &tone(256, 180_000.0, 20_000.0),
        );
        assert_eq!(low, 0.0);
    }

    #[test]
    fn contact_step_does_not_pin_spo2_or_block_pulse() {
        let n = 8 * 64;
        let mut ir = Vec::with_capacity(n);
        let mut red = Vec::with_capacity(n);
        for i in 0..n {
            let t = i as f64 / 64.0;
            let step = if i < 64 { 100_000.0 } else { 0.0 };
            let wave = (2.0 * std::f64::consts::PI * 1.2 * t).sin();
            ir.push(200_000.0 + step + 8_000.0 * wave);
            red.push(180_000.0 + 0.4 * step + 6_000.0 * wave);
        }
        let (spo2, _) = compute_spo2(&ir, &red);
        assert!(
            (70.0..=100.0).contains(&spo2),
            "spo2 {spo2} should follow the pulse, not the step"
        );
        let (bpm, _) = super::compute_pulse(&ir);
        assert!((bpm - 72.0).abs() < 8.0, "bpm {bpm}");
    }
}
