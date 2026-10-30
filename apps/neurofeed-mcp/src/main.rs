//! `neurofeed-mcp`: MCP server over stdio.
//!
//! Headless (default): drives its own Session (simulators, plus Muse BLE
//! and Crown OSC on desktop). `--bridge`: drives the *running* NeuroFeed
//! app instead (start it with NF_BRIDGE=1 or Settings > Agents), adding the
//! `screenshot` and `ui_inspect` tools.

use nf_core::Session;
use nf_mcp::bridge::{default_info_path, BridgeClient, BridgeInfo};
use nf_mcp::{ClockMode, NfMcp};
use rmcp::ServiceExt;
use serde_json::{json, Value};
use std::sync::Arc;

const HELP: &str = "neurofeed-mcp [--manual-clock] [--device ID|none] [--no-hardware] [--db PATH]
neurofeed-mcp --bridge [FILE]

  --device ID     connect at start: sim:muse_s (default), sim:muse2, sim:athena, sim:crown,
                  muse:<ble-id>, crown:<id> (real devices are scanned for first, up to 8 s);
                  run device.scan + device.list to find ids
  --no-hardware   simulators only (no Bluetooth / UDP 9000)
  --manual-clock  time moves only via clock_advance (deterministic)
  --db PATH       SQLite history (default: in memory; or NF_DB)
  --bridge [FILE] drive the running app; FILE defaults to NF_BRIDGE_FILE or the data dir's bridge.json";

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut manual = false;
    let mut hardware = true;
    let mut device = Some("sim:muse_s".to_owned());
    let mut db = std::env::var_os("NF_DB").map(std::path::PathBuf::from);
    let mut bridge: Option<Option<std::path::PathBuf>> = None;
    let mut args = std::env::args().skip(1).peekable();
    while let Some(a) = args.next() {
        match a.as_str() {
            "--manual-clock" => manual = true,
            "--no-hardware" => hardware = false,
            "--device" => device = args.next().filter(|d| d != "none"),
            "--db" => db = args.next().map(std::path::PathBuf::from),
            "--bridge" => bridge = Some(args.next_if(|n| !n.starts_with("--")).map(std::path::PathBuf::from)),
            "-h" | "--help" => {
                println!("{HELP}");
                return Ok(());
            }
            other => return Err(format!("unknown argument `{other}`\n{HELP}").into()),
        }
    }
    let server = if let Some(file) = bridge {
        let path = file.or_else(default_info_path).ok_or("no bridge file (set NF_BRIDGE_FILE)")?;
        let info = BridgeInfo::read(&path).map_err(|e| format!("{e} — is NeuroFeed running with the agent bridge on (NF_BRIDGE=1)?"))?;
        let client = Arc::new(BridgeClient::connect(&info).map_err(|e| format!("bridge {}: {e}", info.addr))?);
        NfMcp::remote(Arc::new(move |tool: &str, args: Value| client.call(tool, args)))
    } else {
        let clock = if manual { ClockMode::Manual } else { ClockMode::Wall(std::time::Instant::now()) };
        let mut session = match db {
            Some(p) => Session::new().with_store(Box::new(nf_store::SqliteStore::open(&p)?)),
            None => Session::new(),
        };
        if hardware {
            for p in nf_device::native_providers() {
                session.register_provider(p);
            }
        }
        session.set_stream_sink(Box::new(nf_device::UdpSink::new()));
        session.set_stream_outlets(Box::new(nf_device::LslOutlets::new()));
        session.set_ai_runtime(Box::new(nf_ai::NativeAi::with_default_root()));
        let server = NfMcp::new(session, clock);
        if let Some(id) = device {
            connect(&server, &id).await?;
        }
        server
    };
    server.serve(rmcp::transport::stdio()).await?.waiting().await?;
    Ok(())
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
