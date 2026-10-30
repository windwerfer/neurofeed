//! Sockets and the per-outlet service threads: the UDP discovery
//! responder (multicast port and a unicast service port) and the TCP data
//! server with its protocol 1.10 handshake.

use crate::clock::local_clock;
use crate::outlet::Shared;
use socket2::{Domain, Protocol, Socket, Type};
use std::io::{self, BufRead, BufReader, Write};
use std::net::{Ipv4Addr, SocketAddr, TcpListener, TcpStream, UdpSocket};
use std::sync::atomic::Ordering;
use std::sync::mpsc::{sync_channel, RecvTimeoutError};
use std::sync::Arc;
use std::time::Duration;

/// Port everybody listens on for multicast/broadcast discovery.
pub const MULTICAST_PORT: u16 = 16_571;
/// First of the ports outlets bind for data and unicast discovery.
pub const BASE_PORT: u16 = 16_572;
/// Number of ports tried from [`BASE_PORT`].
pub const PORT_RANGE: u16 = 32;
/// Groups liblsl resolvers send to (link-local, all-hosts, site-local).
pub const MULTICAST_GROUPS: [Ipv4Addr; 3] = [Ipv4Addr::new(224, 0, 0, 183), Ipv4Addr::new(224, 0, 0, 1), Ipv4Addr::new(239, 255, 172, 215)];
/// Protocol version this crate speaks.
pub const PROTOCOL_VERSION: u32 = 110;

pub(crate) const POLL: Duration = Duration::from_millis(100);

fn in_range<S>(mut bind: impl FnMut(u16) -> io::Result<S>) -> io::Result<S> {
    let mut last = io::Error::new(io::ErrorKind::AddrInUse, "no free port");
    for p in BASE_PORT..BASE_PORT + PORT_RANGE {
        match bind(p) {
            Ok(s) => return Ok(s),
            Err(e) => last = e,
        }
    }
    Err(last)
}

pub(crate) fn bind_tcp() -> io::Result<TcpListener> {
    let l = in_range(|p| TcpListener::bind((Ipv4Addr::UNSPECIFIED, p)))?;
    l.set_nonblocking(true)?;
    Ok(l)
}

pub(crate) fn bind_service_udp() -> io::Result<UdpSocket> {
    let s = in_range(|p| UdpSocket::bind((Ipv4Addr::UNSPECIFIED, p)))?;
    s.set_read_timeout(Some(POLL))?;
    Ok(s)
}

/// Shared multicast/broadcast listener; joins what it can (no network,
/// no multicast route: unicast discovery still works).
pub(crate) fn bind_multicast() -> io::Result<UdpSocket> {
    let s = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    s.set_reuse_address(true)?;
    #[cfg(all(unix, not(any(target_os = "solaris", target_os = "illumos"))))]
    s.set_reuse_port(true)?;
    s.bind(&SocketAddr::from((Ipv4Addr::UNSPECIFIED, MULTICAST_PORT)).into())?;
    let s: UdpSocket = s.into();
    for g in MULTICAST_GROUPS {
        let _ = s.join_multicast_v4(&g, &Ipv4Addr::UNSPECIFIED);
    }
    s.set_read_timeout(Some(POLL))?;
    Ok(s)
}

/// Answer one UDP request; returns (reply, destination).
pub(crate) fn udp_reply(shared: &Shared, msg: &str, from: SocketAddr, received_at: f64) -> Option<(String, SocketAddr)> {
    let mut lines = msg.split('\n').map(str::trim);
    match lines.next()? {
        "LSL:shortinfo" => {
            let query = lines.next().unwrap_or("");
            let mut tail = lines.next().unwrap_or("").split_whitespace();
            let port: u16 = tail.next()?.parse().ok()?;
            let id = tail.next().unwrap_or("");
            crate::query::matches(&shared.info, query).then(|| (format!("{id}\r\n{}", shared.short_xml), SocketAddr::new(from.ip(), port)))
        }
        "LSL:timedata" => {
            let mut f = lines.next().unwrap_or("").split_whitespace();
            let (wave, t0) = (f.next()?, f.next()?);
            Some((format!(" {wave} {t0} {received_at:.16} {:.16}", local_clock()), from))
        }
        _ => None,
    }
}

pub(crate) fn serve_udp(shared: &Arc<Shared>, sock: &UdpSocket) {
    let mut buf = [0u8; 65_536];
    while !shared.stop.load(Ordering::Relaxed) {
        let Ok((n, from)) = sock.recv_from(&mut buf) else { continue };
        let t1 = local_clock();
        let msg = String::from_utf8_lossy(&buf[..n]);
        if let Some((reply, to)) = udp_reply(shared, &msg, from, t1) {
            let _ = sock.send_to(reply.as_bytes(), to);
        }
    }
}

pub(crate) fn serve_tcp(shared: &Arc<Shared>, listener: &TcpListener) {
    while !shared.stop.load(Ordering::Relaxed) {
        match listener.accept() {
            Ok((stream, _)) => {
                let sh = Arc::clone(shared);
                std::thread::spawn(move || {
                    let _ = client(&sh, stream);
                });
            }
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => std::thread::sleep(POLL / 4),
            Err(_) => std::thread::sleep(POLL),
        }
    }
}

/// Parsed `LSL:streamfeed/110` request headers.
#[derive(Debug, Default, PartialEq)]
pub(crate) struct FeedRequest {
    pub version: u32,
    pub uid: String,
    pub value_size: Option<usize>,
    pub max_buffer: usize,
    pub ieee754: bool,
}

pub(crate) fn parse_feed(first: &str, headers: &[String]) -> Option<FeedRequest> {
    let mut parts = first.split_whitespace();
    let version = parts.next()?.strip_prefix("LSL:streamfeed/")?.parse().ok()?;
    let mut r = FeedRequest { version, uid: parts.next().unwrap_or("").into(), max_buffer: 360, ieee754: true, ..Default::default() };
    for h in headers {
        let h = h.split(';').next().unwrap_or("");
        let Some((k, v)) = h.split_once(':') else { continue };
        let v = v.trim();
        match k.trim().to_ascii_lowercase().as_str() {
            "value-size" => r.value_size = v.parse().ok(),
            "max-buffer-length" => r.max_buffer = v.parse().unwrap_or(r.max_buffer),
            "has-ieee754-floats" => r.ieee754 = v != "0" && v != "false",
            "protocol-version" | "data-protocol-version" => r.version = r.version.min(v.parse().unwrap_or(r.version)),
            _ => {}
        }
    }
    Some(r)
}

fn read_line(r: &mut impl BufRead) -> io::Result<String> {
    let mut s = String::new();
    if r.read_line(&mut s)? == 0 {
        return Err(io::ErrorKind::UnexpectedEof.into());
    }
    Ok(s.trim_end_matches(['\r', '\n']).to_string())
}

fn client(shared: &Arc<Shared>, stream: TcpStream) -> io::Result<()> {
    stream.set_nonblocking(false)?;
    stream.set_nodelay(true)?;
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    let mut rd = BufReader::new(stream.try_clone()?);
    let mut w = stream;
    let method = read_line(&mut rd)?;
    match method.trim() {
        "LSL:fullinfo" => w.write_all(shared.full_xml.as_bytes()),
        "LSL:shortinfo" => {
            let q = read_line(&mut rd)?;
            if crate::query::matches(&shared.info, q.trim()) {
                w.write_all(shared.short_xml.as_bytes())?;
            }
            Ok(())
        }
        m if m.starts_with("LSL:streamfeed/") => {
            let mut headers = Vec::new();
            loop {
                let h = read_line(&mut rd)?;
                if h.is_empty() {
                    break;
                }
                headers.push(h);
            }
            feed(shared, &method, &headers, w)
        }
        // Protocol 1.00 (boost archives) is not supported; liblsl clients fall back to 1.10.
        _ => w.write_all(format!("LSL/{PROTOCOL_VERSION} 505 Version not supported\r\n").as_bytes()),
    }
}

/// Handshake status line and headers, or an error status.
pub(crate) fn feed_header(shared: &Shared, req: Option<&FeedRequest>) -> Result<String, String> {
    let bad = |code: &str| Err(format!("LSL/{PROTOCOL_VERSION} {code}\r\n"));
    let Some(req) = req else { return bad("400 Bad request") };
    if req.version / 100 > PROTOCOL_VERSION / 100 || req.version < 110 || !req.ieee754 {
        return bad("505 Version not supported");
    }
    if !req.uid.is_empty() && req.uid != shared.info.uid() {
        return bad("404 Not found");
    }
    let size = shared.info.format().value_size();
    if size != 0 && req.value_size.is_some_and(|v| v != size) {
        return bad("505 Version not supported");
    }
    Ok(format!(
        "LSL/{PROTOCOL_VERSION} 200 OK\r\nUID: {}\r\nByte-Order: 1234\r\nSuppress-Subnormals: 0\r\nData-Protocol-Version: {PROTOCOL_VERSION}\r\n\r\n",
        shared.info.uid()
    ))
}

fn feed(shared: &Arc<Shared>, first: &str, headers: &[String], mut w: TcpStream) -> io::Result<()> {
    let req = parse_feed(first, headers);
    let head = match feed_header(shared, req.as_ref()) {
        Ok(h) => h,
        Err(status) => return w.write_all(status.as_bytes()),
    };
    let mut out = head.into_bytes();
    for offset in [4, 2] {
        crate::format::encode_test_pattern(&mut out, shared.info.format(), shared.info.channel_count(), offset);
    }
    w.write_all(&out)?;
    let cap = req.map_or(0, |r| r.max_buffer);
    if cap == 0 {
        return Ok(());
    }
    let (tx, rx) = sync_channel(cap.clamp(16, 1 << 16));
    shared.add_consumer(tx);
    while !shared.stop.load(Ordering::Relaxed) {
        match rx.recv_timeout(POLL) {
            Ok(bytes) => w.write_all(&bytes)?,
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => break,
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn parses_liblsl_feed_request() {
        let h: Vec<String> = ["Native-Byte-Order: 1234", "Value-Size: 4", "Max-Buffer-Length: 360", "Has-IEEE754-Floats: 1; comment"]
            .map(String::from)
            .to_vec();
        let r = parse_feed("LSL:streamfeed/110 abc", &h).unwrap();
        assert_eq!((r.version, r.uid.as_str(), r.value_size, r.max_buffer, r.ieee754), (110, "abc", Some(4), 360, true));
        assert!(parse_feed("LSL:streamfeed", &[]).is_none());
    }
}
