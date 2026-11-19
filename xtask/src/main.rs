//! Repo gates (AGENTS.md §7):
//!
//! - `cargo xtask layers`: crate layering and engine quarantine.
//! - `cargo xtask wasm`: wasm-clean crates and the web app build for
//!   `wasm32-unknown-unknown`.
//! - `cargo xtask ci`: fmt, clippy, tests, layers, wasm and `cargo deny`
//!   (skipped with a notice when cargo-deny is not installed).
//!
//! Respects `CARGO_TARGET_DIR` (AGENTS.md §8) and `CARGO`.

mod layers;

use std::process::{Command, ExitCode};

const WASM: &str = "wasm32-unknown-unknown";
/// The web app (eframe + trunk); clippy-clean for wasm like CI.
const WEB_APP: &str = "neurofeed-egui";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("layers") => layers_gate(),
        Some("wasm") => wasm_gate(),
        Some("ci") => ci(),
        _ => {
            eprintln!("usage: cargo xtask <ci | layers | wasm>");
            return ExitCode::from(2);
        }
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("xtask: {e}");
            ExitCode::FAILURE
        }
    }
}

fn cargo() -> Command {
    Command::new(std::env::var("CARGO").unwrap_or_else(|_| "cargo".into()))
}

/// Run `cargo <args>`; `Err` names the step that failed.
fn run(args: &[&str]) -> Result<(), String> {
    eprintln!("==> cargo {}", args.join(" "));
    let status = cargo().args(args).status().map_err(|e| format!("cannot run cargo: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("`cargo {}` failed ({status})", args.join(" ")))
    }
}

fn layers_gate() -> Result<(), String> {
    eprintln!("==> layers");
    let out = cargo()
        .args(["metadata", "--format-version", "1", "--no-deps", "--locked"])
        .output()
        .map_err(|e| format!("cannot run cargo metadata: {e}"))?;
    if !out.status.success() {
        return Err(format!("cargo metadata failed: {}", String::from_utf8_lossy(&out.stderr)));
    }
    let meta: serde_json::Value = serde_json::from_slice(&out.stdout).map_err(|e| format!("cargo metadata: {e}"))?;
    let pkgs = layers::packages(&meta);
    if pkgs.is_empty() {
        return Err("cargo metadata listed no packages".into());
    }
    let errors = layers::check(&pkgs);
    for e in &errors {
        eprintln!("  {e}");
    }
    if errors.is_empty() {
        eprintln!("  {} crates ok", pkgs.len());
        Ok(())
    } else {
        Err(format!("{} layering violation(s)", errors.len()))
    }
}

fn wasm_gate() -> Result<(), String> {
    let crates: Vec<&str> = layers::TABLE.iter().filter(|e| e.wasm && e.layer != layers::Layer::App).map(|e| e.name).collect();
    let mut args = vec!["check", "--locked", "--target", WASM];
    for c in &crates {
        args.extend(["-p", c]);
    }
    run(&args)?;
    run(&["clippy", "--locked", "--target", WASM, "-p", WEB_APP, "--", "-D", "warnings"])
}

fn deny_installed() -> bool {
    cargo().args(["deny", "--version"]).output().is_ok_and(|o| o.status.success())
}

fn ci() -> Result<(), String> {
    run(&["fmt", "--all", "--check"])?;
    run(&["clippy", "--locked", "--workspace", "--all-targets", "--", "-D", "warnings"])?;
    run(&["test", "--locked", "--workspace"])?;
    layers_gate()?;
    wasm_gate()?;
    if deny_installed() {
        run(&["deny", "check"])
    } else {
        eprintln!("==> cargo deny: not installed, skipped (`cargo install cargo-deny --locked`)");
        Ok(())
    }
}
