//! Session ↔ [`crate::jobs`]: `job.start` validates the wrapped request and
//! snapshots its inputs, `advance` steps the work (or polls the runner / AI
//! runtime), and the result is applied here when the job finishes.

use super::{Event, Session};
use crate::command::{find, Command, Query, Request};
use crate::jobs::{not_a_job, ExportWork, ImportWork, JobCtl, JobInfo, JobState, Outcome, Work, JOB_COMMANDS, MAX_FINISHED, MAX_RUNNING};
use crate::recording::Finished;
use crate::{CoreError, ExportFormat, Reply};
use nf_types::{AiModel, AiModelState};
use serde_json::{json, Value};
use std::sync::Arc;

/// Job table (session-local; not part of `AppState`, so batch rollback and
/// state snapshots never rewind a job).
#[derive(Default)]
pub(super) struct Jobs {
    entries: Vec<Entry>,
    next_id: u64,
}

struct Entry {
    info: JobInfo,
    ctl: Arc<JobCtl>,
    driver: Driver,
    result: Option<Value>,
    /// Last progress decile reported as an event.
    decile: u8,
}

enum Driver {
    /// Stepped by the session, once per `advance`.
    Inline(Box<dyn Work>),
    /// Running on the injected [`crate::jobs::JobRunner`].
    Spawned,
    /// Watching the AI runtime install / load a model.
    AiInstall(AiModel),
    AiLoad {
        model: AiModel,
        before: Option<AiModel>,
    },
}

impl Driver {
    fn ai(&self) -> bool {
        matches!(self, Driver::AiInstall(_) | Driver::AiLoad { .. })
    }
}

impl Jobs {
    fn running(&self) -> impl Iterator<Item = &Entry> {
        self.entries.iter().filter(|e| !e.info.state.finished())
    }
    fn get(&self, id: u64) -> Option<&Entry> {
        self.entries.iter().find(|e| e.info.id == id)
    }
    /// Drop the oldest finished jobs beyond [`MAX_FINISHED`].
    fn evict(&mut self) {
        let mut finished = self.entries.iter().filter(|e| e.info.state.finished()).count();
        self.entries.retain(|e| {
            let drop = finished > MAX_FINISHED && e.info.state.finished();
            finished -= usize::from(drop);
            !drop
        });
    }
}

impl Session {
    /// Run job work on worker threads (native shells). Without one, jobs
    /// are stepped on `tick` (deterministic; wasm and headless tests).
    pub fn set_job_runner(&mut self, runner: Box<dyn crate::jobs::JobRunner>) {
        self.job_runner = Some(runner);
    }

    /// Jobs, oldest first (running and the last finished ones).
    pub fn jobs(&self) -> Vec<JobInfo> {
        self.jobs.entries.iter().map(|e| e.info.clone()).collect()
    }

    /// `job.start`: validate everything first, so a refusal changes nothing.
    pub(super) fn job_start(&mut self, command: &str, params: Value) -> Result<Reply, CoreError> {
        if !JOB_COMMANDS.contains(&command) {
            return Err(not_a_job(command));
        }
        if self.jobs.running().count() >= MAX_RUNNING {
            return Err(CoreError::BadRequest(format!("{MAX_RUNNING} jobs are running; wait for one or job.cancel it")));
        }
        let req = Request::parse(command, params)?;
        if let Err(reason) = self.enabled(command) {
            return Err(CoreError::Disabled { id: command.to_owned(), reason });
        }
        let driver = match req {
            Request::Command(cmd @ (Command::AiInstall { .. } | Command::AiLoad { .. })) => self.ai_job(cmd)?,
            req => self.work_job(req)?,
        };
        let id = self.jobs.next_id.saturating_add(1);
        self.jobs.next_id = id;
        let ctl = Arc::new(JobCtl::default());
        let driver = match driver {
            Driver::Inline(work) => match self.job_runner.as_mut() {
                Some(r) => {
                    r.spawn(work, ctl.clone()).map_err(|e| CoreError::BadRequest(format!("cannot start the job: {e}")))?;
                    Driver::Spawned
                }
                None => Driver::Inline(work),
            },
            d => d,
        };
        let label = find(command).map_or(command, |s| s.label).to_owned();
        let progress = (!matches!(driver, Driver::AiLoad { .. })).then_some(0.0);
        let info = JobInfo {
            id,
            command: command.to_owned(),
            label,
            state: JobState::Running,
            progress,
            started_s: self.state.time,
            finished_s: None,
            error: None,
        };
        self.emit(Event::JobStarted { id, command: command.to_owned() });
        let reply = serde_json::to_value(&info).unwrap_or_default();
        self.jobs.entries.push(Entry { info, ctl, driver, result: None, decile: 0 });
        Ok(reply)
    }

    /// Snapshot the inputs of an import / export into stepped work.
    fn work_job(&self, req: Request) -> Result<Driver, CoreError> {
        let work: Box<dyn Work> = match req {
            Request::Command(Command::HistoryImport(r)) => {
                let bytes = crate::import::base64_decode(&r.data_base64)?;
                if bytes.len() > crate::import::MAX_IMPORT_BYTES {
                    return Err(CoreError::InvalidArgs(format!("file is larger than {} MB", crate::import::MAX_IMPORT_BYTES >> 20)));
                }
                Box::new(ImportWork::new(bytes, r.file_name, r.utc_offset_minutes.unwrap_or(0), self.state.mains_mode))
            }
            Request::Query(Query::HistoryExport { id, format }) => {
                let reply = json!({ "id": id, "format": format, "extension": format.extension() });
                if format == ExportFormat::Pdf {
                    // The report needs the store; it is small and built here.
                    Box::new(ExportWork::encoded(self.history_export(id, format)?, reply))
                } else {
                    let (f, start) = self.history_finished(id)?;
                    Box::new(ExportWork::encode(f, format, start, reply))
                }
            }
            Request::Query(Query::RecordingExport { format, start }) => {
                let (f, start) = self.recording_finished(start)?;
                if format == ExportFormat::Pdf {
                    return Err(CoreError::BadRequest("pdf export needs the stored session (history.export)".into()));
                }
                Box::new(ExportWork::encode(f.clone(), format, start, json!({ "format": format, "extension": format.extension() })))
            }
            r => return Err(not_a_job(&r.id())),
        };
        Ok(Driver::Inline(work))
    }

    /// Run `ai.install` / `ai.load` as the sync command does, then watch it.
    fn ai_job(&mut self, cmd: Command) -> Result<Driver, CoreError> {
        if let Some(e) = self.jobs.running().find(|e| e.driver.ai()) {
            return Err(CoreError::BadRequest(format!(
                "AI job {} ({}) is running; wait for it or job.cancel it",
                e.info.id, e.info.command
            )));
        }
        let selected = self.state.ai.settings.model();
        let before = self.state.ai.loaded();
        let driver = match &cmd {
            Command::AiInstall { model, .. } => Driver::AiInstall(model.unwrap_or(selected)),
            Command::AiLoad { model } => Driver::AiLoad { model: model.unwrap_or(selected), before },
            _ => return Err(not_a_job(&Request::Command(cmd).id())),
        };
        self.ai_apply(cmd)?;
        Ok(driver)
    }

    /// `job.cancel`: stops the work and discards its result.
    pub(super) fn job_cancel(&mut self, id: u64) -> Result<Reply, CoreError> {
        let e = self.jobs.get(id).ok_or_else(|| CoreError::InvalidArgs(format!("no job {id}")))?;
        if e.info.state.finished() {
            return Err(CoreError::InvalidArgs(format!("job {id} already finished ({})", state_name(e.info.state))));
        }
        match e.driver {
            Driver::AiInstall(m) => {
                let rt = self.ai.as_mut().ok_or_else(|| CoreError::BadRequest(crate::ai::NO_RUNTIME.into()))?;
                rt.cancel_install(m).map_err(CoreError::BadRequest)?;
            }
            Driver::AiLoad { before, .. } => self.ai_restore_loaded(before),
            Driver::Inline(_) | Driver::Spawned => e.ctl.cancel(),
        }
        let (now, idx) = (self.state.time, self.jobs.entries.iter().position(|e| e.info.id == id));
        let Some(e) = idx.and_then(|i| self.jobs.entries.get_mut(i)) else { return Err(CoreError::InvalidArgs(format!("no job {id}"))) };
        e.info.state = JobState::Cancelled;
        e.info.finished_s = Some(now);
        e.driver = Driver::Spawned; // drops inline work; a runner thread sees the flag
        let info = e.info.clone();
        self.emit(Event::JobFinished { id, command: info.command.clone(), state: JobState::Cancelled, error: None });
        self.jobs.evict();
        Ok(serde_json::to_value(info).unwrap_or_default())
    }

    /// `job.status`: one job (with its result once done) or all of them.
    pub(super) fn job_status(&self, id: Option<u64>) -> Result<Reply, CoreError> {
        let Some(id) = id else {
            return Ok(json!({ "jobs": self.jobs() }));
        };
        let e = self
            .jobs
            .get(id)
            .ok_or_else(|| CoreError::InvalidArgs(format!("no job {id} (finished jobs are kept for the last {MAX_FINISHED})")))?;
        Ok(json!({ "job": e.info, "result": e.result }))
    }

    /// Per `advance`: one step per inline job, poll runner / AI jobs, apply
    /// what finished. Skipped inside a batch (a rollback must not race a job).
    pub(super) fn jobs_tick(&mut self) {
        if self.batching || self.jobs.entries.is_empty() {
            return;
        }
        let mut done = Vec::new();
        for (i, e) in self.jobs.entries.iter_mut().enumerate() {
            if e.info.state.finished() {
                continue;
            }
            let outcome = match &mut e.driver {
                Driver::Inline(w) => e.ctl.step(w.as_mut()).then(|| e.ctl.take()).flatten(),
                Driver::Spawned => e.ctl.take(),
                Driver::AiInstall(m) => ai_poll(self.ai.as_deref(), *m, true, &e.ctl),
                Driver::AiLoad { model, .. } => ai_poll(self.ai.as_deref(), *model, false, &e.ctl),
            };
            if e.info.progress.is_some() || !matches!(e.driver, Driver::AiLoad { .. }) {
                e.info.progress = Some(e.ctl.progress());
            }
            let decile = (e.ctl.progress() * 10.0).floor() as u8;
            if decile > e.decile && outcome.is_none() {
                e.decile = decile;
                self.events.push(Event::JobProgress { id: e.info.id, progress: e.ctl.progress() });
            }
            if let Some(o) = outcome {
                done.push((i, o));
            }
        }
        for (i, o) in done.into_iter().rev() {
            self.job_finish(i, o);
        }
        self.jobs.evict();
    }

    fn job_finish(&mut self, i: usize, outcome: Result<Outcome, String>) {
        let applied = match outcome {
            Ok(Outcome::Reply(v)) => Ok(v),
            Ok(Outcome::Import(p)) => {
                let summary = p.preview().summary;
                self.import_save(p.into_stored()).map(|id| json!({ "id": id, "summary": summary })).map_err(|e| e.to_string())
            }
            Err(e) => Err(e),
        };
        let now = self.state.time;
        let ai = crate::ai::status_json(&self.state.ai);
        let Some(e) = self.jobs.entries.get_mut(i) else { return };
        e.info.finished_s = Some(now);
        match applied {
            Ok(v) => {
                e.info.state = JobState::Done;
                e.info.progress = Some(1.0);
                e.result = Some(if e.driver.ai() { ai } else { v });
            }
            Err(msg) => {
                e.info.state = JobState::Failed;
                e.info.error = Some(msg);
            }
        }
        e.driver = Driver::Spawned;
        let ev = Event::JobFinished { id: e.info.id, command: e.info.command.clone(), state: e.info.state, error: e.info.error.clone() };
        self.state.revision += 1;
        self.emit(ev);
    }

    /// The last recording and its EDF start (shared by `recording.export`).
    pub(super) fn recording_finished(&self, start: Option<[u16; 6]>) -> Result<(&Finished, crate::recording::EdfStart), CoreError> {
        let f = self.live.finished.as_ref().ok_or_else(|| CoreError::BadRequest("nothing recorded yet".into()))?;
        let start = match (start, f.info.wall_clock_unix_ms) {
            (Some([y, mo, d, h, mi, se]), _) => (y, mo, d, h, mi, se),
            (None, Some(ms)) => crate::recording::civil_utc(ms),
            (None, None) => (1985, 1, 1, 0, 0, 0),
        };
        Ok((f, start))
    }
}

/// An AI job's runtime state → progress, or the outcome once it settled.
fn ai_poll(rt: Option<&dyn nf_types::AiRuntime>, m: AiModel, install: bool, ctl: &JobCtl) -> Option<Result<Outcome, String>> {
    let Some(rt) = rt else { return Some(Err(crate::ai::NO_RUNTIME.into())) };
    match (rt.state(m), install) {
        (AiModelState::Installing { progress }, true) => {
            ctl.set_progress(progress.unwrap_or(0.0));
            None
        }
        (AiModelState::Loading, false) => None,
        (AiModelState::Failed { message }, _) => Some(Err(message)),
        (AiModelState::Missing, _) => Some(Err(format!("{} is not installed", m.label()))),
        (AiModelState::Installed, false) => Some(Err(format!("{} was unloaded before it was ready", m.label()))),
        // Installed (or already auto-loading after the install), or Ready.
        _ => Some(Ok(Outcome::Reply(Value::Null))),
    }
}

fn state_name(s: JobState) -> &'static str {
    match s {
        JobState::Running => "running",
        JobState::Done => "done",
        JobState::Failed => "failed",
        JobState::Cancelled => "cancelled",
    }
}
