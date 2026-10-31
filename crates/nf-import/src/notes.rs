//! Annotation mapping (ported from `import_types.dart`): only the locked v6
//! note types are kept; nothing is invented.

use crate::Annotation;

pub const LOCKED_TYPES: [&str; 7] = ["pause", "bad_quality", "disconnect", "double_blink", "double_jaw_clench", "eye_up", "eye_down"];
/// Consecutive Blink / Jaw_Clench within this window become a double.
pub const DOUBLE_WINDOW_S: f64 = 2.0;

fn snake(raw: &str) -> String {
    let lower = raw.trim().to_lowercase();
    let mut out = String::with_capacity(lower.len());
    for c in lower.chars() {
        if c.is_whitespace() || c == '-' {
            if !out.ends_with('_') {
                out.push('_');
            }
        } else {
            out.push(c);
        }
    }
    out
}

/// Free text → locked type, `None` when unknown.
pub fn map_type(raw: &str) -> Option<&'static str> {
    let s = snake(raw);
    if let Some(t) = LOCKED_TYPES.iter().find(|t| **t == s) {
        return Some(t);
    }
    match s.as_str() {
        "doubleblink" | "double_blinks" => Some("double_blink"),
        "doubleclench" | "double_clench" | "double_jawclench" | "jaw_clench_double" => Some("double_jaw_clench"),
        "eyeup" | "eyes_up" => Some("eye_up"),
        "eyedown" | "eyes_down" => Some("eye_down"),
        "badquality" | "bad_qual" | "unusable" => Some("bad_quality"),
        _ => None,
    }
}

/// First subfield of the EDF patient id; `None` for missing or `X`.
pub fn edf_patient_code(patient_id: &str) -> Option<String> {
    let code = patient_id.split_whitespace().next()?;
    (!code.eq_ignore_ascii_case("x")).then(|| code.to_owned())
}

#[derive(Clone, Copy, PartialEq)]
enum Gesture {
    Blink,
    Jaw,
}

fn gesture(token: &str) -> Option<Gesture> {
    match snake(token).as_str() {
        "blink" | "/muse/elements/blink" => Some(Gesture::Blink),
        "jaw_clench" | "jawclench" | "/muse/elements/jaw_clench" => Some(Gesture::Jaw),
        _ => None,
    }
}

fn is_marker(token: &str) -> bool {
    let s = snake(token);
    let digits = s.strip_prefix("/marker/").unwrap_or(&s);
    (!digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit())) || s.starts_with("/marker/") || s.starts_with("marker_")
}

#[derive(Default)]
struct Elements {
    notes: Vec<Annotation>,
    pending: Option<(Gesture, f64)>,
    singles: usize,
    markers: usize,
    unknown: usize,
}

impl Elements {
    fn flush(&mut self) {
        if self.pending.take().is_some() {
            self.singles += 1;
        }
    }

    fn gesture(&mut self, g: Gesture, t: f64) {
        match self.pending {
            Some((p, at)) if p == g && t - at <= DOUBLE_WINDOW_S => {
                let kind = if g == Gesture::Blink { "double_blink" } else { "double_jaw_clench" };
                self.notes.push(Annotation::at(t, kind));
                self.pending = None;
            }
            _ => {
                self.flush();
                self.pending = Some((g, t));
            }
        }
    }

    fn mark(&mut self, t: f64, token: &str) {
        if let Some(locked) = map_type(token) {
            self.flush();
            self.notes.push(Annotation::at(t, locked));
        } else if let Some(g) = gesture(token) {
            self.gesture(g, t);
        } else if is_marker(token) {
            self.markers += 1;
        } else {
            self.unknown += 1;
        }
    }

    fn warnings(&self) -> Vec<String> {
        let mut w = Vec::new();
        if self.singles > 0 {
            w.push(format!("skipped {} single Blink/Jaw_Clench (locked types are doubles only)", self.singles));
        }
        if self.markers > 0 {
            w.push(format!("skipped {} numbered Elements markers (no locked note type)", self.markers));
        }
        if self.unknown > 0 {
            w.push(format!("skipped {} unknown Elements values", self.unknown));
        }
        w
    }
}

/// Mind Monitor `Elements` cells `(onset s, text)` → notes + warnings.
pub fn map_elements(marks: &[(f64, String)]) -> (Vec<Annotation>, Vec<String>) {
    let mut e = Elements::default();
    for (t, raw) in marks.iter().filter(|(_, r)| !r.trim().is_empty()) {
        e.mark(*t, raw.trim());
    }
    e.flush();
    let w = e.warnings();
    (e.notes, w)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn locked_and_aliases() {
        assert_eq!(map_type("Double Blink"), Some("double_blink"));
        assert_eq!(map_type("eyes-up"), Some("eye_up"));
        assert_eq!(map_type("unusable"), Some("bad_quality"));
        assert_eq!(map_type("lunch"), None);
        assert_eq!(edf_patient_code("X X X X"), None);
        assert_eq!(edf_patient_code("P01 M 01-JAN-1990 Name"), Some("P01".into()));
    }

    #[test]
    fn elements_pair_doubles_and_count_the_rest() {
        let m: Vec<(f64, String)> = [
            (1.0, "Blink"),
            (2.5, "/muse/elements/blink"),
            (5.0, "Blink"),
            (10.0, "jaw_clench"),
            (11.0, "Jaw_Clench"),
            (12.0, "/Marker/1"),
            (13.0, "??"),
        ]
        .iter()
        .map(|(t, s)| (*t, (*s).to_owned()))
        .collect();
        let (notes, w) = map_elements(&m);
        let kinds: Vec<_> = notes.iter().map(|n| (n.onset, n.kind.as_str())).collect();
        assert_eq!(kinds, vec![(2.5, "double_blink"), (11.0, "double_jaw_clench")]);
        assert_eq!(w.len(), 3, "{w:?}");
        assert!(w[0].starts_with("skipped 1 single"));
    }
}
