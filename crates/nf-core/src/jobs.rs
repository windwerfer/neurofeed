//! Long jobs: `job.start` runs `history.import`, `history.export`,
//! `recording.export`, `ai.install` or `ai.load` in the background with
//! progress and cancel (`job.status`, `job.cancel`).
//!
//! The work is a stepped [`Work`] state machine. By default the session
//! steps it once per `advance` (one UI frame, or 0.1 s of `clock.advance`),
//! so headless runs and wasm stay deterministic and thread-free. A native
//! shell may inject a [`JobRunner`] that loops the same steps on a worker
//! thread. Either way the result is applied on the session thread when the
//! job finishes; a cancelled or failed job changes nothing.

use crate::import::{Bander, Prepared};
use crate::recording::{base64, Finished};
use crate::{CoreError, ExportFormat};
use schemars::JsonSchema;
use serde::Serialize;
use serde_json::{json, Value};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, PoisonError};

/// Commands `job.start` can run.
pub const JOB_COMMANDS: &[&str] = &["history.import", "history.export", "recording.export", "ai.install", "ai.load"];
/// Jobs running at once.
pub const MAX_RUNNING: usize = 4;
/// Finished jobs kept (with their results) for `job.status`; older ones are dropped.
pub const MAX_FINISHED: usize = 8;
/// Records banded per import step (≈ 12 s of Muse EEG, a few ms in release).
const BAND_STEP_RECORDS: usize = 1024;
/// Input bytes base64-encoded per export step (a multiple of 3, so the
/// chunks concatenate to the one-shot encoding).
const B64_STEP_BYTES: usize = 3 << 18;
const _: () = assert!(B64_STEP_BYTES.is_multiple_of(3));

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum JobState {
    Running,
    Done,
    Failed,
    Cancelled,
}

impl JobState {
    pub fn finished(self) -> bool {
        self != JobState::Running
    }
}

/// What `job.start` / `job.status` / `job.cancel` report about a job.
#[derive(Debug, Clone, PartialEq, Serialize, JsonSchema)]
pub struct JobInfo {
    pub id: u64,
    /// The wrapped command id, e.g. `history.import`.
    pub command: String,
    pub label: String,
    pub state: JobState,
    /// 0..1; null while unknown (an AI model load, a download without a size).
    pub progress: Option<f64>,
    /// Session time (s) the job started / finished.
    pub started_s: f64,
    pub finished_s: Option<f64>,
    pub error: Option<String>,
}

/// What finished work hands back to the session thread.
pub enum Outcome {
    /// The wrapped command's reply.
    Reply(Value),
    /// A parsed import; the session stores it (the only side effect).
    Import(Box<Prepared>),
}

pub enum Step {
    /// More to do; progress 0..1.
    Progress(f64),
    Done(Result<Outcome, String>),
}

/// Background work, stepped. Owns its inputs (a snapshot taken at start),
/// so it can run on any thread and never touches the session.
pub trait Work: Send {
    fn step(&mut self) -> Step;
}

/// Shared between the session and a runner thread: cancel flag, progress,
/// the outcome once done.
#[derive(Default)]
pub struct JobCtl {
    cancel: AtomicBool,
    progress_bits: AtomicU64,
    outcome: Mutex<Option<Result<Outcome, String>>>,
}

impl JobCtl {
    pub fn cancelled(&self) -> bool {
        self.cancel.load(Ordering::SeqCst)
    }
    pub fn cancel(&self) {
        self.cancel.store(true, Ordering::SeqCst);
    }
    pub fn progress(&self) -> f64 {
        f64::from_bits(self.progress_bits.load(Ordering::SeqCst))
    }
    pub fn set_progress(&self, p: f64) {
        let p = if p.is_finite() { p.clamp(0.0, 1.0) } else { 0.0 };
        self.progress_bits.store(p.to_bits(), Ordering::SeqCst);
    }
    pub fn finish(&self, r: Result<Outcome, String>) {
        *self.outcome.lock().unwrap_or_else(PoisonError::into_inner) = Some(r);
    }
    pub fn take(&self) -> Option<Result<Outcome, String>> {
        self.outcome.lock().unwrap_or_else(PoisonError::into_inner).take()
    }
    /// One step: records progress or the outcome. `true` when done.
    pub fn step(&self, work: &mut dyn Work) -> bool {
        match work.step() {
            Step::Progress(p) => {
                self.set_progress(p);
                false
            }
            Step::Done(r) => {
                self.set_progress(1.0);
                self.finish(r);
                true
            }
        }
    }
    /// Run `work` to the end or until cancelled (a runner thread's loop).
    pub fn run(&self, work: &mut dyn Work) {
        while !self.cancelled() && !self.step(work) {}
    }
}

/// Runs [`Work`] beside the session (a native shell's worker threads).
/// The runner must call [`JobCtl::run`] (or step until done / cancelled).
pub trait JobRunner: Send {
    fn spawn(&mut self, work: Box<dyn Work>, ctl: Arc<JobCtl>) -> Result<(), String>;
}

/// `history.import` as steps: parse, band (chunks of records), write the body.
pub struct ImportWork {
    phase: ImportPhase,
}

enum ImportPhase {
    Parse { bytes: Vec<u8>, file_name: String, utc_offset_minutes: i32, mains: crate::MainsMode },
    Bands(Box<Bander>),
    Done,
}

impl ImportWork {
    pub fn new(bytes: Vec<u8>, file_name: String, utc_offset_minutes: i32, mains: crate::MainsMode) -> Self {
        Self { phase: ImportPhase::Parse { bytes, file_name, utc_offset_minutes, mains } }
    }
}

impl Work for ImportWork {
    fn step(&mut self) -> Step {
        match std::mem::replace(&mut self.phase, ImportPhase::Done) {
            ImportPhase::Parse { bytes, file_name, utc_offset_minutes, mains } => {
                match crate::import::parse(&bytes, &file_name, utc_offset_minutes) {
                    Ok(imported) => {
                        self.phase = ImportPhase::Bands(Box::new(Bander::new(imported, mains)));
                        Step::Progress(0.1)
                    }
                    Err(e) => Step::Done(Err(e.to_string())),
                }
            }
            ImportPhase::Bands(mut b) => {
                if b.step(BAND_STEP_RECORDS) {
                    Step::Done(Ok(Outcome::Import(Box::new(b.finish()))))
                } else {
                    let p = 0.1 + 0.85 * b.fraction();
                    self.phase = ImportPhase::Bands(b);
                    Step::Progress(p)
                }
            }
            ImportPhase::Done => Step::Done(Err("import already finished".into())),
        }
    }
}

/// `recording.export` / `history.export` as steps: encode, then base64 in chunks.
pub struct ExportWork {
    phase: ExportPhase,
    /// Reply fields besides `bytes` / `base64` (`format`, `extension`, `id`).
    reply: serde_json::Map<String, Value>,
}

enum ExportPhase {
    Encode { finished: Box<Finished>, format: ExportFormat, start: crate::recording::EdfStart },
    Base64 { bytes: Vec<u8>, pos: usize, out: String },
    Done,
}

impl ExportWork {
    /// Encode `finished` in the first step.
    pub fn encode(finished: Finished, format: ExportFormat, start: crate::recording::EdfStart, reply: Value) -> Self {
        Self { phase: ExportPhase::Encode { finished: Box::new(finished), format, start }, reply: object(reply) }
    }
    /// Already encoded (a PDF report is built at start).
    pub fn encoded(bytes: Vec<u8>, reply: Value) -> Self {
        let out = String::with_capacity(bytes.len().div_ceil(3) * 4);
        Self { phase: ExportPhase::Base64 { bytes, pos: 0, out }, reply: object(reply) }
    }
}

fn object(v: Value) -> serde_json::Map<String, Value> {
    match v {
        Value::Object(m) => m,
        _ => serde_json::Map::new(),
    }
}

impl Work for ExportWork {
    fn step(&mut self) -> Step {
        match std::mem::replace(&mut self.phase, ExportPhase::Done) {
            ExportPhase::Encode { finished, format, start } => match crate::recording::export(&finished, format, start) {
                Ok(bytes) => {
                    let out = String::with_capacity(bytes.len().div_ceil(3) * 4);
                    self.phase = ExportPhase::Base64 { bytes, pos: 0, out };
                    Step::Progress(0.5)
                }
                Err(e) => Step::Done(Err(e)),
            },
            ExportPhase::Base64 { bytes, pos, mut out } => {
                let end = pos.saturating_add(B64_STEP_BYTES).min(bytes.len());
                out.push_str(&base64(bytes.get(pos..end).unwrap_or_default()));
                if end >= bytes.len() {
                    let mut reply = std::mem::take(&mut self.reply);
                    reply.insert("bytes".into(), json!(bytes.len()));
                    reply.insert("base64".into(), Value::String(out));
                    return Step::Done(Ok(Outcome::Reply(Value::Object(reply))));
                }
                let p = 0.5 + 0.5 * end as f64 / bytes.len().max(1) as f64;
                self.phase = ExportPhase::Base64 { bytes, pos: end, out };
                Step::Progress(p)
            }
            ExportPhase::Done => Step::Done(Err("export already finished".into())),
        }
    }
}

/// A `job.start` request that failed validation (state unchanged).
pub fn not_a_job(command: &str) -> CoreError {
    CoreError::InvalidArgs(format!("`{command}` cannot run as a job; job commands: {}", JOB_COMMANDS.join(", ")))
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn ctl_progress_is_clamped_and_finite() {
        let c = JobCtl::default();
        for (p, want) in [(0.5, 0.5), (-1.0, 0.0), (7.0, 1.0), (f64::NAN, 0.0), (f64::INFINITY, 0.0)] {
            c.set_progress(p);
            assert_eq!(c.progress(), want);
        }
    }
}
