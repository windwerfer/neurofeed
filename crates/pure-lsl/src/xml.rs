//! Just enough XML: an element tree for `<desc>` metadata and an escaping
//! writer. LSL never needs attributes, namespaces or mixed content.

use std::fmt::Write;

/// An element with either text or children (LSL metadata convention).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Element {
    pub name: String,
    pub text: String,
    pub children: Vec<Element>,
}

impl Element {
    #[must_use]
    pub fn new(name: impl Into<String>) -> Self {
        Self { name: name.into(), ..Self::default() }
    }

    /// Append `<name>value</name>`; returns `self` for chaining.
    pub fn child_value(&mut self, name: impl Into<String>, value: impl Into<String>) -> &mut Self {
        self.children.push(Element { name: name.into(), text: value.into(), children: Vec::new() });
        self
    }

    /// Append an empty child and return it for filling.
    pub fn append_child(&mut self, name: impl Into<String>) -> &mut Element {
        self.children.push(Element::new(name));
        let last = self.children.len() - 1;
        &mut self.children[last]
    }

    /// First child with this name.
    #[must_use]
    pub fn child(&self, name: &str) -> Option<&Element> {
        self.children.iter().find(|c| c.name == name)
    }

    pub(crate) fn write(&self, out: &mut String, depth: usize) {
        let pad = "\t".repeat(depth);
        if self.children.is_empty() {
            if self.text.is_empty() {
                let _ = writeln!(out, "{pad}<{} />", self.name);
            } else {
                let _ = writeln!(out, "{pad}<{0}>{1}</{0}>", self.name, escape(&self.text));
            }
            return;
        }
        let _ = writeln!(out, "{pad}<{}>", self.name);
        for c in &self.children {
            c.write(out, depth + 1);
        }
        let _ = writeln!(out, "{pad}</{}>", self.name);
    }
}

/// Escape text content.
#[must_use]
pub fn escape(s: &str) -> String {
    let mut o = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => o.push_str("&amp;"),
            '<' => o.push_str("&lt;"),
            '>' => o.push_str("&gt;"),
            '"' => o.push_str("&quot;"),
            '\'' => o.push_str("&apos;"),
            _ => o.push(c),
        }
    }
    o
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_nested_and_escaped() {
        let mut d = Element::new("desc");
        d.append_child("channels").append_child("channel").child_value("label", "a<b");
        let mut s = String::new();
        d.write(&mut s, 0);
        assert_eq!(s, "<desc>\n\t<channels>\n\t\t<channel>\n\t\t\t<label>a&lt;b</label>\n\t\t</channel>\n\t</channels>\n</desc>\n");
        assert_eq!(d.child("channels").map(|c| c.children.len()), Some(1));
    }
}
