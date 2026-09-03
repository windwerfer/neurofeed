use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Headset family (montage / features / Crown-start-refused).
/// Simulation is the `simulate` flag on connect, not a kind.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
#[frb(dart_metadata = ("freezed",))]
pub enum DeviceKind {
    Muse,
    Neurosity,
}

impl DeviceKind {
    pub fn is_muse(&self) -> bool {
        matches!(self, DeviceKind::Muse)
    }

    pub fn is_neurosity(&self) -> bool {
        matches!(self, DeviceKind::Neurosity)
    }
}

/// Device configuration — electrode layout, target electrodes for ATR, gate electrodes, enabled features
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceConfig {
    pub kind: DeviceKind,
    pub channel_count: usize,
    pub electrode_names: Vec<String>,
    /// Electrode indices (0-based) used for ATR reward computation
    pub target_electrodes: Vec<usize>,
    /// Electrode indices required for signal gate (calibration/playing)
    pub needed_electrodes: Vec<usize>,
    /// Minimum signal quality (0-100) for "good" electrode
    pub signal_good_threshold: f32,
    /// Minimum signal quality (0-100) for "critical" electrode (pause threshold)
    pub signal_critical_threshold: f32,
    /// Features enabled for this device
    pub features: DeviceFeatures,
    /// Sampling rate in Hz
    pub sampling_rate: u32,
    /// Has PPG sensor
    pub has_ppg: bool,
    /// Has IMU (accel/gyro)
    pub has_imu: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceFeatures {
    pub record: bool,
    pub reward: bool,
    pub guardrail: bool,
    pub gesture: bool,
}

impl Default for DeviceFeatures {
    fn default() -> Self {
        Self {
            record: true,
            reward: true,
            guardrail: false,
            gesture: false,
        }
    }
}

impl DeviceConfig {
    /// Muse S / Muse 2 (4 EEG, PPG, IMU)
    pub fn muse() -> Self {
        Self {
            kind: DeviceKind::Muse,
            channel_count: 4,
            electrode_names: vec!["TP9".into(), "AF7".into(), "AF8".into(), "TP10".into()],
            target_electrodes: vec![1, 2], // AF7, AF8
            needed_electrodes: vec![1, 2],
            signal_good_threshold: 80.0,
            signal_critical_threshold: 40.0,
            features: DeviceFeatures {
                record: true,
                reward: true,
                guardrail: true,
                gesture: true,
            },
            sampling_rate: 256,
            has_ppg: true,
            has_imu: true,
        }
    }

    /// Neurosity Crown (8 EEG, no PPG, IMU)
    pub fn neurosity_crown() -> Self {
        Self {
            kind: DeviceKind::Neurosity,
            channel_count: 8,
            electrode_names: vec![
                "CP3".into(),
                "C3".into(),
                "F5".into(),
                "PO3".into(),
                "PO4".into(),
                "F6".into(),
                "C4".into(),
                "CP4".into(),
            ],
            target_electrodes: vec![3, 4], // PO3, PO4 (posterior alpha)
            needed_electrodes: vec![3, 4],
            signal_good_threshold: 80.0,
            signal_critical_threshold: 40.0,
            features: DeviceFeatures {
                record: true,
                reward: true,
                guardrail: false, // parked
                gesture: false,   // parked
            },
            sampling_rate: 256,
            has_ppg: false,
            has_imu: true,
        }
    }

    /// Get config by kind
    pub fn for_kind(kind: DeviceKind) -> Self {
        match kind {
            DeviceKind::Muse => Self::muse(),
            DeviceKind::Neurosity => Self::neurosity_crown(),
        }
    }

    /// Get electrode index by name
    pub fn electrode_index(&self, name: &str) -> Option<usize> {
        self.electrode_names
            .iter()
            .position(|n| n.eq_ignore_ascii_case(name))
    }

    /// Check if electrode is usable (above threshold)
    pub fn is_usable(&self, quality: &[f32], electrode: usize) -> bool {
        electrode < quality.len() && quality[electrode] >= self.signal_good_threshold
    }

    /// Check if any needed electrode is usable
    pub fn has_needed_electrode(&self, quality: &[f32]) -> bool {
        self.needed_electrodes
            .iter()
            .any(|&i| self.is_usable(quality, i))
    }

    /// Check if all needed electrodes are good
    pub fn all_needed_good(&self, quality: &[f32]) -> bool {
        self.needed_electrodes
            .iter()
            .all(|&i| self.is_usable(quality, i))
    }

    /// Get target electrode values from a map
    pub fn target_values(&self, values: &HashMap<usize, f32>) -> Vec<f32> {
        self.target_electrodes
            .iter()
            .filter_map(|&i| values.get(&i).copied())
            .collect()
    }
}
