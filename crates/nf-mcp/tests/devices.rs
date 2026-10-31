#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! Real-device plumbing with mocks: Crown over a real localhost UDP socket
//! (OSC packets as the Crown sends them) and a push transport standing in for
//! the Android BLE wrapper / a Muse. No hardware.

use std::net::UdpSocket;
use std::time::Duration;

use nf_core::Session;
use nf_device::{muse_info, CrownProvider, LinkState, PushProvider};
use nf_mcp::{ClockMode, NfMcp};
use rosc::{OscArray, OscMessage, OscPacket, OscType};
use serde_json::{json, Value};

fn run(s: &NfMcp, id: &str, params: Value) -> Result<Value, String> {
    s.call("command_run", json!({ "id": id, "params": params })).map_err(|e| e.to_string())
}
fn ok(s: &NfMcp, id: &str, params: Value) -> Value {
    run(s, id, params).unwrap_or_else(|e| panic!("{id}: {e}"))
}

fn free_port() -> u16 {
    UdpSocket::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port()
}

fn osc(addr: &str, args: Vec<OscType>) -> Vec<u8> {
    rosc::encoder::encode(&OscPacket::Message(OscMessage { addr: addr.into(), args })).unwrap()
}

fn sample(s: usize, ch: usize) -> f32 {
    (ch as f32 + 1.0) * 10.0 * (s as f32 * std::f32::consts::TAU * 10.0 / 256.0).sin()
}

#[test]
fn crown_scan_connect_stream_disconnect_over_udp() {
    let port = free_port();
    let mut session = Session::new();
    session.register_provider(Box::new(CrownProvider::with_port(port)));
    let s = NfMcp::new(session, ClockMode::Manual);
    let tx = UdpSocket::bind("127.0.0.1:0").unwrap();
    let to = ("127.0.0.1", port);

    let scan = ok(&s, "device.scan", json!({ "seconds": 5 }));
    assert_eq!(scan["scanning"], json!(["crown"]));
    let info = vec![OscType::String("abc123".into()), OscType::String("Lab Crown".into()), OscType::String("Crown 3".into())];
    let mut listed = Value::Null;
    for _ in 0..40 {
        tx.send_to(&osc("/neurosity/notion/abc123/info", info.clone()), to).unwrap();
        std::thread::sleep(Duration::from_millis(25));
        listed = s.call("command_run", json!({ "id": "device.list" })).unwrap();
        if listed.as_array().unwrap().iter().any(|d| d["id"] == "crown:abc123") {
            break;
        }
    }
    let crown = listed.as_array().unwrap().iter().find(|d| d["id"] == "crown:abc123").cloned().expect("discovered");
    assert_eq!(crown["name"], "Lab Crown");
    assert_eq!(crown["simulated"], false);

    ok(&s, "device.connect", json!({ "id": "crown:abc123" }));
    assert_eq!(ok(&s, "device.status", Value::Null)["link"]["state"], "connecting");
    // 2 s of one-sample /raw packets (BrainFlow / simulator style), 64 per 0.25 s.
    let mut n = 0;
    for _ in 0..8 {
        for _ in 0..64 {
            let frame = (0..8).map(|ch| OscType::Float(sample(n, ch))).collect();
            let args = vec![OscType::Array(OscArray { content: frame }), OscType::String("ts".into()), OscType::Int((n % 256) as i32)];
            tx.send_to(&osc("/neurosity/notion/abc123/raw", args), to).unwrap();
            n += 1;
        }
        std::thread::sleep(Duration::from_millis(30));
        ok(&s, "clock.advance", json!({ "seconds": 0.25 }));
    }
    std::thread::sleep(Duration::from_millis(50));
    ok(&s, "clock.advance", json!({ "seconds": 0.25 }));
    let st = ok(&s, "device.status", Value::Null);
    assert_eq!(st["link"]["state"], "streaming", "{st}");
    let raw = ok(&s, "raw.get", json!({ "seconds": 1.0, "filtered": false }));
    let chans = raw["channels"].as_array().unwrap();
    assert_eq!(chans.len(), 8);
    assert_eq!(chans[2]["channel"], "F5");
    // Sent in batches of 16: everything up to the last full batch arrived, in order.
    let got: Vec<f64> = chans[2]["samples"].as_array().unwrap().iter().map(|v| v.as_f64().unwrap()).collect();
    let last = n - n % 16;
    let want: Vec<f64> = (last - got.len()..last).map(|i| f64::from(sample(i, 2))).collect();
    assert_eq!(got.len(), 256);
    for (g, w) in got.iter().zip(&want) {
        assert!((g - w).abs() < 1e-3, "{g} vs {w}");
    }
    let events = ok(&s, "events.drain", Value::Null);
    assert!(events.to_string().contains("link_changed") || events.to_string().contains("LinkChanged"), "{events}");
    ok(&s, "device.disconnect", Value::Null);
    assert_eq!(ok(&s, "device.status", Value::Null)["connected"], false);
}

#[test]
fn push_transport_streams_like_a_muse_and_reports_drop() {
    let (provider, handle) = PushProvider::new("android");
    let mut session = Session::new();
    session.register_provider(Box::new(provider));
    let s = NfMcp::new(session, ClockMode::Manual);
    let e = run(&s, "device.connect", json!({ "id": "android:AA" })).unwrap_err();
    assert!(e.contains("scan first"), "{e}");
    ok(&s, "device.scan", Value::Null);
    assert_eq!(handle.take_scan_requests(), 1);
    handle.announce(muse_info("android:AA", "Muse-1234"));
    ok(&s, "device.connect", json!({ "id": "android:AA" }));
    let feed = handle.take_opened("android:AA").expect("feed");
    // 12-sample EEG blocks at 256 Hz (Muse Classic), PPG and accel.
    let mut k = 0;
    for _ in 0..40 {
        for _ in 0..(256 / 12 / 4 + 1) {
            for e in 0..4u16 {
                feed.eeg(e, (0..12).map(|i| sample(k + i, usize::from(e))).collect());
            }
            k += 12;
        }
        feed.ppg(1, vec![1000.0; 6]);
        feed.accel(vec![[0.0, 0.0, 1.0]; 3]);
        ok(&s, "clock.advance", json!({ "seconds": 0.25 }));
    }
    let st = ok(&s, "device.status", Value::Null);
    assert_eq!(st["link"]["state"], "streaming");
    let raw = ok(&s, "raw.get", json!({ "seconds": 2.0, "filtered": false }));
    assert_eq!(raw["channels"][0]["samples"].as_array().unwrap().len(), 512);
    feed.link(LinkState::Lost { reason: "BLE link lost".into() });
    ok(&s, "clock.advance", json!({ "seconds": 0.1 }));
    assert_eq!(ok(&s, "device.status", Value::Null)["link"], json!({ "state": "lost", "reason": "BLE link lost" }));
    ok(&s, "device.disconnect", Value::Null);
    assert_eq!(handle.take_closed(), vec!["android:AA".to_owned()]);
}

#[test]
fn scan_is_disabled_with_simulators_only() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    let e = run(&s, "device.scan", Value::Null).unwrap_err();
    assert!(e.contains("simulators only"), "{e}");
}
