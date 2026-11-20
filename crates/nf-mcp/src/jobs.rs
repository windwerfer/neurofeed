//! [`ThreadRunner`]: runs `job.start` work on its own thread (native shells
//! with a wall clock). Headless runs with a manual clock leave the session
//! without a runner, so jobs are stepped on `clock.advance` and stay
//! deterministic.

use nf_core::jobs::{JobCtl, JobRunner, Work};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Arc;

/// One thread per job; it steps the work until done or cancelled.
#[derive(Debug, Default, Clone, Copy)]
pub struct ThreadRunner;

impl JobRunner for ThreadRunner {
    fn spawn(&mut self, mut work: Box<dyn Work>, ctl: Arc<JobCtl>) -> Result<(), String> {
        std::thread::Builder::new()
            .name("nf-job".into())
            .spawn(move || {
                // Last-resort guard: a panic fails the job, never the app.
                if catch_unwind(AssertUnwindSafe(|| ctl.run(work.as_mut()))).is_err() {
                    ctl.finish(Err("internal error: the job panicked; nothing was saved".into()));
                }
            })
            .map(drop)
            .map_err(|e| e.to_string())
    }
}
