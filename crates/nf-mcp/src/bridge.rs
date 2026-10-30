//! Bridge: lets `neurofeed-mcp --bridge` drive the *running* desktop app.
//!
//! The app binds `127.0.0.1:<random port>` and writes `{addr, token, pid}`
//! to a discovery file readable only by the user (0600). A client must send
//! `{"token": ...}` as its first line; then newline-delimited JSON
//! `{"id", "tool", "args"}` requests get `{"id", "ok"}` or
//! `{"id", "error", "invalid"}` replies. Requests are handed to the app's
//! UI thread as [`Request`]s; the app answers with [`Request::respond`].
//! Std only (threads), no async runtime.

use crate::ToolError;
use serde_json::{json, Value};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;

/// Longest accepted request line (screenshots go the other way).
const MAX_REQUEST: u64 = 1 << 20;
/// How long a client waits for the app to answer one request.
pub const REPLY_TIMEOUT: Duration = Duration::from_secs(30);

/// Where the app advertises the bridge: `NF_BRIDGE_FILE`, else
/// `<user data dir>/bridge.json` (same dir as the history DB).
pub fn default_info_path() -> Option<PathBuf> {
    if let Some(p) = std::env::var_os("NF_BRIDGE_FILE") {
        return Some(PathBuf::from(p));
    }
    let env = |k| std::env::var_os(k).map(PathBuf::from);
    let dir = if cfg!(windows) {
        env("APPDATA")?.join("NeuroFeed")
    } else if cfg!(target_os = "macos") {
        env("HOME")?.join("Library/Application Support/NeuroFeed")
    } else {
        env("XDG_DATA_HOME").or_else(|| env("HOME").map(|h| h.join(".local/share")))?.join("neurofeed")
    };
    Some(dir.join("bridge.json"))
}

/// Address and secret of a running bridge.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeInfo {
    pub addr: SocketAddr,
    pub token: String,
}

impl BridgeInfo {
    pub fn read(path: &Path) -> io::Result<Self> {
        let v: Value = serde_json::from_slice(&std::fs::read(path)?).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let bad = |m: &str| io::Error::new(io::ErrorKind::InvalidData, format!("{}: {m}", path.display()));
        let addr = v["addr"].as_str().ok_or_else(|| bad("no addr"))?.parse().map_err(|_| bad("bad addr"))?;
        let token = v["token"].as_str().ok_or_else(|| bad("no token"))?.to_owned();
        Ok(Self { addr, token })
    }
}

fn new_token() -> io::Result<String> {
    let mut b = [0u8; 32];
    getrandom::fill(&mut b).map_err(|e| io::Error::other(e.to_string()))?;
    Ok(b.iter().map(|x| format!("{x:02x}")).collect())
}

/// Constant-time-ish comparison (length leaks, which is fixed anyway).
fn same(a: &str, b: &str) -> bool {
    a.len() == b.len() && a.bytes().zip(b.bytes()).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

fn write_private(path: &Path, body: &str) -> io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let _ = std::fs::remove_file(path);
    let mut o = std::fs::OpenOptions::new();
    o.write(true).create_new(true);
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut o, 0o600);
    o.open(path)?.write_all(body.as_bytes())
}

/// One request from an agent, answered on the app's thread.
pub struct Request {
    pub tool: String,
    pub args: Value,
    reply: Sender<Result<Value, ToolError>>,
}

impl Request {
    pub fn respond(self, r: Result<Value, ToolError>) {
        let _ = self.reply.send(r);
    }
}

/// Called when a request arrives (e.g. `egui::Context::request_repaint`).
pub type Waker = Arc<dyn Fn() + Send + Sync>;

/// The app side. Dropping it stops accepting and removes the discovery file.
pub struct BridgeServer {
    rx: Receiver<Request>,
    info: BridgeInfo,
    path: Option<PathBuf>,
    stop: Arc<AtomicBool>,
}

impl BridgeServer {
    /// Bind 127.0.0.1 on a random port; advertise in `info_path` if given.
    pub fn start(info_path: Option<PathBuf>, waker: Waker) -> io::Result<Self> {
        let listener = TcpListener::bind("127.0.0.1:0")?;
        listener.set_nonblocking(true)?;
        let info = BridgeInfo { addr: listener.local_addr()?, token: new_token()? };
        if let Some(p) = &info_path {
            let body = json!({ "addr": info.addr.to_string(), "token": info.token, "pid": std::process::id() });
            write_private(p, &body.to_string())?;
        }
        let (tx, rx) = mpsc::channel();
        let stop = Arc::new(AtomicBool::new(false));
        let (token, stop2) = (info.token.clone(), stop.clone());
        std::thread::Builder::new().name("nf-bridge".into()).spawn(move || {
            while !stop2.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok((stream, _)) => {
                        let (tx, token, waker, stop) = (tx.clone(), token.clone(), waker.clone(), stop2.clone());
                        let _ = std::thread::Builder::new()
                            .name("nf-bridge-conn".into())
                            .spawn(move || serve(stream, &token, &tx, &waker, &stop));
                    }
                    Err(e) if e.kind() == io::ErrorKind::WouldBlock => std::thread::sleep(Duration::from_millis(50)),
                    Err(_) => std::thread::sleep(Duration::from_millis(200)),
                }
            }
        })?;
        Ok(Self { rx, info, path: info_path, stop })
    }

    pub fn info(&self) -> &BridgeInfo {
        &self.info
    }

    /// Next pending request, if any (non-blocking).
    pub fn try_recv(&self) -> Option<Request> {
        self.rx.try_recv().ok()
    }
}

impl Drop for BridgeServer {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(p) = &self.path {
            // Only remove our own file (another instance may have replaced it).
            if BridgeInfo::read(p).is_ok_and(|i| i == self.info) {
                let _ = std::fs::remove_file(p);
            }
        }
    }
}

fn read_line(r: &mut BufReader<TcpStream>) -> io::Result<Option<Value>> {
    let mut line = String::new();
    if r.by_ref().take(MAX_REQUEST).read_line(&mut line)? == 0 {
        return Ok(None);
    }
    if !line.ends_with('\n') && line.len() as u64 >= MAX_REQUEST {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "request too large"));
    }
    serde_json::from_str(&line).map(Some).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

fn send(w: &mut TcpStream, v: &Value) -> io::Result<()> {
    let mut s = v.to_string();
    s.push('\n');
    w.write_all(s.as_bytes())
}

fn serve(stream: TcpStream, token: &str, tx: &Sender<Request>, waker: &Waker, stop: &AtomicBool) {
    let _ = stream.set_nonblocking(false);
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
    let Ok(mut w) = stream.try_clone() else { return };
    let mut r = BufReader::new(stream);
    let authed = matches!(read_line(&mut r), Ok(Some(v)) if v["token"].as_str().is_some_and(|t| same(t, token)));
    if !authed {
        let _ = send(&mut w, &json!({ "error": "bad token" }));
        return;
    }
    let _ = r.get_ref().set_read_timeout(None);
    if send(&mut w, &json!({ "ok": "neurofeed", "version": env!("CARGO_PKG_VERSION") })).is_err() {
        return;
    }
    while !stop.load(Ordering::Relaxed) {
        let v = match read_line(&mut r) {
            Ok(Some(v)) => v,
            Ok(None) => return,
            Err(e) => {
                let _ = send(&mut w, &json!({ "error": e.to_string(), "invalid": true }));
                return;
            }
        };
        let id = v.get("id").cloned().unwrap_or(Value::Null);
        let Some(tool) = v["tool"].as_str() else {
            let _ = send(&mut w, &json!({ "id": id, "error": "`tool` is required", "invalid": true }));
            continue;
        };
        let (rtx, rrx) = mpsc::channel();
        if tx.send(Request { tool: tool.to_owned(), args: v.get("args").cloned().unwrap_or(Value::Null), reply: rtx }).is_err() {
            return;
        }
        waker();
        let out = match rrx.recv_timeout(REPLY_TIMEOUT) {
            Ok(Ok(v)) => json!({ "id": id, "ok": v }),
            Ok(Err(ToolError::Invalid(m))) => json!({ "id": id, "error": m, "invalid": true }),
            Ok(Err(ToolError::Failed(m))) => json!({ "id": id, "error": m, "invalid": false }),
            Err(_) => json!({ "id": id, "error": "app did not answer (closed or busy)", "invalid": false }),
        };
        if send(&mut w, &out).is_err() {
            return;
        }
    }
}

/// The MCP side: one authenticated connection, calls are serialized.
pub struct BridgeClient {
    conn: Mutex<(BufReader<TcpStream>, TcpStream, u64)>,
}

impl BridgeClient {
    pub fn connect(info: &BridgeInfo) -> io::Result<Self> {
        let s = TcpStream::connect_timeout(&info.addr, Duration::from_secs(3))?;
        s.set_read_timeout(Some(REPLY_TIMEOUT + Duration::from_secs(5)))?;
        let mut w = s.try_clone()?;
        let mut r = BufReader::new(s);
        send(&mut w, &json!({ "token": info.token }))?;
        match read_line(&mut r)? {
            Some(v) if v.get("ok").is_some() => Ok(Self { conn: Mutex::new((r, w, 0)) }),
            Some(v) => Err(io::Error::new(io::ErrorKind::PermissionDenied, v["error"].as_str().unwrap_or("rejected").to_owned())),
            None => Err(io::Error::new(io::ErrorKind::UnexpectedEof, "bridge closed the connection")),
        }
    }

    pub fn call(&self, tool: &str, args: Value) -> Result<Value, ToolError> {
        let mut c = self.conn.lock().unwrap_or_else(PoisonError::into_inner);
        let (r, w, n) = &mut *c;
        *n += 1;
        let lost = |e: io::Error| ToolError::Failed(format!("bridge: {e} (is the app still running?)"));
        send(w, &json!({ "id": *n, "tool": tool, "args": args })).map_err(lost)?;
        let v = read_line(r).map_err(lost)?.ok_or_else(|| ToolError::Failed("bridge: app closed the connection".into()))?;
        match (v.get("ok"), v["error"].as_str()) {
            (Some(ok), _) => Ok(ok.clone()),
            (None, Some(m)) if v["invalid"].as_bool() == Some(true) => Err(ToolError::Invalid(m.to_owned())),
            (None, m) => Err(ToolError::Failed(m.unwrap_or("bridge: malformed reply").to_owned())),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn answer(server: &BridgeServer) {
        for _ in 0..200 {
            if let Some(req) = server.try_recv() {
                let r = match req.tool.as_str() {
                    "echo" => Ok(req.args.clone()),
                    "bad" => Err(ToolError::Invalid("nope".into())),
                    _ => Err(ToolError::Failed("boom".into())),
                };
                req.respond(r);
                return;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        panic!("no request");
    }

    #[test]
    fn roundtrip_auth_and_file() {
        let dir = std::env::temp_dir().join(format!("nfb-{}", std::process::id()));
        let path = dir.join("bridge.json");
        let woke = Arc::new(AtomicBool::new(false));
        let w2 = woke.clone();
        let server = BridgeServer::start(Some(path.clone()), Arc::new(move || w2.store(true, Ordering::Relaxed))).unwrap();
        let info = BridgeInfo::read(&path).unwrap();
        assert_eq!(&info, server.info());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(std::fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600);
        }
        let bad = BridgeInfo { token: "0".repeat(64), ..info.clone() };
        assert!(BridgeClient::connect(&bad).is_err());

        let client = Arc::new(BridgeClient::connect(&info).unwrap());
        for (tool, want) in
            [("echo", Ok(json!({"a": 1}))), ("bad", Err(ToolError::Invalid("nope".into()))), ("x", Err(ToolError::Failed("boom".into())))]
        {
            let c = client.clone();
            let t = std::thread::spawn(move || c.call(tool, json!({"a": 1})));
            answer(&server);
            assert_eq!(t.join().unwrap(), want);
        }
        assert!(woke.load(Ordering::Relaxed));
        drop(server);
        assert!(!path.exists(), "discovery file removed on drop");
        let _ = std::fs::remove_dir_all(dir);
    }
}
