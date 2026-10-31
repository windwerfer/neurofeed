#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! OSC streaming out via MCP, with a capturing sink.

use nf_core::streaming::{decode, DatagramSink};
use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};

type Sent = Arc<Mutex<Vec<(String, u16, Vec<u8>)>>>;
struct Capture(Sent);
impl DatagramSink for Capture {
    fn send(&mut self, ip: &str, port: u16, bytes: &[u8]) -> Result<(), String> {
        self.0.lock().unwrap().push((ip.into(), port, bytes.to_vec()));
        Ok(())
    }
}

fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_or_else(|e| panic!("{id}: {e}"))
}

fn server() -> (NfMcp, Sent) {
    let sent = Sent::default();
    let mut session = Session::new();
    session.set_stream_sink(Box::new(Capture(sent.clone())));
    (NfMcp::new(session, ClockMode::Manual), sent)
}

#[test]
fn needs_a_transport() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    let e = s.call("command_run", json!({ "id": "streaming.set", "params": { "enabled": true } })).unwrap_err().to_string();
    assert!(e.contains("cannot send UDP"), "{e}");
    assert_eq!(run(&s, "streaming.status", Value::Null)["transport"], false);
}

#[test]
fn streams_eeg_chunks_then_all_groups() {
    let (s, sent) = server();
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    run(&s, "streaming.set", json!({ "enabled": true, "ip": "127.0.0.1", "port": 9100 }));
    run(&s, "clock.advance", json!({ "seconds": 1.0 }));
    let msgs: Vec<_> = sent.lock().unwrap().drain(..).collect();
    assert!((18..=22).contains(&msgs.len()), "{} EEG chunks in 1 s", msgs.len());
    let (addr, v) = decode(&msgs[3].2).unwrap();
    assert_eq!((addr.as_str(), v.len(), msgs[3].0.as_str(), msgs[3].1), ("/muse/eeg", 1 + 12 * 4, "127.0.0.1", 9100));
    let (_, w) = decode(&msgs[4].2).unwrap();
    assert!((w[0] - v[0] - 12.0 / 256.0).abs() < 1e-4, "chunk times step 12 samples");
    run(&s, "streaming.set", json!({ "separate_groups": true, "prefix": "/nf" }));
    run(&s, "clock.advance", json!({ "seconds": 2.0 }));
    let mut seen: Vec<String> = sent.lock().unwrap().iter().map(|m| decode(&m.2).unwrap().0).collect();
    seen.sort();
    seen.dedup();
    assert_eq!(seen, ["/nf/bands", "/nf/eeg", "/nf/imu", "/nf/ppg"]);
    let st = run(&s, "streaming.status", Value::Null);
    assert!(st["stats"]["packets_sent"].as_u64().unwrap() > 40, "{st}");
    assert_eq!(st["groups"].as_array().unwrap().len(), 4);
    run(&s, "streaming.set", json!({ "enabled": false }));
    sent.lock().unwrap().clear();
    run(&s, "clock.advance", json!({ "seconds": 1.0 }));
    assert!(sent.lock().unwrap().is_empty());
}
