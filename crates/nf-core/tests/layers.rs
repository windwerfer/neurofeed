#![allow(clippy::panic)]
//! Cheap layering check (PhotoCraft runs this as `cargo xtask layers`):
//! lower crates must not depend on UI toolkits, async runtimes or MCP.

use std::path::Path;

const FORBIDDEN: [&str; 6] = ["egui", "eframe", "winit", "tokio", "rmcp", "btleplug"];

#[test]
fn low_layers_stay_clean() {
    let crates = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    for name in ["nf-types", "nf-dsp", "nf-format", "nf-sim", "nf-core"] {
        let path = crates.join(name).join("Cargo.toml");
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
        for dep in FORBIDDEN {
            let hit =
                text.lines().any(|l| l.trim_start().starts_with(&format!("{dep} ")) || l.trim_start().starts_with(&format!("{dep}=")));
            assert!(!hit, "{name} must not depend on {dep}");
        }
    }
}

/// L1 crates must not reach up into the core or MCP layers.
#[test]
fn l1_does_not_depend_upward() {
    let crates = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    for name in ["nf-types", "nf-dsp", "nf-format", "nf-sim"] {
        let text = std::fs::read_to_string(crates.join(name).join("Cargo.toml")).unwrap_or_default();
        for up in ["nf-core", "nf-mcp"] {
            assert!(!text.contains(up), "{name} must not depend on {up}");
        }
    }
}
