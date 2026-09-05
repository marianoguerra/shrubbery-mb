///|
/// Every way a shrubbery source can be rejected.
///
/// A closed enum with the parameters spelled out, rather than a string: a
/// consumer that wants to react to a particular failure — an editor offering a
/// fix, a test asserting on a case — matches on the constructor and never
/// parses prose. `reference_text` reproduces the Racket wording verbatim, which
/// is what the error-parity oracle compares, and `Diagnostic::to_report` is
/// free to say something better without breaking it.
pub(all) enum ErrorKind {
  // --- lexical -------------------------------------------------------------
  /// Anything the scanner could not make a token of.
  ReadError
  /// `keyword` distinguishes `~#{` from `#{`, which the reference words
  /// differently.
  ExpectedSExp(keyword~ : Bool)
  ExpectedSExpClose(keyword~ : Bool)
  ExpectedSExpOnlyWhitespace(keyword~ : Bool)
  SExpMustNotBePair
  // --- indentation ---------------------------------------------------------
  /// Two columns that neither extends. See `@column.ColumnOrder`.
  IncomparableIndentation
  /// `missing_colon_hint` is the reference's longer wording, used where a `:`
  /// on the previous line would have made the line legal.
  WrongIndentation(missing_colon_hint~ : Bool)
  AltBeforeGroupColumn
  // --- delimiters ----------------------------------------------------------
  DidNotFindMatching(expected~ : String)
  UnexpectedCloser(found~ : String)
  ExpectedCloser(expected~ : String, found~ : String)
  ExpectedQuoteAfterGuillemet
  ExpectedParenAfterGuillemet
  ExpectedGuillemetClose
  // --- separators ----------------------------------------------------------
  /// `paren_immed` is whether the comma was already inside an opener-closer
  /// pair; the reference explains the rule only when it was not.
  MisplacedComma(paren_immed~ : Bool)
  MissingCommaBeforeGroup
  MisplacedSemicolon
  MultiGroupSpliceNotAllowed
  // --- blocks and alternatives ---------------------------------------------
  /// `after` is the token that opened the block, `:` or `|`.
  EmptyBlock(after~ : String, could_empty_if_start~ : Bool)
  NoTermsAfterGuillemet
  UnnecessaryColonBeforeBar
  MisplacedBar
  MisplacedGuillemet
  NotOnSameLine(preceding~ : String)
  // --- limits --------------------------------------------------------------
  /// Nesting deeper than the parser will go.
  ///
  /// The only kind here that is not the reference's. The reference recurs
  /// without a bound and lets the runtime decide; on a native build that
  /// decision is a signal rather than an error, so input nested past anything
  /// a person writes is refused with a diagnostic a caller can catch.
  NestingTooDeep(limit~ : Int)
  // --- comments and continuations ------------------------------------------
  MisplacedGroupComment
  NoGroupForTermComment
  ContinuationFollowedByToken
  // --- at-notation ---------------------------------------------------------
  MissingTermAfterAt
  WhitespaceAfterAt
  InvalidAfterAt
  AtArgCannotStartBracket
  MissingCloserForAtContent
  AtCommentOutsideBody
  EmptyGroupAfterAt
  BlockAfterMidGroupAt
  SecondGroupAfterAt
} derive(Eq)

///|
/// What the reference says, byte for byte.
///
/// This is the measuring instrument, not the message: the error-parity oracle
/// compares it against Racket's `exn-message`, so it must not be improved. If a
/// wording here reads oddly — `a another`, below, is upstream's typo — that is
/// the point.
pub fn ErrorKind::reference_text(self : ErrorKind) -> String {
  let within = "within parentheses, brackets, or braces"
  match self {
    ReadError => "read error"
    ExpectedSExp(keyword~) =>
      if keyword {
        "expected S-expression identifier after `~#{`"
      } else {
        "expected S-expression after `#{`"
      }
    ExpectedSExpClose(keyword~) =>
      if keyword {
        "expected `}` after S-expression identifier for keyword"
      } else {
        "expected `}` after S-expression"
      }
    ExpectedSExpOnlyWhitespace(keyword~) =>
      if keyword {
        "expected only whitespace or `}` after S-expression identifier for keyword"
      } else {
        "expected only whitespace or `}` after S-expression"
      }
    SExpMustNotBePair => "S-expression in `#{` and `}` must not be a pair"
    IncomparableIndentation => "incomparable indentation due to mixed tabs"
    WrongIndentation(missing_colon_hint~) =>
      if missing_colon_hint {
        "wrong indentation (or missing `:` on previous line)"
      } else {
        "wrong indentation"
      }
    AltBeforeGroupColumn =>
      "alternative cannot start before group's initial column"
    // `~s` in the reference, so the closer arrives already quoted.
    DidNotFindMatching(expected~) =>
      "did not find matching \{write_string(expected)}"
    UnexpectedCloser(found~) => "unexpected closer `\{found}`"
    ExpectedCloser(expected~, found~) =>
      "expected closer `\{expected}`, found `\{found}`"
    ExpectedQuoteAfterGuillemet => "expected closing \"'\" after closing \"»\""
    ExpectedParenAfterGuillemet =>
      "expected a closing `)` immediately after closing `»`"
    ExpectedGuillemetClose => "expected `»`"
    MisplacedComma(paren_immed~) =>
      if paren_immed {
        "misplaced comma"
      } else {
        "misplaced comma (not immediately \{within})"
      }
    MissingCommaBeforeGroup => "missing comma before new group (\{within})"
    MisplacedSemicolon => "misplaced semicolon (immediately \{within})"
    MultiGroupSpliceNotAllowed =>
      "multi-group splice not allowed (immediately \{within})"
    EmptyBlock(after~, could_empty_if_start~) => {
      let extra = if could_empty_if_start {
        ", at top, or in an opener-closer pair"
      } else {
        ""
      }
      "empty block not allowed after `\{after}` (except with `«` and `»`\{extra})"
    }
    NoTermsAfterGuillemet => "no terms allowed after `»` within a group"
    UnnecessaryColonBeforeBar => "unnecessary `:` before `|`"
    MisplacedBar => "misplaced `|`"
    MisplacedGuillemet => "misplaced `«`"
    NotOnSameLine(preceding~) =>
      "not on the same line as preceding `\{preceding}`"
    NestingTooDeep(limit~) => "nesting deeper than \{limit} is not supported"
    MisplacedGroupComment => "misplaced group comment"
    NoGroupForTermComment => "no group for term comment"
    // Upstream's typo, reproduced deliberately.
    ContinuationFollowedByToken =>
      "line-continuing '\\' is followed by a another token on the same line"
    MissingTermAfterAt => "missing term after `@`"
    WhitespaceAfterAt => "whitespace is invalid after `@`"
    InvalidAfterAt => "invalid after `@`"
    AtArgCannotStartBracket => "argument position for `@` cannot start `[`"
    MissingCloserForAtContent => "missing closer for `@` content"
    AtCommentOutsideBody =>
      "comments using `@//` are allowed only within `@` body"
    EmptyGroupAfterAt => "empty group after `@` within `«` and `»`"
    BlockAfterMidGroupAt =>
      "block not allowed after mid-group `@` within `«` and `»`"
    SecondGroupAfterAt =>
      "second group not allowed after `@` within `«` and `»`"
  }
}

///|
/// Racket's `~s` for a string: double quotes, with `\` and `"` escaped.
fn write_string(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for c in s {
    if c == '"' || c == '\\' {
      buf.write_char('\\')
    }
    buf.write_char(c)
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// A stable identifier for this failure.
///
/// Stable is the operative word: it is what a test asserts on and what a
/// consumer suppresses by, so it has to survive rewording the message — which
/// is exactly why it is not derived from one.
pub fn ErrorKind::code(self : ErrorKind) -> String {
  let name = match self {
    ReadError => "read_error"
    ExpectedSExp(_) => "expected_s_expression"
    ExpectedSExpClose(_) => "expected_s_expression_close"
    ExpectedSExpOnlyWhitespace(_) => "expected_s_expression_end"
    SExpMustNotBePair => "s_expression_must_not_be_pair"
    IncomparableIndentation => "incomparable_indentation"
    WrongIndentation(_) => "wrong_indentation"
    AltBeforeGroupColumn => "alternative_before_group_column"
    DidNotFindMatching(_) => "did_not_find_matching"
    UnexpectedCloser(_) => "unexpected_closer"
    ExpectedCloser(_) => "expected_closer"
    ExpectedQuoteAfterGuillemet => "expected_quote_after_guillemet"
    ExpectedParenAfterGuillemet => "expected_paren_after_guillemet"
    ExpectedGuillemetClose => "expected_guillemet_close"
    MisplacedComma(_) => "misplaced_comma"
    MissingCommaBeforeGroup => "missing_comma"
    MisplacedSemicolon => "misplaced_semicolon"
    MultiGroupSpliceNotAllowed => "multi_group_splice"
    EmptyBlock(_) => "empty_block"
    NoTermsAfterGuillemet => "terms_after_guillemet"
    UnnecessaryColonBeforeBar => "unnecessary_colon_before_bar"
    MisplacedBar => "misplaced_bar"
    MisplacedGuillemet => "misplaced_guillemet"
    NotOnSameLine(_) => "not_on_same_line"
    NestingTooDeep(_) => "nesting_too_deep"
    MisplacedGroupComment => "misplaced_group_comment"
    NoGroupForTermComment => "no_group_for_term_comment"
    ContinuationFollowedByToken => "continuation_followed_by_token"
    MissingTermAfterAt => "missing_term_after_at"
    WhitespaceAfterAt => "whitespace_after_at"
    InvalidAfterAt => "invalid_after_at"
    AtArgCannotStartBracket => "at_argument_bracket"
    MissingCloserForAtContent => "missing_at_closer"
    AtCommentOutsideBody => "at_comment_outside_body"
    EmptyGroupAfterAt => "empty_group_after_at"
    BlockAfterMidGroupAt => "block_after_mid_group_at"
    SecondGroupAfterAt => "second_group_after_at"
  }
  "shrubbery::" + name
}
