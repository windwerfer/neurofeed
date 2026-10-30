//! Discovery queries: the XPath 1.0 subset resolvers actually send, e.g.
//! `session_id='default' and type='EEG'`. Supported: `and`, `or`,
//! `not(..)`, parentheses, `= != < <= > >=`, string and number literals,
//! `starts-with(a,b)` and `contains(a,b)`, and paths into the info
//! (`name`, `desc/manufacturer`). A query that does not parse matches
//! nothing, like liblsl does with a malformed XPath.

use crate::StreamInfo;

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    Str(String),
    Num(f64),
    Name(String),
    Op(&'static str),
    Open,
    Close,
    Comma,
}

fn lex(q: &str) -> Option<Vec<Tok>> {
    let c: Vec<char> = q.chars().collect();
    let mut i = 0;
    let mut out = Vec::new();
    while i < c.len() {
        let ch = c[i];
        if ch.is_whitespace() {
            i += 1;
            continue;
        }
        let (tok, len) = lex_one(&c[i..])?;
        out.push(tok);
        i += len;
    }
    Some(out)
}

fn lex_one(c: &[char]) -> Option<(Tok, usize)> {
    let two: String = c.iter().take(2).collect();
    for op in ["!=", "<=", ">="] {
        if two == op {
            return Some((Tok::Op(op), 2));
        }
    }
    let simple = match c[0] {
        '=' => Some(Tok::Op("=")),
        '<' => Some(Tok::Op("<")),
        '>' => Some(Tok::Op(">")),
        '(' => Some(Tok::Open),
        ')' => Some(Tok::Close),
        ',' => Some(Tok::Comma),
        _ => None,
    };
    if let Some(t) = simple {
        return Some((t, 1));
    }
    if c[0] == '\'' || c[0] == '"' {
        let end = c[1..].iter().position(|&x| x == c[0])?;
        return Some((Tok::Str(c[1..=end].iter().collect()), end + 2));
    }
    let len = c.iter().take_while(|x| x.is_alphanumeric() || "_-./@*".contains(**x)).count();
    if len == 0 {
        return None;
    }
    let word: String = c[..len].iter().collect();
    let tok = match word.parse::<f64>() {
        Ok(n) if c[0].is_ascii_digit() || c[0] == '.' || c[0] == '-' => Tok::Num(n),
        _ => Tok::Name(word),
    };
    Some((tok, len))
}

/// Operand values: a (possibly empty) node-set of strings, a string, a number or a boolean.
#[derive(Debug, Clone, PartialEq)]
enum Val {
    Nodes(Vec<String>),
    Str(String),
    Num(f64),
    Bool(bool),
}

impl Val {
    fn truthy(&self) -> bool {
        match self {
            Val::Nodes(n) => !n.is_empty(),
            Val::Str(s) => !s.is_empty(),
            Val::Num(n) => *n != 0.0 && !n.is_nan(),
            Val::Bool(b) => *b,
        }
    }
    fn strings(&self) -> Vec<String> {
        match self {
            Val::Nodes(n) => n.clone(),
            Val::Str(s) => vec![s.clone()],
            Val::Num(n) => vec![n.to_string()],
            Val::Bool(b) => vec![b.to_string()],
        }
    }
}

struct Parser<'a> {
    toks: Vec<Tok>,
    pos: usize,
    info: &'a StreamInfo,
}

impl Parser<'_> {
    fn peek(&self) -> Option<&Tok> {
        self.toks.get(self.pos)
    }
    fn next(&mut self) -> Option<Tok> {
        let t = self.toks.get(self.pos).cloned();
        self.pos += 1;
        t
    }
    fn keyword(&mut self, k: &str) -> bool {
        let hit = matches!(self.peek(), Some(Tok::Name(n)) if n == k);
        self.pos += usize::from(hit);
        hit
    }
    fn expect(&mut self, t: &Tok) -> Option<()> {
        (self.next().as_ref() == Some(t)).then_some(())
    }

    fn or(&mut self) -> Option<Val> {
        let mut v = self.and()?.truthy();
        while self.keyword("or") {
            v |= self.and()?.truthy();
        }
        Some(Val::Bool(v))
    }

    fn and(&mut self) -> Option<Val> {
        let first = self.cmp()?;
        if !matches!(self.peek(), Some(Tok::Name(n)) if n == "and") {
            return Some(first);
        }
        let mut v = first.truthy();
        while self.keyword("and") {
            v &= self.cmp()?.truthy();
        }
        Some(Val::Bool(v))
    }

    fn cmp(&mut self) -> Option<Val> {
        let a = self.operand()?;
        let Some(Tok::Op(op)) = self.peek().cloned() else { return Some(a) };
        self.pos += 1;
        let b = self.operand()?;
        Some(Val::Bool(compare(&a, op, &b)))
    }

    fn operand(&mut self) -> Option<Val> {
        match self.next()? {
            Tok::Str(s) => Some(Val::Str(s)),
            Tok::Num(n) => Some(Val::Num(n)),
            Tok::Open => {
                let v = self.or()?;
                self.expect(&Tok::Close)?;
                Some(v)
            }
            Tok::Name(n) if self.peek() == Some(&Tok::Open) => self.call(&n),
            Tok::Name(n) => Some(Val::Nodes(lookup(self.info, &n))),
            _ => None,
        }
    }

    /// Function argument: an expression, but plain operands keep their value.
    fn arg(&mut self) -> Option<Val> {
        let start = self.pos;
        let v = self.operand()?;
        if matches!(self.peek(), Some(Tok::Comma | Tok::Close)) {
            return Some(v);
        }
        self.pos = start;
        self.or()
    }

    fn call(&mut self, f: &str) -> Option<Val> {
        self.expect(&Tok::Open)?;
        let mut args = vec![self.arg()?];
        while self.peek() == Some(&Tok::Comma) {
            self.pos += 1;
            args.push(self.arg()?);
        }
        self.expect(&Tok::Close)?;
        let s = |i: usize| args.get(i).map(|v| v.strings().into_iter().next().unwrap_or_default());
        Some(Val::Bool(match (f, args.len()) {
            ("not", 1) => !args[0].truthy(),
            ("starts-with", 2) => s(0)?.starts_with(&s(1)?),
            ("contains", 2) => s(0)?.contains(&s(1)?),
            _ => return None,
        }))
    }
}

fn compare(a: &Val, op: &str, b: &Val) -> bool {
    let numeric = matches!(a, Val::Num(_)) || matches!(b, Val::Num(_)) || !matches!(op, "=" | "!=");
    a.strings().iter().any(|x| {
        b.strings().iter().any(|y| {
            if numeric {
                match (x.trim().parse::<f64>(), y.trim().parse::<f64>()) {
                    (Ok(p), Ok(q)) => num_cmp(p, op, q),
                    _ => false,
                }
            } else {
                (x == y) == (op == "=")
            }
        })
    })
}

fn num_cmp(p: f64, op: &str, q: f64) -> bool {
    match op {
        "=" => p == q,
        "!=" => p != q,
        "<" => p < q,
        "<=" => p <= q,
        ">" => p > q,
        _ => p >= q,
    }
}

fn lookup(info: &StreamInfo, path: &str) -> Vec<String> {
    let path = path.trim_start_matches("/info/").trim_start_matches("info/");
    let mut parts = path.split('/');
    let Some(head) = parts.next() else { return Vec::new() };
    if head != "desc" {
        return info.field(head).into_iter().collect();
    }
    let mut nodes = vec![info.desc()];
    for p in parts {
        nodes = nodes.iter().flat_map(|n| n.children.iter().filter(|c| c.name == p)).collect();
    }
    nodes.into_iter().map(|n| n.text.clone()).collect()
}

/// Does `info` match the query? The empty query matches everything.
#[must_use]
pub fn matches(info: &StreamInfo, query: &str) -> bool {
    if query.trim().is_empty() {
        return true;
    }
    let Some(toks) = lex(query) else { return false };
    let mut p = Parser { toks, pos: 0, info };
    match p.or() {
        Some(v) if p.pos == p.toks.len() => v.truthy(),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use crate::ChannelFormat;

    fn info() -> StreamInfo {
        let mut i = StreamInfo::new("Muse S", "EEG", 4, 256.0, ChannelFormat::Float32, "muse-1").unwrap();
        i.desc_mut().child_value("manufacturer", "Interaxon");
        i
    }

    #[test]
    fn resolver_queries() {
        let i = info();
        for (q, want) in [
            ("", true),
            ("session_id='default'", true),
            ("session_id='default' and type='EEG'", true),
            ("session_id='default' and name='Other'", false),
            ("name='Other' or type=\"EEG\"", true),
            ("channel_count>2 and nominal_srate=256", true),
            ("channel_count >= 5", false),
            ("starts-with(name,'Muse') and not(type='Markers')", true),
            ("contains(source_id, 'se-')", true),
            ("desc/manufacturer='Interaxon'", true),
            ("desc/nope='x'", false),
            ("name!='Muse S'", false),
            ("(type='EEG' or type='Gaze') and session_id='default'", true),
            ("name='unterminated", false),
            ("name= and", false),
        ] {
            assert_eq!(matches(&i, q), want, "{q}");
        }
    }
}
