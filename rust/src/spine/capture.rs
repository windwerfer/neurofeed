//! Rust-owned capture writer for prefixes `tmp` / `recording` / `session`.
//!
//! Forwarder encodes records and `try_send`s bytes. A dedicated `std::thread`
//! inner-zstd-frames (~64 KiB, level 3) and appends. Never `write` on the
//! forwarder or JNI thread.

use std::collections::HashSet;
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError, SyncSender, TrySendError};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use crate::api::muse::MuseEventDto;
use crate::api::session_format::{
    container_encode_v5_to_path, encode_session_event, session_frame_bytes, session_header_bytes,
};

const MAX_PENDING_BYTES: usize = 4 * 1024 * 1024;
const CHANNEL_SLOTS: usize = 131_072;
const FLUSH_BYTES: usize = 64 * 1024;
const FLUSH_INTERVAL: Duration = Duration::from_secs(30);
const STREAM_ALL: u32 = 0x1FF;

const STREAM_EEG: u32 = 1 << 0;
const STREAM_BANDS: u32 = 1 << 1;
const STREAM_PPG: u32 = 1 << 2;
const STREAM_PULSE: u32 = 1 << 3;
const STREAM_SPO2: u32 = 1 << 4;
const STREAM_IMU: u32 = 1 << 5;
const STREAM_MOVEMENT: u32 = 1 << 6;
const STREAM_PEAK_ALPHA: u32 = 1 << 7;
const STREAM_TELEMETRY: u32 = 1 << 8;

/// 1×1 transparent WebP (same bytes as Dart `placeholderWebP`).
const PLACEHOLDER_WEBP: &[u8] = &[
    0x52, 0x49, 0x46, 0x46, 0x1A, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x58,
    0x0A, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x2F, 0xFF, 0xF0, 0x0E, 0x10, 0x00, 0x00, 0x00,
    0x1C, 0x00, 0x00, 0x00, 0x30, 0x30, 0x31, 0x20, 0x00, 0x00, 0x00, 0x13, 0x04, 0x40, 0x9D, 0x01,
    0x2A, 0x01, 0x00, 0x03, 0x13, 0x1F, 0x03,
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SidecarMode {
    Jsonl,
    Snapshot,
}

#[derive(Debug, Clone)]
pub(crate) struct FlushEntry {
    pub elapsed_s: f64,
    pub end_offset: u64,
}

enum Msg {
    Record {
        bytes: Vec<u8>,
        eeg_ts_ms: Option<f64>,
    },
    Computed(Vec<u8>),
    Sidecar(Vec<u8>),
    Flush {
        ack: mpsc::Sender<Result<(), String>>,
    },
    Stop {
        ack: mpsc::Sender<Result<(), String>>,
    },
}

struct CaptureCtl {
    tx: SyncSender<Msg>,
    pending: Arc<AtomicUsize>,
    drops: Arc<AtomicU64>,
    failed: Arc<AtomicBool>,
    streams: u32,
    channels: Arc<Mutex<HashSet<i32>>>,
}

struct CaptureSession {
    ctl: Arc<CaptureCtl>,
    thread: Option<JoinHandle<()>>,
    write_errors: Arc<AtomicU64>,
    index: Arc<Mutex<Vec<FlushEntry>>>,
    dir: PathBuf,
    prefix: String,
    id: String,
    live: bool,
}

static STARTED: AtomicBool = AtomicBool::new(false);
static CTL: Mutex<Option<Arc<CaptureCtl>>> = Mutex::new(None);
static SESSION: Mutex<Option<CaptureSession>> = Mutex::new(None);

#[cfg(test)]
static TEST_LOCK: Mutex<()> = Mutex::new(());

#[cfg(test)]
pub fn test_lock() -> std::sync::MutexGuard<'static, ()> {
    TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner())
}

fn lock_ctl() -> std::sync::MutexGuard<'static, Option<Arc<CaptureCtl>>> {
    CTL.lock().unwrap_or_else(|e| e.into_inner())
}

fn lock_session() -> std::sync::MutexGuard<'static, Option<CaptureSession>> {
    SESSION.lock().unwrap_or_else(|e| e.into_inner())
}

fn stream_mask(names: &[String]) -> u32 {
    if names.is_empty() {
        return STREAM_ALL;
    }
    let mut mask = 0u32;
    for name in names {
        mask |= match name.as_str() {
            "eeg" => STREAM_EEG,
            "bands" => STREAM_BANDS,
            "ppg" => STREAM_PPG,
            "pulse" => STREAM_PULSE,
            "spo2" => STREAM_SPO2,
            "imu" => STREAM_IMU,
            "movement" => STREAM_MOVEMENT,
            "peakAlpha" => STREAM_PEAK_ALPHA,
            "telemetry" => STREAM_TELEMETRY,
            _ => 0,
        };
    }
    mask
}

fn dto_stream(dto: &MuseEventDto) -> Option<u32> {
    match dto {
        MuseEventDto::Eeg(_) => Some(STREAM_EEG),
        MuseEventDto::Bands(_) => Some(STREAM_BANDS),
        MuseEventDto::Ppg(_) => Some(STREAM_PPG),
        MuseEventDto::Pulse(_) => Some(STREAM_PULSE),
        MuseEventDto::SpO2(_) => Some(STREAM_SPO2),
        MuseEventDto::Accelerometer(_) | MuseEventDto::Gyroscope(_) => Some(STREAM_IMU),
        MuseEventDto::Movement(_) => Some(STREAM_MOVEMENT),
        MuseEventDto::PeakAlpha(_) => Some(STREAM_PEAK_ALPHA),
        MuseEventDto::Telemetry(_) => Some(STREAM_TELEMETRY),
        _ => None,
    }
}

fn sidecar_mode(prefix: &str) -> SidecarMode {
    match prefix {
        "session" => SidecarMode::Jsonl,
        _ => SidecarMode::Snapshot,
    }
}

fn sidecar_path(dir: &Path, prefix: &str, id: &str, mode: SidecarMode) -> PathBuf {
    let ext = match mode {
        SidecarMode::Jsonl => "metadata",
        SidecarMode::Snapshot => "json",
    };
    dir.join(format!("{prefix}_{id}.{ext}"))
}

fn raw_path(dir: &Path, prefix: &str, id: &str) -> PathBuf {
    dir.join(format!("{prefix}_{id}.raw"))
}

fn computed_path(dir: &Path, prefix: &str, id: &str) -> PathBuf {
    dir.join(format!("{prefix}_{id}.computed"))
}

fn neurofeed_path(dir: &Path, prefix: &str, id: &str) -> PathBuf {
    dir.join(format!("{prefix}_{id}.neurofeed"))
}

fn validate_prefix(prefix: &str) -> anyhow::Result<()> {
    match prefix {
        "tmp" | "recording" | "session" => Ok(()),
        other => anyhow::bail!("capture prefix must be tmp|recording|session, got {other}"),
    }
}

fn validate_id(id: &str) -> anyhow::Result<()> {
    if id.is_empty() || id.contains('/') || id.contains('\\') || id.contains("..") {
        anyhow::bail!("invalid capture id");
    }
    Ok(())
}

fn on_queue_full(ctl: &CaptureCtl) {
    ctl.drops.fetch_add(1, Ordering::Relaxed);
    if !ctl.failed.swap(true, Ordering::Relaxed) {
        log::error!("[spine] capture queue full; stop appends, keep temps");
    }
}

fn try_send(ctl: &CaptureCtl, msg: Msg, nbytes: usize) -> bool {
    if ctl.failed.load(Ordering::Relaxed) {
        return false;
    }
    if nbytes > 0 {
        let prev = ctl.pending.fetch_add(nbytes, Ordering::Relaxed);
        if prev.saturating_add(nbytes) > MAX_PENDING_BYTES {
            ctl.pending.fetch_sub(nbytes, Ordering::Relaxed);
            on_queue_full(ctl);
            return false;
        }
    }
    match ctl.tx.try_send(msg) {
        Ok(()) => true,
        Err(TrySendError::Full(msg) | TrySendError::Disconnected(msg)) => {
            if nbytes > 0 {
                ctl.pending.fetch_sub(nbytes, Ordering::Relaxed);
            }
            drop(msg);
            on_queue_full(ctl);
            false
        }
    }
}

fn note_channels(ctl: &CaptureCtl, dto: &MuseEventDto) {
    let electrode = match dto {
        MuseEventDto::Eeg(e) => Some(e.electrode),
        MuseEventDto::Bands(b) => Some(b.electrode),
        _ => None,
    };
    if let Some(ch) = electrode {
        if let Ok(mut set) = ctl.channels.lock() {
            set.insert(ch);
        }
    }
}

/// Encode + `try_send` on the forwarder. No `write` / zstd / fsync here.
pub fn on_dto(dto: &MuseEventDto) {
    if !STARTED.load(Ordering::Relaxed) {
        return;
    }
    let ctl = {
        let g = lock_ctl();
        match g.as_ref() {
            Some(c) => Arc::clone(c),
            None => return,
        }
    };
    if ctl.failed.load(Ordering::Relaxed) {
        return;
    }
    let Some(stream) = dto_stream(dto) else {
        return;
    };
    if ctl.streams & stream == 0 {
        return;
    }
    note_channels(&ctl, dto);
    let bytes = encode_session_event(dto);
    if bytes.is_empty() {
        return;
    }
    let eeg_ts_ms = match dto {
        MuseEventDto::Eeg(e) => Some(e.timestamp),
        _ => None,
    };
    let n = bytes.len();
    try_send(&ctl, Msg::Record { bytes, eeg_ts_ms }, n);
}

fn current_ctl() -> anyhow::Result<Arc<CaptureCtl>> {
    lock_ctl()
        .as_ref()
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("capture is not active"))
}

pub fn capture_start(
    dir: String,
    prefix: String,
    id: String,
    record_streams: Vec<String>,
    started_at_ms: f64,
) -> anyhow::Result<()> {
    validate_prefix(&prefix)?;
    validate_id(&id)?;
    let dir_path = PathBuf::from(&dir);
    fs::create_dir_all(&dir_path).map_err(|e| anyhow::anyhow!("create capture dir {dir}: {e}"))?;

    let mut sess_g = lock_session();
    if sess_g.is_some() {
        anyhow::bail!("capture already started");
    }

    let mode = sidecar_mode(&prefix);
    let raw = raw_path(&dir_path, &prefix, &id);
    let computed = computed_path(&dir_path, &prefix, &id);
    let sidecar = sidecar_path(&dir_path, &prefix, &id, mode);

    let (tx, rx) = mpsc::sync_channel::<Msg>(CHANNEL_SLOTS);
    let (ready_tx, ready_rx) = mpsc::channel::<Result<(), String>>();
    let pending = Arc::new(AtomicUsize::new(0));
    let drops = Arc::new(AtomicU64::new(0));
    let write_errors = Arc::new(AtomicU64::new(0));
    let failed = Arc::new(AtomicBool::new(false));
    let index = Arc::new(Mutex::new(Vec::new()));
    let channels = Arc::new(Mutex::new(HashSet::new()));
    let ctl = Arc::new(CaptureCtl {
        tx: tx.clone(),
        pending: Arc::clone(&pending),
        drops: Arc::clone(&drops),
        failed: Arc::clone(&failed),
        streams: stream_mask(&record_streams),
        channels: Arc::clone(&channels),
    });

    let writer_pending = Arc::clone(&pending);
    let writer_errors = Arc::clone(&write_errors);
    let writer_failed = Arc::clone(&failed);
    let writer_index = Arc::clone(&index);
    let writer_prefix = prefix.clone();
    let writer_id = id.clone();

    let thread = thread::Builder::new()
        .name("neurofeed-capture".into())
        .spawn(move || {
            writer_main(
                rx,
                ready_tx,
                raw,
                computed,
                sidecar,
                mode,
                started_at_ms,
                writer_pending,
                writer_errors,
                writer_failed,
                writer_index,
                writer_prefix,
                writer_id,
            );
        })
        .map_err(|e| anyhow::anyhow!("spawn capture writer: {e}"))?;

    match ready_rx.recv_timeout(Duration::from_secs(5)) {
        Ok(Ok(())) => {}
        Ok(Err(e)) => {
            let _ = thread.join();
            anyhow::bail!(e);
        }
        Err(_) => {
            let _ = thread.join();
            anyhow::bail!("capture writer start timed out");
        }
    }

    *lock_ctl() = Some(Arc::clone(&ctl));
    STARTED.store(true, Ordering::Release);
    *sess_g = Some(CaptureSession {
        ctl,
        thread: Some(thread),
        write_errors,
        index,
        dir: dir_path,
        prefix: prefix.clone(),
        id: id.clone(),
        live: true,
    });
    log::info!("[spine] capture start prefix={prefix} id={id} dir={dir}");
    Ok(())
}

fn join_writer(sess: &mut CaptureSession) -> anyhow::Result<()> {
    if !sess.live {
        return Ok(());
    }
    STARTED.store(false, Ordering::Release);
    *lock_ctl() = None;
    let (ack_tx, ack_rx) = mpsc::channel();
    let send_res = sess.ctl.tx.send(Msg::Stop { ack: ack_tx });
    if let Some(h) = sess.thread.take() {
        let _ = h.join();
    }
    sess.live = false;
    send_res.map_err(|_| anyhow::anyhow!("capture writer gone"))?;
    match ack_rx.recv_timeout(Duration::from_secs(30)) {
        Ok(Ok(())) => Ok(()),
        Ok(Err(e)) => Err(anyhow::anyhow!(e)),
        Err(_) => Ok(()),
    }
}

pub fn capture_stop() -> anyhow::Result<()> {
    let mut g = lock_session();
    let Some(sess) = g.as_mut() else {
        return Ok(());
    };
    join_writer(sess)?;
    log::info!(
        "[spine] capture stop prefix={} id={} drops={} write_errors={}",
        sess.prefix,
        sess.id,
        sess.ctl.drops.load(Ordering::Relaxed),
        sess.write_errors.load(Ordering::Relaxed)
    );
    Ok(())
}

pub fn capture_append_event(event: MuseEventDto) -> anyhow::Result<()> {
    on_dto(&event);
    Ok(())
}

pub fn capture_append_computed_line(line: Vec<u8>) -> anyhow::Result<()> {
    let ctl = current_ctl()?;
    let n = line.len();
    if !try_send(&ctl, Msg::Computed(line), n) {
        anyhow::bail!("capture queue full");
    }
    Ok(())
}

pub fn capture_write_sidecar(json: Vec<u8>) -> anyhow::Result<()> {
    let ctl = current_ctl()?;
    let n = json.len();
    if !try_send(&ctl, Msg::Sidecar(json), n) {
        anyhow::bail!("capture queue full");
    }
    Ok(())
}

pub fn capture_flush() -> anyhow::Result<()> {
    let tx = {
        let g = lock_session();
        match g.as_ref() {
            Some(s) if s.live => s.ctl.tx.clone(),
            _ => return Ok(()),
        }
    };
    let (ack_tx, ack_rx) = mpsc::channel();
    tx.send(Msg::Flush { ack: ack_tx })
        .map_err(|_| anyhow::anyhow!("capture writer gone"))?;
    ack_rx
        .recv_timeout(Duration::from_secs(30))
        .map_err(|_| anyhow::anyhow!("capture flush timed out"))?
        .map_err(|e| anyhow::anyhow!(e))
}

pub fn capture_flush_index() -> Vec<FlushEntry> {
    let g = lock_session();
    match g.as_ref() {
        Some(s) => s.index.lock().map(|v| v.clone()).unwrap_or_default(),
        None => Vec::new(),
    }
}

pub fn capture_recorded_channels() -> Vec<i32> {
    let g = lock_ctl();
    match g.as_ref() {
        Some(c) => c
            .channels
            .lock()
            .map(|s| {
                let mut v: Vec<i32> = s.iter().copied().collect();
                v.sort_unstable();
                v
            })
            .unwrap_or_default(),
        None => {
            drop(g);
            let sg = lock_session();
            match sg.as_ref() {
                Some(s) => s
                    .ctl
                    .channels
                    .lock()
                    .map(|set| {
                        let mut v: Vec<i32> = set.iter().copied().collect();
                        v.sort_unstable();
                        v
                    })
                    .unwrap_or_default(),
                None => Vec::new(),
            }
        }
    }
}

pub fn capture_drop_count() -> u64 {
    let g = lock_session();
    g.as_ref()
        .map(|s| s.ctl.drops.load(Ordering::Relaxed))
        .unwrap_or(0)
}

pub fn capture_write_errors() -> u64 {
    let g = lock_session();
    g.as_ref()
        .map(|s| s.write_errors.load(Ordering::Relaxed))
        .unwrap_or(0)
}

pub fn capture_is_active() -> bool {
    STARTED.load(Ordering::Relaxed)
}

fn delete_temps(dir: &Path, prefix: &str, id: &str) {
    let sidecar_json = sidecar_path(dir, prefix, id, SidecarMode::Snapshot);
    let sidecar_jsonl = sidecar_path(dir, prefix, id, SidecarMode::Jsonl);
    let sidecar_tmp = PathBuf::from(format!("{}.tmp", sidecar_json.display()));
    for p in [
        raw_path(dir, prefix, id),
        computed_path(dir, prefix, id),
        sidecar_json,
        sidecar_jsonl,
        sidecar_tmp,
    ] {
        let _ = fs::remove_file(p);
    }
}

pub fn capture_assemble_v5(metadata_json: Vec<u8>, thumbnail: Vec<u8>) -> anyhow::Result<String> {
    let (dir, prefix, id) = {
        let mut g = lock_session();
        let sess = g
            .as_mut()
            .ok_or_else(|| anyhow::anyhow!("no capture to assemble"))?;
        join_writer(sess)?;
        if sess.write_errors.load(Ordering::Relaxed) > 0 {
            anyhow::bail!("capture write error; temps kept");
        }
        (sess.dir.clone(), sess.prefix.clone(), sess.id.clone())
    };

    let thumb = if thumbnail.is_empty() {
        PLACEHOLDER_WEBP.to_vec()
    } else {
        thumbnail
    };
    let dest = neurofeed_path(&dir, &prefix, &id);
    let computed = computed_path(&dir, &prefix, &id);
    let raw = raw_path(&dir, &prefix, &id);
    let computed_s = if computed.exists() {
        computed.to_string_lossy().into_owned()
    } else {
        String::new()
    };
    let raw_s = if raw.exists() {
        raw.to_string_lossy().into_owned()
    } else {
        String::new()
    };
    let t0 = Instant::now();
    let dest_s = container_encode_v5_to_path(
        dest.to_string_lossy().into_owned(),
        thumb,
        metadata_json,
        computed_s,
        raw_s,
    )
    .map_err(|e| anyhow::anyhow!(e))?;
    let out_len = fs::metadata(&dest_s).map(|m| m.len()).unwrap_or(0);
    log::info!(
        "[spine] assemble dest={} bytes={} ms={} (copy .raw, no whole-file RAM)",
        dest_s,
        out_len,
        t0.elapsed().as_millis()
    );
    delete_temps(&dir, &prefix, &id);
    *lock_session() = None;
    STARTED.store(false, Ordering::Release);
    *lock_ctl() = None;
    Ok(dest_s)
}

pub fn capture_discard() -> anyhow::Result<()> {
    let mut g = lock_session();
    let Some(mut sess) = g.take() else {
        return Ok(());
    };
    let _ = join_writer(&mut sess);
    delete_temps(&sess.dir, &sess.prefix, &sess.id);
    STARTED.store(false, Ordering::Release);
    *lock_ctl() = None;
    log::info!(
        "[spine] capture discard prefix={} id={}",
        sess.prefix,
        sess.id
    );
    Ok(())
}

/// Assemble leftover temps with no live session (crash recovery).
pub fn capture_assemble_v5_at(
    dir: String,
    prefix: String,
    id: String,
    metadata_json: Vec<u8>,
    thumbnail: Vec<u8>,
) -> anyhow::Result<String> {
    validate_prefix(&prefix)?;
    validate_id(&id)?;
    {
        let g = lock_session();
        if let Some(sess) = g.as_ref() {
            if sess.dir == Path::new(&dir) && sess.prefix == prefix && sess.id == id {
                drop(g);
                return capture_assemble_v5(metadata_json, thumbnail);
            }
        }
    }
    let dir_path = PathBuf::from(&dir);
    let thumb = if thumbnail.is_empty() {
        PLACEHOLDER_WEBP.to_vec()
    } else {
        thumbnail
    };
    let dest = neurofeed_path(&dir_path, &prefix, &id);
    let computed = computed_path(&dir_path, &prefix, &id);
    let raw = raw_path(&dir_path, &prefix, &id);
    let computed_s = if computed.exists() {
        computed.to_string_lossy().into_owned()
    } else {
        String::new()
    };
    let raw_s = if raw.exists() {
        raw.to_string_lossy().into_owned()
    } else {
        String::new()
    };
    let dest_s = container_encode_v5_to_path(
        dest.to_string_lossy().into_owned(),
        thumb,
        metadata_json,
        computed_s,
        raw_s,
    )
    .map_err(|e| anyhow::anyhow!(e))?;
    delete_temps(&dir_path, &prefix, &id);
    Ok(dest_s)
}

fn writer_main(
    rx: mpsc::Receiver<Msg>,
    ready: mpsc::Sender<Result<(), String>>,
    raw_path: PathBuf,
    computed_path: PathBuf,
    sidecar_path: PathBuf,
    sidecar_mode: SidecarMode,
    started_at_ms: f64,
    pending: Arc<AtomicUsize>,
    write_errors: Arc<AtomicU64>,
    failed: Arc<AtomicBool>,
    index: Arc<Mutex<Vec<FlushEntry>>>,
    prefix: String,
    id: String,
) {
    let mut raw = match File::create(&raw_path) {
        Ok(mut f) => {
            let header = session_header_bytes();
            if let Err(e) = f.write_all(&header) {
                let _ = ready.send(Err(format!("write raw header: {e}")));
                return;
            }
            f
        }
        Err(e) => {
            let _ = ready.send(Err(format!("create {}: {e}", raw_path.display())));
            return;
        }
    };
    if let Err(e) = File::create(&computed_path) {
        let _ = ready.send(Err(format!("create {}: {e}", computed_path.display())));
        return;
    }
    let _ = File::create(&sidecar_path);
    if ready.send(Ok(())).is_err() {
        return;
    }

    let mut buf: Vec<u8> = Vec::with_capacity(FLUSH_BYTES + 4096);
    let mut file_len: u64 = session_header_bytes().len() as u64;
    let mut last_eeg_ts: Option<f64> = None;
    let mut last_flush = Instant::now();
    let mut last_sync = Instant::now();
    let mut flushes: u64 = 0;

    fn account(pending: &AtomicUsize, n: usize) {
        if n > 0 {
            pending.fetch_sub(n.min(pending.load(Ordering::Relaxed)), Ordering::Relaxed);
        }
    }

    fn flush_frame(
        raw: &mut File,
        buf: &mut Vec<u8>,
        file_len: &mut u64,
        last_eeg_ts: Option<f64>,
        started_at_ms: f64,
        index: &Mutex<Vec<FlushEntry>>,
        write_errors: &AtomicU64,
        failed: &AtomicBool,
        flushes: &mut u64,
    ) -> bool {
        if buf.is_empty() {
            return true;
        }
        let frame = session_frame_bytes(buf);
        buf.clear();
        if let Err(e) = raw.write_all(&frame) {
            log::error!("[spine] capture write failed: {e}");
            write_errors.fetch_add(1, Ordering::Relaxed);
            failed.store(true, Ordering::Relaxed);
            return false;
        }
        *file_len += frame.len() as u64;
        *flushes += 1;
        if let Some(ts) = last_eeg_ts {
            let elapsed_s = (ts - started_at_ms) / 1000.0;
            if let Ok(mut idx) = index.lock() {
                idx.push(FlushEntry {
                    elapsed_s,
                    end_offset: *file_len,
                });
            }
        }
        true
    }

    fn append_line(path: &Path, mut line: Vec<u8>) -> Result<(), String> {
        if line.is_empty() {
            return Ok(());
        }
        if !line.ends_with(&[b'\n']) {
            line.push(b'\n');
        }
        let mut f = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .map_err(|e| format!("open {}: {e}", path.display()))?;
        f.write_all(&line)
            .map_err(|e| format!("write {}: {e}", path.display()))
    }

    fn write_snapshot(path: &Path, json: &[u8]) -> Result<(), String> {
        let tmp = PathBuf::from(format!("{}.tmp", path.display()));
        {
            let mut f = File::create(&tmp).map_err(|e| format!("create {}: {e}", tmp.display()))?;
            f.write_all(json)
                .map_err(|e| format!("write {}: {e}", tmp.display()))?;
            f.flush()
                .map_err(|e| format!("flush {}: {e}", tmp.display()))?;
        }
        match fs::rename(&tmp, path) {
            Ok(()) => Ok(()),
            Err(_) => {
                let _ = fs::remove_file(path);
                fs::rename(&tmp, path).map_err(|e| format!("rename sidecar: {e}"))
            }
        }
    }

    loop {
        match rx.recv_timeout(Duration::from_secs(1)) {
            Ok(Msg::Record { bytes, eeg_ts_ms }) => {
                let n = bytes.len();
                account(&pending, n);
                if write_errors.load(Ordering::Relaxed) > 0 {
                    continue;
                }
                if let Some(ts) = eeg_ts_ms {
                    last_eeg_ts = Some(ts);
                }
                buf.extend_from_slice(&bytes);
                if buf.len() >= FLUSH_BYTES
                    && !flush_frame(
                        &mut raw,
                        &mut buf,
                        &mut file_len,
                        last_eeg_ts,
                        started_at_ms,
                        &index,
                        &write_errors,
                        &failed,
                        &mut flushes,
                    )
                {
                    continue;
                }
            }
            Ok(Msg::Computed(line)) => {
                let n = line.len();
                account(&pending, n);
                if write_errors.load(Ordering::Relaxed) > 0 {
                    continue;
                }
                if let Err(e) = append_line(&computed_path, line) {
                    log::error!("[spine] computed append failed: {e}");
                    write_errors.fetch_add(1, Ordering::Relaxed);
                    failed.store(true, Ordering::Relaxed);
                }
            }
            Ok(Msg::Sidecar(json)) => {
                let n = json.len();
                account(&pending, n);
                if write_errors.load(Ordering::Relaxed) > 0 {
                    continue;
                }
                let res = match sidecar_mode {
                    SidecarMode::Jsonl => append_line(&sidecar_path, json),
                    SidecarMode::Snapshot => write_snapshot(&sidecar_path, &json),
                };
                if let Err(e) = res {
                    log::error!("[spine] sidecar write failed: {e}");
                    write_errors.fetch_add(1, Ordering::Relaxed);
                    failed.store(true, Ordering::Relaxed);
                }
            }
            Ok(Msg::Flush { ack }) => {
                let ok = flush_frame(
                    &mut raw,
                    &mut buf,
                    &mut file_len,
                    last_eeg_ts,
                    started_at_ms,
                    &index,
                    &write_errors,
                    &failed,
                    &mut flushes,
                );
                let res = if ok {
                    raw.flush().map_err(|e| format!("flush raw: {e}"))
                } else {
                    Err("capture write error".into())
                };
                if last_sync.elapsed() >= FLUSH_INTERVAL {
                    let _ = raw.sync_data();
                    last_sync = Instant::now();
                }
                last_flush = Instant::now();
                let _ = ack.send(res);
            }
            Ok(Msg::Stop { ack }) => {
                let ok = flush_frame(
                    &mut raw,
                    &mut buf,
                    &mut file_len,
                    last_eeg_ts,
                    started_at_ms,
                    &index,
                    &write_errors,
                    &failed,
                    &mut flushes,
                );
                let res = if ok {
                    let r = raw
                        .flush()
                        .and_then(|_| raw.sync_data())
                        .map_err(|e| format!("fsync raw: {e}"));
                    r
                } else {
                    Err("capture write error".into())
                };
                log::info!(
                    "[spine] writer stop prefix={prefix} id={id} flushes={flushes} raw_bytes={file_len}"
                );
                let _ = ack.send(res);
                return;
            }
            Err(RecvTimeoutError::Timeout) => {
                if !buf.is_empty() && last_flush.elapsed() >= FLUSH_INTERVAL {
                    let _ = flush_frame(
                        &mut raw,
                        &mut buf,
                        &mut file_len,
                        last_eeg_ts,
                        started_at_ms,
                        &index,
                        &write_errors,
                        &failed,
                        &mut flushes,
                    );
                    let _ = raw.flush();
                    if last_sync.elapsed() >= FLUSH_INTERVAL {
                        let _ = raw.sync_data();
                        last_sync = Instant::now();
                    }
                    last_flush = Instant::now();
                }
            }
            Err(RecvTimeoutError::Disconnected) => {
                let _ = flush_frame(
                    &mut raw,
                    &mut buf,
                    &mut file_len,
                    last_eeg_ts,
                    started_at_ms,
                    &index,
                    &write_errors,
                    &failed,
                    &mut flushes,
                );
                let _ = raw.flush();
                let _ = raw.sync_data();
                return;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::muse::{BandsDto, EegDto};
    use crate::api::session_format::{session_parse_body, V5_MAGIC};
    use std::io::Read;

    fn unique_id(tag: &str) -> String {
        format!(
            "{tag}_{}_{}",
            std::process::id(),
            Instant::now().elapsed().as_nanos()
        )
    }

    fn temp_dir() -> PathBuf {
        let p = std::env::temp_dir().join(format!("neurofeed_cap_{}", unique_id("d")));
        fs::create_dir_all(&p).unwrap();
        p
    }

    fn eeg(ts: f64, electrode: i32) -> MuseEventDto {
        MuseEventDto::Eeg(EegDto {
            index: 0,
            electrode,
            timestamp: ts,
            samples: vec![1.0, 2.0, 3.0],
        })
    }

    fn bands(ts: f64) -> MuseEventDto {
        MuseEventDto::Bands(BandsDto {
            electrode: 1,
            timestamp: ts,
            delta: 1.0,
            theta: 2.0,
            alpha: 3.0,
            beta: 4.0,
            gamma: 5.0,
            line_noise_ratio: 0.05,
        })
    }

    #[test]
    fn start_stop_assemble_and_index() {
        let _lock = test_lock();
        let _ = capture_discard();
        let dir = temp_dir();
        let id = unique_id("rec");
        let started = 1_700_000_000_000.0;
        capture_start(
            dir.to_string_lossy().into_owned(),
            "recording".into(),
            id.clone(),
            vec![],
            started,
        )
        .unwrap();
        on_dto(&eeg(started + 5000.0, 0));
        on_dto(&bands(started + 5000.0));
        capture_append_computed_line(b"{\"t\":5}".to_vec()).unwrap();
        capture_write_sidecar(br#"{"kind":"recording"}"#.to_vec()).unwrap();
        capture_flush().unwrap();
        let idx = capture_flush_index();
        assert_eq!(idx.len(), 1);
        assert!((idx[0].elapsed_s - 5.0).abs() < 0.001);
        assert!(idx[0].end_offset > 12);
        assert_eq!(capture_recorded_channels(), vec![0, 1]);
        assert_eq!(capture_drop_count(), 0);
        assert_eq!(capture_write_errors(), 0);

        let dest = capture_assemble_v5(
            br#"{"formatVersion":5,"kind":"recording"}"#.to_vec(),
            Vec::new(),
        )
        .unwrap();
        assert!(dest.ends_with(&format!("recording_{id}.neurofeed")));
        let mut magic = [0u8; 6];
        File::open(&dest).unwrap().read_exact(&mut magic).unwrap();
        assert_eq!(magic, V5_MAGIC);
        assert!(!raw_path(&dir, "recording", &id).exists());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn second_start_refused_until_discard() {
        let _lock = test_lock();
        let _ = capture_discard();
        let dir = temp_dir();
        let id = unique_id("tmp");
        capture_start(
            dir.to_string_lossy().into_owned(),
            "tmp".into(),
            id,
            vec!["eeg".into()],
            0.0,
        )
        .unwrap();
        assert!(capture_start(
            dir.to_string_lossy().into_owned(),
            "tmp".into(),
            unique_id("tmp2"),
            vec![],
            0.0,
        )
        .is_err());
        capture_discard().unwrap();
        capture_start(
            dir.to_string_lossy().into_owned(),
            "session".into(),
            unique_id("ses"),
            vec![],
            0.0,
        )
        .unwrap();
        capture_discard().unwrap();
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn bands_only_flush_skips_index_until_eeg() {
        let _lock = test_lock();
        let _ = capture_discard();
        let dir = temp_dir();
        let id = unique_id("idx");
        let started = 1_700_000_000_000.0;
        capture_start(
            dir.to_string_lossy().into_owned(),
            "tmp".into(),
            id,
            vec![],
            started,
        )
        .unwrap();
        on_dto(&bands(started + 1000.0));
        capture_flush().unwrap();
        assert!(capture_flush_index().is_empty());
        on_dto(&eeg(started + 2000.0, 2));
        capture_flush().unwrap();
        let idx = capture_flush_index();
        assert_eq!(idx.len(), 1);
        assert!((idx[0].elapsed_s - 2.0).abs() < 0.001);
        capture_discard().unwrap();
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn live_raw_parses_as_inner_frames() {
        let _lock = test_lock();
        let _ = capture_discard();
        let dir = temp_dir();
        let id = unique_id("parse");
        let started = 1_700_000_000_000.0;
        capture_start(
            dir.to_string_lossy().into_owned(),
            "tmp".into(),
            id.clone(),
            vec![],
            started,
        )
        .unwrap();
        on_dto(&eeg(started + 1000.0, 0));
        capture_flush().unwrap();
        capture_stop().unwrap();
        let bytes = fs::read(raw_path(&dir, "tmp", &id)).unwrap();
        let parsed = session_parse_body(&bytes).unwrap();
        assert!(!parsed.eeg.is_empty());
        capture_discard().unwrap();
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn assemble_at_leftover_temps() {
        let _lock = test_lock();
        let _ = capture_discard();
        let dir = temp_dir();
        let id = unique_id("left");
        capture_start(
            dir.to_string_lossy().into_owned(),
            "recording".into(),
            id.clone(),
            vec![],
            0.0,
        )
        .unwrap();
        on_dto(&eeg(1000.0, 0));
        capture_flush().unwrap();
        capture_stop().unwrap();
        capture_discard().unwrap();

        let dir2 = temp_dir();
        let id2 = unique_id("left2");
        fs::write(raw_path(&dir2, "recording", &id2), session_header_bytes()).unwrap();
        fs::write(computed_path(&dir2, "recording", &id2), b"{\"t\":1}\n").unwrap();
        let dest = capture_assemble_v5_at(
            dir2.to_string_lossy().into_owned(),
            "recording".into(),
            id2.clone(),
            br#"{"kind":"recording"}"#.to_vec(),
            Vec::new(),
        )
        .unwrap();
        assert!(Path::new(&dest).exists());
        assert!(!raw_path(&dir2, "recording", &id2).exists());
        let _ = fs::remove_dir_all(&dir);
        let _ = fs::remove_dir_all(&dir2);
    }
}
