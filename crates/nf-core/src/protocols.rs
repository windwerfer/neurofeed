//! Protocol catalog: the built-ins plus custom protocols made in the Protocol
//! Builder. Custom protocols are stored as [`ProtocolDraft`]s (a stable,
//! schema-checked shape) in the store document [`DOC_KEY`].

use nf_feedback::{Eyes, Feature, GuardSpec, Inhibit, Protocol};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Store document holding the custom protocols (JSON array of drafts).
pub const DOC_KEY: &str = "custom_protocols";
/// Longest title / summary the cards can show.
pub const TITLE_MAX: usize = 40;
pub const SUMMARY_MAX: usize = 120;
/// Most band ceilings per protocol (one per band).
pub const INHIBIT_MAX: usize = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum EyesArg {
    Open,
    Closed,
}

/// Reward feature (relative band power of the good pads).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum FeatureArg {
    /// Alpha / theta.
    Atr,
    /// Theta / alpha.
    Tar,
    /// Beta / theta.
    Btr,
    Alpha,
    Theta,
    Beta,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum CeilingBand {
    Beta,
    Delta,
}

/// No reward while the band's relative power is above `max`.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct InhibitDraft {
    pub band: CeilingBand,
    /// Relative power, 0 < max < 1.
    pub max: f64,
}

/// What the Protocol Builder edits.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ProtocolDraft {
    /// Slug: 3..=32 of a-z, 0-9, '-'; not a built-in id.
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub summary: String,
    pub eyes: EyesArg,
    pub feature: FeatureArg,
    /// Default session length, 1..=120 min.
    pub minutes: u32,
    #[serde(default)]
    pub inhibit: Vec<InhibitDraft>,
    /// Offer the band-math drowsiness guard (still off until the user turns it on).
    #[serde(default)]
    pub guard: bool,
    /// While the guard warns, mute and withhold reward.
    #[serde(default)]
    pub muffle_reward: bool,
}

/// One validation problem, keyed by draft field.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Problem {
    pub field: &'static str,
    pub message: String,
}

fn problem(field: &'static str, message: impl Into<String>) -> Problem {
    Problem { field, message: message.into() }
}

fn feature(f: FeatureArg) -> Feature {
    match f {
        FeatureArg::Atr => Feature::Atr,
        FeatureArg::Tar => Feature::Tar,
        FeatureArg::Btr => Feature::Btr,
        FeatureArg::Alpha => Feature::Alpha,
        FeatureArg::Theta => Feature::Theta,
        FeatureArg::Beta => Feature::Beta,
    }
}

fn feature_arg(f: Feature) -> FeatureArg {
    match f {
        Feature::Atr => FeatureArg::Atr,
        Feature::Tar => FeatureArg::Tar,
        Feature::Btr => FeatureArg::Btr,
        Feature::Alpha => FeatureArg::Alpha,
        Feature::Theta => FeatureArg::Theta,
        Feature::Beta => FeatureArg::Beta,
    }
}

fn id_problem(id: &str) -> Option<String> {
    let ok_chars = id.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-');
    if !(3..=32).contains(&id.len()) {
        Some("3 to 32 characters".into())
    } else if !ok_chars || id.starts_with('-') || id.ends_with('-') {
        Some("lowercase letters, digits and inner dashes only".into())
    } else if nf_feedback::protocol(id).is_some() || nf_feedback::builtin().iter().any(|p| p.id.eq_ignore_ascii_case(id)) {
        Some("taken by a built-in protocol".into())
    } else {
        None
    }
}

fn text_problems(d: &ProtocolDraft, out: &mut Vec<Problem>) {
    let title = d.title.trim();
    if title.is_empty() {
        out.push(problem("title", "required"));
    } else if title.chars().count() > TITLE_MAX {
        out.push(problem("title", format!("at most {TITLE_MAX} characters")));
    }
    if d.summary.trim().chars().count() > SUMMARY_MAX {
        out.push(problem("summary", format!("at most {SUMMARY_MAX} characters")));
    }
}

fn inhibit_problems(d: &ProtocolDraft, out: &mut Vec<Problem>) {
    if d.inhibit.len() > INHIBIT_MAX {
        out.push(problem("inhibit", format!("at most {INHIBIT_MAX} ceilings")));
    }
    for (i, x) in d.inhibit.iter().enumerate() {
        if !(x.max > 0.0 && x.max < 1.0) {
            out.push(problem("inhibit", format!("ceiling {}: max must be between 0 and 1 (relative power)", i + 1)));
        }
        if d.inhibit[..i].iter().any(|y| y.band == x.band) {
            out.push(problem("inhibit", format!("ceiling {}: {:?} ceiling given twice", i + 1, x.band).to_lowercase()));
        }
    }
}

/// Problems with `d`; empty = can be saved. `existing` are the custom
/// protocols; an existing id needs `replace`.
pub fn validate(d: &ProtocolDraft, existing: &[Protocol], replace: bool) -> Vec<Problem> {
    let mut out = Vec::new();
    if let Some(m) = id_problem(&d.id) {
        out.push(problem("id", m));
    } else if !replace && existing.iter().any(|p| p.id == d.id) {
        out.push(problem("id", "a custom protocol with this id exists; save with replace"));
    } else if replace && !existing.iter().any(|p| p.id == d.id) {
        out.push(problem("id", "no custom protocol with this id to replace"));
    }
    text_problems(d, &mut out);
    let (lo, hi) = crate::feedback::MINUTES;
    if !(lo..=hi).contains(&d.minutes) {
        out.push(problem("minutes", format!("{lo} to {hi} minutes")));
    }
    inhibit_problems(d, &mut out);
    if d.muffle_reward && !d.guard {
        out.push(problem("muffle_reward", "needs the guard lane"));
    }
    out
}

/// The engine protocol for a (valid) draft.
pub fn to_protocol(d: &ProtocolDraft) -> Protocol {
    let mut p = nf_feedback::builtin().swap_remove(0);
    p.id = d.id.clone();
    p.title = d.title.trim().to_owned();
    p.summary = d.summary.trim().to_owned();
    p.eyes = if d.eyes == EyesArg::Open { Eyes::Open } else { Eyes::Closed };
    p.feature = feature(d.feature);
    p.stability = None;
    p.default_minutes = d.minutes;
    p.experimental = false;
    p.unavailable = None;
    p.guard = d.guard.then_some(GuardSpec { muffle_reward: d.muffle_reward });
    p.inhibit = d
        .inhibit
        .iter()
        .map(|x| match x.band {
            CeilingBand::Beta => Inhibit::BetaCeiling(x.max),
            CeilingBand::Delta => Inhibit::DeltaCeiling(x.max),
        })
        .collect();
    p.custom = true;
    p
}

/// A draft from any protocol (edit a custom one, or start from a built-in).
/// `notes` lists what the builder cannot keep.
pub fn to_draft(p: &Protocol) -> (ProtocolDraft, Vec<&'static str>) {
    let mut notes = Vec::new();
    if p.stability.is_some() {
        notes.push("steadiness reward is not editable; this draft rewards the feature above a percentile");
    }
    if p.unavailable.is_some() {
        notes.push("the original needs the sleep model; this draft uses band math only");
    }
    let inhibit = p
        .inhibit
        .iter()
        .map(|i| match *i {
            Inhibit::BetaCeiling(max) => InhibitDraft { band: CeilingBand::Beta, max },
            Inhibit::DeltaCeiling(max) => InhibitDraft { band: CeilingBand::Delta, max },
        })
        .collect();
    let draft = ProtocolDraft {
        id: if p.custom { p.id.clone() } else { copy_id(&p.id) },
        title: if p.custom { p.title.clone() } else { format!("{} (copy)", p.title).chars().take(TITLE_MAX).collect() },
        summary: p.summary.clone(),
        eyes: if p.eyes == Eyes::Open { EyesArg::Open } else { EyesArg::Closed },
        feature: feature_arg(p.feature),
        minutes: p.default_minutes,
        inhibit,
        guard: p.guard.is_some(),
        muffle_reward: p.guard.is_some_and(|g| g.muffle_reward),
    };
    (draft, notes)
}

/// `restAwake` → `rest-awake-copy`.
fn copy_id(id: &str) -> String {
    let mut s = String::new();
    for c in id.chars() {
        if c.is_ascii_uppercase() {
            s.push('-');
        }
        s.push(c.to_ascii_lowercase());
    }
    s.push_str("-copy");
    s
}

/// Built-ins first, then custom protocols.
pub fn all(custom: &[Protocol]) -> Vec<Protocol> {
    let mut v = nf_feedback::builtin();
    v.extend(custom.iter().cloned());
    v
}

pub fn find(custom: &[Protocol], id: &str) -> Option<Protocol> {
    nf_feedback::protocol(id).or_else(|| custom.iter().find(|p| p.id == id).cloned())
}

/// Read the custom protocols; drafts that no longer validate are skipped
/// and reported.
pub fn load(store: &dyn nf_store::Store) -> (Vec<Protocol>, Vec<String>) {
    let raw = match store.get_doc(DOC_KEY) {
        Ok(Some(raw)) => raw,
        Ok(None) => return (Vec::new(), Vec::new()),
        Err(e) => return (Vec::new(), vec![format!("custom protocols: {e}")]),
    };
    let drafts: Vec<ProtocolDraft> = match serde_json::from_str(&raw) {
        Ok(d) => d,
        Err(e) => return (Vec::new(), vec![format!("custom protocols unreadable: {e}")]),
    };
    let (mut ok, mut bad) = (Vec::new(), Vec::new());
    for d in drafts {
        let problems = validate(&d, &ok, false);
        if problems.is_empty() {
            ok.push(to_protocol(&d));
        } else {
            bad.push(format!("custom protocol `{}` skipped: {}", d.id, problems[0].message));
        }
    }
    (ok, bad)
}

/// Write the custom protocols.
pub fn save(store: &mut dyn nf_store::Store, custom: &[Protocol]) -> Result<(), String> {
    let drafts: Vec<ProtocolDraft> = custom.iter().map(|p| to_draft(p).0).collect();
    let json = serde_json::to_string(&drafts).map_err(|e| e.to_string())?;
    store.put_doc(DOC_KEY, if custom.is_empty() { None } else { Some(&json) }).map_err(|e| e.to_string())
}

/// A valid draft (catalog examples, tests).
pub fn example_draft() -> ProtocolDraft {
    ProtocolDraft {
        id: "calm-focus".into(),
        title: "Calm focus".into(),
        summary: String::new(),
        eyes: EyesArg::Open,
        feature: FeatureArg::Btr,
        minutes: 15,
        inhibit: vec![InhibitDraft { band: CeilingBand::Delta, max: 0.4 }],
        guard: true,
        muffle_reward: false,
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    fn draft() -> ProtocolDraft {
        example_draft()
    }

    #[test]
    fn valid_draft_round_trips_through_protocol() {
        let d = draft();
        assert!(validate(&d, &[], false).is_empty());
        let p = to_protocol(&d);
        assert_eq!(
            (p.custom, p.inhibit.clone(), p.guard),
            (true, vec![Inhibit::DeltaCeiling(0.4)], Some(GuardSpec { muffle_reward: false }))
        );
        assert_eq!(to_draft(&p).0, d);
        assert_eq!(p.config(60).inhibit, vec![Inhibit::DeltaCeiling(0.4)]);
    }

    #[test]
    fn problems_name_their_field() {
        let mut d = draft();
        d.id = "restawake".into();
        d.title = " ".into();
        d.minutes = 0;
        d.inhibit.push(InhibitDraft { band: CeilingBand::Delta, max: 1.5 });
        d.guard = false;
        d.muffle_reward = true;
        let fields: Vec<&str> = validate(&d, &[], false).iter().map(|p| p.field).collect();
        assert_eq!(fields, ["id", "title", "minutes", "inhibit", "inhibit", "muffle_reward"]);
    }

    #[test]
    fn existing_id_needs_replace() {
        let p = to_protocol(&draft());
        assert_eq!(validate(&draft(), std::slice::from_ref(&p), false)[0].field, "id");
        assert!(validate(&draft(), &[p], true).is_empty());
        assert_eq!(validate(&draft(), &[], true)[0].field, "id");
    }

    #[test]
    fn builtin_copies_get_a_free_slug() {
        let (d, notes) = to_draft(&nf_feedback::protocol("bandStability").unwrap());
        assert_eq!((d.id.as_str(), notes.len()), ("band-stability-copy", 1));
        assert!(validate(&d, &[], false).is_empty());
    }

    #[test]
    fn store_round_trip_skips_invalid() {
        let mut s = nf_store::MemoryStore::default();
        save(&mut s, &[to_protocol(&draft())]).unwrap();
        assert_eq!(load(&s).0, vec![to_protocol(&draft())]);
        let mut bad = draft();
        bad.minutes = 999;
        nf_store::Store::put_doc(&mut s, DOC_KEY, Some(&serde_json::to_string(&[draft(), bad]).unwrap())).unwrap();
        let (ok, errs) = load(&s);
        assert_eq!((ok.len(), errs.len()), (1, 1));
    }
}
