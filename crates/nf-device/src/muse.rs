//! Muse over Bluetooth LE via muse-rs + btleplug (ported from
//! `rust/src/api/muse.rs`). A private tokio runtime runs scan and connect in
//! the background; `scan`/`open` never block the caller.
//!
//! Athena optical data arrives as [`Block::Optics`] (never Classic PPG).
//! AUX inputs arrive as electrodes 4.. (shown / recorded only when Settings asks).

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use btleplug::api::{Central, Manager as _, Peripheral as _, ScanFilter};
use btleplug::platform::Manager;
use muse_rs::prelude::{MuseClient, MuseClientConfig, MuseEvent};
use tokio::runtime::Runtime;

use crate::{lock, muse_info, Block, DeviceInfo, DeviceProvider, DeviceSource, LinkState, LiveSource, MUSE_CHANNELS};

const OPTICS_LANES: [&str; 16] = [
    "ambient", "infrared", "red", "opt3", "opt4", "opt5", "opt6", "opt7", "opt8", "opt9", "opt10", "opt11", "opt12", "opt13", "opt14",
    "opt15",
];

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
    /// BLE ids with a link opened by this process.
    linked: HashSet<String>,
}

fn athena_info(ble_id: &str, name: &str, preset: &str) -> DeviceInfo {
    let n = match preset {
        "p1029" | "p102A" | "p1035" | "p1036" | "p1045" | "p1046" => 4,
        "p1027" | "p1028" | "p1033" | "p1034" | "p1043" | "p1044" => 8,
        _ => 16,
    };
    let mut info = muse_info(&format!("muse:{ble_id}"), name);
    info.ppg_channels.clear();
    info.ppg_rate_hz = None;
    info.optics_channels = OPTICS_LANES[..n].iter().map(|s| (*s).to_owned()).collect();
    info.optics_rate_hz = Some(64.0);
    info.optics_preset = Some(preset.to_owned());
    info
}

/// Translate one muse-rs event into feed blocks.
pub fn map_muse_event(ev: MuseEvent) -> Vec<Block> {
    match ev {
        MuseEvent::Eeg(r) if r.electrode < MUSE_CHANNELS.len() + crate::MUSE_AUX.len() => {
            vec![Block::Eeg(r.electrode as u16, r.samples.iter().map(|&x| x as f32).collect())]
        }
        MuseEvent::Ppg(r) if r.ppg_channel < 3 => vec![Block::Ppg(r.ppg_channel as u16, r.samples.iter().map(|&x| x as f32).collect())],
        MuseEvent::Optics(r) => vec![Block::Optics(r.lane as u16, r.samples.iter().map(|&x| x as f32).collect())],
        MuseEvent::Accelerometer(imu) => vec![Block::Accel(imu.samples.iter().map(|s| [s.x, s.y, s.z]).collect())],
        MuseEvent::Disconnected => vec![Block::Link(LinkState::Lost { reason: "headset disconnected".into() })],
        _ => Vec::new(),
    }
}

/// How often the open task asks for a status (`s`) so `bp` stays fresh.
const STATUS_EVERY: Duration = Duration::from_secs(60);

/// Picks the battery reading for one connection. The Control JSON `bp` field
/// is authoritative; telemetry is only used while no `bp` was seen and its
/// fuel gauge is plausible (muse-rs decodes Muse S classic telemetry wrongly:
/// raw 417/512 = 0.81 "percent" with a 91619 mV gauge).
#[derive(Default)]
struct BatterySource {
    control_seen: bool,
}

impl BatterySource {
    fn pick(&mut self, ev: &MuseEvent) -> Option<f32> {
        match ev {
            MuseEvent::Control(c) => {
                let bp = c.fields.get("bp").and_then(|v| v.as_f64()).filter(|b| (0.0..=100.0).contains(b))?;
                self.control_seen = true;
                Some(bp as f32)
            }
            MuseEvent::Telemetry(t)
                if !self.control_seen && (3000.0..=4500.0).contains(&t.fuel_gauge_voltage) && (0.0..=100.0).contains(&t.battery_level) =>
            {
                Some(t.battery_level)
            }
            _ => None,
        }
    }
}

/// Name for a connect: the scanned name, else the generic `Muse` prefix so a
/// `device.connect` right after `device.scan` still works (the connect task
/// rescans by BLE id anyway).
fn connect_name(found: Option<&str>) -> String {
    found.map_or_else(|| "Muse".to_owned(), str::to_owned)
}

/// Muse provider (`muse:<ble id>`).
#[derive(Default)]
pub struct MuseProvider {
    rt: OnceLock<Result<Arc<Runtime>, String>>,
    shared: Arc<Mutex<Shared>>,
    /// One per opened headset until its BLE link is closed (app exit waits).
    tasks: crate::Tasks,
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
        let ours = lock(shared).linked.clone();
        release_stale(&adapter, &ours).await;
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

/// A Muse the OS still holds connected without a link of ours: left over from
/// a process that exited without disconnecting. It does not advertise, so it
/// can never be found again until that link is dropped.
fn is_stale(name: Option<&str>, service: bool, connected: bool, ours: bool) -> bool {
    connected && !ours && (service || name.is_some_and(is_muse_name))
}

/// Disconnect stale Muse links (see [`is_stale`]) before scanning.
async fn release_stale(adapter: &btleplug::platform::Adapter, ours: &HashSet<String>) {
    let Ok(peripherals) = adapter.peripherals().await else { return };
    for p in peripherals {
        let connected = p.is_connected().await.unwrap_or(false);
        if !connected {
            continue;
        }
        let Ok(Some(props)) = p.properties().await else { continue };
        let id = p.id().to_string();
        let service = props.services.iter().any(|u| u.as_u128() == MUSE_SERVICE);
        if is_stale(props.local_name.as_deref(), service, connected, ours.contains(&id)) {
            log::info!("BLE {id} ({:?}) is still connected without a NeuroFeed link; disconnecting it", props.local_name);
            match tokio::time::timeout(Duration::from_secs(3), p.disconnect()).await {
                Ok(Ok(())) => {}
                Ok(Err(e)) => log::warn!("BLE {id}: stale disconnect: {e}"),
                Err(_) => log::warn!("BLE {id}: stale disconnect timed out"),
            }
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

/// Removes a BLE id from [`Shared::linked`] when its connect task ends.
struct Unlink(Arc<Mutex<Shared>>, String);

impl Drop for Unlink {
    fn drop(&mut self) {
        lock(&self.0).linked.remove(&self.1);
    }
}

impl DeviceProvider for MuseProvider {
    fn shutdown(&mut self, timeout_s: f64) -> Result<(), String> {
        self.stop_scan();
        let timeout = Duration::from_secs_f64(timeout_s.clamp(0.0, 60.0));
        if self.tasks.wait_idle(timeout) {
            return Ok(());
        }
        Err(format!("{} Muse link(s) still closing after {timeout_s:.0} s", self.tasks.live()))
    }
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
        if ble.is_empty() {
            return Err(format!("`{id}`: missing BLE id"));
        }
        let name = connect_name(lock(&self.shared).found.get(ble).map(|d| d.name.as_str()));
        // Discovery and a connect each need the adapter. Stop ours first; the
        // connect task waits until that client has called stop_scan.
        self.stop_scan();
        let rt = self.runtime()?;
        let ble_id = ble.to_owned();
        let (src, feed) = LiveSource::new(muse_info(id, &name));
        let preset_slot = src.preset_slot();
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        let shared = self.shared.clone();
        let guard = self.tasks.enter();
        lock(&self.shared).linked.insert(ble.to_owned());
        rt.spawn(async move {
            let _guard = guard; // released after the disconnect below
            let _linked = Unlink(shared.clone(), ble_id.clone());
            let client = MuseClient::new(MuseClientConfig {
                name_prefix: connect_prefix(&name),
                enable_ppg: true,
                enable_aux: true,
                scan_timeout_secs: CONNECT_SCAN_SECS,
                ..Default::default()
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
            if handle.is_athena {
                feed.info(athena_info(&ble_id, &name, "p1041"));
            }
            let mut battery = BatterySource::default();
            let mut last_status = tokio::time::Instant::now();
            'run: while !stop2.load(Ordering::Relaxed) {
                let pending = preset_slot.lock().unwrap_or_else(|e| e.into_inner()).take();
                if let Some(preset) = pending {
                    if let Err(e) = handle.set_athena_preset(&preset).await {
                        log::warn!("muse: set Athena preset {preset}: {e}");
                    } else {
                        feed.info(athena_info(&ble_id, &name, &preset));
                    }
                }
                if last_status.elapsed() >= STATUS_EVERY {
                    last_status = tokio::time::Instant::now();
                    if let Err(e) = handle.send_command("s").await {
                        log::debug!("muse: status request: {e}");
                    }
                }
                match tokio::time::timeout(Duration::from_millis(250), rx.recv()).await {
                    Ok(Some(ev)) => {
                        let pct = battery.pick(&ev);
                        for b in pct.map(Block::Battery).into_iter().chain(map_muse_event(ev)) {
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
            // Halt streaming, then drop the BLE link, so the headset does not
            // keep believing it is connected (and stops advertising).
            let step = Duration::from_secs(3);
            if tokio::time::timeout(step, handle.pause()).await.is_err() {
                log::warn!("muse: halt timed out");
            }
            match tokio::time::timeout(step, handle.disconnect()).await {
                Ok(Ok(())) => log::debug!("muse: disconnected"),
                Ok(Err(e)) => log::warn!("muse: disconnect: {e}"),
                Err(_) => log::warn!("muse: disconnect timed out"),
            }
        });
        Ok(Box::new(src.on_drop(move || stop.store(true, Ordering::Relaxed))))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use muse_rs::prelude::{EegReading, ImuData, PpgReading, TelemetryData, XyzSample};

    fn control(raw: &str) -> MuseEvent {
        let fields = serde_json::from_str::<serde_json::Value>(raw).unwrap().as_object().unwrap().clone();
        MuseEvent::Control(muse_rs::types::ControlResponse { raw: raw.into(), fields })
    }

    #[test]
    fn control_bp_wins_and_garbage_telemetry_is_ignored() {
        // Real MuseS-6235 (classic firmware): bp 64 (Mind Monitor ~65 %).
        let json = r#"{"hn":"MuseS-6235","bp":64,"ps":80}"#;
        let tel =
            || MuseEvent::Telemetry(TelemetryData { sequence_id: 0, battery_level: 0.8145, fuel_gauge_voltage: 91619.0, temperature: 0 });
        let mut b = BatterySource::default();
        assert_eq!(b.pick(&tel()), None, "implausible gauge before bp");
        assert_eq!(b.pick(&control(json)), Some(64.0));
        assert_eq!(b.pick(&tel()), None);
        assert_eq!(b.pick(&control(r#"{"rc":0}"#)), None, "no bp, no reading");
        let ok = || MuseEvent::Telemetry(TelemetryData { sequence_id: 1, battery_level: 70.0, fuel_gauge_voltage: 3900.0, temperature: 0 });
        assert_eq!(b.pick(&ok()), None, "bp seen: telemetry never wins");
        assert_eq!(BatterySource::default().pick(&ok()), Some(70.0), "plausible telemetry without bp");
    }

    #[test]
    fn connect_without_list_uses_generic_name() {
        assert_eq!(connect_name(None), "Muse");
        assert_eq!(connect_prefix(&connect_name(None)), "Muse");
        assert_eq!(connect_name(Some("MuseS-6235")), "MuseS-6235");
    }

    #[test]
    fn only_foreign_connected_muses_are_stale() {
        assert!(is_stale(Some("Muse-1234"), false, true, false));
        assert!(is_stale(None, true, true, false), "service only");
        assert!(!is_stale(Some("Muse-1234"), false, true, true), "our own link");
        assert!(!is_stale(Some("Muse-1234"), false, false, false), "not connected");
        assert!(!is_stale(Some("JBL Flip"), false, true, false), "not a Muse");
    }

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
        assert!(map_muse_event(tel).is_empty(), "battery goes through BatterySource");
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
