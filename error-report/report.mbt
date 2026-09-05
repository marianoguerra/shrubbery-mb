///|
/// How serious a report is.
///
/// `Advice` is miette's third level: a suggestion that is neither wrong nor
/// suspicious, which a formatter or a linter wants and a compiler mostly does
/// not. Keeping it here rather than making consumers extend the enum is what
/// stops every consumer inventing a fourth name for the same thing.
pub(all) enum Severity {
  Error
  Warning
  Advice
} derive(Eq, Compare, Hash, Debug, ToJson)

///|
/// The lowercase name used in rendered output and in JSON.
pub fn Severity::name(self : Severity) -> String {
  match self {
    Error => "error"
    Warning => "warning"
    Advice => "advice"
  }
}

///|
/// Whether a label points at the thing that is wrong, or at context.
///
/// codespan-reporting's distinction, and worth keeping: a report with three
/// labels is unreadable unless the reader can tell which one is the defect and
/// which two are "declared here" and "first used here".
pub(all) enum LabelStyle {
  Primary
  Secondary
} derive(Eq, Debug, ToJson)

///|
/// A span of source with an optional note attached.
pub(all) struct Label {
  source : SourceId
  span : Span
  style : LabelStyle
  /// `None` underlines the span without writing anything beside it, which is
  /// what you want when the message above already says everything.
  message : String?
  /// Tie-break for two labels that would occupy the same underline row: the
  /// larger wins the row nearer the source line. Defaults to 0.
  priority : Int
} derive(Eq, Debug)

///|
pub fn Label::primary(
  source : SourceId,
  span : Span,
  message? : String,
) -> Label {
  { source, span, style: Primary, message, priority: 0, }
}

///|
pub fn Label::secondary(
  source : SourceId,
  span : Span,
  message? : String,
) -> Label {
  { source, span, style: Secondary, message, priority: 0, }
}

///|
pub fn Label::with_priority(self : Label, priority : Int) -> Label {
  { ..self, priority, }
}

///|
/// A machine-applicable repair: replace `span` with `replacement`.
///
/// Separate from `Label` because it is not a thing to point at, it is a thing
/// to do. A consumer that only renders text shows `description`; a consumer
/// wiring up an editor's quick-fix applies the edit and ignores the prose.
/// Conflating the two is what forces the second consumer to parse the first
/// one's output.
pub(all) struct Fix {
  source : SourceId
  span : Span
  replacement : String
  description : String
} derive(Eq, Debug)

///|
/// One diagnostic: what is wrong, where, and what to do about it.
///
/// The fields are the union of what miette, codespan-reporting and ariadne
/// each found necessary, and the split between them is the point of this type:
/// `message` says what is wrong, `labels` say where, `help` says what to do,
/// `notes` say what else to know, and `fixes` say it in a form a machine can
/// apply. A consumer that wants none of the rendering can read all five.
pub(all) struct Report {
  severity : Severity
  /// A stable identifier such as `"lang::wrong_indentation"`. Stable is
  /// the operative word: it is what a user greps for, what a config file
  /// suppresses by, and what a test asserts on -- so it must survive rewording
  /// the message, which is exactly why it is not derived from one.
  code : String?
  message : String
  labels : Array[Label]
  notes : Array[String]
  help : String?
  /// Where to read more. Rendered as a trailing link.
  url : String?
  /// Diagnostics that belong to this one, rendered indented beneath it.
  related : Array[Report]
  fixes : Array[Fix]
}

///|
/// A report with only the required parts. Everything else is added by the
/// `with_*` methods, which is what keeps the common case one line.
pub fn Report::new(severity : Severity, message : String) -> Report {
  {
    severity,
    code: None,
    message,
    labels: [],
    notes: [],
    help: None,
    url: None,
    related: [],
    fixes: [],
  }
}

///|
pub fn Report::error(message : String) -> Report {
  Report::new(Error, message)
}

///|
pub fn Report::warning(message : String) -> Report {
  Report::new(Warning, message)
}

///|
pub fn Report::advice(message : String) -> Report {
  Report::new(Advice, message)
}

///|
pub fn Report::with_code(self : Report, code : String) -> Report {
  { ..self, code: Some(code), }
}

///|
pub fn Report::with_label(self : Report, label : Label) -> Report {
  self.labels.push(label)
  self
}

///|
pub fn Report::with_note(self : Report, note : String) -> Report {
  self.notes.push(note)
  self
}

///|
pub fn Report::with_help(self : Report, help : String) -> Report {
  { ..self, help: Some(help), }
}

///|
pub fn Report::with_url(self : Report, url : String) -> Report {
  { ..self, url: Some(url), }
}

///|
pub fn Report::with_related(self : Report, related : Report) -> Report {
  self.related.push(related)
  self
}

///|
pub fn Report::with_fix(self : Report, fix : Fix) -> Report {
  self.fixes.push(fix)
  self
}

///|
/// The label a renderer should lead with: the first `Primary`, or failing that
/// the first label of any kind.
///
/// "Failing that" rather than "nothing" because a report whose labels are all
/// secondary is a caller mistake that should still render something useful --
/// refusing to show a snippet would punish the reader for the producer's bug.
pub fn Report::anchor(self : Report) -> Label? {
  for label in self.labels {
    if label.style is Primary {
      return Some(label)
    }
  }
  self.labels.get(0)
}
