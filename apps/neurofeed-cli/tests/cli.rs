//! End-to-end tests of every `neurofeed-cli` subcommand (headless, simulators
//! only) plus a doc check: the automation docs must not name a tool or
//! command that does not exist.

#![allow(clippy::panic, clippy::expect_used, clippy::unwrap_used)]
use serde_json::Value;
use std::io::Write;
use std::process::{Command, Output, Stdio};

fn cli(args: &[&str], stdin: Option<&str>) -> Output {
    let mut child = Command::new(env!("CARGO_BIN_EXE_neurofeed-cli"))
        .args(["--no-hardware", "--manual-clock"])
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn neurofeed-cli");
    let mut input = child.stdin.take().expect("stdin");
    input.write_all(stdin.unwrap_or("").as_bytes()).expect("write stdin");
    drop(input);
    child.wait_with_output().expect("wait")
}

fn json_out(o: &Output) -> Value {
    serde_json::from_slice(&o.stdout).unwrap_or_else(|e| panic!("stdout not JSON ({e}): {}", String::from_utf8_lossy(&o.stdout)))
}

#[test]
fn list_and_describe() {
    let o = cli(&["list"], None);
    assert!(o.status.success());
    let list = json_out(&o);
    assert!(list.as_array().expect("array").iter().any(|c| c["id"] == "device.connect"));
    let o = cli(&["list", "device"], None);
    assert!(json_out(&o).as_array().expect("array").iter().all(|c| c["group"] == "device"));
    let o = cli(&["describe", "sim.fault.add"], None);
    assert!(o.status.success());
    assert!(json_out(&o)["params_schema"]["properties"]["kind"]["enum"].is_array());
}

#[test]
fn run_command_tool_and_errors() {
    let o = cli(&["run", "status"], None);
    assert!(o.status.success());
    assert_eq!(json_out(&o)["device"], "sim:muse_s");
    let o = cli(&["--device", "none", "run", "device.connect", r#"{"id":"sim:crown"}"#], None);
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    let o = cli(&["run", "device.connect", r#"{"id":"sim:nope"}"#], None);
    assert_eq!(o.status.code(), Some(1));
    let err: Value = serde_json::from_slice(&o.stderr).expect("stderr JSON");
    assert!(err["error"].as_str().is_some_and(|e| e.contains("sim:nope")));
    assert_eq!(cli(&["run", "no.such"], None).status.code(), Some(2));
    assert_eq!(cli(&["run", "status", "{not json"], None).status.code(), Some(2));
    assert_eq!(cli(&["frobnicate"], None).status.code(), Some(2));
}

#[test]
fn batch_file_stdin_and_rollback() {
    let dir = std::env::temp_dir().join(format!("nf-cli-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("tmp");
    let file = dir.join("b.json");
    std::fs::write(&file, r#"{"steps":[{"id":"view.set","params":{"view":"psd"}},{"id":"scale.set","params":{"scale":"relative"}}]}"#)
        .expect("write");
    let o = cli(&["batch", file.to_str().expect("utf8")], None);
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    assert_eq!(json_out(&o)["results"].as_array().map(Vec::len), Some(2));
    let o = cli(&["batch", "-"], Some(r#"[{"id":"view.set","params":{"view":"psd"}},{"id":"device.connect","params":{"id":"sim:nope"}}]"#));
    assert_eq!(o.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&o.stderr).contains("rolled back"));
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn serve_json_lines() {
    let input = r#"{"id":1,"method":"clock_advance","params":{"seconds":2}}
{"id":"b","method":"bands.get"}
{"id":3,"method":"nope.cmd"}
not json
{"id":5,"method":"status"}
"#;
    let o = cli(&["serve"], Some(input));
    assert!(o.status.success());
    let lines: Vec<Value> = String::from_utf8_lossy(&o.stdout).lines().map(|l| serde_json::from_str(l).expect("line JSON")).collect();
    assert_eq!(lines.len(), 5);
    assert_eq!(lines[0]["result"]["time"], 2.0);
    assert_eq!(lines[1]["id"], "b");
    assert!(lines[1]["ok"].as_bool().unwrap_or(false));
    assert_eq!(lines[2]["ok"], false);
    assert_eq!(lines[2]["invalid"], true);
    assert_eq!(lines[3]["invalid"], true);
    assert_eq!(lines[4]["result"]["device"], "sim:muse_s");
}

#[test]
fn mcp_initialize_and_call() {
    let input = concat!(
        r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#,
        "\n",
        r#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
        "\n",
        r#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"clock_advance","arguments":{"seconds":1}}}"#,
        "\n",
        r#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ui_set","arguments":{}}}"#,
        "\n",
    );
    let o = cli(&["mcp"], Some(input));
    let replies: Vec<Value> = String::from_utf8_lossy(&o.stdout).lines().filter_map(|l| serde_json::from_str(l).ok()).collect();
    let by_id = |id: i64| replies.iter().find(|r| r["id"] == id).unwrap_or_else(|| panic!("no reply {id}: {replies:?}"));
    assert_eq!(by_id(1)["result"]["serverInfo"]["name"], "neurofeed");
    assert_eq!(by_id(2)["result"]["isError"], false);
    assert_eq!(by_id(3)["error"]["code"], -32602);
}

/// Backticked names in the agent-facing docs must exist: dotted ids whose
/// group is a real command group must be commands; `snake_case` names that
/// look like tools must be tools.
#[test]
fn docs_name_only_real_tools_and_commands() {
    let root = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
    let commands: Vec<&str> = nf_core::Session::commands().iter().map(|c| c.id).collect();
    let groups: Vec<&str> = commands.iter().filter_map(|c| c.split('.').next()).collect();
    let forward: nf_mcp::Forward = std::sync::Arc::new(|_: &str, _: Value| Ok(Value::Null));
    let tools: Vec<String> = nf_mcp::NfMcp::remote(forward).tool_list().into_iter().map(|t| t.name.to_string()).collect();
    let tool_prefixes = ["command_", "ui_", "bands_", "device_", "clock_", "recording_", "status_", "screenshot_"];
    let mut bad = Vec::new();
    for doc in ["docs/automation.md", "docs/design-mcp-core.md", "AGENTS.md", ".grok/skills/neurofeed-mcp/SKILL.md"] {
        let text = std::fs::read_to_string(format!("{root}/{doc}")).unwrap_or_else(|e| panic!("{doc}: {e}"));
        for (i, chunk) in text.split('`').enumerate() {
            if i % 2 == 0 {
                continue;
            }
            // The leading word: `device.connect {"id":..}` -> device.connect.
            let word = chunk.split(|c: char| c.is_whitespace() || c == '{' || c == '(').next().unwrap_or("");
            if word.is_empty() || !word.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '.' || c == '_') {
                continue;
            }
            if word.contains('.') {
                let group = word.split('.').next().unwrap_or("");
                if groups.contains(&group) && !commands.contains(&word) {
                    bad.push(format!("{doc}: command `{word}`"));
                }
            } else if tool_prefixes.iter().any(|p| word.starts_with(p)) && !tools.iter().any(|t| t == word) {
                bad.push(format!("{doc}: tool `{word}`"));
            }
        }
    }
    assert!(bad.is_empty(), "docs name things that do not exist:\n{}", bad.join("\n"));
}
