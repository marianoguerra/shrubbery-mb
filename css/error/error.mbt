///|
/// Diagnostics.
///
/// This package exists to be the *only* one in the module that mentions
/// `error-report`. The kinds themselves live in `css/kind`, which has no
/// dependencies, so the AST can name a problem without linking a renderer; here
/// is where a named problem becomes a renderable report, and there is exactly
/// one function that does it.
///
/// The arrangement is the one `lib/error` already uses, and it is what makes
/// `error-report`'s eventual spin-out a rename rather than an untangling. If a
/// second call site into `@report` appears here, the question to ask is whether
/// the thing it needs belongs on `Diagnostic` instead.

///|
/// A problem, with the span it was found at.
pub(all) struct Diagnostic {
  kind : @kind.ErrorKind
  span : @span.Span
  severity : @report.Severity
  /// The second place worth looking: the `{` that was never closed, the
  /// declaration a stray `!important` belonged to. Most of what makes a
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
/// An unknown at-rule is a warning rather than an error, because CSS gains new
/// at-rules faster than any parser learns them; refusing one would make this
/// library wrong every time the language moves.
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
/// A CSS source was rejected.
///
/// One error type for the whole module, raised only in strict mode. The
/// tolerant path never raises: it puts a `Bogus` in the tree and a `Diagnostic`
/// in the list, which is what lets a caller parse Bootstrap and still get a
/// stylesheet.
pub(all) suberror CssError {
  CssError(Diagnostic)
}

///|
pub fn[T] Diagnostic::raise_(self : Diagnostic) -> T raise CssError {
  raise CssError(self)
}

///|
pub fn CssError::diagnostic(self : CssError) -> Diagnostic {
  let CssError(d) = self
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
///
/// Both are measured in UTF-16 code units, deliberately, so this is a change of
/// representation and not of unit -- which is why it can be a three-line
/// function instead of a conversion that has to be got right at every call
/// site.
fn span_of(s : @span.Span) -> @report.Span {
  @report.Span::of_range(s.start, s.end)
}

///|
/// The headline: what went wrong, in one sentence, in the reader's terms.
fn Diagnostic::explain(self : Diagnostic) -> String {
  match self.kind {
    UnexpectedEof => "the file ended in the middle of a rule"
    UnterminatedString => "this string is never closed"
    UnterminatedComment => "this comment is never closed"
    UnterminatedUrl => "this `url(` is never closed"
    BadUrl => "this unquoted url contains a character that must be quoted"
    UnexpectedCloser(c) =>
      "there is no `" + opener_of(c) + "` for this `" + c + "`"
    UnclosedBlock(c) => "this `" + c + "` is never closed"
    BadSelector => "this is not a selector"
    DanglingCombinator => "this combinator has nothing after it"
    BadAttributeSelector => "this is not an attribute selector"
    BadPseudoClass(n) => "`:" + n + "` was given arguments of the wrong shape"
    BadAnB => "this is not an `an+b` formula"
    ExpectedColon =>
      "a declaration needs a `:` between the property and the value"
    EmptyValue => "this declaration has no value"
    ImportantNotLast => "`!important` must be the last thing in a value"
    BadBang => "the only thing a `!` may introduce here is `important`"
    BadDeclaration => "this declaration could not be read"
    BadAtRuleShape(n) => "`@" + n + "` was written with the wrong shape"
    UnknownAtRule(n) => "`@" + n + "` is not an at-rule this library knows"
    BadAtRulePrelude(n) => "the prelude of `@" + n + "` could not be read"
    BadMediaQuery => "this is not a media query"
    BadSupportsCondition => "this is not a `@supports` condition"
    MixedLogicalOps => "`and` and `or` may not be mixed without parentheses"
    BadKeyframeSelector =>
      "a keyframe selector is `from`, `to`, or a percentage"
    DeclarationAtTopLevel => "a declaration must be inside a rule"
    RuleInDeclarationContext => "only declarations may appear here"
    Unexpected(what) => "expected " + what
  }
}

///|
/// The caret label. `None` when the headline has already said it, so that a
/// rendered report does not say the same thing twice at two indents.
fn Diagnostic::point(self : Diagnostic) -> String? {
  match self.kind {
    ExpectedColon => Some("this needs a `:`")
    ImportantNotLast => Some("this comes after `!important`")
    UnknownAtRule(_) => Some("kept as written")
    DanglingCombinator => Some("nothing follows this")
    _ => None
  }
}

///|
/// The rule, in one sentence. This is the part a person actually learns from,
/// so it states the rule rather than restating the failure.
fn Diagnostic::help(self : Diagnostic) -> String? {
  match self.kind {
    UnknownAtRule(_) =>
      Some("its prelude and block are kept unparsed, so nothing is lost")
    MixedLogicalOps => Some("group them: `(a and b) or c`")
    ImportantNotLast => Some("write `color: red !important`")
    BadUrl => Some("quote it: `url(\"a b.png\")`")
    BadKeyframeSelector => Some("for example `0%`, `100%`, `from`, `to`")
    EmptyValue => Some("either give it a value or remove the declaration")
    BadDeclaration =>
      Some(
        "the declaration was skipped up to the next `;` and parsing continued",
      )
    _ => None
  }
}

///|
fn opener_of(closer : String) -> String {
  match closer {
    ")" => "("
    "]" => "["
    "}" => "{"
    _ => closer
  }
}

///|
/// Whether this diagnostic is severe enough to fail a strict parse.
///
/// A predicate rather than a comparison at the call site, because
/// `@report.Severity` has no `Eq` and this is the only question anyone asks of
/// it -- so the match belongs here once rather than everywhere.
pub fn Diagnostic::is_error(self : Diagnostic) -> Bool {
  match self.severity {
    Error => true
    _ => false
  }
}
