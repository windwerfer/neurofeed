//! Wire-level tests: talk to an outlet the way liblsl does, with raw sockets.
#![allow(clippy::unwrap_used, clippy::expect_used)]

use pure_lsl::{ChannelFormat, Outlet, StreamInfo, BASE_PORT};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpStream, UdpSocket};
use std::time::Duration;

fn outlet(name: &str, fmt: ChannelFormat) -> StreamInfo {
    StreamInfo::new(name, "EEG", 2, 100.0, fmt, "test").unwrap()
}

fn udp_query(port: u16, query: &str) -> Option<String> {
    let s = UdpSocket::bind("127.0.0.1:0").unwrap();
    s.set_read_timeout(Some(Duration::from_millis(500))).unwrap();
    let me = s.local_addr().unwrap().port();
    s.send_to(format!("LSL:shortinfo\r\n{query}\r\n{me} 42\r\n").as_bytes(), ("127.0.0.1", port)).unwrap();
    let mut b = [0u8; 8192];
    s.recv(&mut b).ok().map(|n| String::from_utf8_lossy(&b[..n]).into_owned())
}

#[test]
fn unicast_discovery_and_timedata() {
    let o = Outlet::<f32>::new(outlet("disc-a", ChannelFormat::Float32)).unwrap();
    let port = o.info().service_port();
    assert!((BASE_PORT..BASE_PORT + 32).contains(&port));
    let r = udp_query(port, "session_id='default' and name='disc-a'").expect("reply");
    assert!(r.starts_with("42\r\n<?xml"), "{r}");
    assert!(r.contains(&format!("<uid>{}</uid>", o.info().uid())));
    assert!(udp_query(port, "name='other'").is_none());

    let s = UdpSocket::bind("127.0.0.1:0").unwrap();
    s.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
    s.send_to(b"LSL:timedata\r\n7 1.5\r\n", ("127.0.0.1", port)).unwrap();
    let mut b = [0u8; 256];
    let n = s.recv(&mut b).unwrap();
    let f: Vec<f64> = String::from_utf8_lossy(&b[..n]).split_whitespace().map(|x| x.parse().unwrap()).collect();
    assert_eq!((f[0], f[1]), (7.0, 1.5));
    assert!(f[3] >= f[2] && f[2] > 0.0);
}

fn handshake(port: u16, uid: &str, value_size: usize) -> (BufReader<TcpStream>, String) {
    let mut s = TcpStream::connect(("127.0.0.1", port)).unwrap();
    s.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
    write!(s, "LSL:streamfeed/110 {uid}\r\nNative-Byte-Order: 1234\r\nValue-Size: {value_size}\r\nMax-Buffer-Length: 100\r\n\r\n").unwrap();
    let mut r = BufReader::new(s);
    let mut head = String::new();
    loop {
        let mut l = String::new();
        if r.read_line(&mut l).unwrap() == 0 || l == "\r\n" {
            break;
        }
        head.push_str(&l);
    }
    (r, head)
}

#[test]
fn streamfeed_sends_test_patterns_then_samples() {
    let mut o = Outlet::<i16>::new(outlet("feed-a", ChannelFormat::Int16)).unwrap();
    let port = o.info().data_port();
    let (mut r, head) = handshake(port, o.info().uid(), 2);
    assert!(head.starts_with("LSL/110 200 OK\r\n") && head.contains("Data-Protocol-Version: 110"), "{head}");
    let mut tp = [0u8; 2 * 13];
    r.read_exact(&mut tp).unwrap();
    assert_eq!(tp[0], 2);
    assert_eq!(&tp[1..9], &123_456.789f64.to_le_bytes());
    assert_eq!(i16::from_le_bytes([tp[9], tp[10]]), 261);
    assert_eq!(i16::from_le_bytes([tp[11], tp[12]]), -262);
    assert_eq!(i16::from_le_bytes([tp[22], tp[23]]), 259);
    assert!(o.wait_for_consumers(Duration::from_secs(2)));
    o.push_chunk_at(&[1, 2, 3, 4], 10.0).unwrap();
    let mut s = [0u8; 26];
    r.read_exact(&mut s).unwrap();
    assert_eq!(&s[1..9], &9.99f64.to_le_bytes());
    assert_eq!(&s[9..13], &[1, 0, 2, 0]);
    assert_eq!(&s[14..22], &10.0f64.to_le_bytes());
    drop(r);
    o.push_sample(&[5, 6]).unwrap();
}

#[test]
fn handshake_rejects_wrong_uid_size_and_old_protocol() {
    let o = Outlet::<f64>::new(outlet("feed-b", ChannelFormat::Double64)).unwrap();
    let port = o.info().data_port();
    assert!(handshake(port, "nope", 8).1.starts_with("LSL/110 404"));
    assert!(handshake(port, o.info().uid(), 4).1.starts_with("LSL/110 505"));
    let mut s = TcpStream::connect(("127.0.0.1", port)).unwrap();
    s.write_all(b"LSL:streamfeed\r\n360 0\r\n").unwrap();
    let mut l = String::new();
    BufReader::new(s).read_line(&mut l).unwrap();
    assert!(l.contains("505"));
}

#[test]
fn fullinfo_has_desc() {
    let info = outlet("full-a", ChannelFormat::Float32).with_channel_labels(&["x", "y"], "uV", "EEG");
    let o = Outlet::<f32>::new(info).unwrap();
    let mut s = TcpStream::connect(("127.0.0.1", o.info().data_port())).unwrap();
    s.write_all(b"LSL:fullinfo\r\n").unwrap();
    let mut x = String::new();
    s.read_to_string(&mut x).unwrap();
    assert!(x.contains("<label>y</label>") && x.ends_with("</info>\n"));
}

#[test]
fn shape_and_format_errors() {
    assert!(Outlet::<f32>::new(outlet("bad", ChannelFormat::Int8)).is_err());
    let mut o = Outlet::<String>::new(StreamInfo::new("m", "Markers", 1, 0.0, ChannelFormat::String, "").unwrap()).unwrap();
    assert!(o.push_sample(&[]).is_err());
    assert!(o.push_sample(&["start".into()]).is_ok());
}
