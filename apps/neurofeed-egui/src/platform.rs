//! Host hooks for platforms whose file access and window behaviour go
//! through the OS rather than plain paths (Android: the system file picker /
//! Storage Access Framework, screen-on flag, lifecycle). Desktop and web
//! leave it unset and keep their own behaviour. The Android wrapper crate
//! installs an implementation with [`install`] before eframe starts.

use std::sync::OnceLock;

pub trait Platform: Send + Sync {
    /// Save an export. With a chosen export folder it is written there
    /// directly; otherwise the system "save as" dialog opens. Returns a
    /// note for the UI.
    fn export(&self, file_name: &str, mime: &str, bytes: Vec<u8>) -> Result<String, String>;
    /// Open the system file picker for an import; the file arrives later
    /// through [`Platform::take_picked`].
    fn pick_import(&self);
    /// A file the user picked (name, bytes), once.
    fn take_picked(&self) -> Option<(String, Vec<u8>)>;
    /// Open the system folder picker for the export folder.
    fn pick_folder(&self);
    /// The export folder the user chose, for display.
    fn folder_label(&self) -> Option<String>;
    /// Keep the display on (training running) or release it.
    fn keep_screen_on(&self, on: bool);
    /// True once after the app went to the background (checkpoint now).
    fn take_paused(&self) -> bool;
    /// Screen edges covered by system bars / cutouts, in physical pixels,
    /// as `[left, top, right, bottom]`. Desktop and web have none.
    fn safe_insets_px(&self) -> [f32; 4] {
        [0.0; 4]
    }
    /// Minimum top inset in points, used when the OS reports none (insets
    /// not delivered yet, or a vendor that never sends them). Phones: the
    /// status bar / clock must never cover the top bar.
    fn min_top_inset_pt(&self) -> f32 {
        0.0
    }
}

/// Safe-area insets in points (`[left, top, right, bottom]`): the reported
/// px insets divided by `ppp`. `fallback_top_pt` is used only when nothing
/// was reported (all zero), so real insets are never raised or added to.
#[must_use]
pub fn insets_pt(px: [f32; 4], ppp: f32, fallback_top_pt: f32) -> [f32; 4] {
    let ppp = if ppp.is_finite() && ppp > 0.0 { ppp } else { 1.0 };
    let mut v = px.map(|x| if x.is_finite() { x.max(0.0) / ppp } else { 0.0 });
    if v.iter().all(|&x| x == 0.0) {
        v[1] = fallback_top_pt.max(0.0);
    }
    v
}

/// Points per physical pixel for this frame's input: the window's native
/// scale times the egui zoom (the context's own value lags one frame).
#[must_use]
pub fn frame_ppp(native: Option<f32>, zoom: f32, last: f32) -> f32 {
    native.filter(|n| n.is_finite() && *n > 0.0).map_or(last, |n| n * zoom)
}

static PLATFORM: OnceLock<Box<dyn Platform>> = OnceLock::new();

/// Install the host hooks (once, before the app starts).
pub fn install(p: Box<dyn Platform>) {
    if PLATFORM.set(p).is_err() {
        log::warn!("platform hooks installed twice; keeping the first");
    }
}

pub fn get() -> Option<&'static dyn Platform> {
    PLATFORM.get().map(|b| &**b)
}

#[cfg(test)]
mod tests {
    #[test]
    fn insets_scale_and_fallback() {
        assert_eq!(super::insets_pt([0.0, 0.0, 0.0, 0.0], 2.0, 28.0), [0.0, 28.0, 0.0, 0.0]);
        assert_eq!(super::insets_pt([10.0, 96.0, 0.0, 48.0], 2.0, 28.0), [5.0, 48.0, 0.0, 24.0]);
        assert_eq!(super::insets_pt([f32::NAN, -3.0, 0.0, 0.0], 0.0, 0.0), [0.0; 4]);
        // Real insets are not raised by the fallback (no double counting):
        // a status bar of 63 px at 2.625 ppp is 24 pt, not 28.
        assert_eq!(super::insets_pt([0.0, 63.0, 0.0, 0.0], 2.625, 28.0), [0.0, 24.0, 0.0, 0.0]);
        // Landscape with the status bar hidden: only the side cutout.
        assert_eq!(super::insets_pt([84.0, 0.0, 0.0, 0.0], 2.0, 28.0), [42.0, 0.0, 0.0, 0.0]);
    }

    #[test]
    fn ppp_uses_this_frames_scale() {
        assert!((super::frame_ppp(Some(2.625), 1.0, 1.0) - 2.625).abs() < 1e-6);
        assert!((super::frame_ppp(Some(2.0), 1.5, 1.0) - 3.0).abs() < 1e-6);
        assert!((super::frame_ppp(None, 1.0, 2.0) - 2.0).abs() < 1e-6);
        assert!((super::frame_ppp(Some(0.0), 1.0, 2.0) - 2.0).abs() < 1e-6);
    }
}
