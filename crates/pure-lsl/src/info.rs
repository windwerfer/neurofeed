//! Stream metadata: the `<info>` document peers exchange during discovery
//! (short form, empty `<desc>`) and on request (full form).

use crate::format::ChannelFormat;
use crate::xml::{escape, Element};
use std::fmt::Write;

/// Description of one stream. Build it, add `desc` metadata, then hand it
/// to [`crate::Outlet::new`], which fills in the network fields.
#[derive(Debug, Clone, PartialEq)]
pub struct StreamInfo {
    name: String,
    kind: String,
    channel_count: usize,
    nominal_srate: f64,
    format: ChannelFormat,
    source_id: String,
    desc: Element,
    pub(crate) net: NetFields,
}

/// Fields the outlet assigns.
#[derive(Debug, Clone, Default, PartialEq)]
pub(crate) struct NetFields {
    pub uid: String,
    pub session_id: String,
    pub hostname: String,
    pub created_at: f64,
    pub v4data_port: u16,
    pub v4service_port: u16,
}

/// Invalid stream parameters.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InfoError(pub &'static str);

impl std::fmt::Display for InfoError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.0)
    }
}

impl std::error::Error for InfoError {}

impl StreamInfo {
    /// `kind` is the LSL content type (`EEG`, `Markers`, ...); use
    /// `nominal_srate` 0 for irregular streams.
    pub fn new(
        name: impl Into<String>,
        kind: impl Into<String>,
        channel_count: usize,
        nominal_srate: f64,
        format: ChannelFormat,
        source_id: impl Into<String>,
    ) -> Result<Self, InfoError> {
        let name = name.into();
        if name.is_empty() {
            return Err(InfoError("stream name must not be empty"));
        }
        if !(nominal_srate >= 0.0 && nominal_srate.is_finite()) {
            return Err(InfoError("nominal sampling rate must be finite and >= 0"));
        }
        let net = NetFields { session_id: "default".into(), ..NetFields::default() };
        Ok(Self {
            name,
            kind: kind.into(),
            channel_count,
            nominal_srate,
            format,
            source_id: source_id.into(),
            desc: Element::new("desc"),
            net,
        })
    }

    #[must_use]
    pub fn name(&self) -> &str {
        &self.name
    }
    #[must_use]
    pub fn kind(&self) -> &str {
        &self.kind
    }
    #[must_use]
    pub fn channel_count(&self) -> usize {
        self.channel_count
    }
    #[must_use]
    pub fn nominal_srate(&self) -> f64 {
        self.nominal_srate
    }
    #[must_use]
    pub fn format(&self) -> ChannelFormat {
        self.format
    }
    #[must_use]
    pub fn source_id(&self) -> &str {
        &self.source_id
    }
    /// Unique id assigned when the outlet starts.
    #[must_use]
    pub fn uid(&self) -> &str {
        &self.net.uid
    }

    /// TCP data port (0 before the outlet starts).
    #[must_use]
    pub fn data_port(&self) -> u16 {
        self.net.v4data_port
    }
    /// UDP service port for unicast discovery (0 before the outlet starts).
    #[must_use]
    pub fn service_port(&self) -> u16 {
        self.net.v4service_port
    }
    /// Host the outlet runs on.
    #[must_use]
    pub fn hostname(&self) -> &str {
        &self.net.hostname
    }

    /// Free-form metadata (`<desc>`), e.g. channel labels.
    pub fn desc_mut(&mut self) -> &mut Element {
        &mut self.desc
    }
    #[must_use]
    pub fn desc(&self) -> &Element {
        &self.desc
    }

    /// Convenience: `desc/channels/channel{label,unit,type}` per label.
    pub fn with_channel_labels<S: AsRef<str>>(mut self, labels: &[S], unit: &str, kind: &str) -> Self {
        let chans = self.desc.append_child("channels");
        for l in labels {
            chans.append_child("channel").child_value("label", l.as_ref()).child_value("unit", unit).child_value("type", kind);
        }
        self
    }

    /// Value of a top-level field, as discovery queries see it.
    pub(crate) fn field(&self, key: &str) -> Option<String> {
        let n = &self.net;
        Some(match key {
            "name" => self.name.clone(),
            "type" => self.kind.clone(),
            "channel_count" => self.channel_count.to_string(),
            "channel_format" => self.format.as_str().into(),
            "source_id" => self.source_id.clone(),
            "nominal_srate" => num(self.nominal_srate),
            "version" => "1.1".into(),
            "created_at" => num(n.created_at),
            "uid" => n.uid.clone(),
            "session_id" => n.session_id.clone(),
            "hostname" => n.hostname.clone(),
            "v4address" | "v6address" => String::new(),
            "v4data_port" => n.v4data_port.to_string(),
            "v4service_port" => n.v4service_port.to_string(),
            "v6data_port" | "v6service_port" => "0".into(),
            _ => return None,
        })
    }

    const FIELDS: [&'static str; 16] = [
        "name",
        "type",
        "channel_count",
        "channel_format",
        "source_id",
        "nominal_srate",
        "version",
        "created_at",
        "uid",
        "session_id",
        "hostname",
        "v4address",
        "v4data_port",
        "v4service_port",
        "v6address",
        "v6data_port",
    ];

    /// The XML document; `full` includes `<desc>`.
    pub(crate) fn to_xml(&self, full: bool) -> String {
        let mut s = String::from("<?xml version=\"1.0\"?>\n<info>\n");
        for k in Self::FIELDS.iter().chain(std::iter::once(&"v6service_port")) {
            let v = self.field(k).unwrap_or_default();
            if v.is_empty() {
                let _ = writeln!(s, "\t<{k} />");
            } else {
                let _ = writeln!(s, "\t<{k}>{}</{k}>", escape(&v));
            }
        }
        if full {
            self.desc.write(&mut s, 1);
        } else {
            s.push_str("\t<desc />\n");
        }
        s.push_str("</info>\n");
        s
    }
}

/// Locale-free, round-trippable number text (`250` not `250.0`).
fn num(x: f64) -> String {
    if x.fract() == 0.0 && x.abs() < 1e15 {
        format!("{x:.0}")
    } else {
        format!("{x}")
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn xml_has_all_fields() {
        let i = StreamInfo::new("Muse", "EEG", 2, 256.0, ChannelFormat::Float32, "m1").unwrap().with_channel_labels(
            &["TP9", "AF7"],
            "microvolts",
            "EEG",
        );
        let short = i.to_xml(false);
        assert!(short.contains("<name>Muse</name>") && short.contains("<nominal_srate>256</nominal_srate>"));
        assert!(short.contains("<session_id>default</session_id>") && short.contains("<desc />"));
        let full = i.to_xml(true);
        assert!(full.contains("<label>AF7</label>"));
        assert!(StreamInfo::new("", "EEG", 1, 1.0, ChannelFormat::Int8, "").is_err());
        assert!(StreamInfo::new("x", "EEG", 1, -1.0, ChannelFormat::Int8, "").is_err());
    }
}
