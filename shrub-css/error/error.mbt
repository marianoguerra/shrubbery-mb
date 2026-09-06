///|
/// Diagnostics for the bridge.
///
/// The same arrangement as `@css.error` and `lib/error`: one function reaches
/// `error-report`, and everything else names a problem without linking a
/// renderer.
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
pub fn Diagnostic::is_error(self : Diagnostic) -> Bool {
  match self.severity {
    Error => true
    _ => false
  }
}

///|
/// A shrubbery-CSS source was rejected.
pub(all) suberror ShrubCssError {
  ShrubCssError(Diagnostic)
}

///|
pub fn[T] Diagnostic::raise_(self : Diagnostic) -> T raise ShrubCssError {
  raise ShrubCssError(self)
}

///|
pub fn ShrubCssError::diagnostic(self : ShrubCssError) -> Diagnostic {
  let ShrubCssError(d) = self
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
    ExpectedBlock => "this needs a `:` and an indented block"
    HeadlessBlock => "this block has nothing before it"
    AltsUnsupported => "`|` has no meaning in Shrubbery CSS"
    BracesUnsupported => "`{ }` has no meaning in Shrubbery CSS"
    QuotesUnsupported => "`'...'` has no meaning in Shrubbery CSS"
    DeclarationAtTopLevel => "a declaration must be inside a rule"
    RuleInDeclarationContext => "only declarations may appear here"
    TypeSelectorNotFirst =>
      "two element names touch, with no relation between them"
    DanglingCombinator => "this relation has nothing on one side of it"
    StrayKeyword(k) => "`~" + k + "` is not a relation"
    SigilSelector(s) => "`" + s + "` is CSS's spelling, not this syntax's"
    OperatorCombinator(o) =>
      "`" + o + "` is CSS's spelling for a relation, not this syntax's"
    UnknownSelectorCall(n) =>
      "`" + n + "()` is not something a selector can contain"
    BadCallShape(n) => "`" + n + "` was given arguments of the wrong shape"
    HexDigitsLost => "this colour's leading zeros were lost before it got here"
    UnknownUnit(u) => "`" + u + "` is not a unit"
    BadSelector => "this is not a selector"
    BareTermInBlock(t) =>
      "`" + t + "` is a bare word, with no value and no block"
    ColonPseudo(p, v) =>
      if p == "" {
        "`" + v + "` is a bare word here, not the pseudo-class it looks like"
      } else {
        "`" + p + ":` reads as a declaration of the property `" + p + "`"
      }
    SemicolonDeclarations => "`;` does not separate declarations here"
    BadAnB => "this is not an `an+b` formula"
    Unsupported(what) => what + " has no meaning in Shrubbery CSS"
  }
}

///|
fn Diagnostic::point(self : Diagnostic) -> String? {
  match self.kind {
    ColonPseudo(p, v) =>
      if p == "" {
        None
      } else {
        Some("`" + v + "` was read as the value")
      }
    TypeSelectorNotFirst => Some("this one begins a second element")
    DanglingCombinator => Some("nothing on this side")
    SemicolonDeclarations => Some("this ended up inside the value before it")
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
    ExpectedBlock => Some("a rule or a declaration ends with `:` and its body")
    AltsUnsupported => Some("nothing in CSS branches this way; `|` is reserved")
    BracesUnsupported => Some("a block is opened with `:` and indentation")
    TypeSelectorNotFirst =>
      Some("a descendant is written `a ~in b`; the relation is never a space")
    SigilSelector(s) => Some(sigil_help(s))
    OperatorCombinator(o) =>
      Some(
        match o {
          ">" => "write `~child`"
          "+" => "write `~next`"
          "~" => "write `~sibling`"
          _ => "write the relation as a keyword"
        },
      )
    ColonPseudo(_, v) => Some("a pseudo-class is a call: write `" + v + "()`")
    SemicolonDeclarations =>
      Some("the value runs to the end of the line; one declaration per line")
    HexDigitsLost => Some("write it as a string: `hex(\"007700\")`")
    DeclarationAtTopLevel =>
      Some("put it in a rule, or use `root():` for the document element")
    BareTermInBlock(_) =>
      Some("a declaration needs a value, and a rule needs a block")
    UnknownUnit(_) =>
      Some("use `dim(n, \"unit\")` for a unit this library does not know")
    _ => None
  }
}

///|
fn sigil_help(s : String) -> String {
  match s {
    "." => "write `class(card)` for `.card`"
    "#" => "write `id(sidebar)` for `#sidebar`, or `hex(f7f7f7)` for a colour"
    "&" => "write `parent()`"
    "*" => "write `any()`"
    "@" => "an at-rule is a call: write `media(...)` for `@media`"
    _ => "write the thing's name instead of a symbol for it"
  }
}
