//! History import: pick or drop a file, preview what is kept and lost, then
//! save through `history.import`. Parsing happens in the core
//! ([`Session::import_bytes`]); this view only gathers bytes and shows the
//! pre-save summary.

use egui::{Color32, RichText};
use nf_core::import::{base64_encode, ImportRequest, Preview};
use nf_core::{Command, Session};
use std::sync::Arc;

const WARN: Color32 = Color32::from_rgb(0xFF, 0xB7, 0x4D);
const BAD: Color32 = Color32::from_rgb(0xE5, 0x73, 0x73);

/// A file waiting for the user's decision.
#[derive(Clone)]
struct Pending {
    name: String,
    bytes: Arc<Vec<u8>>,
    preview: Result<Arc<Preview>, String>,
}

#[derive(Clone, Default)]
struct Ui {
    open: bool,
    path: String,
    pending: Option<Pending>,
}

/// Minutes east of UTC for files stamped in local time (EDF, Mind Monitor).
fn local_offset_minutes() -> i32 {
    use chrono::Offset;
    chrono::Local::now().offset().fix().local_minus_utc() / 60
}

fn load(session: &Session, name: String, bytes: Vec<u8>) -> Pending {
    let preview = session.import_bytes(&bytes, &name, local_offset_minutes()).map(|p| Arc::new(p.preview())).map_err(|e| e.to_string());
    Pending { name, bytes: Arc::new(bytes), preview }
}

/// The "Import…" button plus its window; also accepts dropped files.
pub fn show(ui: &mut egui::Ui, session: &Session, out: &mut Vec<Command>) {
    let id = ui.id().with("import");
    let mut st: Ui = ui.data(|d| d.get_temp(id)).unwrap_or_default();
    let en = session.enabled("history.import");
    let r = ui.add_enabled(en.is_ok(), egui::Button::new("Import…"));
    let r = r.on_hover_text("EDF/EDF+, Mind Monitor CSV, .neurofeed or raw NFEDBIN — or drop a file here");
    if r.clicked() {
        st.open = true;
    }
    if let Some((name, bytes)) = dropped(ui.ctx()).or_else(picked) {
        st.pending = Some(load(session, name, bytes));
        st.open = true;
    }
    if st.open {
        let mut open = true;
        egui::Window::new("Import a recording").open(&mut open).collapsible(false).default_width(520.0).show(ui.ctx(), |ui| {
            window(ui, session, &mut st, out);
        });
        st.open &= open;
    }
    ui.data_mut(|d| d.insert_temp(id, st));
}

fn window(ui: &mut egui::Ui, session: &Session, st: &mut Ui, out: &mut Vec<Command>) {
    source(ui, session, st);
    let Some(p) = st.pending.clone() else {
        ui.weak("Drop a file onto the window, or choose one above.");
        return;
    };
    ui.separator();
    ui.label(RichText::new(&p.name).strong());
    match &p.preview {
        Err(e) => {
            ui.label(RichText::new(e).color(BAD));
        }
        Ok(pv) => {
            summary(ui, pv);
            ui.add_space(8.0);
            ui.horizontal(|ui| {
                if ui.button("Save to history").clicked() {
                    let req = ImportRequest {
                        file_name: p.name.clone(),
                        data_base64: base64_encode(&p.bytes),
                        utc_offset_minutes: Some(local_offset_minutes()),
                    };
                    out.push(Command::HistoryImport(req));
                    *st = Ui::default();
                }
                if ui.button("Cancel").clicked() {
                    st.pending = None;
                }
            });
        }
    }
}

/// Desktop: a path field; web: the browser's file picker.
fn source(ui: &mut egui::Ui, session: &Session, st: &mut Ui) {
    ui.horizontal(|ui| {
        if cfg!(target_arch = "wasm32") {
            if ui.button("Choose file…").clicked() {
                open_picker();
            }
            return;
        }
        ui.add(egui::TextEdit::singleline(&mut st.path).hint_text("/path/to/recording.edf").desired_width(360.0));
        if ui.add_enabled(!st.path.trim().is_empty(), egui::Button::new("Open")).clicked() {
            st.pending = Some(read_path(session, st.path.trim()));
        }
    });
}

fn summary(ui: &mut egui::Ui, pv: &Preview) {
    let pr = &pv.provenance;
    ui.weak(format!("{} · {} · {:.0} s", pr.source_format, pv.device.channels.join(" "), pv.duration_s));
    if let Some(t) = pv.started_unix_ms {
        ui.weak(format!("recorded {}", super::history::local_time(t)));
    }
    ui.label(RichText::new("Kept").strong());
    for k in &pv.summary.kept {
        ui.label(format!("✔ {k}"));
    }
    if !pv.summary.lost.is_empty() {
        ui.label(RichText::new("Not imported").strong());
        for l in &pv.summary.lost {
            ui.label(RichText::new(format!("✖ {l}")).color(WARN));
        }
    }
    for w in pv.summary.coverage.iter().chain(&pr.warnings).filter(|w| !pv.summary.lost.contains(w)) {
        ui.label(RichText::new(format!("⚠ {w}")).color(WARN));
    }
}

fn dropped(ctx: &egui::Context) -> Option<(String, Vec<u8>)> {
    let f = ctx.input(|i| i.raw.dropped_files.first().cloned())?;
    if let Some(b) = f.bytes {
        return Some((f.name, b.to_vec()));
    }
    let path = f.path?;
    let name = path.file_name()?.to_string_lossy().into_owned();
    std::fs::read(&path).ok().map(|b| (name, b))
}

#[cfg(not(target_arch = "wasm32"))]
fn read_path(session: &Session, path: &str) -> Pending {
    let name = std::path::Path::new(path).file_name().map_or(path.to_owned(), |n| n.to_string_lossy().into_owned());
    match std::fs::read(path) {
        Ok(b) => load(session, name, b),
        Err(e) => Pending { name, bytes: Arc::default(), preview: Err(format!("Cannot read file: {e}")) },
    }
}

#[cfg(target_arch = "wasm32")]
fn read_path(_: &Session, path: &str) -> Pending {
    Pending { name: path.to_owned(), bytes: Arc::default(), preview: Err("no file system in the browser".into()) }
}

#[cfg(not(target_arch = "wasm32"))]
fn open_picker() {}

#[cfg(not(target_arch = "wasm32"))]
fn picked() -> Option<(String, Vec<u8>)> {
    None
}

#[cfg(target_arch = "wasm32")]
use web::{open_picker, picked};

/// Browser file picker: a hidden `<input type=file>`; the chosen file's bytes
/// arrive asynchronously and are polled by [`picked`] each frame.
#[cfg(target_arch = "wasm32")]
mod web {
    use std::cell::RefCell;
    use wasm_bindgen::{closure::Closure, JsCast};

    thread_local! {
        static PICKED: RefCell<Option<(String, Vec<u8>)>> = const { RefCell::new(None) };
    }

    pub fn picked() -> Option<(String, Vec<u8>)> {
        PICKED.with(|p| p.borrow_mut().take())
    }

    pub fn open_picker() {
        let Some(doc) = web_sys::window().and_then(|w| w.document()) else { return };
        let Ok(input) = doc.create_element("input").map(|e| e.unchecked_into::<web_sys::HtmlInputElement>()) else { return };
        input.set_type("file");
        input.set_accept(".edf,.bdf,.csv,.neurofeed,.nfed,.bin");
        let el = input.clone();
        let on_change = Closure::<dyn FnMut()>::new(move || {
            if let Some(file) = el.files().and_then(|f| f.get(0)) {
                wasm_bindgen_futures::spawn_local(read(file));
            }
        });
        input.set_onchange(Some(on_change.as_ref().unchecked_ref()));
        on_change.forget();
        input.click();
    }

    async fn read(file: web_sys::File) {
        let Ok(buf) = wasm_bindgen_futures::JsFuture::from(file.array_buffer()).await else { return };
        let bytes = js_sys::Uint8Array::new(&buf).to_vec();
        PICKED.with(|p| *p.borrow_mut() = Some((file.name(), bytes)));
    }
}
