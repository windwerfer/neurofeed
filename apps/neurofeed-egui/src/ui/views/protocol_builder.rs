//! Protocol Builder: make or edit a custom protocol. Left: the form in four
//! sections (identity, training, reward ceilings, guard). Right: the card as
//! it will appear in the picker, plus the core's validation problems. Saving
//! goes through `protocol.save`; checks come from `nf_core::protocols`.

use egui::{Color32, RichText};
use nf_core::protocols::{self, CeilingBand, EyesArg, FeatureArg, InhibitDraft, Problem, ProtocolDraft};
use nf_core::{Command, Session};

const BAD: Color32 = Color32::from_rgb(0xE5, 0x73, 0x73);
const NOTE: Color32 = Color32::from_rgb(0xFF, 0xB7, 0x4D);
const FEATURES: [(FeatureArg, &str); 6] = [
    (FeatureArg::Atr, "Alpha / theta (ATR)"),
    (FeatureArg::Tar, "Theta / alpha (TAR)"),
    (FeatureArg::Btr, "Beta / theta (BTR)"),
    (FeatureArg::Alpha, "Relative alpha"),
    (FeatureArg::Theta, "Relative theta"),
    (FeatureArg::Beta, "Relative beta"),
];

#[derive(Clone)]
struct Edit {
    draft: ProtocolDraft,
    /// Editing an existing custom protocol (id locked, save replaces).
    replace: bool,
    notes: Vec<&'static str>,
    confirm_delete: bool,
}

fn state_id() -> egui::Id {
    egui::Id::unique("protocol_builder")
}

/// Open the builder on a draft of protocol `id` (custom: edit; built-in: copy).
fn open(ctx: &egui::Context, session: &Session, id: &str, as_copy: bool) {
    let custom = &session.state().custom_protocols;
    let Some(p) = protocols::find(custom, id) else { return };
    let (mut draft, notes) = protocols::to_draft(&p);
    let replace = p.custom && !as_copy;
    if p.custom && as_copy {
        draft.id = free_id(custom, &format!("{}-2", p.id));
        draft.title = format!("{} (copy)", p.title).chars().take(protocols::TITLE_MAX).collect();
    }
    ctx.data_mut(|d| d.insert_temp(state_id(), Some(Edit { draft, replace, notes, confirm_delete: false })));
}

fn free_id(custom: &[nf_core::nf_feedback::Protocol], base: &str) -> String {
    let mut id = base.to_owned();
    let mut n = 2;
    while custom.iter().any(|p| p.id == id) {
        n += 1;
        id = format!("{}-{n}", base.trim_end_matches(char::is_numeric).trim_end_matches('-'));
    }
    id
}

/// "New protocol…" / "Edit …" row under the protocol cards.
pub fn launcher(ui: &mut egui::Ui, session: &Session) {
    let t = session.trainer();
    let en = session.enabled("protocol.save");
    ui.horizontal(|ui| {
        let r = ui.add_enabled(en.is_ok(), egui::Button::new(t!("protocol-builder-new-protocol")));
        let r = r.on_hover_text(format!("Start from {} in the Protocol Builder", t.protocol.title));
        if r.clicked() {
            open(ui.ctx(), session, &t.protocol.id, true);
        }
        if t.protocol.custom {
            let r = ui.add_enabled(en.is_ok(), egui::Button::new(format!("Edit {}…", t.protocol.title)));
            if r.clicked() {
                open(ui.ctx(), session, &t.protocol.id, false);
            }
        }
        if let Err(why) = en {
            ui.weak(why);
        }
    });
}

/// The builder window (call every frame from the feedback view).
pub fn window(ctx: &egui::Context, session: &Session, out: &mut Vec<Command>) {
    let Some(mut e) = ctx.data(|d| d.get_temp::<Option<Edit>>(state_id())).flatten() else { return };
    let mut open = true;
    let mut close = false;
    let title = if e.replace { t!("protocol-builder-protocol-builder-edit") } else { t!("protocol-builder-protocol-builder-new") };
    egui::Window::new(title).open(&mut open).collapsible(false).default_width(760.0).resizable(true).show(ctx, |ui| {
        let problems = protocols::validate(&e.draft, &session.state().custom_protocols, e.replace);
        if crate::ui::layout::current(ui.ctx()).is_compact() {
            form(ui, &mut e, &problems);
            ui.separator();
            preview(ui, &e, &problems);
        } else {
            ui.columns(2, |c| {
                form(&mut c[0], &mut e, &problems);
                preview(&mut c[1], &e, &problems);
            });
        }
        ui.separator();
        close = footer(ui, session, &mut e, &problems, out);
    });
    let next = (open && !close).then_some(e);
    ctx.data_mut(|d| d.insert_temp(state_id(), next));
}

fn field_problems(ui: &mut egui::Ui, problems: &[Problem], field: &str) {
    for p in problems.iter().filter(|p| p.field == field) {
        ui.label(RichText::new(&p.message).small().color(BAD));
    }
}

fn section(ui: &mut egui::Ui, title: &str) {
    ui.add_space(8.0);
    ui.label(RichText::new(title).strong());
}

fn form(ui: &mut egui::Ui, e: &mut Edit, problems: &[Problem]) {
    let d = &mut e.draft;
    section(ui, &t!("protocol-builder-identity"));
    egui::Grid::new("pb_identity").num_columns(2).spacing([8.0, 4.0]).show(ui, |ui| {
        ui.label(t!("protocol-builder-title"));
        ui.add(egui::TextEdit::singleline(&mut d.title).char_limit(protocols::TITLE_MAX + 10).desired_width(260.0));
        ui.end_row();
        ui.label(t!("protocol-builder-id"));
        ui.add_enabled(!e.replace, egui::TextEdit::singleline(&mut d.id).desired_width(260.0))
            .on_hover_text(t!("protocol-builder-lowercase-letters-digits-and-dashes"));
        ui.end_row();
        ui.label(t!("protocol-builder-summary"));
        ui.add(egui::TextEdit::multiline(&mut d.summary).desired_rows(2).desired_width(260.0));
        ui.end_row();
    });
    for f in ["title", "id", "summary"] {
        field_problems(ui, problems, f);
    }
    training(ui, d, problems);
    ceilings(ui, d, problems);
    section(ui, &t!("protocol-builder-drowsiness-guard"));
    ui.checkbox(&mut d.guard, t!("protocol-builder-offer-the-band-math-guard"))
        .on_hover_text(t!("protocol-builder-only-offers-it-the-guard"));
    ui.add_enabled(d.guard, egui::Checkbox::new(&mut d.muffle_reward, t!("protocol-builder-mute-reward-while-the-guard")));
    field_problems(ui, problems, "muffle_reward");
}

fn training(ui: &mut egui::Ui, d: &mut ProtocolDraft, problems: &[Problem]) {
    section(ui, &t!("protocol-builder-training"));
    egui::Grid::new("pb_training").num_columns(2).spacing([8.0, 4.0]).show(ui, |ui| {
        ui.label(t!("protocol-builder-reward"));
        let current = FEATURES.iter().find(|(f, _)| *f == d.feature).map_or("", |(_, l)| l);
        egui::ComboBox::from_id_salt("pb_feature").selected_text(current).width(220.0).show_ui(ui, |ui| {
            for (f, l) in FEATURES {
                ui.selectable_value(&mut d.feature, f, l);
            }
        });
        ui.end_row();
        ui.label(t!("protocol-builder-eyes"));
        ui.horizontal(|ui| {
            ui.radio_value(&mut d.eyes, EyesArg::Closed, "closed");
            ui.radio_value(&mut d.eyes, EyesArg::Open, "open");
        });
        ui.end_row();
        ui.label(t!("protocol-builder-length"));
        let (lo, hi) = nf_core::feedback::MINUTES;
        ui.add(egui::DragValue::new(&mut d.minutes).range(lo..=hi).suffix(" min"));
        ui.end_row();
    });
    field_problems(ui, problems, "minutes");
}

fn ceilings(ui: &mut egui::Ui, d: &mut ProtocolDraft, problems: &[Problem]) {
    section(ui, &t!("protocol-builder-reward-ceilings"));
    ui.weak(t!("protocol-builder-no-reward-while-a-band"));
    let mut remove = None;
    for (i, x) in d.inhibit.iter_mut().enumerate() {
        ui.horizontal(|ui| {
            egui::ComboBox::from_id_salt(("pb_band", i)).selected_text(band_name(x.band)).width(90.0).show_ui(ui, |ui| {
                ui.selectable_value(&mut x.band, CeilingBand::Beta, t!("protocol-builder-beta"));
                ui.selectable_value(&mut x.band, CeilingBand::Delta, t!("protocol-builder-delta"));
            });
            ui.label("above");
            ui.add(egui::Slider::new(&mut x.max, 0.05..=0.95).fixed_decimals(2));
            if ui.small_button(t!("protocol-builder-remove")).clicked() {
                remove = Some(i);
            }
        });
    }
    if let Some(i) = remove {
        d.inhibit.remove(i);
    }
    let free = [CeilingBand::Beta, CeilingBand::Delta].into_iter().find(|b| !d.inhibit.iter().any(|x| x.band == *b));
    if let Some(band) = free {
        if ui.horizontal(|ui| ui.small_button(t!("protocol-builder-add-ceiling")).clicked()).inner {
            d.inhibit.push(InhibitDraft { band, max: if band == CeilingBand::Delta { 0.4 } else { 0.3 } });
        }
    }
    field_problems(ui, problems, "inhibit");
}

fn band_name(b: CeilingBand) -> &'static str {
    match b {
        CeilingBand::Beta => "Beta",
        CeilingBand::Delta => "Delta",
    }
}

fn preview(ui: &mut egui::Ui, e: &Edit, problems: &[Problem]) {
    ui.label(RichText::new(t!("protocol-builder-card-preview")).strong());
    let p = protocols::to_protocol(&e.draft);
    super::feedback::card(ui, &p, true, ui.available_width().min(320.0));
    ui.add_space(8.0);
    let rows = [
        (t!("protocol-builder-reward"), FEATURES.iter().find(|(f, _)| *f == e.draft.feature).map_or("", |(_, l)| l).to_owned()),
        (t!("protocol-builder-threshold"), "percentile of your calibration, adapted while you train".to_owned()),
        (
            t!("protocol-builder-ceilings"),
            if e.draft.inhibit.is_empty() {
                "none".to_owned()
            } else {
                e.draft.inhibit.iter().map(|x| format!("{} ≤ {:.2}", band_name(x.band), x.max)).collect::<Vec<_>>().join(", ")
            },
        ),
        (
            t!("protocol-builder-guard"),
            match (e.draft.guard, e.draft.muffle_reward) {
                (false, _) => "none".to_owned(),
                (true, false) => "offered (warns only)".to_owned(),
                (true, true) => "offered (warns and mutes reward)".to_owned(),
            },
        ),
    ];
    egui::Grid::new("pb_summary").num_columns(2).spacing([8.0, 2.0]).show(ui, |ui| {
        for (k, v) in rows {
            ui.weak(k);
            ui.label(v);
            ui.end_row();
        }
    });
    for n in &e.notes {
        ui.label(RichText::new(*n).small().color(NOTE));
    }
    if !problems.is_empty() {
        ui.add_space(6.0);
        ui.label(RichText::new(format!("{} to fix before saving", problems.len())).color(BAD));
    }
}

/// Save / delete / cancel. Returns true when the window should close.
fn footer(ui: &mut egui::Ui, session: &Session, e: &mut Edit, problems: &[Problem], out: &mut Vec<Command>) -> bool {
    let mut close = false;
    ui.horizontal(|ui| {
        let en = session.enabled("protocol.save");
        let ok = en.is_ok() && problems.is_empty();
        let label = if e.replace { t!("protocol-builder-save-changes") } else { t!("protocol-builder-save-protocol") };
        let r = ui.add_enabled(ok, egui::Button::new(RichText::new(label).strong()));
        let r = match (&en, problems.first()) {
            (Err(why), _) => r.on_disabled_hover_text(why),
            (_, Some(p)) => r.on_disabled_hover_text(format!("{}: {}", p.field, p.message)),
            _ => r,
        };
        if r.clicked() {
            let id = e.draft.id.clone();
            out.push(Command::ProtocolSave { draft: e.draft.clone(), replace: e.replace });
            out.push(Command::ProtocolSet { id, minutes: None });
            close = true;
        }
        if ui.button(t!("protocol-builder-cancel")).clicked() {
            close = true;
        }
        if e.replace {
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| close |= delete(ui, session, e, out));
        }
    });
    close
}

fn delete(ui: &mut egui::Ui, session: &Session, e: &mut Edit, out: &mut Vec<Command>) -> bool {
    let en = session.enabled("protocol.delete");
    if e.confirm_delete {
        if ui.button(RichText::new(t!("protocol-builder-delete-for-good")).color(BAD)).clicked() {
            out.push(Command::ProtocolDelete { id: e.draft.id.clone(), confirm: true });
            return true;
        }
        if ui.button(t!("protocol-builder-keep")).clicked() {
            e.confirm_delete = false;
        }
        ui.weak(t!("protocol-builder-saved-sessions-keep-their-protocol"));
    } else {
        let r = ui.add_enabled(en.is_ok(), egui::Button::new(t!("protocol-builder-delete")));
        if let Err(why) = &en {
            r.on_disabled_hover_text(why);
        } else if r.clicked() {
            e.confirm_delete = true;
        }
    }
    false
}
