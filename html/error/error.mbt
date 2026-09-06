///|
/// Diagnostics.
///
/// This package exists to be the *only* one in the module that mentions
/// `error-report`. The kinds themselves live in `html/kind`, which has no
/// dependencies, so the tree can name a problem without linking a renderer;
/// here is where a named problem becomes a renderable report, and there is
/// exactly one function that does it.
///
/// The arrangement is the one `lib/error` and `css/error` already use, and it
/// is what keeps `error-report`'s eventual spin-out a rename rather than an
/// untangling.

///|
/// A problem, with the span it was found at.
pub(all) struct Diagnostic {
  kind : @kind.ErrorKind
  span : @span.Span
  severity : @report.Severity
  /// The second place worth looking: the `<div>` that was never closed, the
  /// first of two attributes with the same name. Most of what makes a
  /// complaint answerable rather than merely true.
  related : Array[(@span.Span, String)]
}

///|
pub fn Diagnostic::new(
  kind : @kind.ErrorKind,
  span : @span.Span,
  severity? : @report.Severity = Error,
  related? : Array[(@span.Span, String)] = [],
) -> Diagnostic {
  { kind, span, severity, related, }
}

///|
/// A diagnostic whose severity follows from its kind.
///
/// More of these are warnings than on the CSS side, and that is the shape of
/// the problem rather than laxity: a stray `</div>` is what a large fraction of
/// the real web looks like, and a library that called it an error would be a
/// library nobody could point at a real page.
pub fn Diagnostic::of_kind(
  kind : @kind.ErrorKind,
  span : @span.Span,
) -> Diagnostic {
  let severity : @report.Severity = if kind.is_warning() {
    Warning
  } else {
    Error
  }
  { kind, span, severity, related: [], }
}

///|
/// A markup source was rejected.
///
/// One error type for the whole module, raised only in strict mode. The
/// tolerant path never raises: it puts a `Bogus` in the tree and a `Diagnostic`
/// in the list, which is what lets a caller parse a real page and still get a
/// document.
pub(all) suberror HtmlError {
  HtmlError(Diagnostic)
}

///|
pub fn[T] Diagnostic::raise_(self : Diagnostic) -> T raise HtmlError {
  raise HtmlError(self)
}

///|
pub fn HtmlError::diagnostic(self : HtmlError) -> Diagnostic {
  let HtmlError(d) = self
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
/// The one place a `@span.Span` becomes an `@report.Span`.
fn span_of(s : @span.Span) -> @report.Span {
  @report.Span::of_range(s.start, s.end)
}

///|
/// The headline: what went wrong, in one sentence, in the reader's terms.
fn Diagnostic::explain(self : Diagnostic) -> String {
  match self.kind {
    EofInTag => "the file ended in the middle of a tag"
    EofInComment => "this comment is never closed"
    EofInRawText(t) => "this `<" + t + ">` is never closed"
    EofInDoctype => "the file ended in the middle of a doctype"
    UnclosedElement(t) => "this `<" + t + ">` is never closed"
    MismatchedEndTag(got, want) =>
      "this closes `" + got + "`, but `" + want + "` is what is open"
    StrayEndTag(t) => "there is no `<" + t + ">` for this to close"
    EndTagForVoid(t) => "`<" + t + ">` cannot have an end tag"
    ChildrenOnVoid(t) => "`<" + t + ">` cannot have children"
    NonVoidSelfClosing(t) => "the `/` in `<" + t + "/>` does nothing"
    DuplicateAttribute(n) => "`" + n + "` is given twice on this tag"
    UnexpectedSolidusInTag => "this `/` is not the `/` of `/>`"
    MissingTagName => "this tag has no name"
    InvalidFirstCharacterOfTagName => "a tag name has to start with a letter"
    UnexpectedEqualsSignBeforeAttributeName =>
      "this `=` comes before any attribute name"
    UnexpectedCharacterInUnquotedAttributeValue =>
      "an unquoted attribute value may not contain this character"
    AbruptClosingOfEmptyComment => "this comment closes before it opens"
    NestedComment => "a comment may not contain `<!--`"
    IncorrectlyClosedComment => "a comment ends with `-->`, not `--!>`"
    BogusComment => "this is not a tag, and is read as a comment"
    CdataInHtmlContent =>
      "`<![CDATA[` means something only inside `<svg>` or `<math>`"
    DoctypeNotFirst => "a doctype belongs at the very start of the document"
    MalformedDoctype => "this doctype could not be read"
    UnknownNamedCharacterReference(n) =>
      "`&" + n + ";` is not a character reference"
    MissingSemicolonAfterCharacterReference =>
      "this character reference has no `;`"
    AbsenceOfDigitsInNumericCharacterReference =>
      "a numeric character reference needs digits"
    CharacterReferenceOutsideUnicodeRange =>
      "this character reference is not a character"
    UnexpectedNullCharacter => "there is a NUL byte in the source"
    UnprintableRawText(t) =>
      "the body of this `<" + t + ">` contains its own end tag"
    Unexpected(what) => "expected " + what
  }
}

///|
/// The caret label. `None` when the headline has already said it, so that a
/// rendered report does not say the same thing twice at two indents.
fn Diagnostic::point(self : Diagnostic) -> String? {
  match self.kind {
    UnclosedElement(_) => Some("opened here")
    StrayEndTag(_) => Some("dropped")
    DuplicateAttribute(_) => Some("this one is ignored")
    NonVoidSelfClosing(_) => Some("read as a start tag")
    BogusComment => Some("kept as a comment")
    MissingSemicolonAfterCharacterReference => Some("resolved anyway")
    UnknownNamedCharacterReference(_) => Some("kept as literal text")
    _ => None
  }
}

///|
/// The rule, in one sentence. This is the part a person actually learns from,
/// so it states the rule rather than restating the failure.
fn Diagnostic::help(self : Diagnostic) -> String? {
  match self.kind {
    NonVoidSelfClosing(t) =>
      Some("HTML has no self-closing tags: write `</" + t + ">`")
    EndTagForVoid(t) => Some("`<" + t + ">` closes itself; drop the end tag")
    DuplicateAttribute(_) =>
      Some("the first one wins, and the rest are dropped")
    CdataInHtmlContent =>
      Some(
        "in HTML this is read as a comment, which is probably not the intent",
      )
    UnprintableRawText(_) =>
      Some(
        "raw text ends at its own end tag and nothing escapes it, so this cannot be written down",
      )
    MissingSemicolonAfterCharacterReference =>
      Some("write the `;`: what follows decides which reference this is")
    UnexpectedCharacterInUnquotedAttributeValue => Some("quote the value")
    _ => None
  }
}

///|
/// Whether this diagnostic is severe enough to fail a strict parse.
pub fn Diagnostic::is_error(self : Diagnostic) -> Bool {
  match self.severity {
    Error => true
    _ => false
  }
}
