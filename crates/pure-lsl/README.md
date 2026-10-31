# pure-lsl

[Lab Streaming Layer](https://labstreaminglayer.org) **outlets in pure Rust**: no liblsl, no C++ toolchain, no `unsafe`.
Streams you create are discovered and received by pylsl, LabRecorder, OpenViBE, MNE-LSL and every other liblsl program.

```rust
use pure_lsl::{ChannelFormat, Outlet, StreamInfo};

let info = StreamInfo::new("Muse", "EEG", 4, 256.0, ChannelFormat::Float32, "muse-1234")?
    .with_channel_labels(&["TP9", "AF7", "AF8", "TP10"], "microvolts", "EEG");
let mut outlet = Outlet::<f32>::new(info)?;
outlet.push_sample(&[1.0, 2.0, 3.0, 4.0])?;        // stamped with local_clock()
outlet.push_chunk_at(&[0.0; 4 * 12], timestamp)?;  // 12 rows, last row at `timestamp`
```

Run `cargo run --example send_sine` and check it from Python:
`python -c "import pylsl; print(pylsl.resolve_streams())"`.

## Scope

| | |
|---|---|
| Discovery | `LSL:shortinfo` on UDP 16571 (multicast 224.0.0.183, 224.0.0.1, 239.255.172.215, broadcast) and a unicast service port in 16572–16603; XPath-subset query matching (`and`/`or`/`not`, comparisons, `starts-with`, `contains`, `desc/...` paths) |
| Clock sync | `LSL:timedata`, so `time_correction()` works; `local_clock()` is `CLOCK_MONOTONIC` on Unix, identical to liblsl |
| Data | TCP `LSL:fullinfo`, `LSL:shortinfo`, `LSL:streamfeed/110` handshake with liblsl's test patterns, then samples |
| Formats | float32, double64, string, int8, int16, int32, int64 |
| Not yet | inlets/resolvers (receiving), IPv6, protocol 1.00, config files, sync (blocking) outlets |

Slow consumers: each inlet gets a bounded queue (its `max_buflen`); when it is full new chunks are dropped for that inlet and counted in `Outlet::dropped_chunks`.

## Tests

`cargo test` runs unit and raw-socket protocol tests. Interop tests against real liblsl run when
`PURE_LSL_PYTHON` points to a Python with `pylsl` (`pip install pylsl`; it bundles liblsl):

```sh
python -m venv .venv && .venv/bin/pip install pylsl
PURE_LSL_PYTHON=.venv/bin/python cargo test
```

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([LICENSE-MIT](LICENSE-MIT))

at your option. Unless you explicitly state otherwise, any contribution intentionally
submitted for inclusion in this crate shall be dual licensed as above, without any
additional terms or conditions.

The protocol was studied from [liblsl](https://github.com/sccn/liblsl) (MIT, © 2012
Christian A. Kothe); no code was copied. The liblsl notice is kept in `LICENSE-MIT`.
