//! [`Outlet`]: makes a stream discoverable and fans samples out to every
//! connected inlet. Three background threads per outlet (TCP accept,
//! unicast and multicast discovery) plus one per consumer; all stop when
//! the outlet is dropped.

use crate::format::{encode_sample, Value};
use crate::net;
use crate::{local_clock, StreamInfo};
use std::collections::hash_map::RandomState;
use std::hash::{BuildHasher, Hasher};
use std::io;
use std::marker::PhantomData;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{SyncSender, TrySendError};
use std::sync::{Arc, Mutex, PoisonError};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

/// State the service threads share with the outlet.
pub(crate) struct Shared {
    pub info: StreamInfo,
    pub short_xml: String,
    pub full_xml: String,
    pub stop: AtomicBool,
    consumers: Mutex<Vec<SyncSender<Arc<Vec<u8>>>>>,
    dropped: std::sync::atomic::AtomicU64,
}

impl Shared {
    pub(crate) fn add_consumer(&self, tx: SyncSender<Arc<Vec<u8>>>) {
        self.consumers.lock().unwrap_or_else(PoisonError::into_inner).push(tx);
    }

    fn broadcast(&self, bytes: Vec<u8>) {
        let bytes = Arc::new(bytes);
        let mut list = self.consumers.lock().unwrap_or_else(PoisonError::into_inner);
        list.retain(|tx| match tx.try_send(Arc::clone(&bytes)) {
            Ok(()) => true,
            Err(TrySendError::Full(_)) => {
                self.dropped.fetch_add(1, Ordering::Relaxed);
                true
            }
            Err(TrySendError::Disconnected(_)) => false,
        });
    }

    fn consumer_count(&self) -> usize {
        self.consumers.lock().unwrap_or_else(PoisonError::into_inner).len()
    }
}

/// Wrong number of values for the stream's channel count.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ShapeError {
    pub expected_multiple_of: usize,
    pub got: usize,
}

impl std::fmt::Display for ShapeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "expected a multiple of {} values, got {}", self.expected_multiple_of, self.got)
    }
}

impl std::error::Error for ShapeError {}

/// A stream outlet carrying values of type `T` (`f32`, `f64`, `i8`..`i64`, `String`).
pub struct Outlet<T: Value> {
    shared: Arc<Shared>,
    threads: Vec<JoinHandle<()>>,
    buf: Vec<u8>,
    _t: PhantomData<fn(T)>,
}

fn new_uid() -> String {
    let s = RandomState::new();
    let mut h = s.build_hasher();
    h.write_u128(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_nanos()));
    h.write_u32(std::process::id());
    let (a, b) = (h.finish(), s.hash_one(h.finish()));
    let x = (u128::from(a) << 64) | u128::from(b);
    let hex = format!("{x:032x}");
    format!("{}-{}-{}-{}-{}", &hex[..8], &hex[8..12], &hex[12..16], &hex[16..20], &hex[20..])
}

fn hostname() -> String {
    #[cfg(unix)]
    {
        rustix::system::uname().nodename().to_string_lossy().into_owned()
    }
    #[cfg(not(unix))]
    {
        std::env::var("COMPUTERNAME").unwrap_or_else(|_| "localhost".into())
    }
}

fn spawn(shared: &Arc<Shared>, name: &str, f: impl FnOnce(Arc<Shared>) + Send + 'static) -> io::Result<JoinHandle<()>> {
    let sh = Arc::clone(shared);
    std::thread::Builder::new().name(format!("lsl-{name}")).spawn(move || f(sh))
}

impl<T: Value> Outlet<T> {
    /// Bind the sockets and start serving `info`. The stream's channel
    /// format must match `T`.
    pub fn new(mut info: StreamInfo) -> io::Result<Self> {
        if info.format() != T::FORMAT {
            let msg = format!("stream format is {} but the outlet carries {}", info.format(), T::FORMAT);
            return Err(io::Error::new(io::ErrorKind::InvalidInput, msg));
        }
        let tcp = net::bind_tcp()?;
        let udp = net::bind_service_udp()?;
        let mcast = net::bind_multicast().ok();
        info.net.uid = new_uid();
        info.net.hostname = hostname();
        info.net.created_at = local_clock();
        info.net.v4data_port = tcp.local_addr()?.port();
        info.net.v4service_port = udp.local_addr()?.port();
        let shared = Arc::new(Shared {
            short_xml: info.to_xml(false),
            full_xml: info.to_xml(true),
            info,
            stop: AtomicBool::new(false),
            consumers: Mutex::new(Vec::new()),
            dropped: 0.into(),
        });
        let mut threads =
            vec![spawn(&shared, "tcp", move |s| net::serve_tcp(&s, &tcp))?, spawn(&shared, "udp", move |s| net::serve_udp(&s, &udp))?];
        if let Some(m) = mcast {
            threads.push(spawn(&shared, "mcast", move |s| net::serve_udp(&s, &m))?);
        }
        Ok(Self { shared, threads, buf: Vec::new(), _t: PhantomData })
    }

    /// The served stream info (with uid, hostname and ports filled in).
    #[must_use]
    pub fn info(&self) -> &StreamInfo {
        &self.shared.info
    }

    /// Push one sample stamped now.
    pub fn push_sample(&mut self, values: &[T]) -> Result<(), ShapeError> {
        self.push_sample_at(values, local_clock())
    }

    /// Push one sample with an explicit LSL timestamp.
    pub fn push_sample_at(&mut self, values: &[T], timestamp: f64) -> Result<(), ShapeError> {
        let n = self.shared.info.channel_count();
        if values.len() != n {
            return Err(ShapeError { expected_multiple_of: n, got: values.len() });
        }
        self.push_chunk_at(values, timestamp)
    }

    /// Push row-major samples; `last_timestamp` belongs to the last row and
    /// earlier rows are spaced by the nominal rate (all equal if irregular).
    pub fn push_chunk_at(&mut self, values: &[T], last_timestamp: f64) -> Result<(), ShapeError> {
        let n = self.shared.info.channel_count();
        if n == 0 || !values.len().is_multiple_of(n) {
            return Err(ShapeError { expected_multiple_of: n, got: values.len() });
        }
        if self.shared.consumer_count() == 0 {
            return Ok(());
        }
        let rows = values.len() / n;
        let srate = self.shared.info.nominal_srate();
        let dt = if srate > 0.0 { 1.0 / srate } else { 0.0 };
        self.buf.clear();
        for (i, row) in values.chunks(n).enumerate() {
            let t = last_timestamp - (rows - 1 - i) as f64 * dt;
            encode_sample(&mut self.buf, Some(t), row);
        }
        self.shared.broadcast(self.buf.clone());
        Ok(())
    }

    /// Push rows stamped so the last one is now.
    pub fn push_chunk(&mut self, values: &[T]) -> Result<(), ShapeError> {
        self.push_chunk_at(values, local_clock())
    }

    /// Is at least one inlet connected?
    #[must_use]
    pub fn have_consumers(&self) -> bool {
        self.shared.consumer_count() > 0
    }

    /// Number of connected inlets.
    #[must_use]
    pub fn consumers(&self) -> usize {
        self.shared.consumer_count()
    }

    /// Chunks dropped because an inlet fell behind its buffer.
    #[must_use]
    pub fn dropped_chunks(&self) -> u64 {
        self.shared.dropped.load(Ordering::Relaxed)
    }

    /// Block until an inlet connects or `timeout` passes.
    pub fn wait_for_consumers(&self, timeout: Duration) -> bool {
        let end = Instant::now() + timeout;
        while Instant::now() < end {
            if self.have_consumers() {
                return true;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        self.have_consumers()
    }
}

impl<T: Value> Drop for Outlet<T> {
    fn drop(&mut self) {
        self.shared.stop.store(true, Ordering::Relaxed);
        self.shared.consumers.lock().unwrap_or_else(PoisonError::into_inner).clear();
        for t in self.threads.drain(..) {
            let _ = t.join();
        }
    }
}

impl<T: Value> std::fmt::Debug for Outlet<T> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Outlet").field("name", &self.shared.info.name()).field("uid", &self.shared.info.uid()).finish_non_exhaustive()
    }
}
