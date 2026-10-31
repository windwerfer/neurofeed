//! On-disk model folders: `<root>/<model id>/` with the weights file, an
//! app-written `config.json` and a `verified.sha256` stamp. Weights are only
//! accepted after their SHA-256 matches the pinned hash.

use anyhow::{bail, Context};
use nf_types::AiModel;
use sha2::{Digest, Sha256};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

const STAMP: &str = "verified.sha256";

#[derive(Debug, Clone)]
pub struct ModelStore {
    root: PathBuf,
}

/// `NF_AI_DIR`, else `<user data dir>/neurofeed/ai_models`.
pub fn default_root() -> Option<PathBuf> {
    if let Some(p) = std::env::var_os("NF_AI_DIR") {
        return Some(PathBuf::from(p));
    }
    let env = |k| std::env::var_os(k).map(PathBuf::from);
    let base = if cfg!(windows) {
        env("APPDATA")?.join("NeuroFeed")
    } else if cfg!(target_os = "macos") {
        env("HOME")?.join("Library/Application Support/NeuroFeed")
    } else {
        env("XDG_DATA_HOME").or_else(|| env("HOME").map(|h| h.join(".local/share")))?.join("neurofeed")
    };
    Some(base.join("ai_models"))
}

impl ModelStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }
    pub fn dir(&self, m: AiModel) -> PathBuf {
        self.root.join(m.id())
    }
    pub fn weights(&self, m: AiModel) -> PathBuf {
        self.dir(m).join(m.weights_file())
    }
    /// Weights present and stamped as verified.
    pub fn installed(&self, m: AiModel) -> bool {
        self.weights(m).is_file() && fs::read_to_string(self.dir(m).join(STAMP)).is_ok_and(|s| s.trim() == m.sha256())
    }

    /// Copy (hashing) `src` into the model folder. `progress` gets 0..1.
    pub fn import(&self, m: AiModel, src: &Path, progress: &mut dyn FnMut(f64)) -> anyhow::Result<()> {
        let f = fs::File::open(src).with_context(|| format!("open {}", src.display()))?;
        let len = f.metadata().map(|md| md.len()).ok();
        self.write_verified(m, f, len, progress)
    }

    /// Download from the model's public URL.
    #[cfg(feature = "download")]
    pub fn download(&self, m: AiModel, progress: &mut dyn FnMut(f64)) -> anyhow::Result<()> {
        let url = m.download_url().with_context(|| format!("{} is gated: download it in the browser and import the file", m.label()))?;
        let resp = ureq::get(url).call().with_context(|| format!("download {url}"))?;
        let len = resp.headers().get("content-length").and_then(|v| v.to_str().ok()).and_then(|v| v.parse().ok());
        self.write_verified(m, resp.into_body().into_reader(), len, progress)
    }

    fn write_verified(&self, m: AiModel, mut src: impl Read, len: Option<u64>, progress: &mut dyn FnMut(f64)) -> anyhow::Result<()> {
        let dir = self.dir(m);
        fs::create_dir_all(&dir).with_context(|| format!("create {}", dir.display()))?;
        let part = dir.join(format!("{}.part", m.weights_file()));
        let mut out = fs::File::create(&part)?;
        let (mut hasher, mut buf, mut done) = (Sha256::new(), vec![0u8; 1 << 16], 0u64);
        loop {
            let n = src.read(&mut buf)?;
            if n == 0 {
                break;
            }
            hasher.update(&buf[..n]);
            out.write_all(&buf[..n])?;
            done += n as u64;
            if let Some(l) = len.filter(|l| *l > 0) {
                progress((done as f64 / l as f64).min(1.0));
            }
        }
        out.flush()?;
        let hex: String = hasher.finalize().iter().map(|b| format!("{b:02x}")).collect();
        if hex != m.sha256() {
            let _ = fs::remove_file(&part);
            bail!("{} checksum mismatch: this is not the expected {} file (got {}…)", m.label(), m.weights_file(), &hex[..12]);
        }
        fs::rename(&part, self.weights(m))?;
        if m == AiModel::ReveBase {
            #[cfg(feature = "reve")]
            fs::write(dir.join("config.json"), crate::reve::config_json())?;
        }
        fs::write(dir.join(STAMP), m.sha256())?;
        Ok(())
    }

    pub fn remove(&self, m: AiModel) -> anyhow::Result<()> {
        let dir = self.dir(m);
        if dir.is_dir() {
            fs::remove_dir_all(&dir).with_context(|| format!("remove {}", dir.display()))?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    #[test]
    fn wrong_file_is_rejected_and_leaves_nothing() {
        let root = std::env::temp_dir().join(format!("nf-ai-store-{}", std::process::id()));
        let src = root.join("x.pth");
        fs::create_dir_all(&root).unwrap();
        fs::write(&src, b"not a model").unwrap();
        let s = ModelStore::new(root.join("models"));
        let e = s.import(AiModel::CbramodAVig, &src, &mut |_| {}).unwrap_err();
        assert!(e.to_string().contains("checksum"));
        assert!(!s.installed(AiModel::CbramodAVig));
        assert!(!s.weights(AiModel::CbramodAVig).exists());
        fs::remove_dir_all(&root).unwrap();
    }
}
