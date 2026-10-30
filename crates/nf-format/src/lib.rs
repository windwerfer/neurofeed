//! L1 NeuroFeed recording formats, ported from `rust/src/api/session_format.rs`
//! and wrapping `third_party/edf_export`:
//!
//! - [`record`]: the tagged little-endian record codec (tags 1–10).
//! - [`body`]: the NFEDBIN raw body (`magic, version 5, [u32 len][zstd frame]*`).
//! - [`container`]: the NFED6 `.neurofeed` container (68-byte header + sections).
//! - [`edf`]: EEG records → EDF+.
//!
//! Byte-for-byte compatible with files the Flutter app wrote. zstd is the
//! pure-Rust `ruzstd`, so the crate builds for WASM. No file system, no
//! clock: callers pass bytes and timestamps.

pub mod body;
pub mod container;
pub mod edf;
pub mod pdf;
pub mod record;

pub use body::{parse_body, BodyWriter};
pub use container::{decode_container, encode_container, Container, ContainerHeader};
pub use record::{feedback_flags, trust_bits, Record, TAG_FEEDBACK, TAG_TRUST};

/// Format errors carry a human-readable reason (they reach MCP clients).
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("{0}")]
pub struct FormatError(pub String);

pub(crate) fn err<T>(msg: impl Into<String>) -> Result<T, FormatError> {
    Err(FormatError(msg.into()))
}

pub(crate) fn zstd_compress(data: &[u8]) -> Vec<u8> {
    ruzstd::encoding::compress_to_vec(data, ruzstd::encoding::CompressionLevel::Fastest)
}

pub(crate) fn zstd_decompress(data: &[u8]) -> Result<Vec<u8>, FormatError> {
    use std::io::Read;
    let mut src = data;
    let mut dec = ruzstd::decoding::StreamingDecoder::new(&mut src).map_err(|e| FormatError(format!("zstd: {e}")))?;
    let mut out = Vec::new();
    dec.read_to_end(&mut out).map_err(|e| FormatError(format!("zstd: {e}")))?;
    Ok(out)
}
