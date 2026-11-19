//! `cargo run --release -p nf-core --example parse_bench`: cost of
//! `Request::parse` (every MCP / CLI / bridge call goes through it).
//! Prints the median and range of 11 runs of 2 000 parses each.

use nf_core::Request;
use serde_json::json;

fn main() {
    let calls = [
        ("monitor.zoom", json!({ "monitor": "bands", "factor": 2.0 })),
        ("feedback.status", json!(null)),
        ("device.connect", json!({ "id": "sim:muse_s" })),
        ("settings.set", json!({ "subject": "p01" })),
    ];
    let mut runs: Vec<f64> = (0..11)
        .map(|_| {
            let t = std::time::Instant::now();
            for i in 0..2_000 {
                let (id, p) = &calls[i % calls.len()];
                std::hint::black_box(Request::parse(id, p.clone()).is_ok());
            }
            t.elapsed().as_secs_f64() * 1e6 / 2_000.0
        })
        .collect();
    runs.sort_by(f64::total_cmp);
    let (lo, med, hi) = (runs.first().copied().unwrap_or(0.0), runs.get(5).copied().unwrap_or(0.0), runs.last().copied().unwrap_or(0.0));
    println!("Request::parse: median {med:.2} µs/call (range {lo:.2}..{hi:.2}), 11 x 2000 calls");
}
