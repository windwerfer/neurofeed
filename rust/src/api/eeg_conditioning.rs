//! EEG conditioning for Dart: the live stream's mains decisions (recording
//! metadata) and offline conditioning of recorded RAW (History charts,
//! imports) with the exact live rules.

use flutter_rust_bridge::frb;

use crate::analysis::eeg_filter::{self, Mains};
use crate::api::session_format::EegSampleRecord;

/// One mains decision: `notch_hz` 50 / 60, or null when no hum was found.
pub struct NotchDecision {
    pub timestamp_ms: f64,
    pub notch_hz: Option<f64>,
}

/// Conditioning applied to EEG before quality, bands, features and charts.
pub struct EegConditioning {
    pub high_pass_hz: f64,
    pub notch_q: f64,
    pub decisions: Vec<NotchDecision>,
}

pub struct ConditionedEeg {
    pub eeg: Vec<EegSampleRecord>,
    pub conditioning: EegConditioning,
}

fn conditioning(decisions: &[(f64, Mains)]) -> EegConditioning {
    EegConditioning {
        high_pass_hz: eeg_filter::HIGHPASS_HZ,
        notch_q: eeg_filter::NOTCH_Q,
        decisions: decisions
            .iter()
            .map(|(ts, m)| NotchDecision {
                timestamp_ms: *ts,
                notch_hz: m.notch_hz(),
            })
            .collect(),
    }
}

/// Mains decisions of the current connection so far.
#[frb(sync)]
pub fn live_eeg_conditioning() -> EegConditioning {
    conditioning(&eeg_filter::live_decisions())
}

/// Condition recorded EEG records (file order) exactly like the live
/// stream. Records keep their order, electrode, timestamp and length.
#[frb(sync)]
pub fn condition_eeg(eeg: Vec<EegSampleRecord>) -> ConditionedEeg {
    let packets: Vec<(i32, f64, Vec<f64>)> = eeg
        .iter()
        .map(|r| {
            (
                r.electrode as i32,
                r.timestamp,
                r.samples.iter().map(|&v| v as f64).collect(),
            )
        })
        .collect();
    let (out, decisions) = eeg_filter::condition_packets(&packets);
    ConditionedEeg {
        eeg: eeg
            .into_iter()
            .zip(out)
            .map(|(r, samples)| EegSampleRecord {
                timestamp: r.timestamp,
                electrode: r.electrode,
                samples: samples.into_iter().map(|v| v as f32).collect(),
            })
            .collect(),
        conditioning: conditioning(&decisions),
    }
}
