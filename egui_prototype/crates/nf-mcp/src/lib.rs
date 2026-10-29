//! # nf-mcp (L4)
//!
//! MCP server over `nf-core`. Following PhotoCraft/SolidCraft: generic
//! `command_list/describe/run/batch` tools reach every core command (add a
//! command, not a tool), plus a few typed session tools. Native only.
#![forbid(unsafe_code)]

use nf_core::{CoreError, Session};
use rmcp::model::{
    CallToolRequestParams, CallToolResponse, CallToolResult, ContentBlock, Implementation, ListToolsResult, PaginatedRequestParams,
    ServerCapabilities, ServerConfig, Tool, ToolAnnotations,
};
use rmcp::service::RequestContext;
use rmcp::{ErrorData as McpError, RoleServer, ServerHandler};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Instant;

const INSTRUCTIONS: &str = "NeuroFeed EEG neurofeedback app. Everything the app can do is a command: discover with command_list, \
read the typed params schema with command_describe, run with command_run, or several atomically with command_batch (rolls back on failure). \
Shortcuts: status (includes `revision`, bumped on every change), bands_get, device_list, clock_advance. Simulators: sim:muse, sim:crown. \
With --manual-clock, time only moves via clock_advance (deterministic).";

/// How session time advances between tool calls.
#[derive(Debug, Clone, Copy)]
pub enum ClockMode {
    /// Time moves only via `clock_advance`.
    Manual,
    /// Wall clock since server start (plus any `clock_advance`).
    Wall(Instant),
}

#[derive(Clone)]
pub struct NfMcp {
    session: Arc<Mutex<Session>>,
    clock: ClockMode,
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
];

impl NfMcp {
    pub fn new(session: Session, clock: ClockMode) -> Self {
        Self { session: Arc::new(Mutex::new(session)), clock }
    }

    /// MCP tool descriptors.
    pub fn tools() -> Vec<Tool> {
        TOOLS
            .iter()
            .map(|t| {
                let Value::Object(schema) = (t.schema)() else { return Tool::new(t.name, t.description, serde_json::Map::new()) };
                let mut tool = Tool::new(t.name, t.description, schema);
                let title = t.name.replace('_', " ");
                tool.title = Some(title.clone());
                tool.annotations =
                    Some(ToolAnnotations::from_raw(Some(title), Some(t.read_only), Some(false), Some(t.read_only), Some(false)));
                tool
            })
            .collect()
    }

    /// Run one tool call synchronously (used by the MCP handler and tests).
    /// Panics inside the core are caught and reported; the session survives.
    pub fn call(&self, tool: &str, args: Value) -> Result<Value, ToolError> {
        let def = TOOLS.iter().find(|t| t.name == tool).ok_or_else(|| ToolError::Invalid(format!("unknown tool `{tool}`")))?;
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
        let mut s = self.session.lock().unwrap_or_else(PoisonError::into_inner);
        if let ClockMode::Wall(start) = self.clock {
            s.tick(start.elapsed().as_secs_f64());
        }
        let session: &mut Session = &mut s;
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| dispatch(session, tool, args)))
            .unwrap_or_else(|_| Err(ToolError::Failed("internal error (panic caught); session kept".into())))
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

fn dispatch(s: &mut Session, tool: &str, args: serde_json::Map<String, Value>) -> Result<Value, ToolError> {
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
            s.call(id, args.get("params").cloned().unwrap_or(Value::Null)).map_err(failed)
        }
        "command_batch" => {
            let steps =
                args.get("steps").and_then(Value::as_array).ok_or_else(|| ToolError::Invalid("`steps` (array) is required".into()))?;
            let steps = steps
                .iter()
                .map(|st| {
                    let id = st.get("id").and_then(Value::as_str).ok_or_else(|| ToolError::Invalid("each step needs `id`".into()))?;
                    Ok((id.to_owned(), st.get("params").cloned().unwrap_or(Value::Null)))
                })
                .collect::<Result<Vec<_>, ToolError>>()?;
            s.batch(&steps).map_err(failed)
        }
        "status" => s.call("app.status", Value::Null).map_err(failed),
        "bands_get" => s.call("bands.get", Value::Object(args)).map_err(failed),
        "device_list" => s.call("device.list", Value::Null).map_err(failed),
        "clock_advance" => s.call("clock.advance", Value::Object(args)).map_err(failed),
        other => Err(ToolError::Invalid(format!("unknown tool `{other}`"))),
    }
}

impl ServerHandler for NfMcp {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(ServerCapabilities::builder().enable_tools().build())
            .with_server_info(Implementation::new("neurofeed", env!("CARGO_PKG_VERSION")))
            .with_instructions(INSTRUCTIONS)
    }

    async fn list_tools(&self, _: Option<PaginatedRequestParams>, _: RequestContext<RoleServer>) -> Result<ListToolsResult, McpError> {
        serde_json::from_value(json!({ "resultType": "complete", "tools": Self::tools() }))
            .map_err(|e| McpError::internal_error(e.to_string(), None))
    }

    async fn call_tool(&self, request: CallToolRequestParams, _: RequestContext<RoleServer>) -> Result<CallToolResponse, McpError> {
        let args = request.arguments.map(Value::Object).unwrap_or(Value::Null);
        let result = match self.call(&request.name, args) {
            Ok(v) => CallToolResult::success(vec![ContentBlock::text(v.to_string())]),
            Err(ToolError::Invalid(m)) => return Err(McpError::invalid_params(m, None)),
            Err(ToolError::Failed(m)) => CallToolResult::error(vec![ContentBlock::text(m)]),
        };
        Ok(result.into())
    }
}
