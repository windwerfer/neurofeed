//! `neurofeed-mcp`: MCP server over stdio driving a headless Session.
//!
//! Usage: neurofeed-mcp [--manual-clock] [--device sim:muse|sim:crown|none]

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use rmcp::ServiceExt;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut manual = false;
    let mut device = Some("sim:muse".to_owned());
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--manual-clock" => manual = true,
            "--device" => device = args.next().filter(|d| d != "none"),
            "-h" | "--help" => {
                println!("neurofeed-mcp [--manual-clock] [--device sim:muse|sim:crown|none]");
                return Ok(());
            }
            other => return Err(format!("unknown argument `{other}`").into()),
        }
    }
    let clock = if manual { ClockMode::Manual } else { ClockMode::Wall(std::time::Instant::now()) };
    let server = NfMcp::new(Session::new(), clock);
    if let Some(id) = device {
        server.call("command_run", serde_json::json!({ "id": "device.connect", "params": { "id": id } })).map_err(|e| e.to_string())?;
    }
    server.serve(rmcp::transport::stdio()).await?.waiting().await?;
    Ok(())
}
