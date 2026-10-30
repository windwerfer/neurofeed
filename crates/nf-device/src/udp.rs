//! UDP transport for streaming out (OSC).

use nf_types::DatagramSink;
use std::net::UdpSocket;

/// Unicast UDP from an ephemeral local port.
pub struct UdpSink {
    socket: Option<UdpSocket>,
}

impl UdpSink {
    pub fn new() -> Self {
        Self { socket: None }
    }
}

impl Default for UdpSink {
    fn default() -> Self {
        Self::new()
    }
}

impl DatagramSink for UdpSink {
    fn send(&mut self, ip: &str, port: u16, bytes: &[u8]) -> Result<(), String> {
        if self.socket.is_none() {
            let bind = if ip.contains(':') { "[::]:0" } else { "0.0.0.0:0" };
            self.socket = Some(UdpSocket::bind(bind).map_err(|e| format!("bind: {e}"))?);
        }
        let s = self.socket.as_ref().ok_or("no socket")?;
        let addr: std::net::IpAddr = ip.parse().map_err(|_| format!("bad ip {ip}"))?;
        s.send_to(bytes, (addr, port)).map(|_| ()).map_err(|e| format!("send to {ip}:{port}: {e}"))
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn sends_to_loopback() {
        let rx = UdpSocket::bind("127.0.0.1:0").unwrap();
        let port = rx.local_addr().unwrap().port();
        UdpSink::new().send("127.0.0.1", port, b"hi").unwrap();
        let mut buf = [0u8; 8];
        let n = rx.recv(&mut buf).unwrap();
        assert_eq!(&buf[..n], b"hi");
    }
}
