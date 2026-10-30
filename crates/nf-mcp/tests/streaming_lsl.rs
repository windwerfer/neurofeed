#![allow(clippy::panic, clippy::unwrap_used, clippy::expect_used)]
//! LSL streaming out via MCP, with a capturing outlet transport.

use nf_core::Session;
use nf_mcp::{ClockMode, NfMcp};
use nf_types::{OutletSpec, StreamOutlets};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct Log {
    opened: Vec<Vec<OutletSpec>>,
    pushed: Vec<(usize, usize)>,
    closed: usize,
}
struct Capture(Arc<Mutex<Log>>);
impl StreamOutlets for Capture {
    fn open(&mut self, specs: &[OutletSpec]) -> Result<(), String> {
        self.0.lock().unwrap().opened.push(specs.to_vec());
        Ok(())
    }
    fn push(&mut self, index: usize, rows: &[f32]) -> Result<(), String> {
        self.0.lock().unwrap().pushed.push((index, rows.len()));
        Ok(())
    }
    fn close(&mut self) {
        self.0.lock().unwrap().closed += 1;
    }
    fn consumers(&self) -> usize {
        2
    }
}

fn run(s: &NfMcp, id: &str, params: Value) -> Value {
    s.call("command_run", json!({ "id": id, "params": params })).unwrap_or_else(|e| panic!("{id}: {e}"))
}

#[test]
fn lsl_needs_a_transport() {
    let s = NfMcp::new(Session::new(), ClockMode::Manual);
    let e =
        s.call("command_run", json!({ "id": "streaming.set", "params": { "enabled": true, "protocol": "lsl" } })).unwrap_err().to_string();
    assert!(e.contains("desktop"), "{e}");
}

#[test]
fn opens_one_outlet_per_group_and_pushes_chunks() {
    let log = Arc::new(Mutex::new(Log::default()));
    let mut session = Session::new();
    session.set_stream_outlets(Box::new(Capture(log.clone())));
    let s = NfMcp::new(session, ClockMode::Manual);
    run(&s, "device.connect", json!({ "id": "sim:muse_s" }));
    run(&s, "streaming.set", json!({ "enabled": true, "protocol": "lsl" }));
    run(&s, "clock.advance", json!({ "seconds": 1.0 }));
    {
        let l = log.lock().unwrap();
        assert_eq!(l.opened.len(), 1);
        let eeg = &l.opened[0][0];
        assert_eq!((eeg.kind.as_str(), eeg.channels.len(), eeg.rate_hz), ("EEG", 4, 256.0));
        assert!(eeg.source_id.starts_with("neurofeed:sim:muse_s"));
        assert!((18..=22).contains(&l.pushed.len()), "{} chunks", l.pushed.len());
        assert_eq!(l.pushed[0], (0, 48));
    }
    let st = run(&s, "streaming.status", Value::Null);
    assert_eq!((st["protocol"].as_str(), st["stats"]["lsl_consumers"].as_u64()), (Some("lsl"), Some(2)));
    run(&s, "streaming.set", json!({ "separate_groups": true }));
    run(&s, "clock.advance", json!({ "seconds": 1.0 }));
    {
        let l = log.lock().unwrap();
        assert_eq!(l.opened.len(), 2, "reopened for the new groups");
        let kinds: Vec<&str> = l.opened[1].iter().map(|o| o.kind.as_str()).collect();
        assert_eq!(kinds, ["EEG", "PPG", "Accelerometer", "EEG-bands"]);
        assert!(l.pushed.iter().any(|p| p.0 == 3));
    }
    run(&s, "streaming.set", json!({ "enabled": false }));
    run(&s, "clock.advance", json!({ "seconds": 0.5 }));
    let l = log.lock().unwrap();
    assert!(l.closed >= 2 && l.opened.len() == 2);
}
