//! NFED6 `.neurofeed` container:
//! `[68-byte header][WebP thumbnail][metadata JSON (zstd)][computed 1 Hz JSONL (zstd)][raw body]`.
//!
//! Header: magic `b"NFED6\0"`, version u8 = 6, flags u8, then u64 LE
//! thumbnail offset/len, metadata offset/len, computed offset/len, raw offset,
//! then crc32 of bytes 0..64. Raw length = file length − raw offset.

use crate::{err, zstd_compress, zstd_decompress, FormatError};

pub const V6_MAGIC: [u8; 6] = *b"NFED6\0";
pub const V6_VERSION: u8 = 6;
pub const HEADER_SIZE: usize = 68;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ContainerHeader {
    pub thumbnail_offset: u64,
    pub thumbnail_length: u64,
    pub metadata_offset: u64,
    pub metadata_length: u64,
    pub computed_offset: u64,
    pub computed_length: u64,
    pub raw_offset: u64,
}

/// Decoded container sections (metadata and computed are decompressed).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Container {
    pub thumbnail: Vec<u8>,
    pub metadata_json: Vec<u8>,
    /// Newline-separated JSON objects, one per second.
    pub computed_jsonl: Vec<u8>,
    /// NFEDBIN raw body (see [`crate::body`]).
    pub raw_body: Vec<u8>,
}

impl ContainerHeader {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut h = Vec::with_capacity(HEADER_SIZE);
        h.extend_from_slice(&V6_MAGIC);
        h.push(V6_VERSION);
        h.push(0);
        for v in [
            self.thumbnail_offset,
            self.thumbnail_length,
            self.metadata_offset,
            self.metadata_length,
            self.computed_offset,
            self.computed_length,
            self.raw_offset,
        ] {
            h.extend_from_slice(&v.to_le_bytes());
        }
        let crc = crc32fast::hash(&h);
        h.extend_from_slice(&crc.to_le_bytes());
        h
    }

    pub fn parse(bytes: &[u8]) -> Result<Self, FormatError> {
        let Some(h) = bytes.get(..HEADER_SIZE) else { return err("Truncated NFED6 container header") };
        if h[..6] != V6_MAGIC {
            return err("Not an NFED6 container (bad magic)");
        }
        if h[6] != V6_VERSION {
            return err(format!("Unsupported NFED format version {}", h[6]));
        }
        if crc32fast::hash(&h[..64]).to_le_bytes() != h[64..68] {
            return err("container header CRC32 mismatch");
        }
        let u = |i: usize| {
            let mut b = [0u8; 8];
            b.copy_from_slice(&h[8 + 8 * i..16 + 8 * i]);
            u64::from_le_bytes(b)
        };
        Ok(Self {
            thumbnail_offset: u(0),
            thumbnail_length: u(1),
            metadata_offset: u(2),
            metadata_length: u(3),
            computed_offset: u(4),
            computed_length: u(5),
            raw_offset: u(6),
        })
    }
}

pub fn encode_container(c: &Container) -> Vec<u8> {
    let meta = zstd_compress(&c.metadata_json);
    let computed = zstd_compress(&c.computed_jsonl);
    let thumbnail_offset = HEADER_SIZE as u64;
    let metadata_offset = thumbnail_offset + c.thumbnail.len() as u64;
    let computed_offset = metadata_offset + meta.len() as u64;
    let raw_offset = computed_offset + computed.len() as u64;
    let header = ContainerHeader {
        thumbnail_offset,
        thumbnail_length: c.thumbnail.len() as u64,
        metadata_offset,
        metadata_length: meta.len() as u64,
        computed_offset,
        computed_length: computed.len() as u64,
        raw_offset,
    };
    let mut out = header.to_bytes();
    for part in [&c.thumbnail, &meta, &computed, &c.raw_body] {
        out.extend_from_slice(part);
    }
    out
}

fn section(bytes: &[u8], off: u64, len: u64, name: &str) -> Result<Vec<u8>, FormatError> {
    let start = usize::try_from(off).map_err(|_| FormatError(format!("{name}: offset overflow")))?;
    let end = start.checked_add(usize::try_from(len).unwrap_or(usize::MAX));
    match end.and_then(|e| bytes.get(start..e)) {
        Some(s) => Ok(s.to_vec()),
        None => err(format!("{name} section out of bounds")),
    }
}

fn unzstd(b: Vec<u8>) -> Result<Vec<u8>, FormatError> {
    if b.is_empty() {
        Ok(b)
    } else {
        zstd_decompress(&b)
    }
}

pub fn decode_container(bytes: &[u8]) -> Result<Container, FormatError> {
    let h = ContainerHeader::parse(bytes)?;
    let raw_start = usize::try_from(h.raw_offset).unwrap_or(usize::MAX);
    let Some(raw) = bytes.get(raw_start..) else { return err("raw section out of bounds") };
    Ok(Container {
        thumbnail: section(bytes, h.thumbnail_offset, h.thumbnail_length, "thumbnail")?,
        metadata_json: unzstd(section(bytes, h.metadata_offset, h.metadata_length, "metadata")?)?,
        computed_jsonl: unzstd(section(bytes, h.computed_offset, h.computed_length, "computed")?)?,
        raw_body: raw.to_vec(),
    })
}
