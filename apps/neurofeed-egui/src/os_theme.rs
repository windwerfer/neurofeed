//! The OS light/dark preference where eframe does not report one.
//!
//! eframe already gives egui the system theme on macOS and Windows (winit,
//! live via `ThemeChanged`) and on the web (`prefers-color-scheme`, live).
//! winit reports nothing on X11 and Android (and often on Wayland), so egui
//! would fall back to dark. This fills the gap:
//! - Android: the installed [`crate::platform`] hook (Configuration.uiMode).
//! - Linux desktop: the XDG desktop portal `org.freedesktop.appearance
//!   color-scheme`, else GNOME's `color-scheme` / `gtk-theme`, re-read every
//!   few seconds on a background thread (never on the UI thread).

use egui::Theme;

/// The OS preference from our own probes (`None`: unknown / no preference).
#[must_use]
pub fn get() -> Option<Theme> {
    if let Some(dark) = crate::platform::get().and_then(crate::platform::Platform::system_dark) {
        return Some(if dark { Theme::Dark } else { Theme::Light });
    }
    linux::get()
}

/// Portal `color-scheme` from `gdbus call ... Settings.Read(One)` output, e.g.
/// `(<<uint32 1>>,)` or `(<uint32 2>,)`: 1 = prefer dark, 2 = prefer light,
/// 0 = no preference.
#[must_use]
pub fn parse_portal(out: &str) -> Option<Theme> {
    let n = out.split("uint32").nth(1)?.trim_start().chars().take_while(char::is_ascii_digit).collect::<String>();
    match n.parse::<u32>().ok()? {
        1 => Some(Theme::Dark),
        2 => Some(Theme::Light),
        _ => None,
    }
}

/// `gsettings get org.gnome.desktop.interface color-scheme` (`'prefer-dark'`,
/// `'prefer-light'`, `'default'`; `default` means light on GNOME).
#[must_use]
pub fn parse_color_scheme(out: &str) -> Option<Theme> {
    let v = out.trim().trim_matches('\'');
    match v {
        "prefer-dark" => Some(Theme::Dark),
        "prefer-light" | "default" => Some(Theme::Light),
        _ => None,
    }
}

/// `gsettings get org.gnome.desktop.interface gtk-theme`, e.g. `'Adwaita-dark'`.
#[must_use]
pub fn parse_gtk_theme(out: &str) -> Option<Theme> {
    let v = out.trim().trim_matches('\'');
    if v.is_empty() {
        None
    } else if v.to_ascii_lowercase().contains("dark") {
        Some(Theme::Dark)
    } else {
        Some(Theme::Light)
    }
}

#[cfg(all(target_os = "linux", not(target_arch = "wasm32")))]
mod linux {
    use super::{parse_color_scheme, parse_gtk_theme, parse_portal};
    use egui::Theme;
    use std::process::{Command, Stdio};
    use std::sync::atomic::{AtomicU8, Ordering};
    use std::sync::Once;
    use std::time::Duration;

    /// 0 unknown, 1 light, 2 dark.
    static THEME: AtomicU8 = AtomicU8::new(0);
    static START: Once = Once::new();
    const POLL: Duration = Duration::from_secs(3);

    pub fn get() -> Option<Theme> {
        START.call_once(|| {
            let spawned = std::thread::Builder::new().name("os-theme".into()).spawn(|| loop {
                let t = probe();
                let v = match t {
                    None => 0,
                    Some(Theme::Light) => 1,
                    Some(Theme::Dark) => 2,
                };
                if THEME.swap(v, Ordering::Relaxed) != v {
                    log::info!("OS theme: {t:?}");
                }
                std::thread::sleep(POLL);
            });
            if let Err(e) = spawned {
                log::warn!("OS theme probe thread: {e}");
            }
        });
        match THEME.load(Ordering::Relaxed) {
            1 => Some(Theme::Light),
            2 => Some(Theme::Dark),
            _ => None,
        }
    }

    fn run(cmd: &str, args: &[&str]) -> Option<String> {
        let out = Command::new(cmd).args(args).stdin(Stdio::null()).stderr(Stdio::null()).output().ok()?;
        out.status.success().then(|| String::from_utf8_lossy(&out.stdout).into_owned())
    }

    fn probe() -> Option<Theme> {
        // Portal first: KDE, GNOME 42+, and inside Flatpak.
        let portal = |method: &str| {
            run(
                "gdbus",
                &[
                    "call",
                    "--session",
                    "--timeout",
                    "2",
                    "--dest",
                    "org.freedesktop.portal.Desktop",
                    "--object-path",
                    "/org/freedesktop/portal/desktop",
                    "--method",
                    method,
                    "org.freedesktop.appearance",
                    "color-scheme",
                ],
            )
        };
        if let Some(out) = portal("org.freedesktop.portal.Settings.ReadOne").or_else(|| portal("org.freedesktop.portal.Settings.Read")) {
            if let Some(t) = parse_portal(&out) {
                return Some(t);
            }
        }
        let gs = |key: &str| run("gsettings", &["get", "org.gnome.desktop.interface", key]);
        gs("color-scheme").as_deref().and_then(parse_color_scheme).or_else(|| gs("gtk-theme").as_deref().and_then(parse_gtk_theme))
    }
}

#[cfg(not(all(target_os = "linux", not(target_arch = "wasm32"))))]
mod linux {
    pub fn get() -> Option<egui::Theme> {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn portal_replies() {
        assert_eq!(parse_portal("(<<uint32 1>>,)\n"), Some(Theme::Dark));
        assert_eq!(parse_portal("(<uint32 2>,)"), Some(Theme::Light));
        assert_eq!(parse_portal("(<<uint32 0>>,)"), None);
        assert_eq!(parse_portal("Error: GDBus.Error:org.freedesktop.portal.Error.NotFound"), None);
    }

    #[test]
    fn gnome_settings() {
        assert_eq!(parse_color_scheme("'prefer-dark'\n"), Some(Theme::Dark));
        assert_eq!(parse_color_scheme("'default'"), Some(Theme::Light));
        assert_eq!(parse_color_scheme(""), None);
        assert_eq!(parse_gtk_theme("'Adwaita-dark'"), Some(Theme::Dark));
        assert_eq!(parse_gtk_theme("'Adwaita'"), Some(Theme::Light));
        assert_eq!(parse_gtk_theme("''"), None);
    }
}
