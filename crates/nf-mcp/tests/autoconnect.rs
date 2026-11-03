#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! Contract `.ai/contracts/device-autoconnect.md` with a push transport
//! standing in for a Muse and the manual clock. No hardware.

use nf_core::Session;
use std::time::{Duration, Instant};

use nf_core::SHUTDOWN_TIMEOUT_S;
use nf_device::{muse_info, DeviceInfo, DeviceProvider, DeviceSource, LinkState, LiveSource, PushHandle, PushProvider, Tasks};
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
        // No further command: streaming alone must have saved last_device.
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

fn temp_store(tag: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("nf-autoconnect-{tag}-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    dir.join("store.db")
}

#[test]
fn switch_from_simulator_is_remembered_and_startup_never_picks_a_simulator() {
    let path = temp_store("switch");
    {
        let (mut s, h) = session(Some(&path));
        s.call("device.connect", json!({ "id": "sim:muse_s" })).unwrap();
        advance(&mut s, 1.0);
        connect_and_stream(&mut s, &h, A); // dialog Switch
                                           // App closes without Disconnect (shutdown, not a user disconnect).
        assert!(s.shutdown(1.0).is_empty());
    }
    let (mut s, h) = session(Some(&path));
    assert_eq!(s.state().auto.target.as_deref(), Some(A));
    advance(&mut s, 60.0);
    assert_eq!(connected(&s), None, "the headset is not advertising yet: nothing, and no simulator");
    assert_eq!(status(&mut s)["auto_reconnect"]["searching"], true);
    h.announce(muse_info(A, "Muse-AA"));
    advance(&mut s, 0.5);
    assert_eq!(connected(&s).as_deref(), Some(A));
    std::fs::remove_dir_all(path.parent().unwrap()).ok();
}

#[test]
fn no_last_device_means_nothing_connects() {
    let (mut s, h) = session(None);
    h.announce(muse_info(B, "Muse-BB"));
    advance(&mut s, 120.0);
    assert_eq!(connected(&s), None);
    assert_eq!(status(&mut s)["scan_mode"], "idle");
}

/// A transport whose disconnect takes `delay` after its source is dropped.
struct SlowBle {
    delay: Duration,
    tasks: Tasks,
}

impl DeviceProvider for SlowBle {
    fn scheme(&self) -> &'static str {
        "muse"
    }
    fn list(&self) -> Vec<DeviceInfo> {
        vec![muse_info(A, "Muse-AA")]
    }
    fn open(&mut self, id: &str) -> Result<Box<dyn DeviceSource>, String> {
        let (src, feed) = LiveSource::new(muse_info(id, "Muse-AA"));
        feed.link(LinkState::Streaming);
        let guard = self.tasks.enter();
        let delay = self.delay;
        Ok(Box::new(src.on_drop(move || {
            std::thread::spawn(move || {
                std::thread::sleep(delay);
                drop((guard, feed));
            });
        })))
    }
    fn shutdown(&mut self, timeout_s: f64) -> Result<(), String> {
        if self.tasks.wait_idle(Duration::from_secs_f64(timeout_s)) {
            Ok(())
        } else {
            Err("still closing".into())
        }
    }
}

fn slow_session(delay_ms: u64) -> Session {
    let mut s = Session::new();
    s.register_provider(Box::new(SlowBle { delay: Duration::from_millis(delay_ms), tasks: Tasks::default() }));
    s.call("device.connect", json!({ "id": A })).unwrap();
    advance(&mut s, 0.1);
    s
}

#[test]
fn shutdown_waits_for_the_disconnect() {
    assert!((SHUTDOWN_TIMEOUT_S - 10.0).abs() < f64::EPSILON);
    let mut s = slow_session(150);
    let t = Instant::now();
    assert!(s.shutdown(SHUTDOWN_TIMEOUT_S).is_empty());
    assert!(t.elapsed() >= Duration::from_millis(150), "returned before the link closed");
    assert_eq!(connected(&s), None);
    let st = status(&mut s);
    assert_eq!((st["auto_reconnect"]["target"].as_str(), st["auto_reconnect"]["suspended"].as_bool()), (Some(A), Some(false)));
}

#[test]
fn shutdown_gives_up_at_the_timeout() {
    let mut s = slow_session(5_000);
    let t = Instant::now();
    let errors = s.shutdown(0.3);
    assert!(t.elapsed() >= Duration::from_millis(300) && t.elapsed() < Duration::from_secs(3));
    assert_eq!(errors, vec!["muse: still closing".to_owned()]);
}
