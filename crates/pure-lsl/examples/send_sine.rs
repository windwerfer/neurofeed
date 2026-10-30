//! Stream a 4-channel 250 Hz sine as float32 until killed (or for N seconds).
//! `cargo run --example send_sine -- [seconds] [name]`

use pure_lsl::{ChannelFormat, Outlet, StreamInfo};
use std::time::{Duration, Instant};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let secs: f64 = args.next().and_then(|a| a.parse().ok()).unwrap_or(f64::INFINITY);
    let name = args.next().unwrap_or_else(|| "PureSine".into());
    let info = StreamInfo::new(name, "EEG", 4, 250.0, ChannelFormat::Float32, "pure-lsl-sine")?.with_channel_labels(
        &["a", "b", "c", "d"],
        "microvolts",
        "EEG",
    );
    let mut outlet = Outlet::<f32>::new(info)?;
    println!("serving uid {} on tcp {}", outlet.info().uid(), outlet.info().source_id());
    let start = Instant::now();
    let mut n = 0u64;
    while start.elapsed().as_secs_f64() < secs {
        let due = (start.elapsed().as_secs_f64() * 250.0) as u64;
        let mut chunk = Vec::new();
        while n < due {
            let t = n as f32 / 250.0;
            chunk.extend((0..4).map(|c| (t * 10.0 + c as f32).sin()));
            n += 1;
        }
        if !chunk.is_empty() {
            outlet.push_chunk(&chunk)?;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    Ok(())
}
