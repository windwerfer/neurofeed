//! Interop with the real liblsl through pylsl (test-only tool, never a
//! dependency). Set `PURE_LSL_PYTHON` to a Python that has `pylsl`
//! installed; without it these tests print a note and pass.
#![allow(clippy::unwrap_used, clippy::expect_used)]

use pure_lsl::{local_clock, ChannelFormat, Outlet, StreamInfo, Value};
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::time::Duration;

fn python() -> Option<String> {
    let p = std::env::var("PURE_LSL_PYTHON").ok()?;
    let ok = Command::new(&p).args(["-c", "import pylsl"]).stderr(Stdio::null()).status().ok()?.success();
    ok.then_some(p)
}

/// Run the receiver; `push` is called once it is connected.
fn receive(name: &str, n: usize, push: impl FnOnce()) -> serde_like::Json {
    let py = python().expect("checked");
    let script = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/interop_recv.py");
    let mut child = Command::new(py).args([script, name, &n.to_string()]).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().unwrap();
    let mut out = BufReader::new(child.stdout.take().unwrap());
    let mut line = String::new();
    out.read_line(&mut line).unwrap();
    assert_eq!(line.trim(), "READY", "receiver did not connect: {line}");
    push();
    line.clear();
    out.read_line(&mut line).unwrap();
    let _ = child.wait();
    serde_like::parse(&line)
}

fn run<T: Value>(fmt: ChannelFormat, name: &str, rows: &[Vec<T>]) -> serde_like::Json {
    let info = StreamInfo::new(name, "EEG", rows[0].len(), 100.0, fmt, "interop").unwrap().with_channel_labels(
        &["c0", "c1", "c2"][..rows[0].len()],
        "uV",
        "EEG",
    );
    let mut o = Outlet::<T>::new(info).unwrap();
    let t0 = local_clock();
    receive(name, rows.len(), || {
        assert!(o.wait_for_consumers(Duration::from_secs(5)));
        for (i, r) in rows.iter().enumerate() {
            o.push_sample_at(r, t0 + i as f64 * 0.01).unwrap();
        }
    })
}

macro_rules! skip_without_pylsl {
    () => {
        if python().is_none() {
            eprintln!("PURE_LSL_PYTHON with pylsl not set: interop test skipped");
            return;
        }
    };
}

#[test]
fn pylsl_receives_float32_with_metadata_and_clock() {
    skip_without_pylsl!();
    let rows: Vec<Vec<f32>> = (0..50).map(|i| vec![i as f32, -(i as f32) * 0.5, 1e-3]).collect();
    let j = run(ChannelFormat::Float32, "pure-f32", &rows);
    assert_eq!(j.get("name").str(), "pure-f32");
    assert_eq!(j.get("channels").num(), 3.0);
    assert_eq!(j.get("srate").num(), 100.0);
    assert_eq!(j.get("labels").list().iter().map(serde_like::Json::str).collect::<Vec<_>>(), ["c0", "c1", "c2"]);
    let s = j.get("samples").list();
    assert_eq!(s.len(), 50);
    assert_eq!(s[49].list()[1].num(), -24.5);
    let st = j.get("stamps").list();
    assert!((st[1].num() - st[0].num() - 0.01).abs() < 1e-9);
    assert!(j.get("offset").num().abs() < 0.01, "same host, same clock");
    assert!((j.get("now").num() - local_clock()).abs() < 5.0);
}

#[test]
fn pylsl_receives_every_numeric_format() {
    skip_without_pylsl!();
    let check = |j: serde_like::Json, want: &[f64]| {
        let got: Vec<f64> = j.get("samples").list()[0].list().iter().map(serde_like::Json::num).collect();
        assert_eq!(got, want);
    };
    check(run(ChannelFormat::Double64, "pure-f64", &[vec![1.25f64, -1e300]]), &[1.25, -1e300]);
    check(run(ChannelFormat::Int32, "pure-i32", &[vec![i32::MIN, 7]]), &[f64::from(i32::MIN), 7.0]);
    check(run(ChannelFormat::Int16, "pure-i16", &[vec![-300i16, 300]]), &[-300.0, 300.0]);
    check(run(ChannelFormat::Int8, "pure-i8", &[vec![-128i8, 127]]), &[-128.0, 127.0]);
    check(run(ChannelFormat::Int64, "pure-i64", &[vec![1i64 << 40, -5]]), &[(1u64 << 40) as f64, -5.0]);
}

#[test]
fn pylsl_receives_strings() {
    skip_without_pylsl!();
    let long = "é".repeat(200);
    let j = run(ChannelFormat::String, "pure-str", &[vec!["start".to_string(), long.clone()]]);
    let s = j.get("samples").list()[0].list();
    assert_eq!((s[0].str(), s[1].str()), ("start", long.as_str()));
}

/// Minimal JSON reader so the crate needs no dev-dependencies.
mod serde_like {
    #[derive(Debug, Clone, PartialEq)]
    pub enum Json {
        Null,
        Num(f64),
        Str(String),
        List(Vec<Json>),
        Obj(Vec<(String, Json)>),
    }
    impl Json {
        pub fn get(&self, k: &str) -> Json {
            match self {
                Json::Obj(o) => o.iter().find(|(n, _)| n == k).map_or(Json::Null, |(_, v)| v.clone()),
                _ => Json::Null,
            }
        }
        pub fn num(&self) -> f64 {
            if let Json::Num(n) = self {
                *n
            } else {
                f64::NAN
            }
        }
        pub fn str(&self) -> &str {
            if let Json::Str(s) = self {
                s
            } else {
                ""
            }
        }
        pub fn list(&self) -> Vec<Json> {
            if let Json::List(l) = self {
                l.clone()
            } else {
                Vec::new()
            }
        }
    }
    pub fn parse(s: &str) -> Json {
        let c: Vec<char> = s.chars().collect();
        value(&c, &mut 0)
    }
    fn ws(c: &[char], i: &mut usize) {
        while *i < c.len() && c[*i].is_whitespace() {
            *i += 1;
        }
    }
    fn value(c: &[char], i: &mut usize) -> Json {
        ws(c, i);
        match c.get(*i) {
            Some('{') => seq(c, i, '}', true),
            Some('[') => seq(c, i, ']', false),
            Some('"') => Json::Str(string(c, i)),
            Some('n') => {
                *i += 4;
                Json::Null
            }
            _ => {
                let st = *i;
                while *i < c.len() && !",]} ".contains(c[*i]) {
                    *i += 1;
                }
                let t: String = c[st..*i].iter().collect();
                Json::Num(t.parse().unwrap_or(f64::NAN))
            }
        }
    }
    fn seq(c: &[char], i: &mut usize, end: char, obj: bool) -> Json {
        *i += 1;
        let (mut l, mut o) = (Vec::new(), Vec::new());
        loop {
            ws(c, i);
            if c.get(*i) == Some(&end) {
                *i += 1;
                break;
            }
            if obj {
                let k = string(c, i);
                ws(c, i);
                *i += 1;
                o.push((k, value(c, i)));
            } else {
                l.push(value(c, i));
            }
            ws(c, i);
            if c.get(*i) == Some(&',') {
                *i += 1;
            }
        }
        if obj {
            Json::Obj(o)
        } else {
            Json::List(l)
        }
    }
    fn string(c: &[char], i: &mut usize) -> String {
        *i += 1;
        let mut s = String::new();
        while let Some(&ch) = c.get(*i) {
            *i += 1;
            match ch {
                '"' => break,
                '\\' => {
                    let e = c.get(*i).copied().unwrap_or('"');
                    *i += 1;
                    if e == 'u' {
                        let h: String = c[*i..*i + 4].iter().collect();
                        *i += 4;
                        s.push(char::from_u32(u32::from_str_radix(&h, 16).unwrap_or(63)).unwrap_or('?'));
                    } else {
                        s.push(match e {
                            'n' => '\n',
                            't' => '\t',
                            o => o,
                        });
                    }
                }
                o => s.push(o),
            }
        }
        s
    }
}
