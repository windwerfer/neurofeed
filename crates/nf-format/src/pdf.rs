//! Minimal PDF 1.4 writer: A4 pages with Helvetica text, lines and filled
//! rectangles. Pure Rust, no allocation tricks, wasm-clean. Coordinates are
//! PDF points with the origin at the top-left (flipped on output).

use std::fmt::Write;

pub const A4: (f64, f64) = (595.0, 842.0);

/// RGB colour, components 0–1.
pub type Rgb = (f64, f64, f64);

/// One page's content stream under construction.
#[derive(Debug, Default, Clone)]
pub struct Page {
    ops: String,
}

fn esc(s: &str) -> String {
    let mut o = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '(' | ')' | '\\' => {
                o.push('\\');
                o.push(c);
            }
            // WinAnsi covers Latin-1; anything else becomes '?'.
            c if (c as u32) < 256 && !c.is_control() => o.push(c),
            _ => o.push('?'),
        }
    }
    o
}

impl Page {
    fn y(y: f64) -> f64 {
        A4.1 - y
    }

    /// Text with its baseline at (x, y); `bold` picks Helvetica-Bold.
    pub fn text(&mut self, x: f64, y: f64, size: f64, bold: bool, s: &str) {
        let f = if bold { "F2" } else { "F1" };
        let _ = writeln!(self.ops, "BT /{f} {size:.1} Tf {x:.2} {:.2} Td ({}) Tj ET", Self::y(y), esc(s));
    }

    pub fn fill(&mut self, c: Rgb) {
        let _ = writeln!(self.ops, "{:.3} {:.3} {:.3} rg", c.0, c.1, c.2);
    }

    pub fn stroke(&mut self, c: Rgb, width: f64) {
        let _ = writeln!(self.ops, "{:.3} {:.3} {:.3} RG {width:.2} w", c.0, c.1, c.2);
    }

    /// Filled rectangle, top-left (x, y).
    pub fn rect(&mut self, x: f64, y: f64, w: f64, h: f64) {
        let _ = writeln!(self.ops, "{x:.2} {:.2} {w:.2} {h:.2} re f", Self::y(y + h));
    }

    /// Stroked polyline (needs ≥ 2 points).
    pub fn polyline(&mut self, pts: &[(f64, f64)]) {
        let Some((first, rest)) = pts.split_first() else { return };
        if rest.is_empty() {
            return;
        }
        let _ = write!(self.ops, "{:.2} {:.2} m", first.0, Self::y(first.1));
        for p in rest {
            let _ = write!(self.ops, " {:.2} {:.2} l", p.0, Self::y(p.1));
        }
        self.ops.push_str(" S\n");
    }
}

/// Approximate Helvetica width (avg 0.5 em) for simple wrapping.
pub fn wrap(s: &str, size: f64, width: f64) -> Vec<String> {
    let max = ((width / (size * 0.5)) as usize).max(8);
    let mut out = Vec::new();
    for para in s.lines() {
        let mut line = String::new();
        let chars: Vec<char> = para.chars().collect();
        let words: Vec<String> = if chars.iter().any(|c| c.is_whitespace()) || chars.len() <= max {
            para.split_whitespace().map(str::to_string).collect()
        } else {
            chars.chunks(max).map(|c| c.iter().collect()).collect()
        };
        for w in &words {
            if !line.is_empty() && line.chars().count() + 1 + w.chars().count() > max {
                out.push(std::mem::take(&mut line));
            }
            if !line.is_empty() {
                line.push(' ');
            }
            line.push_str(w);
        }
        out.push(line);
    }
    out
}

/// Serialise pages into a complete PDF file.
pub fn write(pages: &[Page], title: &str) -> Vec<u8> {
    let n = pages.len().max(1);
    // Objects: 1 catalog, 2 pages, 3 F1, 4 F2, 5 info, then (page, content) pairs.
    let mut objs: Vec<String> = Vec::with_capacity(5 + 2 * n);
    let kids: Vec<String> = (0..n).map(|i| format!("{} 0 R", 6 + 2 * i)).collect();
    objs.push("<< /Type /Catalog /Pages 2 0 R >>".into());
    objs.push(format!("<< /Type /Pages /Kids [{}] /Count {n} >>", kids.join(" ")));
    for f in ["Helvetica", "Helvetica-Bold"] {
        objs.push(format!("<< /Type /Font /Subtype /Type1 /BaseFont /{f} /Encoding /WinAnsiEncoding >>"));
    }
    objs.push(format!("<< /Title ({}) /Producer (NeuroFeed) >>", esc(title)));
    let empty = Page::default();
    for i in 0..n {
        let p = pages.get(i).unwrap_or(&empty);
        objs.push(format!(
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {} {}] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents {} 0 R >>",
            A4.0,
            A4.1,
            7 + 2 * i
        ));
        objs.push(format!("<< /Length {} >>\nstream\n{}endstream", p.ops.chars().count(), p.ops));
    }
    let mut out: Vec<u8> = b"%PDF-1.4\n%\xE2\xE3\xCF\xD3\n".to_vec();
    let mut offs = Vec::with_capacity(objs.len());
    for (i, o) in objs.iter().enumerate() {
        offs.push(out.len());
        out.extend_from_slice(format!("{} 0 obj\n", i + 1).as_bytes());
        // Content is Latin-1 by construction (esc); write chars as bytes.
        out.extend(o.chars().map(|c| u8::try_from(u32::from(c)).unwrap_or(b'?')));
        out.extend_from_slice(b"\nendobj\n");
    }
    let xref = out.len();
    let mut t = format!("xref\n0 {}\n0000000000 65535 f \n", objs.len() + 1);
    for o in offs {
        let _ = writeln!(t, "{o:010} 00000 n ");
    }
    let _ = write!(t, "trailer\n<< /Size {} /Root 1 0 R /Info 5 0 R >>\nstartxref\n{xref}\n%%EOF\n", objs.len() + 1);
    out.extend_from_slice(t.as_bytes());
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_valid_skeleton() {
        let mut p = Page::default();
        p.text(40.0, 60.0, 12.0, true, "Hi (there) \\ ü");
        p.rect(40.0, 70.0, 10.0, 10.0);
        p.polyline(&[(0.0, 0.0), (10.0, 10.0)]);
        let b = write(&[p], "t");
        let s = String::from_utf8_lossy(&b);
        assert!(s.starts_with("%PDF-1.4"));
        assert!(s.contains("(Hi \\(there\\) \\\\ "));
        assert!(s.trim_end().ends_with("%%EOF"));
        let x: usize = s.rsplit("startxref\n").next().unwrap().lines().next().unwrap().parse().unwrap();
        assert!(b[x..].starts_with(b"xref"));
    }

    #[test]
    fn wraps_long_text() {
        let l = wrap("aaa bbb ccc ddd eee fff ggg hhh", 10.0, 50.0);
        assert!(l.len() > 1 && l.iter().all(|s| s.len() <= 10));
    }
}
