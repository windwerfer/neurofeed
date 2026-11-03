//! Muse over Bluetooth LE via muse-rs + btleplug (ported from
//! `rust/src/api/muse.rs`). A private tokio runtime runs scan and connect in
//! the background; `scan`/`open` never block the caller.
//!
//! Limits (same as the legacy app): Athena firmware streams EEG ch 0–3 but
//! its PPG is not decoded yet. AUX inputs arrive as electrodes 4.. (the
//! session shows / records them only when Settings asks for it).

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use btleplug::api::{Central, Manager as _, Peripheral as _, ScanFilter};
use btleplug::platform::Manager;
use muse_rs::prelude::{MuseClient, MuseClientConfig, MuseEvent};
use tokio::runtime::Runtime;

use crate::{lock, muse_info, Block, DeviceInfo, DeviceProvider, DeviceSource, LinkState, LiveSource, MUSE_CHANNELS};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(18);
/// Length of the rescan before connecting (muse-rs `scan_all` waits it out).
const CONNECT_SCAN_SECS: u64 = 4;
/// Drop a headset that has not advertised for this long while discovery is on.
/// Muses advertise about once a second; BlueZ may coalesce updates, so be generous.
const SEEN_TTL: Duration = Duration::from_secs(10);
/// Muse GATT service (0xFE8D), advertised by Muse 2, Muse S and Athena.
const MUSE_SERVICE: u128 = 0x0000fe8d_0000_1000_8000_00805f9b34fb;

/// Advertised name of a Muse headset: "Muse-AB12", "MuseS-6235", "Muse 2", ...
/// (case-insensitive; Athena advertises as a Muse S).
fn is_muse_name(name: &str) -> bool {
    name.trim_start().to_ascii_lowercase().starts_with("muse")
}

/// Decide whether one advertisement is a Muse worth listing; returns its
/// display name. `cached` = BlueZ already knew the device when the scan
/// started: without RSSI that is a stale cache entry, not a nearby headset.
fn classify(name: Option<&str>, service: bool, rssi: Option<i16>, cached: bool) -> Option<String> {
    let named = name.filter(|n| is_muse_name(n));
    if named.is_none() && !service {
        return None;
    }
    if rssi.is_none() && cached {
        return None;
    }
    // A Muse found by its service before its name arrived: "Muse" is also the
    // prefix muse-rs matches on connect.
    Some(named.unwrap_or("Muse").to_owned())
}

/// muse-rs filters its rescan by a case-sensitive name prefix; widen it to
/// whatever case the headset used, so the id match below does the choosing.
fn connect_prefix(name: &str) -> String {
    name.trim_start().chars().take(4).collect()
}

struct Seen {
    name: String,
    rssi: Option<i16>,
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

/// Scan on every adapter that starts, polling while discovery is active
/// (BlueZ drops `Device1.RSSI` once discovery stops).
async fn discover(shared: &Arc<Mutex<Shared>>, epoch: u64, limit: Duration) -> Result<(), String> {
    let manager = Manager::new().await.map_err(|e| e.to_string())?;
    let adapters = manager.adapters().await.map_err(|e| e.to_string())?;
    let mut active = Vec::new();
    let mut errors = Vec::new();
    for adapter in adapters {
        let label = adapter.adapter_info().await.unwrap_or_else(|_| "adapter".into());
        // Devices BlueZ already knows (paired, or seen earlier) before we scan.
        let cached: HashSet<String> = match adapter.peripherals().await {
            Ok(ps) => ps.iter().map(|p| p.id().to_string()).collect(),
            Err(_) => HashSet::new(),
        };
        match adapter.start_scan(ScanFilter::default()).await {
            Ok(()) => {
                log::debug!("BLE scan started on {label}");
                active.push((adapter, cached));
            }
            Err(e) => {
                log::warn!("BLE scan on {label}: {e}");
                errors.push(format!("{label}: {e}"));
            }
        }
    }
    if active.is_empty() {
        return Err(if errors.is_empty() { "No Bluetooth adapter found".into() } else { errors.join("; ") });
    }
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
        let mut live = HashMap::new();
        for (adapter, cached) in &active {
            harvest(adapter, cached, &mut live).await;
        }
        record(shared, epoch, live, Instant::now());
        tokio::time::sleep(Duration::from_millis(400)).await;
    }
    for (adapter, _) in &active {
        adapter.stop_scan().await.ok();
    }
    let mut s = lock(shared);
    if s.epoch == epoch {
        s.scanning = false;
        s.hold = false;
    }
    Ok(())
}

/// Collect the Muses one adapter sees right now (id -> name, rssi).
async fn harvest(adapter: &btleplug::platform::Adapter, cached: &HashSet<String>, live: &mut HashMap<String, (String, Option<i16>)>) {
    let Ok(peripherals) = adapter.peripherals().await else { return };
    for p in peripherals {
        let Ok(Some(props)) = p.properties().await else { continue };
        let id = p.id().to_string();
        let service = props.services.iter().any(|u| u.as_u128() == MUSE_SERVICE);
        let hit = classify(props.local_name.as_deref(), service, props.rssi, cached.contains(&id));
        log::debug!(
            "BLE adv id={id} name={:?} rssi={:?} services={} muse_service={service} cached={} -> {}",
            props.local_name,
            props.rssi,
            props.services.len(),
            cached.contains(&id),
            if hit.is_some() { "listed" } else { "ignored" }
        );
        if let Some(name) = hit {
            live.insert(id, (name, props.rssi));
        }
    }
}

/// Merge one poll into the found list and prune headsets gone quiet.
fn record(shared: &Arc<Mutex<Shared>>, epoch: u64, live: HashMap<String, (String, Option<i16>)>, now: Instant) {
    let mut s = lock(shared);
    if s.epoch != epoch {
        return;
    }
    for (id, (name, rssi)) in live {
        // Keep a real name once known; a later name-less poll must not reset it.
        let name = match s.found.get(&id) {
            Some(old) if name == "Muse" => old.name.clone(),
            _ => name,
        };
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
            s.found.iter().map(|(id, d)| DeviceInfo { rssi: d.rssi, ..muse_info(&format!("muse:{id}"), &d.name) }).collect();
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
        let ble_id = ble.to_owned();
        let (src, feed) = LiveSource::new(muse_info(id, &name));
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        let shared = self.shared.clone();
        rt.spawn(async move {
            let client = MuseClient::new(MuseClientConfig {
                name_prefix: connect_prefix(&name),
                enable_ppg: true,
                enable_aux: true,
                scan_timeout_secs: CONNECT_SCAN_SECS,
            });
            let conn = tokio::time::timeout(CONNECT_TIMEOUT, async {
                // Let the watch task drop its BlueZ discovery session.
                tokio::time::sleep(Duration::from_millis(400)).await;
                // muse-rs cannot adopt our btleplug peripheral, so rescan briefly
                // and pick the *selected* headset by its BLE id (not the first
                // one whose name matches).
                let devices = client.scan_all().await?;
                log::debug!("connect {ble_id}: rescan saw {:?}", devices.iter().map(|d| &d.id).collect::<Vec<_>>());
                let dev = devices.into_iter().find(|d| d.id == ble_id).ok_or_else(|| {
                    anyhow::anyhow!("{ble_id} not seen in a {CONNECT_SCAN_SECS} s rescan (out of range, or connected elsewhere?)")
                })?;
                let (rx, handle) = client.connect_to(dev).await?;
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
                    lock(&shared).error = Some(format!("connect: timed out after {} s", CONNECT_TIMEOUT.as_secs()));
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
        for n in ["MuseS-6235", "Muse-AB12", "Muse 2", "muse-s", "MUSE-AB12"] {
            assert!(is_muse_name(n), "{n}");
        }
        assert!(!is_muse_name("QCY T13"));
        assert_eq!(connect_prefix("MuseS-6235"), "Muse");
        assert_eq!(connect_prefix("MUSE-AB12"), "MUSE");
    }

    #[test]
    fn classify_keeps_late_names_and_missing_rssi() {
        assert_eq!(classify(Some("MuseS-6235"), false, None, false).as_deref(), Some("MuseS-6235"), "no RSSI is fine");
        assert_eq!(classify(None, true, Some(-60), false).as_deref(), Some("Muse"), "service before name");
        assert_eq!(classify(Some("QCY T13"), false, Some(-40), false), None);
        assert_eq!(classify(Some("Muse-AB12"), false, None, true), None, "stale BlueZ cache");
        assert_eq!(classify(Some("Muse-AB12"), false, Some(-70), true).as_deref(), Some("Muse-AB12"), "cached but advertising");
    }

    #[test]
    fn record_keeps_names_and_prunes_after_ttl() {
        let shared = Arc::new(Mutex::new(Shared::default()));
        let t0 = Instant::now();
        let poll = |name: &str, rssi| HashMap::from([("AA".to_owned(), (name.to_owned(), rssi))]);
        record(&shared, 0, poll("MuseS-1", Some(-50)), t0);
        record(&shared, 0, poll("Muse", None), t0 + Duration::from_secs(1));
        assert_eq!(lock(&shared).found["AA"].name, "MuseS-1");
        record(&shared, 0, HashMap::new(), t0 + Duration::from_secs(9));
        assert!(lock(&shared).found.contains_key("AA"), "within TTL");
        record(&shared, 0, HashMap::new(), t0 + Duration::from_secs(12));
        assert!(lock(&shared).found.is_empty());
        record(&shared, 7, poll("MuseS-1", None), t0);
        assert!(lock(&shared).found.is_empty(), "stale epoch ignored");
    }
}
