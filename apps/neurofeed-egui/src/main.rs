//! Entry points. The only platform-specific code in the crate lives here.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")] // no console window in release

#[cfg(not(target_arch = "wasm32"))]
fn main() -> eframe::Result<()> {
    env_logger::init();
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("NeuroFeed")
            .with_inner_size([1100.0, 700.0])
            .with_min_inner_size([480.0, 320.0]),
        ..Default::default()
    };
    eframe::run_native("NeuroFeed", options, Box::new(|cc| Ok(Box::new(neurofeed_egui::NeuroFeedApp::new(cc)))))
}

#[cfg(target_arch = "wasm32")]
fn main() {
    use wasm_bindgen_futures::wasm_bindgen::JsCast;

    wasm_bindgen_futures::spawn_local(async {
        let Some(document) = web_sys::window().and_then(|w| w.document()) else {
            log::error!("no browser document");
            return;
        };
        let Some(canvas) = document.get_element_by_id("neurofeed_canvas").and_then(|e| e.dyn_into::<web_sys::HtmlCanvasElement>().ok())
        else {
            log::error!("canvas #neurofeed_canvas not found");
            return;
        };
        let result = eframe::WebRunner::new()
            .start(canvas, eframe::WebOptions::default(), Box::new(|cc| Ok(Box::new(neurofeed_egui::NeuroFeedApp::new(cc)))))
            .await;
        if let Err(err) = result {
            log::error!("failed to start eframe: {err:?}");
        }
    });
}
