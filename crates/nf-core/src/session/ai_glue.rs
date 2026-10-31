//! Session ↔ [`AiRuntime`]: mirror model states into `AppState::ai`, feed one
//! window per second while the selected model is ready, take scores back
//! (anchors, live readout) and run the `ai.*` commands.

use super::Session;
use crate::ai::{status, AiLive};
use crate::{Command, CoreError, Reply};
use nf_feedback::CalStage;
use nf_types::{AiModel, AiModelState, AiSource, AiWindow};

impl Session {
    /// Register the model runtime (desktop shells). Loads the selected model
    /// when it is installed and auto-load is on.
    pub fn set_ai_runtime(&mut self, rt: Box<dyn nf_types::AiRuntime>) {
        self.ai = Some(rt);
        self.state.ai.runtime = true;
        self.ai_sync();
    }

    /// Per frame: sync states, auto-load, take scores, submit the next window.
    pub(super) fn ai_tick(&mut self) {
        if self.ai.is_none() {
            return;
        }
        self.ai_sync();
        self.ai_take_scores();
        self.ai_submit();
        let f = &self.state.feedback;
        if self.live.ai_sleep_pending && f.phase == crate::feedback::Phase::Playing {
            self.live.ai_sleep_pending = false;
            self.state.ai.sleep_anchor = self.live.anchors.capture_sleep();
        }
        self.state.feedback.ai_guard = self.state.ai.ready().then(|| self.state.ai.settings.fixed());
    }

    fn ai_sync(&mut self) {
        let Some(rt) = self.ai.as_ref() else { return };
        let models: Vec<_> = AiModel::ALL.iter().map(|&m| status(m, rt.state(m), rt.folder(m))).collect();
        if models != self.state.ai.models {
            self.state.ai.models = models;
            self.state.revision += 1;
        }
        let a = &self.state.ai;
        let m = a.settings.model();
        if a.settings.auto_load && a.model_state(m) == Some(&AiModelState::Installed) && !self.ai_autoloaded.contains(&m) {
            self.ai_autoloaded.push(m);
            if let Some(rt) = self.ai.as_mut() {
                // A failure shows up as the model's `failed` state.
                let _ = rt.load(m);
            }
        }
    }

    fn ai_take_scores(&mut self) {
        let Some(rt) = self.ai.as_mut() else { return };
        let scores = rt.poll();
        let f = &self.state.feedback;
        let stage = f.calibration.as_ref().map(|c| c.stage);
        // Legacy: V_clear comes from eyes-open calibration (the staged
        // eyes-open step, or the whole baseline of an eyes-open protocol).
        let eyes_open = !f.protocol.guard_only && f.protocol.eyes == nf_feedback::Eyes::Open;
        for s in scores {
            let id = s.model.id();
            match stage {
                Some(CalStage::EyesOpen) => self.live.anchors.capture_clear(id, &s.embedding),
                Some(CalStage::EyesClosed) if eyes_open => self.live.anchors.capture_clear(id, &s.embedding),
                Some(CalStage::Artifacts) | None => {}
                Some(CalStage::EyesClosed) => self.live.ai_sleep_pending |= self.live.anchors.has_clear(),
            }
            let anchors = self.live.anchors.observe(id, &s.embedding, stage == Some(CalStage::EyesClosed));
            let scorer = &self.state.ai.settings.scorer;
            let value = s.heads.iter().find(|(k, _)| k == scorer).map(|(_, v)| *v);
            let windows = self.state.ai.live.as_ref().map_or(0, |l| l.windows) + 1;
            self.state.ai.clear_anchor = self.live.anchors.has_clear();
            self.state.ai.live = Some(AiLive {
                t: self.state.time,
                model: s.model,
                heads: s.heads,
                value,
                ms: s.ms,
                clarity: anchors.map(|a| a.clarity),
                sleep_dir: anchors.map(|a| a.sleep_dir),
                windows,
            });
            self.state.revision += 1;
        }
    }

    /// One window per second of session time from the 10 s filtered buffers.
    fn ai_submit(&mut self) {
        if !self.state.ai.ready() || self.state.time + 1e-9 < self.live.ai_next {
            return;
        }
        let (Some(dev), Some(sig), Some(rt)) = (&self.state.device, &self.live.signal, self.ai.as_mut()) else { return };
        let Some(rows) = crate::ai::model_rows(&dev.channels) else { return };
        let model = self.state.ai.settings.model();
        let n = model.window_samples();
        let mut signal = Vec::with_capacity(4 * n);
        for ch in rows {
            let r = sig.last(ch, n, true);
            if r.len() < n {
                return; // buffering (first window after ~2 s)
            }
            signal.extend(r);
        }
        self.live.ai_next = self.state.time + 1.0;
        rt.submit(AiWindow { model, t: self.state.time, n_times: n, signal });
    }

    /// The `ai.*` commands (anything else is a bug in the caller).
    pub(super) fn ai_apply(&mut self, cmd: Command) -> Result<Reply, CoreError> {
        match cmd {
            Command::AiSet(patch) => self.ai_set(&patch),
            Command::AiInstall { model, path } => self.ai_command(AiCmd::Install { model, path }),
            Command::AiLoad { model } => self.ai_command(AiCmd::Load(model)),
            Command::AiUnload => self.ai_command(AiCmd::Unload),
            Command::AiRemove { model, confirm: true } => self.ai_command(AiCmd::Remove(model)),
            Command::AiRemove { model, confirm: false } => {
                Err(CoreError::InvalidArgs(format!("removing {} deletes its files; pass confirm=true", model.label())))
            }
            _ => Err(CoreError::BadRequest("not an ai command".into())),
        }
    }

    /// Batch rollback: put the runtime back to the model that was loaded
    /// before the batch (ai.load / ai.unload are reversible).
    pub(super) fn ai_restore_loaded(&mut self, before: Option<AiModel>) {
        let Some(rt) = self.ai.as_mut() else { return };
        let now = AiModel::ALL.iter().copied().find(|&m| matches!(rt.state(m), AiModelState::Ready { .. } | AiModelState::Loading));
        if now == before {
            return;
        }
        match before {
            // A failure shows up as the model's `failed` state.
            Some(m) => {
                let _ = rt.load(m);
            }
            None => rt.unload(),
        }
        self.ai_sync();
    }

    fn ai_command(&mut self, cmd: AiCmd) -> Result<Reply, CoreError> {
        let rt = self.ai.as_mut().ok_or_else(|| CoreError::BadRequest(crate::ai::NO_RUNTIME.into()))?;
        let selected = self.state.ai.settings.model();
        let r = match cmd {
            AiCmd::Install { model, path } => {
                let m = model.unwrap_or(selected);
                self.ai_autoloaded.retain(|x| *x != m);
                rt.install(m, path.map_or(AiSource::Download, |path| AiSource::Import { path }))
            }
            AiCmd::Load(model) => rt.load(model.unwrap_or(selected)),
            AiCmd::Unload => {
                rt.unload();
                Ok(())
            }
            AiCmd::Remove(m) => {
                self.ai_autoloaded.retain(|x| *x != m);
                rt.remove(m)
            }
        };
        r.map_err(CoreError::BadRequest)?;
        self.ai_sync();
        Ok(crate::ai::status_json(&self.state.ai))
    }

    fn ai_set(&mut self, p: &crate::ai::AiPatch) -> Result<Reply, CoreError> {
        let locked = self.state.feedback.phase.active();
        crate::ai::set(&mut self.state.ai.settings, p, locked)?;
        if p.threshold_mode.is_some() || p.fixed_threshold.is_some() {
            let fixed = self.state.ai.settings.fixed();
            self.state.feedback.set_guard_fixed(fixed);
        }
        self.ai_sync();
        Ok(crate::ai::status_json(&self.state.ai))
    }
}

/// Runtime-side `ai.*` commands.
enum AiCmd {
    Install { model: Option<AiModel>, path: Option<String> },
    Load(Option<AiModel>),
    Unload,
    Remove(AiModel),
}
