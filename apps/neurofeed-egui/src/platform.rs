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
