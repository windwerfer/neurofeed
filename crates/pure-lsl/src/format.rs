//! Channel formats and the protocol 1.10 sample encoding.
//!
//! A sample on the wire is a tag byte (`1` = deduced timestamp, `2` =
//! transmitted timestamp followed by an `f64`), then the channel values in
//! the negotiated byte order (this crate always sends little endian).
//! Strings are length-prefixed: a byte giving the width of the length
//! (1, 4 or 8) and then the length itself.

use std::fmt;

const TAG_DEDUCED: u8 = 1;
const TAG_TRANSMITTED: u8 = 2;
/// Timestamp liblsl uses for its two handshake test samples.
pub(crate) const TEST_PATTERN_TIME: f64 = 123_456.789;

/// The value type every channel of a stream shares.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ChannelFormat {
    Float32,
    Double64,
    String,
    Int32,
    Int16,
    Int8,
    Int64,
}

impl ChannelFormat {
    /// Name used in the stream info XML.
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Float32 => "float32",
            Self::Double64 => "double64",
            Self::String => "string",
            Self::Int32 => "int32",
            Self::Int16 => "int16",
            Self::Int8 => "int8",
            Self::Int64 => "int64",
        }
    }

    /// Bytes per value; 0 for strings (variable length).
    #[must_use]
    pub fn value_size(self) -> usize {
        match self {
            Self::Float32 | Self::Int32 => 4,
            Self::Double64 | Self::Int64 => 8,
            Self::String => 0,
            Self::Int16 => 2,
            Self::Int8 => 1,
        }
    }
}

impl fmt::Display for ChannelFormat {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// A Rust type that can be one channel value.
pub trait Value: Clone + Send + 'static {
    const FORMAT: ChannelFormat;
    /// Append the little-endian wire form.
    fn encode(&self, out: &mut Vec<u8>);
}

macro_rules! numeric {
    ($($t:ty => $f:ident),*) => {$(
        impl Value for $t {
            const FORMAT: ChannelFormat = ChannelFormat::$f;
            fn encode(&self, out: &mut Vec<u8>) {
                out.extend_from_slice(&self.to_le_bytes());
            }
        }
    )*};
}
numeric!(f32 => Float32, f64 => Double64, i32 => Int32, i16 => Int16, i8 => Int8, i64 => Int64);

impl Value for String {
    const FORMAT: ChannelFormat = ChannelFormat::String;
    fn encode(&self, out: &mut Vec<u8>) {
        let n = self.len();
        if let Ok(b) = u8::try_from(n) {
            out.extend_from_slice(&[1, b]);
        } else if let Ok(w) = u32::try_from(n) {
            out.push(4);
            out.extend_from_slice(&w.to_le_bytes());
        } else {
            out.push(8);
            out.extend_from_slice(&(n as u64).to_le_bytes());
        }
        out.extend_from_slice(self.as_bytes());
    }
}

/// Encode one sample; `None` lets the receiver deduce the timestamp.
pub(crate) fn encode_sample<T: Value>(out: &mut Vec<u8>, timestamp: Option<f64>, values: &[T]) {
    match timestamp {
        Some(t) => {
            out.push(TAG_TRANSMITTED);
            out.extend_from_slice(&t.to_le_bytes());
        }
        None => out.push(TAG_DEDUCED),
    }
    for v in values {
        v.encode(out);
    }
}

/// liblsl's handshake test pattern: channel `k` holds `k + offset + base`,
/// negated on odd channels (integers wrap at the type's max).
fn pattern(k: u64, offset: u64, base: u64, max: u64) -> (u64, bool) {
    let v = k + offset + base;
    (if max == 0 { v } else { v % max }, k % 2 == 1)
}

/// The test sample (offsets 4 and 2 are sent before any data).
pub(crate) fn encode_test_pattern(out: &mut Vec<u8>, format: ChannelFormat, channels: usize, offset: u64) {
    out.push(TAG_TRANSMITTED);
    out.extend_from_slice(&TEST_PATTERN_TIME.to_le_bytes());
    for k in 0..channels as u64 {
        test_value(out, format, k, offset);
    }
}

fn test_value(out: &mut Vec<u8>, format: ChannelFormat, k: u64, offset: u64) {
    macro_rules! int {
        ($t:ty, $base:expr) => {{
            let (v, neg) = pattern(k, offset, $base, <$t>::MAX as u64);
            let v = v as $t;
            out.extend_from_slice(&(if neg { v.wrapping_neg() } else { v }).to_le_bytes());
        }};
    }
    match format {
        ChannelFormat::Float32 => {
            let (v, neg) = pattern(k, offset, 0, 0);
            let v = v as f32;
            out.extend_from_slice(&(if neg { -v } else { v }).to_le_bytes());
        }
        ChannelFormat::Double64 => {
            let (v, neg) = pattern(k, offset, 16_777_217, 0);
            let v = v as f64;
            out.extend_from_slice(&(if neg { -v } else { v }).to_le_bytes());
        }
        ChannelFormat::Int32 => int!(i32, 65_537),
        ChannelFormat::Int16 => int!(i16, 257),
        ChannelFormat::Int8 => int!(i8, 1),
        ChannelFormat::Int64 => {
            let v = (k + offset + 2_147_483_649) as i64;
            out.extend_from_slice(&(if k % 2 == 1 { -v } else { v }).to_le_bytes());
        }
        ChannelFormat::String => {
            // liblsl ignores the offset for strings: (k + 10), negated on odd k.
            let v = (k as i64 + 10) * if k.is_multiple_of(2) { 1 } else { -1 };
            v.to_string().encode(out);
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn float_sample_layout() {
        let mut b = Vec::new();
        encode_sample(&mut b, Some(1.5), &[1.0f32, -2.0]);
        assert_eq!(b[0], 2);
        assert_eq!(&b[1..9], &1.5f64.to_le_bytes());
        assert_eq!(&b[9..13], &1.0f32.to_le_bytes());
        assert_eq!(b.len(), 17);
        let mut d = Vec::new();
        encode_sample(&mut d, None, &[7i16]);
        assert_eq!(d, vec![1, 7, 0]);
    }

    #[test]
    fn strings_are_length_prefixed() {
        let mut b = Vec::new();
        encode_sample(&mut b, None, &["hi".to_string(), "x".repeat(300)]);
        assert_eq!(&b[..5], &[1, 1, 2, b'h', b'i']);
        assert_eq!(&b[5..10], &[4, 44, 1, 0, 0]);
        assert_eq!(b.len(), 10 + 300);
    }

    #[test]
    fn test_pattern_matches_liblsl() {
        let mut b = Vec::new();
        encode_test_pattern(&mut b, ChannelFormat::Int16, 3, 4);
        let vals: Vec<i16> = b[9..].chunks(2).map(|c| i16::from_le_bytes([c[0], c[1]])).collect();
        assert_eq!(vals, vec![261, -262, 263]);
        let mut f = Vec::new();
        encode_test_pattern(&mut f, ChannelFormat::Float32, 2, 2);
        assert_eq!(&f[9..13], &2.0f32.to_le_bytes());
        assert_eq!(&f[13..17], &(-3.0f32).to_le_bytes());
        let mut s = Vec::new();
        encode_test_pattern(&mut s, ChannelFormat::String, 2, 4);
        assert_eq!(&s[9..], &[1, 2, b'1', b'0', 1, 3, b'-', b'1', b'1']);
    }
}
