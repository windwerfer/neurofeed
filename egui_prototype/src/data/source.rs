//! The seam where a real device plugs in.

/// Static description of the connected device.
#[derive(Debug, Clone, PartialEq)]
pub struct DeviceInfo {
    pub name: String,
    pub channels: Vec<String>,
    /// True for simulated sources, so the UI can label them.
    pub simulated: bool,
}

/// Anything that can produce band power snapshots: a mock, a Muse/Crown
/// bridge, a recording player.
///
/// `poll` is called once per UI frame with the current time in seconds and
/// returns a new snapshot when one is ready. Implementations must not block.
pub trait BandSource {
    fn device_info(&self) -> DeviceInfo;
    fn poll(&mut self, now: f64) -> Option<super::BandSnapshot>;
}
