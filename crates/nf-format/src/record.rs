//! Record tags (all sample payloads f32, timestamps f64, little-endian):
//!
//! | tag | record        | fields                                         |
//! |-----|---------------|------------------------------------------------|
//! | 1   | EEG           | ts f64, electrode i16, n u16, n × f32          |
//! | 2   | Telemetry     | ts f64, battery f32, fuel f32, temp u16        |
//! | 3/4 | Accel / Gyro  | ts f64, seq u16, n u16, n × (x y z f32)        |
//! | 5   | PPG           | ts f64, channel i16, n u16, n × f32            |
//! | 6   | Bands         | ts f64, electrode i16, δ θ α β γ f32           |
//! | 7   | Pulse         | ts f64, bpm f32, conf f32                      |
//! | 8   | Movement      | ts f64, score f32                              |
//! | 9   | PeakAlpha     | ts f64, freq f32, power f32                    |
//! | 10  | SpO2          | ts f64, spo2 f32, conf f32                     |
//! | 11  | Feedback      | ts f64, value f32, threshold f32, flags u16    |
//! | 12  | Trust         | ts f64, native pct thr_pct f32, bits u16       |
//! | 13  | Guard         | ts f64, value f32, line f32 (decision scale)   |
//! | 14  | Optics        | ts f64, lane i16, n u16, n × f32               |
//!
//! Tag 11 is new (not in the legacy app). Legacy readers stop at the first
//! unknown tag, so writers append all feedback records at the end of the
//! body; older readers then still see every other record.

pub const TAG_EEG: u8 = 1;
pub const TAG_TELEMETRY: u8 = 2;
pub const TAG_ACCELEROMETER: u8 = 3;
pub const TAG_GYROSCOPE: u8 = 4;
pub const TAG_PPG: u8 = 5;
pub const TAG_BANDS: u8 = 6;
pub const TAG_PULSE: u8 = 7;
pub const TAG_MOVEMENT: u8 = 8;
pub const TAG_PEAK_ALPHA: u8 = 9;
pub const TAG_SPO2: u8 = 10;
pub const TAG_FEEDBACK: u8 = 11;
pub const TAG_TRUST: u8 = 12;
pub const TAG_GUARD: u8 = 13;
pub const TAG_OPTICS: u8 = 14;

/// `Record::Trust` bits: dirty reason in the low 3 bits, then flags.
pub mod trust_bits {
    pub const DIRTY_MASK: u16 = 0b111;
    pub const DIRTY_MOVEMENT: u16 = 1;
    pub const DIRTY_BLINK: u16 = 2;
    pub const DIRTY_JAW: u16 = 3;
    pub const DIRTY_PADS: u16 = 4;
    /// No verdict: no usable feature this second (not an artifact).
    pub const DIRTY_NO_SIGNAL: u16 = 5;
    pub const HELD_BETA: u16 = 1 << 3;
    pub const HELD_DELTA: u16 = 1 << 4;
    pub const HELD_GUARD: u16 = 1 << 5;
    pub const HELD_NO_THRESHOLD: u16 = 1 << 6;
    pub const WARN: u16 = 1 << 7;
    pub const GUARD_CHIME: u16 = 1 << 8;
    pub const MUTED: u16 = 1 << 9;
    /// The protocol ran a guard lane this second.
    pub const HAS_GUARD: u16 = 1 << 10;
    /// The engine produced a reward verdict this second.
    pub const PRODUCED: u16 = 1 << 11;
}

/// `Record::Feedback` flag bits.
pub mod feedback_flags {
    pub const COUNTED: u16 = 1;
    pub const IN_TARGET: u16 = 1 << 1;
    pub const CHIME: u16 = 1 << 2;
    /// Artifact or no usable pad.
    pub const DIRTY: u16 = 1 << 3;
    /// Above threshold but withheld (inhibit/guard).
    pub const HELD_BACK: u16 = 1 << 4;
    pub const PAUSED: u16 = 1 << 5;
    pub const CALIBRATING: u16 = 1 << 6;
}

#[derive(Debug, Clone, PartialEq)]
pub enum Record {
    Eeg {
        ts: f64,
        electrode: i16,
        samples: Vec<f32>,
    },
    Telemetry {
        ts: f64,
        battery: f32,
        fuel: f32,
        temp: u16,
    },
    Accelerometer {
        ts: f64,
        seq: u16,
        xyz: Vec<[f32; 3]>,
    },
    Gyroscope {
        ts: f64,
        seq: u16,
        xyz: Vec<[f32; 3]>,
    },
    Ppg {
        ts: f64,
        channel: i16,
        samples: Vec<f32>,
    },
    /// Athena optical lane (raw ADC counts). Tag 14.
    Optics {
        ts: f64,
        lane: i16,
        samples: Vec<f32>,
    },
    Bands {
        ts: f64,
        electrode: i16,
        bands: [f32; 5],
    },
    Pulse {
        ts: f64,
        bpm: f32,
        confidence: f32,
    },
    Movement {
        ts: f64,
        score: f32,
    },
    PeakAlpha {
        ts: f64,
        frequency: f32,
        power: f32,
    },
    SpO2 {
        ts: f64,
        spo2: f32,
        confidence: f32,
    },
    /// One feedback second; `value`/`threshold` NaN when absent.
    Feedback {
        ts: f64,
        value: f32,
        threshold: f32,
        flags: u16,
    },
    /// Trust details of one feedback second (written after its `Feedback`):
    /// native feature, output percentile, threshold percentile (NaN when
    /// absent) and [`trust_bits`].
    Trust {
        ts: f64,
        native: f32,
        pct: f32,
        thr_pct: f32,
        bits: u16,
    },
    /// Drowsiness guard per feedback second (written after its `Trust`):
    /// value and warn line on the decision scale 0–100 (NaN when absent).
    Guard {
        ts: f64,
        value: f32,
        line: f32,
    },
}

fn len_u16(n: usize) -> u16 {
    u16::try_from(n).unwrap_or(u16::MAX)
}

impl Record {
    /// Append the encoded record. Blocks longer than `u16::MAX` samples are
    /// truncated to fit the length field (live packets are ≤ 12 samples).
    pub fn encode(&self, out: &mut Vec<u8>) {
        fn f32s(out: &mut Vec<u8>, v: &[f32]) {
            out.extend_from_slice(&len_u16(v.len()).to_le_bytes());
            for s in v.iter().take(usize::from(u16::MAX)) {
                out.extend_from_slice(&s.to_le_bytes());
            }
        }
        fn imu(out: &mut Vec<u8>, tag: u8, ts: f64, seq: u16, xyz: &[[f32; 3]]) {
            out.push(tag);
            out.extend_from_slice(&ts.to_le_bytes());
            out.extend_from_slice(&seq.to_le_bytes());
            out.extend_from_slice(&len_u16(xyz.len()).to_le_bytes());
            for v in xyz.iter().take(usize::from(u16::MAX)).flatten() {
                out.extend_from_slice(&v.to_le_bytes());
            }
        }
        let head = |out: &mut Vec<u8>, tag: u8, ts: f64| {
            out.push(tag);
            out.extend_from_slice(&ts.to_le_bytes());
        };
        match self {
            Record::Eeg { ts, electrode, samples } => {
                head(out, TAG_EEG, *ts);
                out.extend_from_slice(&electrode.to_le_bytes());
                f32s(out, samples);
            }
            Record::Telemetry { ts, battery, fuel, temp } => {
                head(out, TAG_TELEMETRY, *ts);
                for v in [battery, fuel] {
                    out.extend_from_slice(&v.to_le_bytes());
                }
                out.extend_from_slice(&temp.to_le_bytes());
            }
            Record::Accelerometer { ts, seq, xyz } => imu(out, TAG_ACCELEROMETER, *ts, *seq, xyz),
            Record::Gyroscope { ts, seq, xyz } => imu(out, TAG_GYROSCOPE, *ts, *seq, xyz),
            Record::Ppg { ts, channel, samples } => {
                head(out, TAG_PPG, *ts);
                out.extend_from_slice(&channel.to_le_bytes());
                f32s(out, samples);
            }
            Record::Optics { ts, lane, samples } => {
                head(out, TAG_OPTICS, *ts);
                out.extend_from_slice(&lane.to_le_bytes());
                f32s(out, samples);
            }
            Record::Bands { ts, electrode, bands } => {
                head(out, TAG_BANDS, *ts);
                out.extend_from_slice(&electrode.to_le_bytes());
                for v in bands {
                    out.extend_from_slice(&v.to_le_bytes());
                }
            }
            Record::Pulse { ts, bpm: a, confidence: b }
            | Record::PeakAlpha { ts, frequency: a, power: b }
            | Record::SpO2 { ts, spo2: a, confidence: b } => {
                let tag = match self {
                    Record::Pulse { .. } => TAG_PULSE,
                    Record::PeakAlpha { .. } => TAG_PEAK_ALPHA,
                    _ => TAG_SPO2,
                };
                head(out, tag, *ts);
                out.extend_from_slice(&a.to_le_bytes());
                out.extend_from_slice(&b.to_le_bytes());
            }
            Record::Feedback { ts, value, threshold, flags } => {
                head(out, TAG_FEEDBACK, *ts);
                out.extend_from_slice(&value.to_le_bytes());
                out.extend_from_slice(&threshold.to_le_bytes());
                out.extend_from_slice(&flags.to_le_bytes());
            }
            Record::Trust { ts, native, pct, thr_pct, bits } => {
                head(out, TAG_TRUST, *ts);
                for v in [native, pct, thr_pct] {
                    out.extend_from_slice(&v.to_le_bytes());
                }
                out.extend_from_slice(&bits.to_le_bytes());
            }
            Record::Guard { ts, value, line } => {
                head(out, TAG_GUARD, *ts);
                out.extend_from_slice(&value.to_le_bytes());
                out.extend_from_slice(&line.to_le_bytes());
            }
            Record::Movement { ts, score } => {
                head(out, TAG_MOVEMENT, *ts);
                out.extend_from_slice(&score.to_le_bytes());
            }
        }
    }
}

struct Reader<'a> {
    b: &'a [u8],
}

impl Reader<'_> {
    fn take<const N: usize>(&mut self) -> Option<[u8; N]> {
        let (h, t) = self.b.split_first_chunk::<N>()?;
        self.b = t;
        Some(*h)
    }
    fn u8(&mut self) -> Option<u8> {
        self.take::<1>().map(|b| b[0])
    }
    fn u16(&mut self) -> Option<u16> {
        self.take().map(u16::from_le_bytes)
    }
    fn i16(&mut self) -> Option<i16> {
        self.take().map(i16::from_le_bytes)
    }
    fn f32(&mut self) -> Option<f32> {
        self.take().map(f32::from_le_bytes)
    }
    fn f64(&mut self) -> Option<f64> {
        self.take().map(f64::from_le_bytes)
    }
    fn f32s(&mut self, n: usize) -> Option<Vec<f32>> {
        (0..n).map(|_| self.f32()).collect()
    }
    fn xyz(&mut self, n: usize) -> Option<Vec<[f32; 3]>> {
        (0..n).map(|_| Some([self.f32()?, self.f32()?, self.f32()?])).collect()
    }
    fn record(&mut self) -> Option<Record> {
        let tag = self.u8()?;
        let ts = self.f64()?;
        Some(match tag {
            TAG_EEG => {
                let electrode = self.i16()?;
                let n = self.u16()?;
                Record::Eeg { ts, electrode, samples: self.f32s(n.into())? }
            }
            TAG_TELEMETRY => Record::Telemetry { ts, battery: self.f32()?, fuel: self.f32()?, temp: self.u16()? },
            TAG_ACCELEROMETER | TAG_GYROSCOPE => {
                let seq = self.u16()?;
                let n = self.u16()?;
                let xyz = self.xyz(n.into())?;
                if tag == TAG_GYROSCOPE {
                    Record::Gyroscope { ts, seq, xyz }
                } else {
                    Record::Accelerometer { ts, seq, xyz }
                }
            }
            TAG_OPTICS => {
                let lane = self.i16()?;
                let n = self.u16()?;
                Record::Optics { ts, lane, samples: self.f32s(n.into())? }
            }
            TAG_PPG => {
                let channel = self.i16()?;
                let n = self.u16()?;
                Record::Ppg { ts, channel, samples: self.f32s(n.into())? }
            }
            TAG_BANDS => {
                let electrode = self.i16()?;
                let v = self.f32s(5)?;
                Record::Bands { ts, electrode, bands: [v[0], v[1], v[2], v[3], v[4]] }
            }
            TAG_PULSE => Record::Pulse { ts, bpm: self.f32()?, confidence: self.f32()? },
            TAG_MOVEMENT => Record::Movement { ts, score: self.f32()? },
            TAG_PEAK_ALPHA => Record::PeakAlpha { ts, frequency: self.f32()?, power: self.f32()? },
            TAG_SPO2 => Record::SpO2 { ts, spo2: self.f32()?, confidence: self.f32()? },
            TAG_FEEDBACK => Record::Feedback { ts, value: self.f32()?, threshold: self.f32()?, flags: self.u16()? },
            TAG_GUARD => Record::Guard { ts, value: self.f32()?, line: self.f32()? },
            TAG_TRUST => Record::Trust { ts, native: self.f32()?, pct: self.f32()?, thr_pct: self.f32()?, bits: self.u16()? },
            _ => return None,
        })
    }
}

/// Decode concatenated records. Like the legacy reader, stops at the first
/// unknown tag or truncated record and returns what was decoded so far.
pub fn decode_records(bytes: &[u8]) -> Vec<Record> {
    let mut r = Reader { b: bytes };
    std::iter::from_fn(|| r.record()).collect()
}
