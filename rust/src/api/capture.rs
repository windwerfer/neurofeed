//! FRB re-exports of the spine capture writer.

use flutter_rust_bridge::frb;

use crate::api::muse::MuseEventDto;
use crate::spine::capture;

/// Flush-boundary index entry: elapsed seconds from capture start and the
/// exclusive end offset of the inner zstd frame in the live `.raw`.
pub struct CaptureFlushEntry {
    pub elapsed_s: f64,
    pub end_offset: u64,
}

/// prefix: "tmp" | "recording" | "session". Empty [record_streams] = all.
/// [started_at_ms] is the Inspect clock origin (EEG timestamps are ms epoch).
pub fn capture_start(
    dir: String,
    prefix: String,
    id: String,
    record_streams: Vec<String>,
    started_at_ms: f64,
) -> anyhow::Result<()> {
    capture::capture_start(dir, prefix, id, record_streams, started_at_ms)
}

pub fn capture_stop() -> anyhow::Result<()> {
    capture::capture_stop()
}

/// Dart posts one JSONL line (no trailing interpretation in Rust).
#[frb(sync)]
pub fn capture_append_computed_line(line: Vec<u8>) -> anyhow::Result<()> {
    capture::capture_append_computed_line(line)
}

/// JSONL append (session) or atomic snapshot (monitor); mode from start/prefix.
#[frb(sync)]
pub fn capture_write_sidecar(json: Vec<u8>) -> anyhow::Result<()> {
    capture::capture_write_sidecar(json)
}

/// Tests / Inspect injectors. Live EEG is forked in-process from the forwarder.
#[frb(sync)]
pub fn capture_append_event(event: MuseEventDto) -> anyhow::Result<()> {
    capture::capture_append_event(event)
}

pub fn capture_flush() -> anyhow::Result<()> {
    capture::capture_flush()
}

/// Stream-assemble into `{dir}/{prefix}_{id}.neurofeed`. Deletes temps on success.
/// Returns the destination path. Never returns file bytes.
pub fn capture_assemble(metadata_json: Vec<u8>, thumbnail: Vec<u8>) -> anyhow::Result<String> {
    capture::capture_assemble(metadata_json, thumbnail)
}

/// Assemble leftover temps with no live session (crash recovery).
pub fn capture_assemble_at(
    dir: String,
    prefix: String,
    id: String,
    metadata_json: Vec<u8>,
    thumbnail: Vec<u8>,
) -> anyhow::Result<String> {
    capture::capture_assemble_at(dir, prefix, id, metadata_json, thumbnail)
}

pub fn capture_discard() -> anyhow::Result<()> {
    capture::capture_discard()
}

#[frb(sync)]
pub fn capture_flush_index() -> Vec<CaptureFlushEntry> {
    capture::capture_flush_index()
        .into_iter()
        .map(|e| CaptureFlushEntry {
            elapsed_s: e.elapsed_s,
            end_offset: e.end_offset,
        })
        .collect()
}

#[frb(sync)]
pub fn capture_recorded_channels() -> Vec<i32> {
    capture::capture_recorded_channels()
}

#[frb(sync)]
pub fn capture_drop_count() -> u64 {
    capture::capture_drop_count()
}

#[frb(sync)]
pub fn capture_write_errors() -> u64 {
    capture::capture_write_errors()
}

#[frb(sync)]
pub fn capture_is_active() -> bool {
    capture::capture_is_active()
}

/// Pause/resume raw fork without tearing down the session (no FRB yet —
/// Dart also drives this via `__capture_pause` sidecar control).
pub fn capture_set_paused(paused: bool) {
    capture::capture_set_paused(paused)
}

pub fn capture_is_paused() -> bool {
    capture::capture_is_paused()
}
