//! `cargo xtask layers`: every workspace crate is registered in [`TABLE`],
//! depends only on crates in its own or a lower layer, and uses the
//! quarantined third-party engines only where AGENTS.md §2 allows them.
//!
//! Edges come from `cargo metadata` (any target), not from grepping
//! manifests. Layer order applies to every edge; the engine quarantine
//! applies to normal and build dependencies (tests may drive a protocol).

use serde_json::Value;

/// Crate layers. Same-layer edges are allowed (cargo forbids cycles); an
/// edge to a higher layer is not.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Layer {
    /// Ids, units, stream descriptors, DTOs; zero-dependency codecs.
    L0,
    /// DSP, formats, simulators, feedback math, audio, storage, import.
    L1,
    /// `nf-core`: Session, commands, events, Clock.
    L2,
    /// Real devices and ML engines (native, optional).
    L3,
    /// MCP server.
    L4,
    /// Binaries and repo tooling.
    App,
}

pub struct Entry {
    pub name: &'static str,
    pub layer: Layer,
    /// Must build for `wasm32-unknown-unknown` (`cargo xtask wasm`).
    pub wasm: bool,
}

const fn e(name: &'static str, layer: Layer, wasm: bool) -> Entry {
    Entry { name, layer, wasm }
}

/// The layers table. A new crate must be added here (AGENTS.md §2).
pub const TABLE: &[Entry] = &[
    e("nf-types", Layer::L0, true),
    e("edf_export", Layer::L0, true),
    e("nf-dsp", Layer::L1, true),
    e("nf-format", Layer::L1, true),
    e("nf-sim", Layer::L1, true),
    e("nf-feedback", Layer::L1, true),
    e("nf-audio", Layer::L1, true),
    e("nf-store", Layer::L1, true),
    e("nf-import", Layer::L1, true),
    e("pure-lsl", Layer::L1, false),
    e("nf-core", Layer::L2, true),
    e("nf-device", Layer::L3, false),
    e("nf-ai", Layer::L3, false),
    e("nf-mcp", Layer::L4, false),
    e("neurofeed-egui", Layer::App, true),
    e("neurofeed-cli", Layer::App, false),
    e("neurofeed-android", Layer::App, false),
    e("xtask", Layer::App, false),
];

/// Third-party crates allowed only in the listed workspace crates (and apps).
const QUARANTINE: &[(&str, &[&str])] = &[
    ("egui", &[]),
    ("eframe", &[]),
    ("winit", &[]),
    ("rfd", &[]),
    ("tokio", &["nf-device", "nf-mcp"]),
    ("btleplug", &["nf-device"]),
    ("muse-rs", &["nf-device"]),
    ("rosc", &["nf-device"]),
    ("rmcp", &["nf-mcp"]),
    ("candle-core", &["nf-ai"]),
    ("candle-nn", &["nf-ai"]),
    ("reve-rs", &["nf-ai"]),
];

pub fn entry(name: &str) -> Option<&'static Entry> {
    TABLE.iter().find(|e| e.name == name)
}

/// One dependency edge.
pub struct Dep {
    pub name: String,
    /// `[dev-dependencies]` only.
    pub dev: bool,
}

/// One workspace package and everything it depends on.
pub struct Package {
    pub name: String,
    pub deps: Vec<Dep>,
}

/// Workspace packages from `cargo metadata --no-deps` JSON.
pub fn packages(metadata: &Value) -> Vec<Package> {
    let list = metadata.get("packages").and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default();
    list.iter()
        .map(|p| Package {
            name: p.get("name").and_then(Value::as_str).unwrap_or_default().to_owned(),
            deps: p
                .get("dependencies")
                .and_then(Value::as_array)
                .map(Vec::as_slice)
                .unwrap_or_default()
                .iter()
                .filter_map(|d| {
                    let name = d.get("name").and_then(Value::as_str)?.to_owned();
                    Some(Dep { name, dev: d.get("kind").and_then(Value::as_str) == Some("dev") })
                })
                .collect(),
        })
        .collect()
}

/// Every violation, one line each (empty = clean).
pub fn check(pkgs: &[Package]) -> Vec<String> {
    let mut errors = Vec::new();
    for p in pkgs {
        let Some(me) = entry(&p.name) else {
            errors.push(format!("{}: not registered in the layers table (xtask/src/layers.rs)", p.name));
            continue;
        };
        for d in &p.deps {
            check_edge(me, d, &mut errors);
        }
    }
    errors
}

fn check_edge(me: &Entry, d: &Dep, errors: &mut Vec<String>) {
    let dep = d.name.as_str();
    if let Some(other) = entry(dep) {
        if other.layer > me.layer {
            errors.push(format!("{} ({:?}) depends on {} ({:?}): a higher layer", me.name, me.layer, dep, other.layer));
        }
        return;
    }
    if me.layer == Layer::App || d.dev {
        return;
    }
    if let Some((_, allowed)) = QUARANTINE.iter().find(|(q, _)| *q == dep) {
        if !allowed.contains(&me.name) {
            errors.push(format!("{} must not depend on {dep} (quarantined to {})", me.name, list(allowed)));
        }
    }
}

fn list(allowed: &[&str]) -> String {
    if allowed.is_empty() {
        "apps only".into()
    } else {
        allowed.join(", ")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pkg(name: &str, deps: &[&str]) -> Package {
        Package { name: name.into(), deps: deps.iter().map(|d| Dep { name: (*d).to_owned(), dev: false }).collect() }
    }

    #[test]
    fn dev_dependencies_skip_quarantine_but_not_layers() {
        let dev = |n: &str| Dep { name: n.into(), dev: true };
        assert!(check(&[Package { name: "nf-mcp".into(), deps: vec![dev("rosc")] }]).is_empty());
        assert!(!check(&[Package { name: "nf-dsp".into(), deps: vec![dev("nf-core")] }]).is_empty());
    }

    #[test]
    fn lower_and_same_layer_edges_pass() {
        let pkgs = [pkg("nf-core", &["nf-types", "nf-store", "serde"]), pkg("nf-import", &["nf-format", "nf-dsp"])];
        assert!(check(&pkgs).is_empty(), "{:?}", check(&pkgs));
    }

    #[test]
    fn upward_edge_fails() {
        let e = check(&[pkg("nf-dsp", &["nf-core"])]);
        assert_eq!(e.len(), 1);
        assert!(e[0].contains("higher layer"), "{e:?}");
    }

    #[test]
    fn quarantined_engine_outside_its_crate_fails() {
        assert!(check(&[pkg("nf-core", &["tokio"])])[0].contains("quarantined to nf-device, nf-mcp"));
        assert!(check(&[pkg("nf-sim", &["egui"])])[0].contains("apps only"));
        assert!(check(&[pkg("nf-device", &["btleplug", "tokio"]), pkg("nf-ai", &["candle-core"])]).is_empty());
        assert!(check(&[pkg("neurofeed-egui", &["eframe", "tokio"])]).is_empty(), "apps may use anything");
    }

    #[test]
    fn unregistered_crate_fails() {
        assert!(check(&[pkg("nf-new", &[])])[0].contains("not registered"));
    }

    #[test]
    fn metadata_json_is_read() {
        let v = serde_json::json!({ "packages": [{ "name": "nf-sim", "dependencies": [
            { "name": "nf-types", "kind": null }, { "name": "nf-dsp", "kind": "dev" }
        ] }] });
        let p = packages(&v);
        assert_eq!((p[0].name.as_str(), p[0].deps.len()), ("nf-sim", 2));
        assert!(!p[0].deps[0].dev && p[0].deps[1].dev);
        assert!(packages(&serde_json::json!({})).is_empty(), "malformed metadata is empty, not a panic");
    }
}
