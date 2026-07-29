use flutter_rust_bridge::frb;
use std::time::{SystemTime, UNIX_EPOCH};
use crate::frb_generated::StreamSink;
use muse_rs::prelude::*;

use crate::connection::{state, ActiveConnection};

fn now_ms() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
        * 1000.0
}

// ── DTOs (serializable across the bridge) ──────────────────────────────────────

/// A Muse device discovered during a scan.
#[frb(dart_metadata = ("freezed",))]
pub struct DeviceInfo {
    pub name: String,
    pub id: String,
}

/// Connection / link status reported to the UI.
#[frb(dart_metadata = ("freezed",))]
pub struct ConnectionStatus {
    pub connected: bool,
    pub name: String,
    pub id: String,
    pub firmware: String,
}

impl Default for ConnectionStatus {
    fn default() -> Self {
        Self {
            connected: false,
            name: String::new(),
            id: String::new(),
            firmware: String::new(),
        }
    }
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
#[frb(dart_metadata = ("freezed",))]
pub struct BandsDto {
    pub electrode: i32,
    pub timestamp: f64,
    pub delta: f64,
    pub theta: f64,
    pub alpha: f64,
    pub beta: f64,
    pub gamma: f64,
}

/// Heart-rate pulse estimate from PPG infrared channel.
#[frb(dart_metadata = ("freezed",))]
pub struct PulseDto {
    pub timestamp: f64,
    pub bpm: f64,
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
    Movement(MovementDto),
    PeakAlpha(PeakAlphaDto),
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
                .with_tag("muse_ml"),
        );
        // Ensure the max level takes effect even if android_logger was
        // already initialized (e.g. by flutter_rust_bridge). Without this,
        // jni::trace!() spam floods logcat at verbose priority.
        log::set_max_level(log::LevelFilter::Debug);
    }
    #[cfg(not(target_os = "android"))]
    {
        env_logger::Builder::from_env(
            env_logger::Env::default().default_filter_or("info"),
        )
        .init();
    }
}

/// Compress a block of recording data using zstd (level 3).
/// Returns the compressed bytes as an independent zstd frame.
/// On failure (e.g. pathological input) returns the original data unchanged.
pub fn compress_block(data: Vec<u8>) -> Vec<u8> {
    match zstd::encode_all(std::io::Cursor::new(&data), 3) {
        Ok(compressed) => compressed,
        Err(e) => {
            log::warn!("[muse] zstd compress failed: {e}, storing uncompressed");
            data
        }
    }
}

/// Called from Kotlin `MainActivity.onCreate` with the JNI environment so that
/// btleplug's global Android adapter can be registered. On Android, btleplug
/// requires `btleplug::platform::init(&env)` to be called from a JNI context
/// before any BLE scan/connect; otherwise it panics with
/// "Droidplug has not been initialized".
#[cfg(target_os = "android")]
#[no_mangle]
pub extern "C" fn Java_com_example_muse_1ml_MainActivity_museAndroidInit(
    env: *mut jni::sys::JNIEnv,
) {
    let env = unsafe { jni::JNIEnv::from_raw(env) };
    if let Ok(env) = env {
        if let Err(e) = btleplug::platform::init(&env) {
            log::error!("[muse] btleplug init failed: {e:?}");
        } else {
            log::info!("[muse] btleplug initialized");
        }
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
        .map(|d| DeviceInfo {
            name: d.name.clone(),
            id: d.id.clone(),
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
        guard.devices.get(&device_id).cloned().ok_or_else(|| {
            anyhow::anyhow!("Device {device_id} not found; scan first")
        })?
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

        // Start streaming — on Android the BLE stack drops rapid-fire
        // WriteWithoutResponse commands, so we add delays between each
        // step for the Classic protocol.  Athena's start() already has
        // built-in delays and is used as-is.
        let start_result = if handle.is_athena {
            tokio::time::timeout(
                std::time::Duration::from_secs(8),
                handle.start(false, false),
            )
            .await
        } else {
            tokio::time::timeout(
                std::time::Duration::from_secs(8),
                async {
                    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                    handle.send_command("h").await?;
                    tokio::time::sleep(std::time::Duration::from_millis(150)).await;
                    handle.send_command("s").await?;
                    tokio::time::sleep(std::time::Duration::from_millis(150)).await;
                    handle.send_command("p21").await?;
                    tokio::time::sleep(std::time::Duration::from_millis(150)).await;
                    handle.send_command("d").await?;
                    tokio::time::sleep(std::time::Duration::from_millis(300)).await;
                    Ok(())
                },
            )
            .await
        };
        match start_result {
            Ok(Err(e)) => log::warn!("[muse] start commands failed: {e:#}"),
            Err(_) => log::warn!("[muse] start commands timed out after 8 s"),
            _ => {}
        }

        // Request device info once so the control JSON with bp (battery
        // percentage) arrives.  The forwarder extracts bp from Control events
        // and emits a Telemetry event with the correct 0-100 value.
        let _ = handle.send_command("v1").await;

        {
            let mut guard = state().inner.lock().unwrap();
            guard.connection_epoch += 1;
            guard.active = Some(ActiveConnection {
                handle,
                name: name.clone(),
                id: device_id.clone(),
                firmware: firmware.clone(),
            });
            guard.events = Some(rx);
        }

        spawn_event_forwarder();

        Ok(ConnectionStatus {
            connected: true,
            name,
            id: device_id,
            firmware,
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
        },
        None => ConnectionStatus::default(),
    }
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
        let mut accums: std::collections::HashMap<i32, Vec<f64>> =
            std::collections::HashMap::new();
        let mut bp_override: Option<f32> = None;

        // PPG and accelerometer buffers for derived metrics
        let mut ppg_ir_buffer: Vec<f64> = Vec::new();
        let mut accel_mag_buffer: Vec<f64> = Vec::new();
        let mut last_metrics = tokio::time::Instant::now();

        // Per-electrode virtual timestamp tracking for Athena firmware.
        // muse-rs emits timestamp=0.0 for Athena packets because they lack
        // per-channel sequence indices.  We synthesise wall-clock timestamps
        // by anchoring to the first packet arrival and advancing at 256 Hz.
        let mut eeg_ts_base: std::collections::HashMap<i32, f64> = std::collections::HashMap::new(); // ms epoch
        let mut eeg_ts_count: std::collections::HashMap<i32, u64> = std::collections::HashMap::new(); // total samples

        const FFT_N: usize = 256;
        loop {
            let rx = {
                let mut guard =
                    state().inner.lock().unwrap_or_else(|e| e.into_inner());
                guard.events.take()
            };
            let Some(mut rx) = rx else {
                tokio::time::sleep(std::time::Duration::from_millis(200)).await;
                continue;
            };
            loop {
                let ev = match tokio::time::timeout(
                    std::time::Duration::from_secs(5),
                    rx.recv(),
                )
                .await
                {
                    Ok(Some(ev)) => ev,
                    Ok(None) => {
                        log::info!(
                            "[muse] forwarder: event channel closed (epoch={epoch})"
                        );
                        break;
                    }
                    Err(_) => {
                        log::info!(
                            "[muse] forwarder: alive (epoch={epoch}, no events for 5s, eeg={} telem={} accel={} gyro={})",
                            counts.eeg, counts.telemetry,
                            counts.accelerometer, counts.gyroscope,
                        );
                        counts = PktCounts::default();
                        last_print = tokio::time::Instant::now();
                        continue;
                    }
                };
                match &ev {
                    MuseEvent::Eeg(_) => counts.eeg += 1,
                    MuseEvent::Ppg(_) => counts.ppg += 1,
                    MuseEvent::Telemetry(_) => counts.telemetry += 1,
                    MuseEvent::Accelerometer(_) => counts.accelerometer += 1,
                    MuseEvent::Gyroscope(_) => counts.gyroscope += 1,
                    MuseEvent::Control(_) => counts.control += 1,
                    MuseEvent::Connected(_) => counts.connected += 1,
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
                let mut dto = map_event(ev);
                // Patch Athena EEG timestamps (0.0) with virtual wall-clock
                // timestamps derived from total sample count @ 256 Hz.
                if let MuseEventDto::Eeg(ref mut e) = dto {
                    if e.timestamp == 0.0 {
                        let count = eeg_ts_count.entry(e.electrode).or_insert(0);
                        let base = eeg_ts_base
                            .entry(e.electrode)
                            .or_insert_with(now_ms);
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

                // Extract PPG IR samples for pulse detection
                if let MuseEventDto::Ppg(ref ppg) = dto {
                    if ppg.channel == 1 {
                        ppg_ir_buffer.extend(ppg.samples.iter().copied());
                        if ppg_ir_buffer.len() > 1280 {
                            let drain_to = ppg_ir_buffer.len() - 1280;
                            ppg_ir_buffer.drain(..drain_to);
                        }
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

                let eeg_samples = if let MuseEventDto::Eeg(ref e) = dto {
                    Some((e.electrode, e.timestamp, e.samples.clone()))
                } else {
                    None
                };
                let should_stop = {
                    let mut guard =
                        state().inner.lock().unwrap_or_else(|e| e.into_inner());
                    match guard.sink.as_ref() {
                        Some(sink) => {
                            if sink.add(dto).is_err() {
                                guard.sink = None;
                                true
                            } else {
                                false
                            }
                        }
                        None => false,
                    }
                };
                if should_stop {
                    break;
                }
                if let Some((electrode, timestamp, samples)) = eeg_samples {
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
                        let result = match tokio::task::spawn_blocking(
                            move || compute_fft_bands(&trimmed),
                        )
                        .await
                        {
                            Ok(r) => r,
                            Err(e) => {
                                log::error!("[muse] FFT blocking task panicked: {e}");
                                continue;
                            }
                        };
                        // result: [delta, theta, alpha, beta, gamma, peak_alpha_freq, peak_alpha_power]
                        counts.bands += 1;
                        let should_stop = {
                            let mut guard = state()
                                .inner
                                .lock()
                                .unwrap_or_else(|e| e.into_inner());
                            let sink_ok = match guard.sink.as_ref() {
                                Some(sink) => {
                                    sink.add(MuseEventDto::Bands(BandsDto {
                                        electrode,
                                        timestamp,
                                        delta: result[0],
                                        theta: result[1],
                                        alpha: result[2],
                                        beta: result[3],
                                        gamma: result[4],
                                    }))
                                    .is_ok()
                                }
                                None => false,
                            };
                            if !sink_ok {
                                guard.sink = None;
                                true
                            } else {
                                // Emit peak alpha alongside bands
                                if result[5] > 0.0 {
                                    let _ = guard.sink.as_ref().map(|s| {
                                        s.add(MuseEventDto::PeakAlpha(PeakAlphaDto {
                                            timestamp,
                                            frequency: result[5],
                                            power: result[6],
                                        }))
                                    });
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

                        let (bpm, confidence) = compute_pulse(&ppg_ir_buffer);
                        if bpm > 0.0 {
                            let mut guard = state()
                                .inner
                                .lock()
                                .unwrap_or_else(|e| e.into_inner());
                            if let Some(sink) = &guard.sink {
                                if sink
                                    .add(MuseEventDto::Pulse(PulseDto {
                                        timestamp: now_ms,
                                        bpm,
                                        confidence,
                                    }))
                                    .is_err()
                                {
                                    guard.sink = None;
                                }
                            }
                        }

                        let movement_score = compute_movement(&accel_mag_buffer);
                        {
                            let mut guard = state()
                                .inner
                                .lock()
                                .unwrap_or_else(|e| e.into_inner());
                            if let Some(sink) = &guard.sink {
                                if sink
                                    .add(MuseEventDto::Movement(MovementDto {
                                        timestamp: now_ms,
                                        score: movement_score,
                                    }))
                                    .is_err()
                                {
                                    guard.sink = None;
                                }
                            }
                        }
                    }
                }
            }
        }
    });
}

fn compute_fft_bands(samples: &[f64]) -> [f64; 7] {
    let n = samples.len();
    if n < 2 {
        return [0.0; 7];
    }
    let sample_rate = 256.0;
    let hz_per_bin = sample_rate / n as f64;
    let bin = |hz: f64| (hz / hz_per_bin).round() as usize;

    // Reuse scratch buffers across calls via a small thread-local pool to
    // avoid repeated allocations.  Each electrode does one FFT per second,
    // and one blocking task runs at a time, so 2 buffers × n is enough.
    thread_local! {
        static RE: std::cell::RefCell<Vec<f64>> = const { std::cell::RefCell::new(Vec::new()) };
        static IM: std::cell::RefCell<Vec<f64>> = const { std::cell::RefCell::new(Vec::new()) };
    }

    RE.with(|re_buf| IM.with(|im_buf| {
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

        let half_n = n / 2;
        let powers = [
            (1..=bin(4.0)).map(|k| re[k] * re[k] + im[k] * im[k]).sum::<f64>() / (n * n) as f64,
            (bin(4.0)..=bin(8.0)).map(|k| re[k] * re[k] + im[k] * im[k]).sum::<f64>() / (n * n) as f64,
            (bin(8.0)..=bin(13.0)).map(|k| re[k] * re[k] + im[k] * im[k]).sum::<f64>() / (n * n) as f64,
            (bin(13.0)..=bin(30.0)).map(|k| re[k] * re[k] + im[k] * im[k]).sum::<f64>() / (n * n) as f64,
            (bin(30.0)..=bin(half_n.min(50) as f64)).map(|k| re[k] * re[k] + im[k] * im[k]).sum::<f64>() / (n * n) as f64,
        ];

        let (peak_freq, peak_power) = compute_peak_alpha(&re, &im, hz_per_bin);

        [
            powers[0], powers[1], powers[2], powers[3], powers[4],
            peak_freq, peak_power,
        ]
    }))
}

/// Pulse detection from PPG infrared channel using peak-finding.
/// Returns (bpm, confidence).
fn compute_pulse(ir_samples: &[f64]) -> (f64, f64) {
    if ir_samples.len() < 128 {
        return (0.0, 0.0);
    }
    // Use the last 8 seconds of data
    let window_size = (8.0 * 64.0) as usize;
    let start = ir_samples.len().saturating_sub(window_size);
    let window = &ir_samples[start..];

    let mean = window.iter().copied().sum::<f64>() / window.len() as f64;
    let ac: Vec<f64> = window.iter().map(|s| s - mean).collect();

    let max_abs = ac.iter().copied().map(f64::abs).fold(0.0, f64::max);
    if max_abs < 1.0 {
        return (0.0, 0.0);
    }
    let threshold = max_abs * 0.4;

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
    let variance =
        window.iter().map(|m| (m - mean).powi(2)).sum::<f64>() / window.len() as f64;
    variance.sqrt()
}

/// Peak alpha frequency via parabolic interpolation over FFT bins.
/// `re` and `im` are the full FFT output (half_n + 1 usable bins).
/// Returns (frequency_hz, power).
fn compute_peak_alpha(re: &[f64], im: &[f64], hz_per_bin: f64) -> (f64, f64) {
    let bin_start = (8.0 / hz_per_bin).round() as usize;
    let bin_end = (13.0 / hz_per_bin).round() as usize;
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

    let offset = (next_power - prev_power)
        / (2.0 * (2.0 * max_power - prev_power - next_power));
    let frequency = (max_bin as f64 + offset) * hz_per_bin;
    (frequency, max_power)
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
        MuseEvent::Telemetry(t) => {
            // log::debug!(
            //     "[muse] telemetry: battery={:.6} fuel_gauge={:.2} temp={}",
            //     t.battery_level, t.fuel_gauge_voltage, t.temperature,
            // );
            MuseEventDto::Telemetry(TelemetrySnapshot {
                battery_level: t.battery_level,
                fuel_gauge_voltage: t.fuel_gauge_voltage,
                temperature: t.temperature,
            })
        }
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
