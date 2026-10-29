use crate::record::{decode_records, Record};
use crate::{err, zstd_compress, zstd_decompress, FormatError};

/// On-disk bytes of the u64 LE sentinel `0x4E46_4544_4249_4E0A`.
pub const HEADER_MAGIC_BYTES: [u8; 8] = 0x4E46_4544_4249_4E0A_u64.to_le_bytes();
/// NFEDBIN raw-body wire version (not the NFED6 container version).
pub const FORMAT_VERSION: u32 = 5;

/// Streaming NFEDBIN writer: buffer records, `flush_frame` compresses them
/// into one `[u32 len][zstd frame]`. The legacy recorder flushed about once
/// a second; callers choose.
#[derive(Debug, Clone)]
pub struct BodyWriter {
    out: Vec<u8>,
    pending: Vec<u8>,
}

impl Default for BodyWriter {
    fn default() -> Self {
        Self::new()
    }
}

impl BodyWriter {
    pub fn new() -> Self {
        let mut out = HEADER_MAGIC_BYTES.to_vec();
        out.extend_from_slice(&FORMAT_VERSION.to_le_bytes());
        Self { out, pending: Vec::new() }
    }

    pub fn push(&mut self, r: &Record) {
        r.encode(&mut self.pending);
    }

    /// Bytes written so far (header + flushed frames + pending records).
    pub fn len(&self) -> usize {
        self.out.len() + self.pending.len()
    }

    /// Never true: the header is always present.
    pub fn is_empty(&self) -> bool {
        false
    }

    pub fn pending_bytes(&self) -> usize {
        self.pending.len()
    }

    pub fn flush_frame(&mut self) {
        if self.pending.is_empty() {
            return;
        }
        let frame = zstd_compress(&self.pending);
        self.out.extend_from_slice(&u32::try_from(frame.len()).unwrap_or(u32::MAX).to_le_bytes());
        self.out.extend_from_slice(&frame);
        self.pending.clear();
    }

    /// Flush and return the complete body.
    pub fn finish(mut self) -> Vec<u8> {
        self.flush_frame();
        self.out
    }
}

/// Decode a raw body. A truncated trailing frame is ignored and an
/// undecodable frame is skipped (crash-tolerant, as in the legacy reader).
pub fn parse_body(bytes: &[u8]) -> Result<Vec<Record>, FormatError> {
    let Some((head, mut rest)) = bytes.split_first_chunk::<12>() else {
        return err("Truncated raw-body header");
    };
    if head[..8] != HEADER_MAGIC_BYTES {
        return err("Not a NeuroFeed raw body");
    }
    let version = u32::from_le_bytes([head[8], head[9], head[10], head[11]]);
    if version != FORMAT_VERSION {
        return err(format!("Unsupported format version {version}"));
    }
    let mut out = Vec::new();
    while let Some((len, tail)) = rest.split_first_chunk::<4>() {
        let n = u32::from_le_bytes(*len) as usize;
        let Some(frame) = tail.get(..n) else { break };
        rest = &tail[n..];
        if let Ok(d) = zstd_decompress(frame) {
            out.extend(decode_records(&d));
        }
    }
    Ok(out)
}
