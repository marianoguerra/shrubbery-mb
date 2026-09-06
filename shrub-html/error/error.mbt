///|
/// Diagnostics for the bridge.
///
/// The same arrangement as `@html.error`, `@css.error` and `lib/error`: one
/// function reaches `error-report`, and everything else names a problem without
/// linking a renderer.
///
/// Spans come from `@basic.Span`, the shrubbery side's position type, because
/// what a bridge diagnostic points at is a place in a shrubbery file. The
/// conversion to `@report.Span` reads `.idx`, which is already a UTF-16 code
/// unit offset, so this is a change of representation and not of unit.

///|
pub(all) struct Diagnostic {
  kind : @kind.ErrorKind
  span : @basic.Span
  severity : @report.Severity
  related : Array[(@basic.Span, String)]
}

///|
pub fn Diagnostic::new(
  kind : @kind.ErrorKind,
  span : @basic.Span,
  severity? : @report.Severity = Error,
  related? : Array[(@basic.Span, String)] = [],
) -> Diagnostic {
  { kind, span, severity, related, }
}

///|
/// A diagnostic whose severity follows from its kind.
pub fn Diagnostic::of_kind(
  kind : @kind.ErrorKind,
  span : @basic.Span,
) -> Diagnostic {
  let severity : @report.Severity = if kind.is_warning() {
    Warning
  } else {
    Error
  }
  { kind, span, severity, related: [], }
}

///|
pub fn Diagnostic::is_error(self : Diagnostic) -> Bool {
  match self.severity {
    Error => true
    _ => false
  }
}

///|
/// A Shrubbery HTML source was rejected.
pub(all) suberror ShrubHtmlError {
  ShrubHtmlError(Diagnostic)
}

///|
pub fn[T] Diagnostic::raise_(self : Diagnostic) -> T raise ShrubHtmlError {
  raise ShrubHtmlError(self)
}

///|
pub fn ShrubHtmlError::diagnostic(self : ShrubHtmlError) -> Diagnostic {
  let ShrubHtmlError(d) = self
  d
}

///|
/// Turn a diagnostic into a renderable report.
///
/// **This is the only function in the module that mentions `error-report`.**
pub fn Diagnostic::to_report(
  self : Diagnostic,
  source : @report.SourceId,
) -> @report.Report {
  let r = @report.Report::new(self.severity, self.explain())
    .with_code(self.kind.code())
    .with_label(
      @report.Label::primary(source, span_of(self.span), message?=self.point()),
    )
  for rel in self.related {
    let (span, note) = rel
    let _ = r.with_label(
      @report.Label::secondary(source, span_of(span), message=note),
    )
  }
  match self.help() {
    Some(h) => r.with_help(h)
    None => r
  }
}

///|
fn span_of(s : @basic.Span) -> @report.Span {
  @report.Span::of_range(s.start.idx, s.end.idx)
}

///|
fn Diagnostic::explain(self : Diagnostic) -> String {
  match self.kind {
    SigilTag(t) => "`" + t + "` is HTML's spelling, not this syntax's"
    ReservedCall(n) => "`" + n + "()` is taken by this syntax"
    BareTermInBlock(t) =>
      "`" + t + "` is a bare word, with no call and no block"
    AttrNotDeclaration => "this is not an attribute"
    BadAttrValue => "an attribute's value has to be a literal or a name"
    ChildrenOnVoid(t) => "`" + t + "` cannot have children"
    BadEscapeCall(n) => "`" + n + "` was given arguments of the wrong shape"
    BlockOnNonElement => "only an element can have a block"
    AltsUnsupported => "`|` has no meaning in Shrubbery HTML"
    BracesUnsupported => "`{ }` has no meaning in Shrubbery HTML"
    TrailingRunAfterBlock =>
      "everything after the `:` on this line went inside the block"
    NameNotSpellable(n) => "`" + n + "` has no bare spelling"
    Unsupported(what) => what + " has no meaning in Shrubbery HTML"
  }
}

///|
fn Diagnostic::point(self : Diagnostic) -> String? {
  match self.kind {
    TrailingRunAfterBlock => Some("this became a child, not a sibling")
    ReservedCall(_) => Some("read as this syntax's own construct")
    BareTermInBlock(_) => Some("nothing here says what it is")
    _ => None
  }
}

///|
/// The rule, in one sentence, and where possible the exact thing to type.
///
/// This is the part that teaches, and for a syntax nobody has seen before it is
/// most of the value of the diagnostic. So it names the replacement rather than
/// describing it.
fn Diagnostic::help(self : Diagnostic) -> String? {
  match self.kind {
    SigilTag(t) => Some(sigil_help(t))
    ReservedCall(n) =>
      Some("for the element of that name write `element(\"" + n + "\")`")
    BareTermInBlock(t) =>
      Some("an element is a call: write `" + t + "()`, or quote it for text")
    AttrNotDeclaration =>
      Some("an attribute is `name: \"value\"`, or a bare name for a flag")
    BadAttrValue =>
      Some("write a string: `class: \"card\"`; a bare name means the same text")
    TrailingRunAfterBlock =>
      Some(
        "a block runs to the end of its line, so an element with children has to come last",
      )
    NameNotSpellable(n) => Some("write it literally: `element(\"" + n + "\")`")
    AltsUnsupported =>
      Some("nothing in markup branches this way; `|` is reserved")
    BracesUnsupported => Some("a block is opened with `:` and indentation")
    ChildrenOnVoid(t) => Some("`" + t + "` closes itself; write `" + t + "()`")
    _ => None
  }
}

///|
fn sigil_help(t : String) -> String {
  match t {
    "<" => "an element is a call: write `div():` for `<div>`"
    "</" => "an element's children are its block; there is no end tag to write"
    "&" => "write the character itself, inside the string"
    _ => "write the thing's name instead of a symbol for it"
  }
}
