//! `neurofeed-cli`: NeuroFeed automation from the shell or an agent.
//!
//! Every subcommand goes through the same [`NfMcp::call`] dispatcher as the
//! MCP server (command registry in nf-core), against either a headless
//! Session (default: simulators, plus Muse BLE / Crown OSC on desktop) or the
//! running app (`--bridge`, start the app with NF_BRIDGE=1 or Settings > About
//! > Agents). Installed as `neurofeed-mcp` too, which defaults to `mcp`.

use nf_core::Session;
use nf_mcp::bridge::{default_info_path, BridgeClient, BridgeInfo};
use nf_mcp::{ClockMode, NfMcp, ToolError};
use rmcp::ServiceExt;
use serde_json::{json, Value};
use std::io::{BufRead, Read, Write};
use std::sync::Arc;

const HELP: &str = "neurofeed-cli [GLOBAL FLAGS] <SUBCOMMAND>

Subcommands:
  list [GROUP]              commands (id, label, group, read_only, enabled, disabled_reason)
  describe <ID>             one command with its params JSON Schema
  run <ID|TOOL> [JSON]      run a command (dotted id, e.g. device.connect) or a tool
                            (e.g. status, bands_get, screenshot) with JSON params
  batch <FILE|->            run steps atomically (rolls back on failure); JSON
                            [{\"id\",\"params\"}, ...] or {\"steps\": [...]}
  serve                     JSON lines on stdin/stdout: {\"id\",\"method\",\"params\"} ->
                            {\"id\",\"ok\":true,\"result\"} | {\"id\",\"ok\":false,\"error\",\"invalid\"}
  mcp                       MCP server over stdio (default when run as neurofeed-mcp)

Global flags (before the subcommand):
  --device ID     connect at start: sim:muse_s (default), sim:muse2, sim:athena, sim:crown,
                  muse:<ble-id>, crown:<id> (real devices are scanned for first, up to 8 s),
                  or none
  --no-hardware   simulators only (no Bluetooth / UDP 9000)
  --manual-clock  time moves only via clock_advance (deterministic)
  --db PATH       SQLite history (default: in memory; or NF_DB)
  --bridge [FILE] drive the running app instead; FILE defaults to NF_BRIDGE_FILE or the
                  data dir's bridge.json (--device/--db/--manual-clock are ignored)

Results are JSON on stdout. Errors are JSON on stderr ({\"error\",\"invalid\"}), exit code
1 (command failed, nothing changed) or 2 (invalid arguments / usage).";

struct Opts {
    manual: bool,
    hardware: bool,
    device: Option<String>,
    db: Option<std::path::PathBuf>,
    bridge: Option<Option<std::path::PathBuf>>,
}

fn usage(msg: &str) -> ! {
    eprintln!("{}", json!({ "error": msg, "invalid": true }));
    eprintln!("\n{HELP}");
    std::process::exit(2)
}

/// Entry point of both binaries. `default_mcp`: no subcommand means `mcp`
/// (the `neurofeed-mcp` compatibility binary).
pub fn run(default_mcp: bool) {
    match tokio::runtime::Builder::new_multi_thread().enable_all().build() {
        Ok(rt) => rt.block_on(async_main(default_mcp)),
        Err(e) => {
            eprintln!("{}", json!({ "error": format!("tokio runtime: {e}") }));
            std::process::exit(1)
        }
    }
}

async fn async_main(as_mcp: bool) {
    let mut o = Opts {
        manual: false,
        hardware: true,
        device: Some("sim:muse_s".to_owned()),
        db: std::env::var_os("NF_DB").map(Into::into),
        bridge: None,
    };
    let mut args = std::env::args().skip(1).peekable();
    let mut rest: Vec<String> = Vec::new();
    while let Some(a) = args.next() {
        if !rest.is_empty() {
            rest.push(a);
            continue;
        }
        match a.as_str() {
            "--manual-clock" => o.manual = true,
            "--no-hardware" => o.hardware = false,
            "--device" => o.device = args.next().filter(|d| d != "none"),
            "--db" => o.db = args.next().map(Into::into),
            "--bridge" => o.bridge = Some(args.next_if(|n| !n.starts_with("--") && !is_subcommand(n)).map(Into::into)),
            "-h" | "--help" | "help" => {
                println!("{HELP}");
                return;
            }
            s if s.starts_with("--") => usage(&format!("unknown flag `{s}`")),
            _ => rest.push(a),
        }
    }
    if rest.is_empty() {
        if as_mcp {
            rest.push("mcp".into());
        } else {
            usage("missing subcommand");
        }
    }
    let server = match build(&o).await {
        Ok(s) => s,
        Err(e) => {
            eprintln!("{}", json!({ "error": e, "invalid": false }));
            std::process::exit(1)
        }
    };
    tokio::spawn(exit_on_signal(server.clone()));
    let sub = rest.remove(0);
    let code = match sub.as_str() {
        "mcp" => match server.clone().serve(rmcp::transport::stdio()).await {
            Ok(running) => i32::from(running.waiting().await.is_err()),
            Err(e) => {
                eprintln!("mcp: {e}");
                1
            }
        },
        "serve" => serve(&server),
        "list" => print(server.call("command_list", rest.first().map_or(json!({}), |g| json!({ "group": g })))),
        "describe" => {
            let id = rest.first().unwrap_or_else(|| usage("describe <ID>"));
            print(server.call("command_describe", json!({ "id": id })))
        }
        "run" => {
            let id = rest.first().unwrap_or_else(|| usage("run <ID|TOOL> [JSON]"));
            let params = match rest.get(1) {
                Some(s) => serde_json::from_str(s).unwrap_or_else(|e| usage(&format!("params are not JSON: {e}"))),
                None => Value::Null,
            };
            print(call(&server, id, params))
        }
        "batch" => {
            let src = rest.first().unwrap_or_else(|| usage("batch <FILE|->"));
            let path = src.clone();
            let text = tokio::task::spawn_blocking(move || {
                if path == "-" {
                    let mut s = String::new();
                    std::io::stdin().read_to_string(&mut s).map(|_| s)
                } else {
                    std::fs::read_to_string(&path)
                }
            })
            .await
            .unwrap_or_else(|e| Err(std::io::Error::other(e)))
            .unwrap_or_else(|e| usage(&format!("read {src}: {e}")));
            let v: Value = serde_json::from_str(&text).unwrap_or_else(|e| usage(&format!("{src} is not JSON: {e}")));
            let steps = if v.is_array() {
                v
            } else {
                v.get("steps").cloned().unwrap_or_else(|| usage("expected an array of steps or {\"steps\": [...]}"))
            };
            print(server.call("command_batch", json!({ "steps": steps })))
        }
        other => usage(&format!("unknown subcommand `{other}`")),
    };
    shutdown(&server);
    std::process::exit(code)
}

/// Disconnect the headset and wait (max 10 s) before the process ends, so it
/// advertises again for the next start (.ai/contracts/device-autoconnect.md).
fn shutdown(server: &NfMcp) {
    for e in server.shutdown(nf_core::SHUTDOWN_TIMEOUT_S) {
        eprintln!("{}", json!({ "warning": format!("shutdown: {e}") }));
    }
}

/// SIGINT / SIGTERM: same clean shutdown, then exit 130.
async fn exit_on_signal(server: NfMcp) {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let Ok(mut term) = signal(SignalKind::terminate()) else { return };
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            _ = term.recv() => {}
        }
    }
    #[cfg(not(unix))]
    if tokio::signal::ctrl_c().await.is_err() {
        return;
    }
    tokio::task::spawn_blocking(move || shutdown(&server)).await.ok();
    std::process::exit(130)
}

fn is_subcommand(s: &str) -> bool {
    matches!(s, "list" | "describe" | "run" | "batch" | "serve" | "mcp")
}

async fn build(o: &Opts) -> Result<NfMcp, String> {
    if let Some(file) = &o.bridge {
        let path = file.clone().or_else(default_info_path).ok_or("no bridge file (set NF_BRIDGE_FILE)")?;
        let info = BridgeInfo::read(&path)
            .map_err(|e| format!("{e} — is NeuroFeed running with the agent bridge on (NF_BRIDGE=1 or Settings > About > Agents)?"))?;
        let client = Arc::new(BridgeClient::connect(&info).map_err(|e| format!("bridge {}: {e}", info.addr))?);
        return Ok(NfMcp::remote(Arc::new(move |tool: &str, args: Value| client.call(tool, args))));
    }
    let clock = if o.manual { ClockMode::Manual } else { ClockMode::Wall(std::time::Instant::now()) };
    let mut session = match &o.db {
        Some(p) => Session::new().with_store(Box::new(nf_store::SqliteStore::open(p).map_err(|e| format!("--db {}: {e}", p.display()))?)),
        None => Session::new(),
    };
    if o.hardware {
        for p in nf_device::native_providers() {
            session.register_provider(p);
        }
    }
    session.set_stream_sink(Box::new(nf_device::UdpSink::new()));
    session.set_stream_outlets(Box::new(nf_device::LslOutlets::new()));
    session.set_ai_runtime(Box::new(nf_ai::NativeAi::with_default_root()));
    let server = NfMcp::new(session, clock);
    if let Some(id) = &o.device {
        connect(&server, id).await?;
    }
    Ok(server)
}

/// A dotted command id runs through `command_run`; a tool name is called as is.
fn call(server: &NfMcp, method: &str, params: Value) -> Result<Value, ToolError> {
    if server.tool_list().iter().any(|t| t.name == method) {
        server.call(method, params)
    } else {
        server.call("command_run", json!({ "id": method, "params": params }))
    }
}

/// Bad input (exit 2): a tool-level -32602 or a command rejecting its id/params.
fn is_invalid(e: &ToolError) -> bool {
    match e {
        ToolError::Invalid(_) => true,
        ToolError::Failed(m) => m.starts_with("invalid arguments") || m.starts_with("unknown command"),
    }
}

fn print(r: Result<Value, ToolError>) -> i32 {
    match r {
        Ok(v) => {
            println!("{}", serde_json::to_string_pretty(&v).unwrap_or_else(|_| v.to_string()));
            0
        }
        Err(e) => {
            let invalid = is_invalid(&e);
            eprintln!("{}", json!({ "error": e.to_string(), "invalid": invalid }));
            if invalid {
                2
            } else {
                1
            }
        }
    }
}

/// JSON lines: one request per line, one reply per line, in order.
fn serve(server: &NfMcp) -> i32 {
    let stdout = std::io::stdout();
    for line in std::io::stdin().lock().lines() {
        let Ok(line) = line else { return 1 };
        if line.trim().is_empty() {
            continue;
        }
        let reply = match serde_json::from_str::<Value>(&line) {
            Err(e) => json!({ "id": Value::Null, "ok": false, "error": format!("not JSON: {e}"), "invalid": true }),
            Ok(req) => {
                let id = req.get("id").cloned().unwrap_or(Value::Null);
                match req.get("method").and_then(Value::as_str) {
                    None => json!({ "id": id, "ok": false, "error": "`method` (string) is required", "invalid": true }),
                    Some(m) => match call(server, m, req.get("params").cloned().unwrap_or(Value::Null)) {
                        Ok(result) => json!({ "id": id, "ok": true, "result": result }),
                        Err(e) => json!({ "id": id, "ok": false, "error": e.to_string(), "invalid": is_invalid(&e) }),
                    },
                }
            }
        };
        let mut out = stdout.lock();
        if writeln!(out, "{reply}").and_then(|()| out.flush()).is_err() {
            return 1;
        }
    }
    0
}

/// Connect; for a real device id not seen yet, scan first.
async fn connect(server: &NfMcp, id: &str) -> Result<(), String> {
    let run = |cmd: &str, params: Value| server.call("command_run", json!({ "id": cmd, "params": params })).map_err(|e| e.to_string());
    let known = |s: &NfMcp| s.call("device_list", Value::Null).is_ok_and(|l| l.as_array().is_some_and(|a| a.iter().any(|d| d["id"] == id)));
    if !id.starts_with("sim:") && !known(server) {
        run("device.scan", json!({ "seconds": 8 }))?;
        for _ in 0..90 {
            if known(server) {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        }
    }
    run("device.connect", json!({ "id": id })).map(drop)
}
