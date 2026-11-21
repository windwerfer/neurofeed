//! Session ↔ layer stack: the `layers.*` commands, seeding on protocol
//! choice, and the first-layer mapping onto the audio / guard slots
//! (see [`crate::layers`]).

use super::Session;
use crate::layers::{self, Caps, LayerConfig, LayerKind};
use crate::{CoreError, Reply};
use serde_json::json;

fn bad(e: String) -> CoreError {
    CoreError::InvalidArgs(e)
}

impl Session {
    fn layer_caps(&self) -> Caps {
        Caps::of(&self.state.feedback.protocol)
    }

    /// Stack → audio / guard slots (after a layer edit).
    fn layers_push(&mut self) {
        let caps = self.layer_caps();
        let st = &mut self.state;
        layers::push(&st.layers, &mut st.audio, &mut st.feedback.guard, caps);
    }

    /// Audio / guard slots → stack (after `audio.set` / `guard.set`).
    pub(super) fn layers_pull(&mut self) {
        let caps = self.layer_caps();
        let st = &mut self.state;
        layers::pull(&mut st.layers, &st.audio, st.feedback.guard, caps);
    }

    /// Re-seed from the selected protocol (`protocol.set`, `layers.reset`).
    pub(super) fn layers_reseed(&mut self) {
        self.state.reseed_layers();
    }

    /// Mark a protocol as used (a session started with it).
    pub(super) fn recent_touch(&mut self, id: &str) {
        layers::touch_recent(&mut self.state.recent_protocols, id);
    }

    pub(super) fn recent_forget(&mut self, id: &str) {
        self.state.recent_protocols.retain(|r| r != id);
    }

    /// The `layers.add` / `layers.remove` / `layers.set` / `layers.reset` commands.
    pub(super) fn layers_apply(&mut self, cmd: crate::Command) -> Result<Reply, CoreError> {
        use crate::Command as C;
        let reply = match cmd {
            C::LayersAdd { kind, settings } => {
                let cfg = settings.apply(LayerConfig::default_of(kind)).map_err(bad)?;
                let id = self.state.layers.add(cfg).map_err(bad)?;
                json!({ "id": id })
            }
            C::LayersRemove { id } => {
                let l = self.state.layers.remove(id).map_err(bad)?;
                json!({ "removed": l })
            }
            C::LayersSet { id, settings } => json!(self.state.layers.configure(id, &settings).map_err(bad)?),
            _ => {
                self.layers_reseed();
                json!({ "seeded_from": self.state.layers.seeded_from })
            }
        };
        self.layers_push();
        Ok(reply)
    }
}

/// `layers.list`: sections in display order, each with its layers.
pub fn list(s: &crate::AppState) -> Reply {
    let sections: Vec<_> = LayerKind::ALL
        .iter()
        .map(|k| {
            let layers: Vec<_> = s.layers.of_kind(*k).map(|l| json!({ "id": l.id, "layer": l, "summary": l.config.summary() })).collect();
            json!({ "kind": k, "label": k.label(), "layers": layers, "can_add": s.layers.count(*k) < layers::MAX_PER_KIND })
        })
        .collect();
    json!({ "setup_open": s.feedback_setup, "seeded_from": s.layers.seeded_from, "sections": sections })
}

/// `protocol.recent`: the last used protocols, newest first, still existing.
pub fn recent(s: &crate::AppState) -> Reply {
    let list: Vec<_> =
        s.recent_protocols.iter().filter_map(|id| crate::protocols::find(&s.custom_protocols, id)).take(layers::RECENT_SHOWN).collect();
    json!(list)
}
