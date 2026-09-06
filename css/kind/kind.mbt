///|
/// What went wrong, as a closed set.
///
/// This package has no dependencies at all, and that is deliberate: the AST
/// stores a kind on every `Bogus` node, so if kinds lived beside the
/// `Diagnostic` that renders them, building a tree would link the diagnostic
/// library. Splitting the *name* of a problem from the *reporting* of one is
/// what keeps `ast` and `write` free of `error-report`.
///
/// The set is closed rather than a string because a consumer is expected to
/// match on it -- an editor deciding which quick fix to offer, a harness
/// deciding whether a corpus file is expected to fail. A string would make
/// every such decision a spelling comparison.
pub(all) enum ErrorKind {
  /// The input ended in the middle of something.
  UnexpectedEof
  /// A string literal ran to the end of the line or the file.
  UnterminatedString
  /// A `/*` with no `*/`.
  UnterminatedComment
  /// A `url(` with no `)`.
  UnterminatedUrl
  /// A `url()` whose unquoted body contains a character that may not appear
  /// there -- whitespace, a quote, a paren, or a control character.
  BadUrl
  /// A `)`, `]` or `}` with nothing open.
  UnexpectedCloser(String)
  /// A block opened and never closed.
  UnclosedBlock(String)
  /// A rule's prelude did not parse as a selector list.
  BadSelector
  /// A selector ran out where a compound was expected: a dangling combinator.
  DanglingCombinator
  /// `[` ... `]` that is not an attribute selector.
  BadAttributeSelector
  /// A pseudo-class whose argument list did not match its shape.
  BadPseudoClass(String)
  /// An `An+B` micro-syntax that did not parse.
  BadAnB
  /// A declaration with no `:`.
  ExpectedColon
  /// A declaration whose value is empty.
  EmptyValue
  /// `!important` somewhere other than the end of a value.
  ImportantNotLast
  /// A `!` that is not `!important`.
  BadBang
  /// A declaration that did not parse; the whole thing was skipped.
  BadDeclaration
  /// An at-rule that needed a block and did not have one, or the reverse.
  BadAtRuleShape(String)
  /// An at-rule name this library does not know. Tolerated: the rule is kept
  /// with an unparsed prelude.
  UnknownAtRule(String)
  /// An at-rule prelude that did not parse as the shape its name requires.
  BadAtRulePrelude(String)
  /// A media query that did not parse.
  BadMediaQuery
  /// A `@supports` condition that did not parse.
  BadSupportsCondition
  /// `a and b or c` without parentheses. CSS requires them too.
  MixedLogicalOps
  /// A `@keyframes` selector that is neither `from`, `to`, nor a percentage.
  BadKeyframeSelector
  /// A declaration outside any rule.
  DeclarationAtTopLevel
  /// A rule where only declarations are allowed -- inside `@font-face`, say.
  RuleInDeclarationContext
  /// Anything else that could not be read. Carries what was expected.
  Unexpected(String)
} derive(Eq, Debug)

///|
/// A stable identifier for this kind.
///
/// Stable is the whole point: it goes in `error[...]` headers, in JSON output
/// and in a harness's expectations, so it must not change when the prose does.
/// That is why it is written out rather than derived from the variant name --
/// renaming a variant is then a local edit, not a silent break of everything
/// downstream that matched on the string.
pub fn ErrorKind::code(self : ErrorKind) -> String {
  let name = match self {
    UnexpectedEof => "unexpected_eof"
    UnterminatedString => "unterminated_string"
    UnterminatedComment => "unterminated_comment"
    UnterminatedUrl => "unterminated_url"
    BadUrl => "bad_url"
    UnexpectedCloser(_) => "unexpected_closer"
    UnclosedBlock(_) => "unclosed_block"
    BadSelector => "bad_selector"
    DanglingCombinator => "dangling_combinator"
    BadAttributeSelector => "bad_attribute_selector"
    BadPseudoClass(_) => "bad_pseudo_class"
    BadAnB => "bad_anb"
    ExpectedColon => "expected_colon"
    EmptyValue => "empty_value"
    ImportantNotLast => "important_not_last"
    BadBang => "bad_bang"
    BadDeclaration => "bad_declaration"
    BadAtRuleShape(_) => "bad_at_rule_shape"
    UnknownAtRule(_) => "unknown_at_rule"
    BadAtRulePrelude(_) => "bad_at_rule_prelude"
    BadMediaQuery => "bad_media_query"
    BadSupportsCondition => "bad_supports_condition"
    MixedLogicalOps => "mixed_logical_ops"
    BadKeyframeSelector => "bad_keyframe_selector"
    DeclarationAtTopLevel => "declaration_at_top_level"
    RuleInDeclarationContext => "rule_in_declaration_context"
    Unexpected(_) => "unexpected"
  }
  "css::" + name
}

///|
/// Whether this kind is a hard error or something a tolerant parse may carry.
///
/// The distinction is what makes strict mode meaningful: strict fails on the
/// first `Error`, and an `UnknownAtRule` is deliberately not one -- CSS grows
/// new at-rules faster than any parser learns them, so refusing an unknown one
/// would make the library wrong every time the language moves.
pub fn ErrorKind::is_warning(self : ErrorKind) -> Bool {
  match self {
    UnknownAtRule(_) => true
    _ => false
  }
}
