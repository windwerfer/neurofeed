//! Side streams for the monitors that are not EEG: Muse AUX inputs and the
//! accelerometer (Movement pane). Plain rolling buffers, frozen while paused.

use nf_types::{AccelPacket, DeviceInfo, EegPacket};
use std::collections::VecDeque;

/// Seconds kept for AUX and accelerometer traces.
pub const SIDE_S: f64 = 30.0;

#[derive(Debug, Clone, Default)]
pub struct Side {
    /// AUX channel names (`DeviceInfo::aux_channels`).
    pub aux_names: Vec<String>,
    /// Raw AUX samples (µV) per input.
    pub aux: Vec<VecDeque<f32>>,
    pub aux_rate: f64,
    /// (session time of the sample, x/y/z in g).
    pub accel: VecDeque<(f64, [f32; 3])>,
    pub accel_rate: Option<f64>,
    first_aux: usize,
}

impl Side {
    pub fn new(info: &DeviceInfo) -> Self {
        Self {
            aux_names: info.aux_channels.clone(),
            aux: vec![VecDeque::new(); info.aux_channels.len()],
            aux_rate: info.sample_rate_hz,
            accel: VecDeque::new(),
            accel_rate: info.accel_rate_hz,
            first_aux: info.channels.len(),
        }
    }

    /// AUX index of an EEG packet, `None` for an EEG electrode.
    pub fn aux_index(&self, p: &EegPacket) -> Option<usize> {
        usize::from(p.electrode).checked_sub(self.first_aux).filter(|k| *k < self.aux.len())
    }

    /// First AUX electrode index (= EEG channel count).
    pub fn aux_index_base(&self) -> usize {
        self.first_aux
    }

    pub fn push_aux(&mut self, k: usize, samples: &[f32]) {
        let cap = (SIDE_S * self.aux_rate) as usize;
        if let Some(b) = self.aux.get_mut(k) {
            b.extend(samples.iter().copied());
            let over = b.len().saturating_sub(cap);
            b.drain(..over);
        }
    }

    pub fn push_accel(&mut self, p: &AccelPacket) {
        let Some(rate) = self.accel_rate else { return };
        let n = p.samples.len();
        for (i, s) in p.samples.iter().enumerate() {
            self.accel.push_back((p.time - (n - 1 - i) as f64 / rate, *s));
        }
        let cap = (SIDE_S * rate) as usize;
        let over = self.accel.len().saturating_sub(cap);
        self.accel.drain(..over);
    }

    /// AUX inputs that delivered data.
    pub fn live_aux(&self) -> impl Iterator<Item = (&str, &VecDeque<f32>)> {
        self.aux_names.iter().map(String::as_str).zip(&self.aux).filter(|(_, b)| !b.is_empty())
    }
}
