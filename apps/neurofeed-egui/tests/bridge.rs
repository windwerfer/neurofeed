//! Bridge end to end without a window: a client thread drives the session
//! through the app's bridge while a headless egui context plays the UI loop.

use neurofeed_egui::bridge::Bridge;
use neurofeed_egui::ui;
use nf_core::Session;
use nf_mcp::bridge::{BridgeClient, BridgeInfo};
use serde_json::{json, Value};

fn find<'a>(v: &'a Value, label: &str) -> Option<&'a Value> {
    if v["label"] == label {
        return Some(v);
    }
    v["children"].as_array()?.iter().find_map(|c| find(c, label))
}

#[test]
fn agent_drives_live_ui() {
    let file = std::env::temp_dir().join(format!("nf-bridge-test-{}.json", std::process::id()));
    std::env::set_var("NF_BRIDGE_FILE", &file);
    let ctx = egui::Context::default();
    let mut bridge = Bridge::start(&ctx).unwrap();
    let mut session = Session::new();
    session.execute(nf_core::Command::DeviceConnect { id: "sim:muse_s".into() }).unwrap();

    let info = BridgeInfo::read(&file).unwrap();
    let agent = std::thread::spawn(move || {
        let c = BridgeClient::connect(&info).unwrap();
        let r1 = c.call("command_run", json!({ "id": "view.set", "params": { "view": "settings" } })).unwrap();
        let status = c.call("status", Value::Null).unwrap();
        let tree = c.call("ui_inspect", Value::Null).unwrap();
        let bad = c.call("command_run", json!({ "id": "stability.set", "params": { "window": 9999 } }));
        (r1, status, tree, bad)
    });
    let input = || egui::RawInput {
        screen_rect: Some(egui::Rect::from_min_size(egui::Pos2::ZERO, egui::vec2(1200.0, 800.0))),
        ..Default::default()
    };
    for _ in 0..400 {
        ctx.run_ui(input(), |u| {
            bridge.poll(&u.ctx().clone(), &mut session, None);
            drop(ui::show(u, &session, None));
        })
        .textures_delta
        .clear();
        if agent.is_finished() {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    let (_, status, tree, bad) = agent.join().unwrap();
    assert_eq!(status["view"], "settings");
    assert_eq!(session.state().view, nf_core::View::Settings, "the app's own session changed");
    assert!(find(&tree, "Appearance").is_some(), "General section first: {tree}");
    assert!(find(&tree, "Skip tour").is_some(), "first-run tour on a fresh session");
    assert!(bad.is_err());
    drop(bridge);
    assert!(!file.exists());
}
