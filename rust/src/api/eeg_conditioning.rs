//! EEG conditioning for Dart: the live stream's notch (recording metadata),
//! the per-device saved mains decision, and offline conditioning of
//! recorded RAW (History charts, imports) with the live filter chain.

use flutter_rust_bridge::frb;

use crate::analysis::eeg_filter::{self, Mains};
use crate::api::session_format::EegSampleRecord;

/// Where a recording's notch came from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NotchSource {
    /// Mains detection of this connection (or a scan of the file).
    Detected,
    /// The device's last saved decision; detection had not decided yet.
    Saved,
    /// Neither: both 50 and 60 Hz notched.
    Undecided,
}

/// Conditioning applied to EEG before quality, bands, features and charts.
/// `notch_hz`: mains notched (harmonics implied): `[50]`, `[60]`, `[]` (no
/// hum) or `[50, 60]` (undecided).
#[derive(Debug, Clone)]
pub struct EegConditioning {
    pub high_pass_hz: f64,
    pub notch_q: f64,
    pub notch_hz: Vec<f64>,
    pub notch_source: NotchSource,
}

pub struct ConditionedEeg {
    pub eeg: Vec<EegSampleRecord>,
    pub conditioning: EegConditioning,
}

fn conditioning((mains, source): (Mains, NotchSource)) -> EegConditioning {
    EegConditioning {
        high_pass_hz: eeg_filter::HIGHPASS_HZ,
        notch_q: eeg_filter::NOTCH_Q,
        notch_hz: mains.notched_mains(),
        notch_source: source,
    }
}

/// Notch the live stream applies now: the recording lock while a recording
/// or session is written, else detection, else the saved decision.
#[frb(sync)]
pub fn live_eeg_conditioning() -> EegConditioning {
    conditioning(eeg_filter::recording_lock().unwrap_or_else(eeg_filter::live_notch))
}

/// Saved mains decision of the device being connected (`None`: nothing
/// saved). Seeds the live notch until detection decides.
#[frb(sync)]
pub fn set_saved_mains(notch_hz: Option<Vec<f64>>) {
    eeg_filter::set_saved_mains(notch_hz.map(|hz| Mains::from_notched(&hz)));
}

/// Live detection's decision (`[50]`, `[60]`, `[]`), `None` while
/// undecided. Dart saves it per device.
#[frb(sync)]
pub fn live_mains_decision() -> Option<Vec<f64>> {
    match eeg_filter::live_mains() {
        Mains::Unknown => None,
        m => Some(m.notched_mains()),
    }
}

/// Condition recorded EEG records (file order) like the live stream, with
/// one notch for the whole recording: the recording's `conditioning`, or
/// else one found by scanning the RAW. Records keep their order, electrode,
/// timestamp and length.
#[frb(sync)]
pub fn condition_eeg(eeg: Vec<EegSampleRecord>, conditioning: Option<EegConditioning>) -> ConditionedEeg {
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
    let notch = conditioning.as_ref().map(|c| Mains::from_notched(&c.notch_hz));
    let (out, mains) = eeg_filter::condition_packets(&packets, notch);
    let source = match mains {
        Mains::Unknown => NotchSource::Undecided,
        _ => NotchSource::Detected,
    };
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
        conditioning: conditioning.unwrap_or_else(|| self::conditioning((mains, source))),
    }
}
