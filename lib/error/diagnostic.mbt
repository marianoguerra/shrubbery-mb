///|
/// A rejected source, with the span it was rejected at.
///
/// The data a consumer reads. `related` carries the second place worth looking
/// — the opener that was never closed, the `|` an alternative was expected to
/// line up with — which the reference does not record and which is most of what
/// makes an indentation complaint answerable.
pub(all) struct Diagnostic {
  kind : ErrorKind
  span : @basic.Span
  severity : @report.Severity
  related : Array[(@basic.Span, String)]
}

///|
pub fn Diagnostic::new(
  kind : ErrorKind,
  span : @basic.Span,
  severity? : @report.Severity = Error,
  related? : Array[(@basic.Span, String)] = [],
) -> Diagnostic {
  { kind, span, severity, related, }
}

///|
/// A shrubbery source was rejected.
///
/// One error type for the whole library. `Diagnostic` carries the structure, so
/// nothing is lost by there being a single constructor.
pub(all) suberror ShrubberyError {
  ShrubberyError(Diagnostic)
}

///|
/// Raise this diagnostic.
pub fn[T] Diagnostic::raise_(self : Diagnostic) -> T raise ShrubberyError {
  raise ShrubberyError(self)
}

///|
/// The diagnostic inside an error.
pub fn ShrubberyError::diagnostic(self : ShrubberyError) -> Diagnostic {
  let ShrubberyError(d) = self
  d
}

///|
/// Turn a diagnostic into a renderable report.
///
/// **This is the only function in the library that mentions `error-report`.**
/// Keeping it to one is what makes that library's eventual spin-out a rename
/// rather than an untangling, and `tools/boundary-check.sh` gates the other
/// half of the arrangement. If a second call site appears, the question to ask
/// is whether the thing it needs belongs in `Diagnostic` instead.
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
fn span_of(span : @basic.Span) -> @report.Span {
  @report.Span::of_range(span.start.idx, span.end.idx)
}

///|
/// The headline. Defaults to the reference's wording, and says something
/// clearer where the reference's phrasing assumes you already know the rule.
fn Diagnostic::explain(self : Diagnostic) -> String {
  match self.kind {
    WrongIndentation(missing_colon_hint~) =>
      if missing_colon_hint {
        "this line is indented, but the line before it does not open a block"
      } else {
        "this group is not indented like the ones around it"
      }
    IncomparableIndentation =>
      "these two lines are indented with different mixtures of tabs and spaces"
    EmptyBlock(after~, ..) => "nothing follows this `\{after}`"
    DidNotFindMatching(_) => "this opener is never closed"
    ExpectedCloser(expected~, found~) =>
      "expected `\{expected}` to close this, found `\{found}`"
    UnexpectedCloser(found~) => "there is nothing here for `\{found}` to close"
    NoGroupForTermComment => "`#//` has nothing after it to comment out"
    _ => self.kind.reference_text()
  }
}

///|
/// What to write beside the caret. `None` where the headline already said it.
fn Diagnostic::point(self : Diagnostic) -> String? {
  match self.kind {
    WrongIndentation(_) => Some("this column does not line up")
    IncomparableIndentation => Some("this indentation is not comparable")
    EmptyBlock(after~, ..) => Some("this `\{after}` opens a block")
    DidNotFindMatching(_) => Some("opened here")
    NoGroupForTermComment => Some("nothing to comment out")
    MisplacedComma(_) => Some("this comma")
    MissingCommaBeforeGroup => Some("a comma is needed before this")
    AltBeforeGroupColumn => Some("this `|` starts too far left")
    _ => None
  }
}

///|
/// The rule, in one sentence, where knowing it is the whole fix.
fn Diagnostic::help(self : Diagnostic) -> String? {
  match self.kind {
    WrongIndentation(missing_colon_hint~) =>
      if missing_colon_hint {
        Some(
          "end the previous line with `:` to open a block, or unindent this line",
        )
      } else {
        Some("every group in a sequence starts at the same column")
      }
    IncomparableIndentation =>
      Some(
        "one indentation is more than another only when it extends it; mixing tabs and spaces differently makes them incomparable",
      )
    EmptyBlock(..) =>
      Some("a block needs at least one group, or explicit `«»` to be empty")
    MisplacedSemicolon =>
      Some(
        "inside `()`, `[]` or `{}`, groups are separated by `,` rather than `;`",
      )
    MissingCommaBeforeGroup =>
      Some(
        "inside `()`, `[]` or `{}`, groups on separate lines still need a `,`",
      )
    AltBeforeGroupColumn =>
      Some("a `|` may not start left of the column its group started at")
    UnnecessaryColonBeforeBar =>
      Some("drop the `:`; a `|` on the next line opens the block by itself")
    NoGroupForTermComment =>
      Some("`#//` comments out the group or `|` after it")
    _ => None
  }
}
