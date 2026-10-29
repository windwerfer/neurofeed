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

#[derive(Debug, Clone, PartialEq)]
pub enum Record {
    Eeg { ts: f64, electrode: i16, samples: Vec<f32> },
    Telemetry { ts: f64, battery: f32, fuel: f32, temp: u16 },
    Accelerometer { ts: f64, seq: u16, xyz: Vec<[f32; 3]> },
    Gyroscope { ts: f64, seq: u16, xyz: Vec<[f32; 3]> },
    Ppg { ts: f64, channel: i16, samples: Vec<f32> },
    Bands { ts: f64, electrode: i16, bands: [f32; 5] },
    Pulse { ts: f64, bpm: f32, confidence: f32 },
    Movement { ts: f64, score: f32 },
    PeakAlpha { ts: f64, frequency: f32, power: f32 },
    SpO2 { ts: f64, spo2: f32, confidence: f32 },
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
