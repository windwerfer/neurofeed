//! Muse over Bluetooth LE via muse-rs + btleplug (ported from
//! `rust/src/api/muse.rs`). A private tokio runtime runs scan and connect in
//! the background; `scan`/`open` never block the caller.
//!
//! Limits (same as the legacy app): Athena firmware streams EEG ch 0–3 but
//! its PPG is not decoded yet. AUX inputs arrive as electrodes 4.. (the
//! session shows / records them only when Settings asks for it).

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use btleplug::api::{Central, Manager as _, Peripheral as _, ScanFilter};
use btleplug::platform::Manager;
use muse_rs::prelude::{MuseClient, MuseClientConfig, MuseEvent};
use tokio::runtime::Runtime;

use crate::{lock, muse_info, Block, DeviceInfo, DeviceProvider, DeviceSource, LinkState, LiveSource, MUSE_CHANNELS};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(18);
/// Drop a headset that has not advertised for this long while discovery is on.
const SEEN_TTL: Duration = Duration::from_secs(4);
const NAME_PREFIX: &str = "Muse";

/// Advertised name of a Muse headset (Muse, MuseS, Muse-2, …).
fn is_muse_name(name: &str) -> bool {
    name.starts_with(NAME_PREFIX)
}

struct Seen {
    name: String,
    rssi: i16,
    at: Instant,
}

#[derive(Default)]
struct Shared {
    found: HashMap<String, Seen>,
    /// Bumped to cancel the in-flight discovery task.
    epoch: u64,
    scanning: bool,
    /// Device dialog: do not stop when a timed limit elapses.
    hold: bool,
    error: Option<String>,
}

/// Translate one muse-rs event into feed blocks.
pub fn map_muse_event(ev: MuseEvent) -> Vec<Block> {
    match ev {
        MuseEvent::Eeg(r) if r.electrode < MUSE_CHANNELS.len() + crate::MUSE_AUX.len() => {
            vec![Block::Eeg(r.electrode as u16, r.samples.iter().map(|&x| x as f32).collect())]
        }
        MuseEvent::Ppg(r) if r.ppg_channel < 3 => vec![Block::Ppg(r.ppg_channel as u16, r.samples.iter().map(|&x| x as f32).collect())],
        MuseEvent::Accelerometer(imu) => vec![Block::Accel(imu.samples.iter().map(|s| [s.x, s.y, s.z]).collect())],
        MuseEvent::Telemetry(t) => vec![Block::Battery(t.battery_level)],
        MuseEvent::Disconnected => vec![Block::Link(LinkState::Lost { reason: "headset disconnected".into() })],
        _ => Vec::new(),
    }
}

/// Muse provider (`muse:<ble id>`).
#[derive(Default)]
pub struct MuseProvider {
    rt: OnceLock<Result<Arc<Runtime>, String>>,
    shared: Arc<Mutex<Shared>>,
}

impl MuseProvider {
    fn runtime(&self) -> Result<Arc<Runtime>, String> {
        self.rt
            .get_or_init(|| {
                tokio::runtime::Builder::new_multi_thread()
                    .worker_threads(2)
                    .thread_name("muse-ble")
                    .enable_all()
                    .build()
                    .map(Arc::new)
                    .map_err(|e| e.to_string())
            })
            .clone()
    }

    /// Last scan/connect error (no adapter, BlueZ down, ...).
    pub fn error(&self) -> Option<String> {
        lock(&self.shared).error.clone()
    }

    /// `unlimited` keeps the radio on until [`DeviceProvider::stop_scan`].
    /// A timed scan does not replace a watch that is already running.
    fn begin(&mut self, unlimited: bool, seconds: f64) -> Result<(), String> {
        let rt = self.runtime()?;
        let epoch = {
            let mut s = lock(&self.shared);
            if s.scanning {
                if unlimited {
                    s.hold = true;
                }
                return Ok(());
            }
            s.epoch = s.epoch.wrapping_add(1);
            s.scanning = true;
            s.hold = unlimited;
            s.error = None;
            s.epoch
        };
        let shared = self.shared.clone();
        let limit = Duration::from_secs_f64(seconds.clamp(1.0, 60.0));
        rt.spawn(async move {
            if let Err(e) = discover(&shared, epoch, limit).await {
                let mut s = lock(&shared);
                if s.epoch == epoch {
                    s.error = Some(format!("BLE scan: {e}"));
                    s.scanning = false;
                    s.hold = false;
                }
            }
        });
        Ok(())
    }
}

/// Poll BlueZ while `start_scan` is still active so RSSI is present.
/// BlueZ drops `Device1.RSSI` once discovery stops.
async fn discover(shared: &Arc<Mutex<Shared>>, epoch: u64, limit: Duration) -> Result<(), String> {
    let manager = Manager::new().await.map_err(|e| e.to_string())?;
    let adapters = manager.adapters().await.map_err(|e| e.to_string())?;
    let adapter = adapters.into_iter().next().ok_or_else(|| "No Bluetooth adapter found".to_string())?;
    adapter.start_scan(ScanFilter::default()).await.map_err(|e| e.to_string())?;
    let started = tokio::time::Instant::now();
    loop {
        let hold = {
            let s = lock(shared);
            if s.epoch != epoch {
                break;
            }
            s.hold
        };
        if !hold && started.elapsed() >= limit {
            break;
        }
        harvest(&adapter, shared, epoch).await;
        tokio::time::sleep(Duration::from_millis(400)).await;
    }
    adapter.stop_scan().await.ok();
    let mut s = lock(shared);
    if s.epoch == epoch {
        s.scanning = false;
        s.hold = false;
    }
    Ok(())
}

/// Record headsets that are advertising right now. Names without RSSI are
/// cached by BlueZ and are not nearby.
async fn harvest(adapter: &btleplug::platform::Adapter, shared: &Arc<Mutex<Shared>>, epoch: u64) {
    let Ok(peripherals) = adapter.peripherals().await else { return };
    let mut live = HashMap::new();
    for p in peripherals {
        let Ok(Some(props)) = p.properties().await else { continue };
        let Some(name) = props.local_name else { continue };
        let Some(rssi) = props.rssi else { continue };
        if !is_muse_name(&name) {
            continue;
        }
        live.insert(p.id().to_string(), (name, rssi));
    }
    let mut s = lock(shared);
    if s.epoch != epoch {
        return;
    }
    let now = Instant::now();
    for (id, (name, rssi)) in live {
        s.found.insert(id, Seen { name, rssi, at: now });
    }
    s.found.retain(|_, d| now.saturating_duration_since(d.at) <= SEEN_TTL);
}

impl DeviceProvider for MuseProvider {
    fn scheme(&self) -> &'static str {
        "muse"
    }
    fn list(&self) -> Vec<DeviceInfo> {
        let s = lock(&self.shared);
        let mut v: Vec<DeviceInfo> =
            s.found.iter().map(|(id, d)| DeviceInfo { rssi: Some(d.rssi), ..muse_info(&format!("muse:{id}"), &d.name) }).collect();
        v.sort_by(|a, b| a.id.cmp(&b.id));
        v
    }
    fn can_scan(&self) -> bool {
        true
    }
    fn last_error(&self) -> Option<String> {
        self.error()
    }
    fn scanning(&self) -> bool {
        lock(&self.shared).scanning
    }
    fn scan(&mut self, seconds: f64) -> Result<(), String> {
        self.begin(false, seconds)
    }
    fn watch(&mut self) -> Result<(), String> {
        self.begin(true, 8.0)
    }
    fn stop_scan(&mut self) {
        let mut s = lock(&self.shared);
        if s.scanning || s.hold {
            s.epoch = s.epoch.wrapping_add(1);
            s.hold = false;
            s.scanning = false;
        }
    }
    fn open(&mut self, id: &str) -> Result<Box<dyn DeviceSource>, String> {
        let ble = id.strip_prefix("muse:").unwrap_or(id);
        let name = lock(&self.shared)
            .found
            .get(ble)
            .map(|d| d.name.clone())
            .ok_or_else(|| format!("`{id}` not found; open the device window to scan"))?;
        // Discovery and a connect each need the adapter. Stop ours first; the
        // connect task waits until that client has called stop_scan.
        self.stop_scan();
        let rt = self.runtime()?;
        let (src, feed) = LiveSource::new(muse_info(id, &name));
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        let shared = self.shared.clone();
        rt.spawn(async move {
            let client = MuseClient::new(MuseClientConfig { name_prefix: name, enable_ppg: true, enable_aux: true, scan_timeout_secs: 10 });
            let conn = tokio::time::timeout(CONNECT_TIMEOUT, async {
                // Let the watch task drop its BlueZ discovery session.
                tokio::time::sleep(Duration::from_millis(400)).await;
                let (rx, handle) = client.connect().await?;
                handle.start(true, false).await?;
                anyhow::Ok((rx, handle))
            })
            .await;
            let (mut rx, handle) = match conn {
                Ok(Ok(x)) => x,
                Ok(Err(e)) => {
                    lock(&shared).error = Some(format!("connect: {e}"));
                    feed.link(LinkState::Lost { reason: format!("connect failed: {e}") });
                    return;
                }
                Err(_) => {
                    feed.link(LinkState::Lost { reason: "connect timed out".into() });
                    return;
                }
            };
            'run: while !stop2.load(Ordering::Relaxed) {
                match tokio::time::timeout(Duration::from_millis(250), rx.recv()).await {
                    Ok(Some(ev)) => {
                        for b in map_muse_event(ev) {
                            if !feed.send(b) {
                                break 'run;
                            }
                        }
                    }
                    Ok(None) => {
                        feed.link(LinkState::Lost { reason: "event stream ended".into() });
                        break;
                    }
                    Err(_) => {} // idle; re-check stop
                }
            }
            let _ = handle.disconnect().await;
        });
        Ok(Box::new(src.on_drop(move || stop.store(true, Ordering::Relaxed))))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use muse_rs::prelude::{EegReading, ImuData, PpgReading, TelemetryData, XyzSample};

    #[test]
    fn muse_events_map_to_blocks() {
        let eeg = |electrode| MuseEvent::Eeg(EegReading { index: 1, electrode, timestamp: 0.0, samples: vec![1.5; 12] });
        assert_eq!(map_muse_event(eeg(2)), vec![Block::Eeg(2, vec![1.5; 12])]);
        assert_eq!(map_muse_event(eeg(4)).len(), 1, "AUX1 is forwarded");
        assert!(map_muse_event(eeg(8)).is_empty(), "beyond AUX4 is dropped");
        let ppg = MuseEvent::Ppg(PpgReading { index: 1, ppg_channel: 1, timestamp: 0.0, samples: vec![70_000; 6] });
        assert_eq!(map_muse_event(ppg), vec![Block::Ppg(1, vec![70_000.0; 6])]);
        let xyz = XyzSample { x: 0.0, y: 0.1, z: 1.0 };
        let acc = MuseEvent::Accelerometer(ImuData { sequence_id: 0, samples: [xyz; 3] });
        assert_eq!(map_muse_event(acc), vec![Block::Accel(vec![[0.0, 0.1, 1.0]; 3])]);
        let tel = MuseEvent::Telemetry(TelemetryData { sequence_id: 0, battery_level: 81.5, fuel_gauge_voltage: 0.0, temperature: 0 });
        assert_eq!(map_muse_event(tel), vec![Block::Battery(81.5)]);
        assert!(matches!(map_muse_event(MuseEvent::Disconnected).as_slice(), [Block::Link(LinkState::Lost { .. })]));
    }

    #[test]
    fn only_muse_names_are_headsets() {
        assert!(is_muse_name("MuseS-6235"));
        assert!(is_muse_name("Muse-AB12"));
        assert!(!is_muse_name("QCY T13"));
    }
}
