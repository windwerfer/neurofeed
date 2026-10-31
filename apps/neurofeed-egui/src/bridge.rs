//! Desktop only: answers `neurofeed-mcp --bridge` requests on the UI thread.
//! Session tools go through `nf_mcp::run_tool` (same dispatcher as the stdio
//! server); `screenshot` grabs the real window, `ui_inspect` re-runs the UI
//! once off-screen with AccessKit on and returns the widget tree.

use crate::ui;
use egui::accesskit;
use nf_core::Session;
use nf_mcp::bridge::{BridgeServer, Request};
use nf_mcp::{ClockMode, ToolError};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};

type Shot = Arc<Mutex<Option<Arc<egui::ColorImage>>>>;

/// Give up on a screenshot the window never delivered (minimized, ...).
const SHOT_TIMEOUT_S: f64 = 5.0;

pub struct Bridge {
    server: BridgeServer,
    shots: Vec<(Request, f64)>,
    /// Filled by the screenshot callback (egui 0.37 delivers it there).
    shot: Shot,
}

impl Bridge {
    pub fn start(ctx: &egui::Context) -> std::io::Result<Self> {
        let c = ctx.clone();
        let server = BridgeServer::start(nf_mcp::bridge::default_info_path(), Arc::new(move || c.request_repaint()))?;
        log::info!("MCP bridge on {} (neurofeed-mcp --bridge)", server.info().addr);
        Ok(Self { server, shots: Vec::new(), shot: Shot::default() })
    }

    pub fn addr(&self) -> String {
        self.server.info().addr.to_string()
    }

    /// Answer pending requests. Returns true if a session tool ran.
    pub fn poll(&mut self, ctx: &egui::Context, session: &mut Session, last_error: Option<&str>) -> bool {
        let now = ctx.input(|i| i.time);
        let shot = self.shot.lock().ok().and_then(|mut s| s.take());
        if let Some(img) = shot {
            let reply = png_reply(&img);
            self.shots.drain(..).for_each(|(r, _)| r.respond(reply.clone()));
        }
        let (late, keep): (Vec<_>, Vec<_>) = self.shots.drain(..).partition(|(_, t)| now - t > SHOT_TIMEOUT_S);
        self.shots = keep;
        late.into_iter().for_each(|(r, _)| r.respond(Err(ToolError::Failed("window did not deliver a screenshot (minimized?)".into()))));
        let mut ran = false;
        while let Some(req) = self.server.try_recv() {
            match req.tool.as_str() {
                "screenshot" => {
                    let (slot, c) = (self.shot.clone(), ctx.clone());
                    let cb = egui::ScreenshotCallback::new(move |img| {
                        if let Ok(mut s) = slot.lock() {
                            *s = Some(img);
                        }
                        c.request_repaint();
                    });
                    ctx.send_viewport_cmd(egui::ViewportCommand::Screenshot(cb));
                    self.shots.push((req, now));
                }
                "ui_inspect" => {
                    let r = Ok(inspect(ctx, session, last_error));
                    req.respond(r);
                }
                _ => {
                    let r = nf_mcp::run_tool(session, ClockMode::Host, &req.tool, req.args.clone());
                    req.respond(r);
                    ran = true;
                }
            }
        }
        ran
    }
}

fn png_reply(img: &egui::ColorImage) -> Result<Value, ToolError> {
    let [w, h] = img.size;
    let mut buf = Vec::new();
    {
        let mut enc = png::Encoder::new(&mut buf, w as u32, h as u32);
        enc.set_color(png::ColorType::Rgba);
        enc.set_depth(png::BitDepth::Eight);
        let fail = |e: png::EncodingError| ToolError::Failed(format!("png: {e}"));
        let mut wr = enc.write_header().map_err(fail)?;
        wr.write_image_data(img.as_raw()).map_err(fail)?;
    }
    Ok(json!({ "mime": "image/png", "width": w, "height": h, "base64": base64(&buf) }))
}

fn base64(b: &[u8]) -> String {
    const A: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut s = String::with_capacity(b.len().div_ceil(3) * 4);
    for c in b.chunks(3) {
        let n = (u32::from(c[0]) << 16) | (u32::from(*c.get(1).unwrap_or(&0)) << 8) | u32::from(*c.get(2).unwrap_or(&0));
        for i in 0..4 {
            s.push(if i <= c.len() { A[(n >> (18 - 6 * i) & 63) as usize] as char } else { '=' });
        }
    }
    s
}

/// The widget tree the user currently sees, as nested JSON.
pub fn inspect(live: &egui::Context, session: &Session, last_error: Option<&str>) -> Value {
    let ctx = egui::Context::default();
    ui::theme::apply(&ctx);
    ctx.enable_accesskit();
    let input = egui::RawInput { screen_rect: Some(live.viewport_rect()), ..Default::default() };
    // Two passes: layouts that size themselves on the first frame settle.
    // Nothing renders these passes; drop their texture uploads explicitly.
    ctx.run_ui(input.clone(), |u| drop(ui::show(u, session, last_error))).textures_delta.clear();
    let mut out = ctx.run_ui(input, |u| drop(ui::show(u, session, last_error)));
    out.textures_delta.clear();
    let Some(update) = out.platform_output.accesskit_update else { return json!({ "error": "no accessibility output" }) };
    let nodes: std::collections::HashMap<_, _> = update.nodes.into_iter().collect();
    let root = update.tree.map(|t| t.root);
    root.map_or(Value::Null, |r| node_json(&nodes, r, 0))
}

fn node_json(nodes: &std::collections::HashMap<accesskit::NodeId, accesskit::Node>, id: accesskit::NodeId, depth: usize) -> Value {
    let Some(n) = nodes.get(&id) else { return Value::Null };
    let mut v = serde_json::Map::new();
    v.insert("role".into(), json!(format!("{:?}", n.role())));
    // AccessKit 0.25 carries a text label's words in `value`; keep `label` for agents.
    let text_label = (n.role() == accesskit::Role::Label).then(|| n.value()).flatten();
    if let Some(s) = n.label().or(text_label) {
        v.insert("label".into(), json!(s));
    }
    if let Some(s) = n.value() {
        v.insert("value".into(), json!(s));
    }
    if let Some(x) = n.numeric_value() {
        v.insert("number".into(), json!(x));
    }
    if n.is_disabled() {
        v.insert("disabled".into(), json!(true));
    }
    if let Some(t) = n.toggled() {
        v.insert("toggled".into(), json!(format!("{t:?}").to_lowercase()));
    }
    if let Some(b) = n.bounds() {
        let r = |x: f64| (x * 10.0).round() / 10.0;
        v.insert("rect".into(), json!([r(b.x0), r(b.y0), r(b.x1 - b.x0), r(b.y1 - b.y0)]));
    }
    let kids: Vec<Value> =
        if depth < 64 { n.children().iter().map(|c| node_json(nodes, *c, depth + 1)).filter(|c| !c.is_null()).collect() } else { vec![] };
    // Collapse anonymous containers with a single child.
    if v.len() <= 2 && v.get("role").is_some_and(|r| r == "GenericContainer") && kids.len() == 1 && !v.contains_key("label") {
        return kids.into_iter().next().unwrap_or(Value::Null);
    }
    if !kids.is_empty() {
        v.insert("children".into(), Value::Array(kids));
    }
    Value::Object(v)
}
