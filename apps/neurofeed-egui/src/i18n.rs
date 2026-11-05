//! UI translations: Fluent (`locales/<lang>.ftl`, compiled in), looked up
//! with `t!("key")` or `t!("key", name = value)`. English is the fallback
//! for a missing key; an unknown key renders as the key itself. The active
//! language follows `settings.language` (`auto` = system locale).

use fluent_bundle::{FluentArgs, FluentBundle, FluentResource, FluentValue};
use nf_core::settings::Language;
use std::sync::atomic::{AtomicU8, Ordering};

/// `(code, ftl source)`; index 0 (English) is the fallback.
pub const LOCALES: [(&str, &str); 2] = [("en", include_str!("../locales/en.ftl")), ("de", include_str!("../locales/de.ftl"))];

static ACTIVE: AtomicU8 = AtomicU8::new(0);

thread_local! {
    static BUNDLES: Vec<FluentBundle<FluentResource>> = LOCALES.iter().map(|(code, src)| bundle(code, src)).collect();
}

fn bundle(code: &str, src: &str) -> FluentBundle<FluentResource> {
    let lang: unic_langid::LanguageIdentifier = code.parse().unwrap_or_default();
    let mut b = FluentBundle::new(vec![lang]);
    b.set_use_isolating(false);
    let res = FluentResource::try_new(src.to_owned()).unwrap_or_else(|(r, errs)| {
        log::warn!("{code}.ftl: {} parse errors", errs.len());
        r
    });
    if let Err(e) = b.add_resource(res) {
        log::warn!("{code}.ftl: {} duplicate keys", e.len());
    }
    b
}

/// Language code for a setting (`auto` → system locale, else English).
#[must_use]
pub fn resolve(lang: Language) -> &'static str {
    match lang {
        Language::En => "en",
        Language::De => "de",
        Language::Auto => {
            static SYS: std::sync::OnceLock<&'static str> = std::sync::OnceLock::new();
            SYS.get_or_init(|| from_locale(sys_locale::get_locale().as_deref().unwrap_or("en")))
        }
    }
}

/// Best supported language for a BCP-47 tag like `de-AT` (English fallback).
#[must_use]
pub fn from_locale(tag: &str) -> &'static str {
    let primary = tag.split(['-', '_']).next().unwrap_or("").to_ascii_lowercase();
    LOCALES.iter().map(|(c, _)| *c).find(|c| *c == primary).unwrap_or("en")
}

/// Switch the UI language (cheap; call every frame).
pub fn set(lang: Language) {
    let code = resolve(lang);
    let i = LOCALES.iter().position(|(c, _)| *c == code).unwrap_or(0);
    ACTIVE.store(i as u8, Ordering::Relaxed);
}

/// Active language code.
#[must_use]
pub fn active() -> &'static str {
    LOCALES[usize::from(ACTIVE.load(Ordering::Relaxed)).min(LOCALES.len() - 1)].0
}

/// Translate `key` with optional named arguments.
#[must_use]
pub fn tr(key: &str, args: &[(&str, FluentValue<'_>)]) -> String {
    let fa = (!args.is_empty()).then(|| {
        let mut a = FluentArgs::new();
        for (k, v) in args {
            a.set(*k, v.clone());
        }
        a
    });
    let active = usize::from(ACTIVE.load(Ordering::Relaxed));
    BUNDLES.with(|bs| {
        for i in [active, 0] {
            let Some(b) = bs.get(i) else { continue };
            if let Some(p) = b.get_message(key).and_then(|m| m.value()) {
                let mut errs = vec![];
                return b.format_pattern(p, fa.as_ref(), &mut errs).into_owned();
            }
        }
        key.to_owned()
    })
}

/// `key` translated, or `fallback` when no locale has it.
fn tr_or(key: &str, fallback: &str) -> String {
    let s = tr(key, &[]);
    if s == key {
        fallback.to_owned()
    } else {
        s
    }
}

/// `protocol-<kebab id>-<field>` for a built-in protocol id like `restAwake`.
fn protocol_key(id: &str, field: &str) -> String {
    let mut k = String::from("protocol-");
    for c in id.chars() {
        if c.is_ascii_uppercase() {
            k.push('-');
        }
        k.push(c.to_ascii_lowercase());
    }
    format!("{k}-{field}")
}

/// Display title of a protocol: built-ins are translated (`protocol-<id>-title`),
/// custom protocols show the user's own text. The id and the English title in
/// `nf-core` stay as they are for MCP / CLI.
#[must_use]
pub fn protocol_title(p: &nf_core::nf_feedback::Protocol) -> String {
    if p.custom {
        p.title.clone()
    } else {
        tr_or(&protocol_key(&p.id, "title"), &p.title)
    }
}

/// Display summary of a protocol (see [`protocol_title`]).
#[must_use]
pub fn protocol_summary(p: &nf_core::nf_feedback::Protocol) -> String {
    if p.custom {
        p.summary.clone()
    } else {
        tr_or(&protocol_key(&p.id, "summary"), &p.summary)
    }
}

/// `t!("key")`, `t!("key", n = 3, name = "x")`.
#[macro_export]
macro_rules! t {
    ($key:literal) => {
        $crate::i18n::tr($key, &[])
    };
    ($key:literal, $($name:ident = $val:expr),+ $(,)?) => {
        $crate::i18n::tr($key, &[$((stringify!($name), fluent_bundle::FluentValue::from($val))),+])
    };
}

/// Message ids of one `.ftl` source.
#[must_use]
pub fn keys(src: &str) -> std::collections::BTreeSet<String> {
    src.lines()
        .filter(|l| l.chars().next().is_some_and(|c| c.is_ascii_alphabetic()))
        .filter_map(|l| l.split_once('=').map(|(k, _)| k.trim().to_owned()))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_key_in_every_locale() {
        let en = keys(LOCALES[0].1);
        assert!(en.len() > 50);
        for (code, src) in &LOCALES[1..] {
            let other = keys(src);
            let missing: Vec<_> = en.difference(&other).collect();
            let extra: Vec<_> = other.difference(&en).collect();
            assert!(missing.is_empty() && extra.is_empty(), "{code}: missing {missing:?}, extra {extra:?}");
        }
    }

    #[test]
    fn ftl_parses_cleanly() {
        for (code, src) in LOCALES {
            assert!(FluentResource::try_new(src.to_owned()).is_ok(), "{code}.ftl has syntax errors");
        }
    }

    #[test]
    fn every_used_key_exists() {
        let en = keys(LOCALES[0].1);
        let root = concat!(env!("CARGO_MANIFEST_DIR"), "/src");
        let mut stack = vec![std::path::PathBuf::from(root)];
        let mut missing = vec![];
        while let Some(p) = stack.pop() {
            if p.is_dir() {
                stack.extend(std::fs::read_dir(&p).into_iter().flatten().flatten().map(|e| e.path()));
            } else if p.extension().is_some_and(|e| e == "rs") && !p.ends_with("i18n.rs") {
                let src = std::fs::read_to_string(&p).unwrap_or_default();
                let parts: Vec<&str> = src.split("t!(\"").collect();
                for (prev, part) in parts.iter().zip(parts.iter().skip(1)) {
                    if prev.chars().last().is_some_and(|c| c.is_alphanumeric() || c == '_') {
                        continue; // format!(", print!(", ...
                    }
                    let key = part.split('"').next().unwrap_or_default();
                    if !en.contains(key) {
                        missing.push(format!("{}: {key}", p.display()));
                    }
                }
            }
        }
        assert!(missing.is_empty(), "keys missing from en.ftl: {missing:?}");
    }

    #[test]
    fn builtin_protocols_translated() {
        for p in nf_core::nf_feedback::builtin() {
            for f in ["title", "summary"] {
                let k = protocol_key(&p.id, f);
                for (code, src) in &LOCALES {
                    assert!(keys(src).contains(&k), "{code}.ftl misses {k}");
                }
            }
        }
    }

    #[test]
    fn variables_and_plurals() {
        set(Language::De);
        assert_eq!(tr("history-n-selected", &[("n", FluentValue::from(3))]), "3 ausgewählt");
        assert_eq!(tr("history-n-notes", &[("n", FluentValue::from(1))]), "1 Notiz");
        set(Language::En);
        assert_eq!(tr("history-n-notes", &[("n", FluentValue::from(2))]), "2 notes");
        assert_eq!(
            tr("sound-band-guard-warns", &[("mute", FluentValue::from("yes"))]).split(" when").next(),
            Some("Warns and mutes the reward")
        );
    }

    #[test]
    fn lookup_and_fallback() {
        assert_eq!(from_locale("de-AT"), "de");
        assert_eq!(from_locale("fr_FR"), "en");
        set(Language::De);
        assert_eq!(active(), "de");
        assert_eq!(tr("no-such-key", &[]), "no-such-key");
        set(Language::En);
    }
}
