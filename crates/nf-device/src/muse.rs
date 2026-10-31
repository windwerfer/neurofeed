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
use std::time::Duration;

use muse_rs::prelude::{MuseClient, MuseClientConfig, MuseDevice, MuseEvent};
use tokio::runtime::Runtime;

use crate::{lock, muse_info, Block, DeviceInfo, DeviceProvider, DeviceSource, LinkState, LiveSource, MUSE_CHANNELS};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(18);

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

#[derive(Default)]
struct Shared {
    found: HashMap<String, MuseDevice>,
    scanning: bool,
    error: Option<String>,
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
}

impl DeviceProvider for MuseProvider {
    fn scheme(&self) -> &'static str {
        "muse"
    }
    fn list(&self) -> Vec<DeviceInfo> {
        let s = lock(&self.shared);
        let mut v: Vec<DeviceInfo> =
            s.found.values().map(|d| DeviceInfo { rssi: d.rssi, ..muse_info(&format!("muse:{}", d.id), &d.name) }).collect();
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
        let rt = self.runtime()?;
        {
            let mut s = lock(&self.shared);
            if s.scanning {
                return Ok(());
            }
            s.scanning = true;
            s.error = None;
        }
        let shared = self.shared.clone();
        let secs = seconds.clamp(1.0, 60.0).round() as u64;
        rt.spawn(async move {
            let client = MuseClient::new(MuseClientConfig { scan_timeout_secs: secs, enable_ppg: true, ..Default::default() });
            let r = client.scan_all().await;
            let mut s = lock(&shared);
            s.scanning = false;
            match r {
                // Only advertising devices (with RSSI), merged into the cache.
                Ok(devs) => devs.into_iter().filter(|d| d.rssi.is_some()).for_each(|d| {
                    s.found.insert(d.id.clone(), d);
                }),
                Err(e) => s.error = Some(format!("BLE scan: {e}")),
            }
        });
        Ok(())
    }
    fn open(&mut self, id: &str) -> Result<Box<dyn DeviceSource>, String> {
        let ble = id.strip_prefix("muse:").unwrap_or(id);
        let dev = lock(&self.shared).found.get(ble).cloned().ok_or_else(|| format!("`{id}` not found; run device.scan first"))?;
        let rt = self.runtime()?;
        let (src, feed) = LiveSource::new(muse_info(id, &dev.name));
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        let shared = self.shared.clone();
        rt.spawn(async move {
            let client = MuseClient::new(MuseClientConfig { enable_ppg: true, enable_aux: true, ..Default::default() });
            let conn = tokio::time::timeout(CONNECT_TIMEOUT, async {
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
}
