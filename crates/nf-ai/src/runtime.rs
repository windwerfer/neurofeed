//! [`NativeAi`]: the desktop [`AiRuntime`]. One worker thread owns the loaded
//! model, so loading and scoring never overlap and never block the UI; an
//! install runs on its own thread. State is shared behind a mutex.

use crate::store::ModelStore;
use crate::{heads, Model};
use nf_types::{AiModel, AiModelState, AiRuntime, AiScore, AiSource, AiWindow};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Instant;

enum Job {
    Load(AiModel),
    Unload,
    Score(AiWindow),
}

type States = Arc<Mutex<HashMap<AiModel, AiModelState>>>;

pub struct NativeAi {
    store: ModelStore,
    states: States,
    jobs: Sender<Job>,
    scores: Receiver<AiScore>,
    busy: Arc<AtomicBool>,
}

fn set(states: &States, m: AiModel, s: AiModelState) {
    states.lock().unwrap_or_else(PoisonError::into_inner).insert(m, s);
}

impl NativeAi {
    /// Runtime over `root` (see [`crate::store::default_root`]).
    pub fn new(root: impl Into<std::path::PathBuf>) -> Self {
        let store = ModelStore::new(root);
        let states: States = Arc::default();
        for m in AiModel::ALL {
            set(&states, m, if store.installed(m) { AiModelState::Installed } else { AiModelState::Missing });
        }
        let (jobs, rx) = channel();
        let (tx, scores) = channel();
        let busy = Arc::new(AtomicBool::new(false));
        let w = Worker { store: store.clone(), states: states.clone(), busy: busy.clone(), scores: tx, loaded: None };
        std::thread::Builder::new().name("nf-ai".into()).spawn(move || w.run(&rx)).ok();
        Self { store, states, jobs, scores, busy }
    }

    /// Runtime over the default model folder (temp dir if none).
    pub fn with_default_root() -> Self {
        Self::new(crate::store::default_root().unwrap_or_else(|| std::env::temp_dir().join("neurofeed-ai")))
    }
}

impl AiRuntime for NativeAi {
    fn state(&self, model: AiModel) -> AiModelState {
        self.states.lock().unwrap_or_else(PoisonError::into_inner).get(&model).cloned().unwrap_or(AiModelState::Missing)
    }

    fn folder(&self, model: AiModel) -> Option<String> {
        Some(self.store.dir(model).display().to_string())
    }

    fn install(&mut self, model: AiModel, source: AiSource) -> Result<(), String> {
        if matches!(self.state(model), AiModelState::Installing { .. } | AiModelState::Loading) {
            return Err(format!("{} is busy", model.label()));
        }
        if source == AiSource::Download && model.download_url().is_none() {
            return Err(format!("{} is gated: download {} on Hugging Face, then import it", model.label(), model.weights_file()));
        }
        set(&self.states, model, AiModelState::Installing { progress: None });
        let (store, states) = (self.store.clone(), self.states.clone());
        let run = move || {
            let mut prog = |p: f64| set(&states, model, AiModelState::Installing { progress: Some(p) });
            let r = match &source {
                AiSource::Import { path } => store.import(model, std::path::Path::new(path), &mut prog),
                #[cfg(feature = "download")]
                AiSource::Download => store.download(model, &mut prog),
                #[cfg(not(feature = "download"))]
                AiSource::Download => Err(anyhow::anyhow!("this build cannot download; import the file instead")),
            };
            set(&states, model, r.map_or_else(|e| AiModelState::Failed { message: format!("{e:#}") }, |()| AiModelState::Installed));
        };
        std::thread::Builder::new().name("nf-ai-install".into()).spawn(run).map(drop).map_err(|e| e.to_string())
    }

    fn remove(&mut self, model: AiModel) -> Result<(), String> {
        if matches!(self.state(model), AiModelState::Ready { .. } | AiModelState::Loading) {
            self.unload();
        }
        self.store.remove(model).map_err(|e| format!("{e:#}"))?;
        set(&self.states, model, AiModelState::Missing);
        Ok(())
    }

    fn load(&mut self, model: AiModel) -> Result<(), String> {
        if !self.store.installed(model) {
            return Err(format!("{} is not installed", model.label()));
        }
        set(&self.states, model, AiModelState::Loading);
        self.jobs.send(Job::Load(model)).map_err(|_| "AI worker stopped".to_owned())
    }

    fn unload(&mut self) {
        let _ = self.jobs.send(Job::Unload);
    }

    fn submit(&mut self, window: AiWindow) -> bool {
        if self.busy.swap(true, Ordering::SeqCst) {
            return false;
        }
        self.jobs.send(Job::Score(window)).is_ok()
    }

    fn poll(&mut self) -> Vec<AiScore> {
        self.scores.try_iter().collect()
    }
}

struct Worker {
    store: ModelStore,
    states: States,
    busy: Arc<AtomicBool>,
    scores: Sender<AiScore>,
    loaded: Option<(AiModel, Model, Vec<heads::LinearHead>)>,
}

impl Worker {
    fn run(mut self, rx: &Receiver<Job>) {
        for job in rx {
            match job {
                Job::Load(m) => self.load(m),
                Job::Unload => self.unload(),
                Job::Score(w) => {
                    self.score(&w);
                    self.busy.store(false, Ordering::SeqCst);
                }
            }
        }
    }

    fn unload(&mut self) {
        if let Some((m, ..)) = self.loaded.take() {
            set(&self.states, m, if self.store.installed(m) { AiModelState::Installed } else { AiModelState::Missing });
        }
    }

    fn load(&mut self, m: AiModel) {
        self.unload();
        let r = Model::load(m, &self.store.dir(m)).and_then(|(model, desc)| Ok((model, desc, heads::for_model(m)?)));
        match r {
            Ok((model, desc, hs)) => {
                let names: Vec<&str> = hs.iter().map(|h| h.scorer).collect();
                set(&self.states, m, AiModelState::Ready { description: format!("{desc}; heads {}", names.join(", ")) });
                self.loaded = Some((m, model, hs));
            }
            Err(e) => set(&self.states, m, AiModelState::Failed { message: format!("{e:#}") }),
        }
    }

    fn score(&mut self, w: &AiWindow) {
        let Some((m, model, hs)) = self.loaded.as_mut() else { return };
        if *m != w.model {
            return;
        }
        let t0 = Instant::now();
        match model.embed(&w.signal, w.n_times) {
            Ok(embedding) => {
                let heads = heads::score_all(hs, &embedding);
                let ms = t0.elapsed().as_secs_f64() * 1000.0;
                let _ = self.scores.send(AiScore { model: *m, t: w.t, embedding, heads, ms });
            }
            Err(e) => log::warn!("[ai] {} inference failed: {e:#}", m.label()),
        }
    }
}
