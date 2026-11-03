#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! Contract `.ai/contracts/device-autoconnect.md` with a push transport
//! standing in for a Muse and the manual clock. No hardware.

use nf_core::Session;
use nf_device::{muse_info, LinkState, PushHandle, PushProvider};
use serde_json::{json, Value};

const A: &str = "muse:AA";
const B: &str = "muse:BB";

fn session(store: Option<&std::path::Path>) -> (Session, PushHandle) {
    let mut s = Session::new();
    if let Some(p) = store {
        s = s.with_store(Box::new(nf_store::SqliteStore::open(p).unwrap()));
    }
    let (prov, h) = PushProvider::new("muse");
    s.register_provider(Box::new(prov));
    (s, h)
}

fn advance(s: &mut Session, secs: f64) {
    s.call("clock.advance", json!({ "seconds": secs })).unwrap();
}

fn status(s: &mut Session) -> Value {
    s.call("device.status", json!({})).unwrap()
}

fn connected(s: &Session) -> Option<String> {
    s.state().device.as_ref().map(|d| d.id.clone())
}

/// Connect `id` as the user would and let it stream once.
fn connect_and_stream(s: &mut Session, h: &PushHandle, id: &str) {
    h.announce(muse_info(id, "Muse-AA"));
    s.call("device.connect", json!({ "id": id })).unwrap();
    h.take_opened(id).unwrap().link(LinkState::Streaming);
    advance(s, 0.1);
}

#[test]
fn lost_link_reconnects_only_the_remembered_device() {
    let (mut s, h) = session(None);
    h.announce(muse_info(A, "Muse-AA"));
    s.call("device.connect", json!({ "id": A })).unwrap();
    let feed = h.take_opened(A).unwrap();
    feed.link(LinkState::Streaming);
    advance(&mut s, 0.1);
    assert_eq!(status(&mut s)["auto_reconnect"]["target"], A);
    // Headset drops and stops advertising: the source stays, bursts start.
    h.forget(A);
    h.take_scan_requests();
    feed.link(LinkState::Lost { reason: "headset disconnected".into() });
    advance(&mut s, 0.1);
    let st = status(&mut s);
    assert_eq!((st["scan_mode"].as_str(), st["auto_reconnect"]["searching"].as_bool()), (Some("background"), Some(true)));
    assert_eq!(h.take_scan_requests(), 1, "first burst at once");
    advance(&mut s, 10.0);
    assert_eq!(h.take_scan_requests(), 0, "pause between bursts");
    advance(&mut s, 25.0);
    assert_eq!(h.take_scan_requests(), 1, "next burst after the period");
    // Another Muse shows up: never auto-connected.
    h.announce(muse_info(B, "Muse-BB"));
    advance(&mut s, 31.0);
    assert_eq!(connected(&s).as_deref(), Some(A));
    assert!(h.take_opened(B).is_none());
    // The remembered one comes back: reopened in place.
    h.announce(muse_info(A, "Muse-AA"));
    advance(&mut s, 0.5);
    let again = h.take_opened(A).expect("A reopened");
    again.link(LinkState::Streaming);
    advance(&mut s, 0.1);
    assert_eq!(connected(&s).as_deref(), Some(A));
    assert_eq!(status(&mut s)["auto_reconnect"]["searching"], false);
}

#[test]
fn user_disconnect_suspends_until_the_user_connects() {
    let (mut s, h) = session(None);
    connect_and_stream(&mut s, &h, A);
    s.call("device.disconnect", json!({})).unwrap();
    h.take_scan_requests();
    advance(&mut s, 60.0);
    assert_eq!(connected(&s), None);
    assert_eq!(h.take_scan_requests(), 0, "no background scan after Disconnect");
    assert_eq!(status(&mut s)["auto_reconnect"]["suspended"], true);
    // A sim connect is a user connect: lifts the suspension, keeps the target.
    s.call("device.connect", json!({ "id": "sim:muse" })).unwrap();
    advance(&mut s, 1.0);
    assert_eq!(status(&mut s)["auto_reconnect"]["target"], A, "simulators are never the target");
    s.call("device.disconnect", json!({})).unwrap();
    s.call("device.connect", json!({ "id": A })).unwrap();
    assert_eq!(status(&mut s)["auto_reconnect"]["suspended"], false);
}

#[test]
fn remembered_device_survives_restart_and_connects_when_seen() {
    let dir = std::env::temp_dir().join(format!("nf-autoconnect-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("store.db");
    {
        let (mut s, h) = session(Some(&path));
        connect_and_stream(&mut s, &h, A);
        s.call("view.set", json!({ "view": "psd" })).unwrap(); // any command persists settings
    }
    let (mut s, h) = session(Some(&path));
    assert_eq!(s.state().auto.target.as_deref(), Some(A));
    advance(&mut s, 0.1);
    assert_eq!(h.take_scan_requests(), 1, "scan on start");
    h.announce(muse_info(B, "Muse-BB"));
    advance(&mut s, 1.0);
    assert_eq!(connected(&s), None, "a new device needs the user");
    h.announce(muse_info(A, "Muse-AA"));
    advance(&mut s, 0.1);
    assert_eq!(connected(&s).as_deref(), Some(A));
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn dialog_keeps_scanning_and_close_hands_over_to_background() {
    let (mut s, h) = session(None);
    s.call("device.dialog", json!({ "open": true })).unwrap();
    assert_eq!(status(&mut s)["scan_mode"], "dialog");
    h.take_scan_requests();
    // PushProvider reports scanning() = false, so the watch is re-armed.
    advance(&mut s, 0.1);
    advance(&mut s, 6.0);
    assert!(h.take_scan_requests() >= 2, "dialog re-arms discovery");
    s.call("device.dialog", json!({ "open": false })).unwrap();
    h.take_scan_requests();
    advance(&mut s, 30.0);
    assert_eq!(h.take_scan_requests(), 0, "no target: closed dialog stops scanning");
    assert_eq!(status(&mut s)["scan_mode"], "idle");
}
