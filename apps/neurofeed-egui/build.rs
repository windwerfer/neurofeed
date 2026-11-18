//! Windows-only: embed the version resource and app icon into `neurofeed.exe`.
//! A no-op for every other target (Linux, macOS, Android, wasm).

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=assets/neurofeed.ico");
    println!("cargo:rerun-if-env-changed=NEUROFEED_VERSION");
    #[cfg(windows)]
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        if let Err(e) = embed_resources() {
            println!("cargo:warning=could not embed Windows resources: {e}");
        }
    }
}

/// Dotted numeric version (up to 4 parts) packed as the Win32 `FILEVERSION` u64.
#[cfg(windows)]
fn pack_version(v: &str) -> u64 {
    let mut parts = [0u64; 4];
    for (slot, p) in parts.iter_mut().zip(v.split(|c: char| !c.is_ascii_digit()).filter(|s| !s.is_empty())) {
        *slot = p.parse::<u64>().unwrap_or(0).min(0xFFFF);
    }
    (parts[0] << 48) | (parts[1] << 32) | (parts[2] << 16) | parts[3]
}

#[cfg(windows)]
fn embed_resources() -> std::io::Result<()> {
    let cargo_version = std::env::var("CARGO_PKG_VERSION").unwrap_or_default();
    let version = std::env::var("NEUROFEED_VERSION").ok().filter(|v| !v.trim().is_empty()).unwrap_or(cargo_version);
    let version = version.trim().trim_start_matches('v').to_owned();
    let packed = pack_version(&version);
    let mut res = winresource::WindowsResource::new();
    res.set_icon("assets/neurofeed.ico")
        .set("ProductName", "NeuroFeed")
        .set("FileDescription", "NeuroFeed - EEG neurofeedback")
        .set("CompanyName", "Thomas Barth")
        .set("LegalCopyright", "Copyright (c) Thomas Barth. Licensed under the Apache License 2.0.")
        .set("OriginalFilename", "neurofeed.exe")
        .set("InternalName", "neurofeed")
        .set("FileVersion", &version)
        .set("ProductVersion", &version)
        .set_version_info(winresource::VersionInfo::FILEVERSION, packed)
        .set_version_info(winresource::VersionInfo::PRODUCTVERSION, packed);
    res.compile()
}
