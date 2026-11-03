//! # nf-mcp (L4)
//!
//! MCP server over `nf-core`. Following PhotoCraft/SolidCraft: generic
//! `command_list/describe/run/batch` tools reach every core command (add a
//! command, not a tool), plus a few typed session tools. Native only.
//!
//! Without the `server` feature (no rmcp/tokio) it is just the tool
//! dispatcher plus the [`bridge`], which the desktop app embeds so
//! `neurofeed-cli --bridge` can drive the live app.
#![forbid(unsafe_code)]

pub mod bridge;

use nf_core::{CoreError, Session};
#[cfg(feature = "server")]
use rmcp::model::{
    CallToolRequestParams, CallToolResponse, CallToolResult, ContentBlock, Implementation, ListToolsResult, PaginatedRequestParams,
    ServerCapabilities, ServerConfig, Tool, ToolAnnotations,
};
#[cfg(feature = "server")]
use rmcp::service::RequestContext;
#[cfg(feature = "server")]
use rmcp::{ErrorData as McpError, RoleServer, ServerHandler};
use serde_json::{json, Value};
#[cfg(feature = "server")]
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Instant;

#[cfg(feature = "server")]
const INSTRUCTIONS: &str = "NeuroFeed EEG neurofeedback app. Everything the app can do is a command: discover with command_list, \
read the typed params schema with command_describe, run with command_run, or several atomically with command_batch (rolls back on failure). \
Shortcuts: status (includes `revision`, bumped on every change), bands_get, device_list, clock_advance. Simulators: sim:muse_s, sim:muse2, sim:athena, sim:crown. \
With --manual-clock, time only moves via clock_advance (deterministic).";

/// How session time advances between tool calls.
#[derive(Debug, Clone, Copy)]
pub enum ClockMode {
    /// Time moves only via `clock_advance`.
    Manual,
    /// Wall clock since server start (plus any `clock_advance`).
    Wall(Instant),
    /// The host (the egui app) ticks the session itself; wall-clock stamps
    /// are still injected.
    Host,
}

/// Forwards a tool call elsewhere (bridge client).
#[cfg(feature = "server")]
pub type Forward = Arc<dyn Fn(&str, Value) -> Result<Value, ToolError> + Send + Sync>;

#[cfg(feature = "server")]
#[derive(Clone)]
enum Backend {
    Local { session: Arc<Mutex<Session>>, clock: ClockMode },
    Remote(Forward),
}

#[cfg(feature = "server")]
#[derive(Clone)]
pub struct NfMcp {
    backend: Backend,
}

/// A tool failure: `Invalid` maps to JSON-RPC -32602, `Failed` to an
/// `isError` result the model can read and correct.
#[derive(Debug, Clone, PartialEq)]
pub enum ToolError {
    Invalid(String),
    Failed(String),
}

impl std::fmt::Display for ToolError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ToolError::Invalid(m) | ToolError::Failed(m) => f.write_str(m),
        }
    }
}

fn failed(e: CoreError) -> ToolError {
    ToolError::Failed(e.to_string())
}

#[cfg_attr(not(feature = "server"), allow(dead_code))]
struct ToolDef {
    name: &'static str,
    description: &'static str,
    read_only: bool,
    schema: fn() -> Value,
}

fn schema(props: Value, required: &[&str]) -> Value {
    json!({ "type": "object", "properties": props, "required": required, "additionalProperties": false })
}

const TOOLS: &[ToolDef] = &[
    ToolDef {
        name: "command_list",
        description: "List commands (id, label, group, read_only, enabled, disabled_reason). Optional `group` filter.",
        read_only: true,
        schema: || schema(json!({ "group": { "type": "string" } }), &[]),
    },
    ToolDef {
        name: "command_describe",
        description: "Describe one command: metadata plus its JSON Schema (2020-12) for params.",
        read_only: true,
        schema: || schema(json!({ "id": { "type": "string" } }), &["id"]),
    },
    ToolDef {
        name: "command_run",
        description: "Run one command by id with params. A failing command changes nothing.",
        read_only: false,
        schema: || schema(json!({ "id": { "type": "string" }, "params": { "type": "object" } }), &["id"]),
    },
    ToolDef {
        name: "command_batch",
        description: "Run steps atomically: all are validated first; on any failure the state is rolled back.",
        read_only: false,
        schema: || {
            schema(
                json!({ "steps": { "type": "array", "items": schema(json!({ "id": { "type": "string" }, "params": { "type": "object" } }), &["id"]) } }),
                &["steps"],
            )
        },
    },
    ToolDef {
        name: "status",
        description: "App status incl. `revision` (compare to detect changes), view, device, paused, time.",
        read_only: true,
        schema: || schema(json!({}), &[]),
    },
    ToolDef {
        name: "bands_get",
        description: "Latest delta..gamma band powers per channel. `scale`: absolute (log10) or relative.",
        read_only: true,
        schema: || schema(json!({ "scale": { "type": "string", "enum": ["absolute", "relative"] } }), &[]),
    },
    ToolDef {
        name: "device_list",
        description: "Connectable devices (simulators and real providers).",
        read_only: true,
        schema: || schema(json!({}), &[]),
    },
    ToolDef {
        name: "clock_advance",
        description: "Advance session time by `seconds` (0 < s <= 3600), running the pipeline.",
        read_only: false,
        schema: || schema(json!({ "seconds": { "type": "number", "exclusiveMinimum": 0, "maximum": 3600 } }), &["seconds"]),
    },
    ToolDef {
        name: "recording_export",
        description: "Native shell only: like command_run recording.export, but with `path` writes the file there and returns \
                      {path, bytes} instead of base64. Without `path` it returns base64.",
        read_only: false,
        schema: || {
            schema(
                json!({
                    "format": { "enum": ["nfed6", "raw_body", "edf", "pdf"] },
                    "start": { "type": "array", "items": { "type": "integer" }, "minItems": 6, "maxItems": 6 },
                    "path": { "type": "string" },
                }),
                &["format"],
            )
        },
    },
];

/// Tools only the live app answers (bridge mode).
const BRIDGE_TOOLS: &[ToolDef] = &[
    ToolDef {
        name: "screenshot",
        description: "Bridge mode: PNG of the live app window. With `path` the PNG is written there and {path,width,height} \
                      returned; otherwise an image.",
        read_only: true,
        schema: || schema(json!({ "path": { "type": "string" } }), &[]),
    },
    ToolDef {
        name: "ui_inspect",
        description: "Bridge mode: the live app's widget tree (accessibility roles, labels, values, disabled/toggled, rects in points) \
                      for the current state. Drive the app with command_run; use this to check what the user sees.",
        read_only: true,
        schema: || schema(json!({}), &[]),
    },
];

/// Validate `args` against the tool's schema keys; returns the tool and the object.
fn check_args(tool: &str, args: Value, bridge: bool) -> Result<(&'static ToolDef, serde_json::Map<String, Value>), ToolError> {
    let def = TOOLS
        .iter()
        .chain(BRIDGE_TOOLS.iter().filter(|_| bridge))
        .find(|t| t.name == tool)
        .ok_or_else(|| ToolError::Invalid(format!("unknown tool `{tool}`")))?;
    let args = match args {
        Value::Null => serde_json::Map::new(),
        Value::Object(m) => m,
        _ => return Err(ToolError::Invalid("arguments must be an object".into())),
    };
    let schema = (def.schema)();
    let props = schema.get("properties").and_then(Value::as_object);
    if let Some(k) = args.keys().find(|k| !props.is_some_and(|p| p.contains_key(*k))) {
        return Err(ToolError::Invalid(format!("unknown argument `{k}` for {tool}")));
    }
    Ok((def, args))
}

/// Run a session tool directly on a session (the app's bridge handler and
/// the stdio server both end here). Panics are caught; the session survives.
pub fn run_tool(session: &mut Session, clock: ClockMode, tool: &str, args: Value) -> Result<Value, ToolError> {
    let (_, args) = check_args(tool, args, false)?;
    if let ClockMode::Wall(start) = clock {
        session.tick(start.elapsed().as_secs_f64());
    }
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| dispatch(session, clock, tool, args)))
        .unwrap_or_else(|_| Err(ToolError::Failed("internal error (panic caught); session kept".into())))
}

/// Shell-side injection: in wall-clock mode the MCP shell stamps
/// `recording.start` with the real start time (the core never reads a clock).
/// Manual-clock mode stays deterministic and injects nothing.
fn inject(clock: ClockMode, id: &str, params: Value) -> Value {
    if !matches!(id, "recording.start" | "feedback.start") || matches!(clock, ClockMode::Manual) {
        return params;
    }
    let mut m = match params {
        Value::Object(m) => m,
        Value::Null => serde_json::Map::new(),
        other => return other,
    };
    if !m.contains_key("wall_clock_unix_ms") {
        let ms = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs_f64() * 1000.0).unwrap_or(0.0);
        m.insert("wall_clock_unix_ms".into(), json!(ms));
    }
    Value::Object(m)
}

#[cfg(feature = "server")]
impl NfMcp {
    pub fn new(session: Session, clock: ClockMode) -> Self {
        Self { backend: Backend::Local { session: Arc::new(Mutex::new(session)), clock } }
    }

    /// Bridge mode: every call goes to the live app (adds screenshot, ui_inspect).
    pub fn remote(forward: Forward) -> Self {
        Self { backend: Backend::Remote(forward) }
    }

    fn is_remote(&self) -> bool {
        matches!(self.backend, Backend::Remote(_))
    }

    /// MCP tool descriptors (bridge tools only in bridge mode).
    /// App exit: disconnect devices and wait (see [`Session::shutdown`]).
    /// A remote (bridge) client owns no devices: nothing to do.
    pub fn shutdown(&self, timeout_s: f64) -> Vec<String> {
        match &self.backend {
            Backend::Local { session, .. } => session.lock().unwrap_or_else(std::sync::PoisonError::into_inner).shutdown(timeout_s),
            Backend::Remote(_) => Vec::new(),
        }
    }

    pub fn tool_list(&self) -> Vec<Tool> {
        Self::describe(TOOLS.iter().chain(BRIDGE_TOOLS.iter().filter(|_| self.is_remote())))
    }

    /// MCP tool descriptors of the local server.
    pub fn tools() -> Vec<Tool> {
        Self::describe(TOOLS.iter())
    }

    fn describe<'a>(defs: impl Iterator<Item = &'a ToolDef>) -> Vec<Tool> {
        defs.map(|t| {
            let Value::Object(schema) = (t.schema)() else { return Tool::new(t.name, t.description, serde_json::Map::new()) };
            let mut tool = Tool::new(t.name, t.description, schema);
            let title = t.name.replace('_', " ");
            tool.title = Some(title.clone());
            tool.annotations = Some(ToolAnnotations::from_raw(Some(title), Some(t.read_only), Some(false), Some(t.read_only), Some(false)));
            tool
        })
        .collect()
    }

    /// Run one tool call synchronously (used by the MCP handler and tests).
    /// Panics inside the core are caught and reported; the session survives.
    pub fn call(&self, tool: &str, args: Value) -> Result<Value, ToolError> {
        match &self.backend {
            Backend::Local { session, clock } => {
                let mut s = session.lock().unwrap_or_else(PoisonError::into_inner);
                run_tool(&mut s, *clock, tool, args)
            }
            Backend::Remote(fwd) => {
                let (_, mut args) = check_args(tool, args, true)?;
                // Files are written where this server runs.
                let path = if matches!(tool, "screenshot") { args.remove("path") } else { None };
                let mut v = fwd(tool, Value::Object(args))?;
                if let Some(path) = path {
                    let path = path.as_str().ok_or_else(|| ToolError::Invalid("`path` must be a string".into()))?;
                    let bytes = decode_base64(v["base64"].as_str().unwrap_or_default())
                        .ok_or_else(|| ToolError::Failed("bad base64 from app".into()))?;
                    std::fs::write(path, &bytes).map_err(|e| ToolError::Failed(format!("write {path}: {e}")))?;
                    if let Some(m) = v.as_object_mut() {
                        m.remove("base64");
                        m.insert("path".into(), json!(path));
                    }
                }
                Ok(v)
            }
        }
    }
}

fn str_arg<'a>(args: &'a serde_json::Map<String, Value>, key: &str) -> Result<&'a str, ToolError> {
    args.get(key).and_then(Value::as_str).ok_or_else(|| ToolError::Invalid(format!("`{key}` (string) is required")))
}

fn spec_json(s: &Session, spec: &nf_core::CommandSpec) -> Value {
    let enabled = s.enabled(spec.id);
    json!({
        "id": spec.id, "label": spec.label, "group": spec.group, "read_only": spec.read_only,
        "description": spec.description, "enabled": enabled.is_ok(), "disabled_reason": enabled.err(),
    })
}

fn dispatch(s: &mut Session, clock: ClockMode, tool: &str, args: serde_json::Map<String, Value>) -> Result<Value, ToolError> {
    match tool {
        "command_list" => {
            let group = args.get("group").and_then(Value::as_str);
            Ok(Value::Array(Session::commands().iter().filter(|c| group.is_none_or(|g| g == c.group)).map(|c| spec_json(s, c)).collect()))
        }
        "command_describe" => {
            let id = str_arg(&args, "id")?;
            let spec = nf_core::find(id).ok_or_else(|| ToolError::Failed(format!("unknown command `{id}`")))?;
            let mut v = spec_json(s, spec);
            v["params_schema"] = nf_core::input_schema(id).unwrap_or(Value::Null);
            Ok(v)
        }
        "command_run" => {
            let id = str_arg(&args, "id")?;
            s.call(id, inject(clock, id, args.get("params").cloned().unwrap_or(Value::Null))).map_err(failed)
        }
        "command_batch" => {
            let steps =
                args.get("steps").and_then(Value::as_array).ok_or_else(|| ToolError::Invalid("`steps` (array) is required".into()))?;
            let steps = steps
                .iter()
                .map(|st| {
                    let id = st.get("id").and_then(Value::as_str).ok_or_else(|| ToolError::Invalid("each step needs `id`".into()))?;
                    Ok((id.to_owned(), inject(clock, id, st.get("params").cloned().unwrap_or(Value::Null))))
                })
                .collect::<Result<Vec<_>, ToolError>>()?;
            s.batch(&steps).map_err(failed)
        }
        "status" => s.call("app.status", Value::Null).map_err(failed),
        "bands_get" => s.call("bands.get", Value::Object(args)).map_err(failed),
        "device_list" => s.call("device.list", Value::Null).map_err(failed),
        "clock_advance" => s.call("clock.advance", Value::Object(args)).map_err(failed),
        "recording_export" => {
            let mut params = args.clone();
            let path = params.remove("path");
            let mut reply = s.call("recording.export", Value::Object(params)).map_err(failed)?;
            let Some(path) = path else { return Ok(reply) };
            let path = path.as_str().ok_or_else(|| ToolError::Invalid("`path` must be a string".into()))?;
            let bytes = decode_base64(reply["base64"].as_str().unwrap_or_default())
                .ok_or_else(|| ToolError::Failed("internal: bad base64 from core".into()))?;
            std::fs::write(path, &bytes).map_err(|e| ToolError::Failed(format!("write {path}: {e}")))?;
            if let Some(m) = reply.as_object_mut() {
                m.remove("base64");
                m.insert("path".into(), json!(path));
            }
            Ok(reply)
        }
        other => Err(ToolError::Invalid(format!("unknown tool `{other}`"))),
    }
}

#[cfg(feature = "server")]
impl ServerHandler for NfMcp {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(ServerCapabilities::builder().enable_tools().build())
            .with_server_info(Implementation::new("neurofeed", nf_core::APP_VERSION))
            .with_instructions(INSTRUCTIONS)
    }

    async fn list_tools(&self, _: Option<PaginatedRequestParams>, _: RequestContext<RoleServer>) -> Result<ListToolsResult, McpError> {
        serde_json::from_value(json!({ "resultType": "complete", "tools": self.tool_list() }))
            .map_err(|e| McpError::internal_error(e.to_string(), None))
    }

    async fn call_tool(&self, request: CallToolRequestParams, _: RequestContext<RoleServer>) -> Result<CallToolResponse, McpError> {
        let args = request.arguments.map(Value::Object).unwrap_or(Value::Null);
        let result = match self.call(&request.name, args) {
            Ok(v) if v.get("mime").is_some() && v.get("base64").is_some() => {
                let data = v["base64"].as_str().unwrap_or_default().to_owned();
                let mime = v["mime"].as_str().unwrap_or("image/png").to_owned();
                let meta = json!({ "width": v["width"], "height": v["height"] });
                CallToolResult::success(vec![ContentBlock::image(data, mime), ContentBlock::text(meta.to_string())])
            }
            Ok(v) => CallToolResult::success(vec![ContentBlock::text(v.to_string())]),
            Err(ToolError::Invalid(m)) => return Err(McpError::invalid_params(m, None)),
            Err(ToolError::Failed(m)) => CallToolResult::error(vec![ContentBlock::text(m)]),
        };
        Ok(result.into())
    }
}

/// Standard base64 decode (no line breaks).
pub fn decode_base64(s: &str) -> Option<Vec<u8>> {
    let val = |c: u8| -> Option<u32> {
        Some(u32::from(match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => return None,
        }))
    };
    if !s.len().is_multiple_of(4) {
        return None;
    }
    let mut out = Vec::with_capacity(s.len() / 4 * 3);
    for chunk in s.as_bytes().chunks(4) {
        let pad = chunk.iter().rev().take_while(|&&c| c == b'=').count();
        let mut n = 0u32;
        for &c in &chunk[..4 - pad] {
            n = (n << 6) | val(c)?;
        }
        n <<= 6 * pad as u32;
        out.extend_from_slice(&n.to_be_bytes()[1..4 - pad]);
    }
    Some(out)
}
