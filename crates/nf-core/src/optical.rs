//! Athena optical (raw ADC) ring. Five minutes per lane at 64 Hz, like Raw EEG.
//! Never mixed with Classic PPG / HR / SpO2 ([`crate::optics`]).

use nf_types::{DeviceInfo, OpticsPacket};
use std::collections::VecDeque;

/// Seconds of optical history kept in memory (live, whether recording or not).
pub const BUFFER_S: f64 = 300.0;
/// Largest `optics.get` request (seconds).
pub const GET_MAX_S: f64 = 60.0;
pub const RATE_HZ: f64 = 64.0;

/// Lane labels used by muse-rs / OpenMuse indexes. Names, not wavelengths.
pub const LANE_NAMES: [&str; 16] = [
    "ambient", "infrared", "red", "opt3", "opt4", "opt5", "opt6", "opt7", "opt8", "opt9", "opt10", "opt11", "opt12", "opt13", "opt14",
    "opt15",
];

/// Lanes selected by a measured Athena preset. Unknown presets get 16 lanes.
pub fn names_for_preset(preset: &str) -> &'static [&'static str] {
    let n = match preset {
        "p1029" | "p102A" | "p1035" | "p1036" | "p1045" | "p1046" => 4,
        "p1027" | "p1028" | "p1033" | "p1034" | "p1043" | "p1044" => 8,
        _ => 16,
    };
    &LANE_NAMES[..n]
}

/// Rolling per-lane ADC counts.
#[derive(Debug, Clone)]
pub struct Optical {
    pub rate: f64,
    cap: usize,
    pub lanes: Vec<VecDeque<f32>>,
    last_t: Vec<Option<f64>>,
    pub time: Option<f64>,
}

impl Optical {
    pub fn new(info: &DeviceInfo) -> Option<Self> {
        let n = info.optics_channels.len();
        let rate = info.optics_rate_hz?;
        if n == 0 || !rate.is_finite() || rate <= 0.0 {
            return None;
        }
        let cap = (BUFFER_S * rate).ceil() as usize;
        Some(Self { rate, cap, lanes: vec![VecDeque::with_capacity(cap); n], last_t: vec![None; n], time: None })
    }

    pub fn push(&mut self, p: &OpticsPacket) {
        let i = usize::from(p.lane);
        let Some(buf) = self.lanes.get_mut(i) else { return };
        if p.samples.is_empty() {
            return;
        }
        for &s in &p.samples {
            if buf.len() == self.cap {
                buf.pop_front();
            }
            buf.push_back(s);
        }
        self.last_t[i] = Some(p.time);
        self.time = Some(self.time.map(|t| t.max(p.time)).unwrap_or(p.time));
    }

    pub fn channel_time(&self, i: usize) -> Option<f64> {
        self.last_t.get(i).copied().flatten()
    }

    /// Oldest and newest sample time across lanes.
    pub fn span(&self) -> Option<(f64, f64)> {
        let newest = self.time?;
        let n = self.lanes.iter().map(VecDeque::len).max().unwrap_or(0);
        if n == 0 {
            return None;
        }
        Some((newest - (n.saturating_sub(1) as f64) / self.rate, newest))
    }

    /// `need` samples ending `skip` samples before the lane's newest (newest last).
    pub fn slice(&self, lane: usize, skip: usize, need: usize) -> Vec<f32> {
        let Some(buf) = self.lanes.get(lane) else { return Vec::new() };
        let len = buf.len();
        let end = len.saturating_sub(skip);
        let start = end.saturating_sub(need);
        buf.iter().skip(start).take(end.saturating_sub(start)).copied().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use nf_types::{DeviceInfo, DeviceKind};

    fn info(n: usize) -> DeviceInfo {
        DeviceInfo {
            id: "sim:athena".into(),
            name: "t".into(),
            kind: DeviceKind::Muse,
            channels: vec!["TP9".into()],
            sample_rate_hz: 256.0,
            simulated: true,
            ppg_channels: Vec::new(),
            ppg_rate_hz: None,
            optics_channels: LANE_NAMES[..n].iter().map(|s| (*s).to_owned()).collect(),
            optics_rate_hz: Some(RATE_HZ),
            optics_preset: Some("p1041".into()),
            accel_rate_hz: None,
            aux_channels: Vec::new(),
            rssi: None,
        }
    }

    #[test]
    fn ring_keeps_five_minutes_and_slices() {
        let mut o = Optical::new(&info(16)).unwrap();
        assert_eq!(o.lanes.len(), 16);
        let rate = RATE_HZ;
        for i in 0..100 {
            let time = (i as f64 + 5.0) / rate;
            o.push(&OpticsPacket { time, lane: 0, samples: vec![i as f32; 6] });
        }
        assert!(o.span().is_some());
        let s = o.slice(0, 0, 6);
        assert_eq!(s.len(), 6);
        assert_eq!(s[5], 99.0);
        assert!(names_for_preset("p1041").len() == 16);
        assert!(names_for_preset("p1044").len() == 8);
        assert!(names_for_preset("p1045").len() == 4);
    }
}
