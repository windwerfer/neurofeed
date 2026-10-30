//! LSL outlets for streaming out, on top of the pure-Rust `pure-lsl` crate.

use nf_types::{OutletSpec, StreamOutlets};
use pure_lsl::{ChannelFormat, Outlet, StreamInfo};

/// One float32 outlet per announced group.
#[derive(Debug, Default)]
pub struct LslOutlets {
    outlets: Vec<Outlet<f32>>,
}

impl LslOutlets {
    pub fn new() -> Self {
        Self::default()
    }
}

fn outlet(s: &OutletSpec) -> Result<Outlet<f32>, String> {
    let info = StreamInfo::new(&s.name, &s.kind, s.channels.len(), s.rate_hz, ChannelFormat::Float32, &s.source_id)
        .map_err(|e| e.to_string())?
        .with_channel_labels(&s.channels, &s.unit, &s.kind);
    let mut info = info;
    info.desc_mut().child_value("manufacturer", "NeuroFeed");
    Outlet::new(info).map_err(|e| format!("LSL outlet {}: {e}", s.name))
}

impl StreamOutlets for LslOutlets {
    fn open(&mut self, specs: &[OutletSpec]) -> Result<(), String> {
        self.outlets = specs.iter().map(outlet).collect::<Result<_, _>>()?;
        Ok(())
    }

    fn push(&mut self, index: usize, rows: &[f32]) -> Result<(), String> {
        let o = self.outlets.get_mut(index).ok_or("no such LSL outlet")?;
        o.push_chunk(rows).map_err(|e| e.to_string())
    }

    fn close(&mut self) {
        self.outlets.clear();
    }

    fn consumers(&self) -> usize {
        self.outlets.iter().map(Outlet::consumers).sum()
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn opens_pushes_and_closes() {
        let mut l = LslOutlets::new();
        let spec = OutletSpec {
            name: "nf-test".into(),
            kind: "EEG".into(),
            channels: vec!["a".into(), "b".into()],
            unit: "uV".into(),
            rate_hz: 256.0,
            source_id: "x".into(),
        };
        l.open(&[spec]).unwrap();
        l.push(0, &[1.0, 2.0, 3.0, 4.0]).unwrap();
        assert!(l.push(0, &[1.0]).is_err() && l.push(1, &[1.0, 2.0]).is_err());
        assert_eq!(l.consumers(), 0);
        l.close();
        assert!(l.push(0, &[1.0, 2.0]).is_err());
    }
}
