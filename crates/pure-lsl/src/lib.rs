//! # pure-lsl
//!
//! [Lab Streaming Layer](https://labstreaminglayer.org) outlets in pure
//! Rust. A stream created here is found by `pylsl.resolve_streams()`,
//! LabRecorder and any other liblsl program, and they receive its samples
//! as if it came from liblsl itself, without linking the C++ library.
//!
//! ```no_run
//! use pure_lsl::{ChannelFormat, Outlet, StreamInfo};
//! let info = StreamInfo::new("Muse", "EEG", 4, 256.0, ChannelFormat::Float32, "muse-1234")?
//!     .with_channel_labels(&["TP9", "AF7", "AF8", "TP10"], "microvolts", "EEG");
//! let mut outlet = Outlet::<f32>::new(info)?;
//! outlet.push_sample(&[1.0, 2.0, 3.0, 4.0])?;
//! # Ok::<(), Box<dyn std::error::Error>>(())
//! ```
//!
//! ## What is implemented
//! - Discovery: `LSL:shortinfo` over UDP on the multicast port (16571,
//!   groups 224.0.0.183, 224.0.0.1, 239.255.172.215, and broadcast) and on
//!   a unicast service port (16572–16603), with an XPath-subset query
//!   matcher; `LSL:timedata` for clock-offset estimation.
//! - TCP: `LSL:fullinfo`, `LSL:shortinfo` and the `LSL:streamfeed/110`
//!   handshake with the two test-pattern samples, then the data feed.
//! - All channel formats (`float32`, `double64`, `string`, `int8`–`int64`).
//! - IPv4 only. Protocol 1.00 (boost archives) and inlets are not
//!   implemented; liblsl clients negotiate 1.10 automatically.
//!
//! The protocol was studied from liblsl (MIT, (c) 2012 Christian A. Kothe);
//! no code was copied.

mod clock;
mod format;
mod info;
mod net;
mod outlet;
pub mod query;
pub mod xml;

pub use clock::local_clock;
pub use format::{ChannelFormat, Value};
pub use info::{InfoError, StreamInfo};
pub use net::{BASE_PORT, MULTICAST_GROUPS, MULTICAST_PORT, PORT_RANGE, PROTOCOL_VERSION};
pub use outlet::{Outlet, ShapeError};
