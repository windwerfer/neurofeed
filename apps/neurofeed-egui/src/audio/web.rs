//! Web Audio: a ScriptProcessorNode whose callback renders the mixer.
//! Clips decode synchronously the first time a cue needs them.

use super::{audible, decode_asset, Audio};
use nf_core::nf_audio::{Cue, Mixer, OneShot};
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;
use wasm_bindgen_futures::wasm_bindgen::closure::Closure;
use wasm_bindgen_futures::wasm_bindgen::{JsCast, JsValue};
use web_sys::{AudioContext, AudioProcessingEvent, ScriptProcessorNode};

const BLOCK: u32 = 4096;

#[derive(Default)]
pub struct WebAudio {
    ctx: Option<AudioContext>,
    node: Option<ScriptProcessorNode>,
    callback: Option<Closure<dyn FnMut(AudioProcessingEvent)>>,
    mixer: Option<Rc<RefCell<Mixer>>>,
    failed: bool,
    last: Option<Cue>,
}

impl WebAudio {
    fn ensure_open(&mut self) -> Option<Rc<RefCell<Mixer>>> {
        if self.mixer.is_none() && !self.failed {
            if let Err(e) = self.open() {
                log::warn!("audio disabled: {e:?}");
                self.failed = true;
            }
        }
        if let Some(ctx) = &self.ctx {
            let _ = ctx.resume();
        }
        self.mixer.clone()
    }

    fn open(&mut self) -> Result<(), JsValue> {
        let ctx = AudioContext::new()?;
        let node = ctx.create_script_processor_with_buffer_size_and_number_of_input_channels_and_number_of_output_channels(BLOCK, 0, 2)?;
        let mixer = Rc::new(RefCell::new(Mixer::new(ctx.sample_rate() as u32)));
        let m = Rc::clone(&mixer);
        let mut inter = Vec::new();
        let (mut l, mut r) = (Vec::new(), Vec::new());
        let cb = Closure::<dyn FnMut(AudioProcessingEvent)>::new(move |ev: AudioProcessingEvent| {
            let Ok(out) = ev.output_buffer() else { return };
            let n = out.length() as usize;
            inter.resize(2 * n, 0.0f32);
            m.borrow_mut().render(&mut inter, 2);
            l.clear();
            r.clear();
            for f in inter.as_chunks::<2>().0 {
                l.push(f[0]);
                r.push(f[1]);
            }
            let _ = out.copy_to_channel(&l, 0);
            let _ = out.copy_to_channel(&r, 1);
        });
        node.set_onaudioprocess(Some(cb.as_ref().unchecked_ref()));
        node.connect_with_audio_node(&ctx.destination())?;
        self.ctx = Some(ctx);
        self.node = Some(node);
        self.callback = Some(cb);
        self.mixer = Some(mixer);
        Ok(())
    }

    fn load_missing(m: &Rc<RefCell<Mixer>>, cue: &Cue) {
        let missing = m.borrow().missing(cue);
        for a in missing {
            if let Some(p) = decode_asset(a) {
                m.borrow_mut().insert(a, Arc::new(p));
            }
        }
    }
}

impl Audio for WebAudio {
    fn update(&mut self, cue: &Cue, _music_dir: Option<&str>) {
        if self.last.as_ref() == Some(cue) {
            return;
        }
        self.last = Some(*cue);
        let mixer = if audible(cue) { self.ensure_open() } else { self.mixer.clone() };
        let Some(m) = mixer else { return };
        Self::load_missing(&m, cue);
        m.borrow_mut().set_cue(*cue);
    }

    fn trigger(&mut self, shot: OneShot) {
        if let Some(m) = self.ensure_open() {
            if let Some(cue) = self.last {
                Self::load_missing(&m, &cue);
            }
            m.borrow_mut().trigger(shot);
        }
    }
}
