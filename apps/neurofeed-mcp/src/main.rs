//! `neurofeed-mcp`: MCP server over stdio driving a headless Session.
//!
//! Usage: neurofeed-mcp [--manual-clock] [--device sim:muse|sim:crown|none] [--db PATH]
//! History is in memory unless `--db` (or `NF_DB`) names a SQLite file.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use rmcp::ServiceExt;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut manual = false;
    let mut device = Some("sim:muse".to_owned());
    let mut db = std::env::var_os("NF_DB").map(std::path::PathBuf::from);
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--manual-clock" => manual = true,
            "--device" => device = args.next().filter(|d| d != "none"),
            "--db" => db = args.next().map(std::path::PathBuf::from),
            "-h" | "--help" => {
                println!("neurofeed-mcp [--manual-clock] [--device sim:muse|sim:crown|none] [--db PATH]");
                return Ok(());
            }
            other => return Err(format!("unknown argument `{other}`").into()),
        }
    }
    let clock = if manual { ClockMode::Manual } else { ClockMode::Wall(std::time::Instant::now()) };
    let session = match db {
        Some(p) => Session::new().with_store(Box::new(nf_store::SqliteStore::open(&p)?)),
        None => Session::new(),
    };
    let server = NfMcp::new(session, clock);
    if let Some(id) = device {
        server.call("command_run", serde_json::json!({ "id": "device.connect", "params": { "id": id } })).map_err(|e| e.to_string())?;
    }
    server.serve(rmcp::transport::stdio()).await?.waiting().await?;
    Ok(())
}
