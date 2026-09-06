///|
/// CSS tokens, as CSS Syntax Level 3 defines them.
///
/// The token set is the specification's, not a convenient subset, because the
/// specification's error handling is defined in terms of it: "consume the
/// remnants of a bad declaration" means "discard tokens until a `;` or a
/// matching `}`", and that rule is only implementable if `;` and `}` are
/// tokens rather than characters. A tokenizer that folded them into a generic
/// `Delim` would have to re-derive the block structure to recover.
///
/// Whitespace and comments are tokens too. The parser skips them, but they have
/// to exist: whitespace is the descendant combinator, so a selector parser that
/// could not see it would be unable to tell `a b` from `ab`.

///|
/// Whether a `#...` can be an id selector, or only a hex colour.
///
/// The distinction is the specification's and it is load-bearing: `#1a2b3c` is
/// a colour but not a valid id, so `#foo` and `#1a2b3c` cannot be the same
/// token if a selector parser is to reject the second.
pub(all) enum HashKind {
  Id
  Unrestricted
} derive(Eq, Debug)

///|
pub(all) enum TokenKind {
  Ident(String)
  /// An ident immediately followed by `(`. The `(` is part of this token, so a
  /// function call can never be confused with an ident beside a group.
  Function(String)
  AtKeyword(String)
  Hash(String, HashKind)
  Str(String)
  /// A string that hit a newline or the end of input.
  BadStr
  /// A `url(...)` with an unquoted body. A quoted one is `Function("url")`
  /// followed by a `Str`, exactly as the specification has it.
  Url(String)
  BadUrl
  /// A number, with its source spelling kept.
  Number(String, Double, Bool)
  Percentage(String, Double)
  Dimension(String, Double, Bool, String)
  Whitespace
  Colon
  Semicolon
  Comma
  LBracket
  RBracket
  LParen
  RParen
  LBrace
  RBrace
  /// `<!--` and `-->`, which are legal at the top level of a stylesheet.
  Cdo
  Cdc
  /// The body, without the `/*` and `*/`.
  Comment(String)
  /// Any other single character.
  Delim(Char)
  /// A real variant rather than an `Option`, so that no lookahead has to
  /// unwrap and every parser loop has a terminating case to match.
  Eof
} derive(Eq, Debug)

///|
pub(all) struct Token {
  kind : TokenKind
  span : @span.Span
} derive(Eq, Debug)

///|
/// Whether this token is skipped when looking for the next meaningful one.
pub fn Token::is_trivia(self : Token) -> Bool {
  match self.kind {
    Whitespace | Comment(_) => true
    _ => false
  }
}

///|
/// The opener that this closer matches, if it is one.
///
/// Used by error recovery, which has to know how deep it is before it can know
/// whether a `}` ends the thing it is skipping.
pub fn TokenKind::closer_for(self : TokenKind) -> TokenKind? {
  match self {
    RParen => Some(LParen)
    RBracket => Some(LBracket)
    RBrace => Some(LBrace)
    _ => None
  }
}

///|
pub fn TokenKind::is_opener(self : TokenKind) -> Bool {
  match self {
    LParen | LBracket | LBrace | Function(_) => true
    _ => false
  }
}

///|
/// A stable one-line rendering of a token, for tests and for the oracle.
///
/// Hand-written rather than derived because this string is an interface: the
/// differential harness compares it, so it must not change when a variant is
/// renamed or a field reordered. It is also the only place a `Char` or a
/// `Double` gets formatted, which keeps backend differences in number printing
/// confined to one function.
pub fn TokenKind::to_debug(self : TokenKind) -> String {
  match self {
    Ident(s) => "Ident(" + q(s) + ")"
    Function(s) => "Function(" + q(s) + ")"
    AtKeyword(s) => "AtKeyword(" + q(s) + ")"
    Hash(s, k) =>
      "Hash(" +
      q(s) +
      ", " +
      (match k {
        Id => "Id"
        Unrestricted => "Unrestricted"
      }) +
      ")"
    Str(s) => "Str(" + q(s) + ")"
    BadStr => "BadStr"
    Url(s) => "Url(" + q(s) + ")"
    BadUrl => "BadUrl"
    Number(r, _, i) =>
      "Number(" + q(r) + ", " + (if i { "int" } else { "num" }) + ")"
    Percentage(r, _) => "Percentage(" + q(r) + ")"
    Dimension(r, _, _, u) => "Dimension(" + q(r) + ", " + q(u) + ")"
    Whitespace => "Whitespace"
    Colon => "Colon"
    Semicolon => "Semicolon"
    Comma => "Comma"
    LBracket => "LBracket"
    RBracket => "RBracket"
    LParen => "LParen"
    RParen => "RParen"
    LBrace => "LBrace"
    RBrace => "RBrace"
    Cdo => "Cdo"
    Cdc => "Cdc"
    Comment(s) => "Comment(" + q(s) + ")"
    Delim(c) => "Delim(" + q(c.to_string()) + ")"
    Eof => "Eof"
  }
}

///|
/// A quoted, escaped string, so that a token dump is one line whatever the
/// token contained.
fn q(s : String) -> String {
  let b = StringBuilder()
  b.write_string("\"")
  for c in s {
    match c {
      '"' => b.write_string("\\\"")
      '\\' => b.write_string("\\\\")
      '\n' => b.write_string("\\n")
      '\r' => b.write_string("\\r")
      '\t' => b.write_string("\\t")
      _ => b.write_char(c)
    }
  }
  b.write_string("\"")
  b.to_string()
}

///|
/// A whole token stream, one token per line, for the differential harness.
pub fn dump(toks : Array[Token]) -> String {
  let b = StringBuilder()
  for t in toks {
    b.write_string(t.span.start.to_string())
    b.write_string("..")
    b.write_string(t.span.end.to_string())
    b.write_string(" ")
    b.write_string(t.kind.to_debug())
    b.write_string("\n")
  }
  b.to_string()
}
