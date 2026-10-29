//! EEG domain types and data sources. No egui in here.

mod bands;
mod mock;
mod source;

pub use bands::{Band, BandSnapshot};
pub use mock::MockBandSource;
pub use source::{BandSource, DeviceInfo};
