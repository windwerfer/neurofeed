//! Supported-montage matching (ported from `montage_match.dart`). Missing
//! electrodes are never interpolated.

use nf_types::DeviceKind;

pub const MUSE: [&str; 4] = ["TP9", "AF7", "AF8", "TP10"];
pub const MUSE_AUX: [&str; 4] = ["AUX1", "AUX2", "AUX3", "AUX4"];
pub const CROWN: [&str; 8] = ["CP3", "C3", "F5", "PO3", "PO4", "F6", "C4", "CP4"];
const REFERENCE_SUFFIXES: [&str; 3] = ["-REF", "-LE", "-AVG"];

/// Upper-case electrode name without an `EEG ` prefix or reference suffix.
pub fn normalize_label(raw: &str) -> String {
    let mut s = raw.trim().to_uppercase();
    if let Some(rest) = s.strip_prefix("EEG ") {
        s = rest.trim().to_owned();
    }
    for suf in REFERENCE_SUFFIXES {
        if let Some(rest) = s.strip_suffix(suf) {
            return rest.trim().to_owned();
        }
    }
    s
}

/// `REF` / `LE` / `AVG` from a label suffix.
pub fn reference_suffix(raw: &str) -> Option<&'static str> {
    let s = raw.trim().to_uppercase();
    REFERENCE_SUFFIXES.iter().find(|suf| s.ends_with(*suf)).map(|suf| &suf[1..])
}

#[derive(Debug, Clone, PartialEq)]
pub struct MontageMatch {
    pub kind: DeviceKind,
    /// Our labels in electrode order (head, then AUX).
    pub labels: Vec<String>,
    /// Source index per label.
    pub source: Vec<usize>,
    /// Source labels not kept.
    pub dropped: Vec<String>,
}

/// Muse TP9/AF7/AF8/TP10 (+ leading AUX1..4) or the Crown 8; Muse wins.
pub fn match_montage(source: &[String]) -> Option<MontageMatch> {
    let names: Vec<String> = source.iter().map(|s| normalize_label(s)).collect();
    let find = |l: &str| names.iter().position(|n| n == l);
    for (kind, head) in [(DeviceKind::Muse, &MUSE[..]), (DeviceKind::Crown, &CROWN[..])] {
        let Some(mut idx) = head.iter().map(|l| find(l)).collect::<Option<Vec<_>>>() else { continue };
        let mut labels: Vec<String> = head.iter().map(|s| (*s).to_owned()).collect();
        if kind == DeviceKind::Muse {
            for aux in MUSE_AUX.iter().map_while(|a| find(a).map(|i| (a, i))) {
                labels.push((*aux.0).to_owned());
                idx.push(aux.1);
            }
        }
        let dropped = source.iter().enumerate().filter(|(i, _)| !idx.contains(i)).map(|(_, s)| s.clone()).collect();
        return Some(MontageMatch { kind, labels, source: idx, dropped });
    }
    None
}

/// User-facing refusal when no complete montage is present.
pub fn no_montage_message(source: &[String]) -> String {
    let found = if source.is_empty() { "no EEG channels".to_owned() } else { source.join(", ") };
    format!(
        "No supported headset montage in this file. Import needs all of {} (Muse) or {} (Crown); \
         missing electrodes are never interpolated. Found: {found}.",
        MUSE.join(", "),
        CROWN.join(", ")
    )
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|x| (*x).to_owned()).collect()
    }

    #[test]
    fn muse_with_prefix_suffix_and_aux() {
        let m = match_montage(&s(&["EEG TP9-REF", "AF7", "ECG", "af8", "TP10-LE", "AUX1"])).unwrap();
        assert_eq!(m.kind, DeviceKind::Muse);
        assert_eq!(m.labels, s(&["TP9", "AF7", "AF8", "TP10", "AUX1"]));
        assert_eq!(m.source, vec![0, 1, 3, 4, 5]);
        assert_eq!(m.dropped, s(&["ECG"]));
        assert_eq!(reference_suffix("TP9-REF"), Some("REF"));
    }

    #[test]
    fn incomplete_is_refused() {
        assert!(match_montage(&s(&["TP9", "AF7", "AF8"])).is_none());
        assert!(no_montage_message(&s(&["Fp1"])).contains("Found: Fp1."));
        let crown = match_montage(&s(&CROWN)).map(|m| m.kind);
        assert_eq!(crown, Some(DeviceKind::Crown));
    }
}
