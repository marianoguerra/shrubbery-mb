///|
/// What a token is.
///
/// The names are the reference's own, because the parser is written against
/// them and a rename here would be a rename in two places that must agree.
pub(all) enum TokenKind {
  Identifier
  Keyword
  Literal(@sexp.Datum)
  Operator
  /// `:`
  BlockOperator
  /// `\`
  ContinueOperator
  /// `|`
  BarOperator
  Opener
  Closer
  CommaOperator
  SemicolonOperator
  Comment
  Whitespace
  /// `#//`
  GroupComment
  /// `#{` or `~#{` and the datum inside.
  SExp(@sexp.Datum)
  At
  AtOpener
  AtContent
  AtCloser
  AtComment
  /// A `'`, before `rewrite_quotes` decides whether it opens or closes.
  SQuote
  EndOfInput
  /// A lexical failure, carried as a token rather than raised so that recovery
  /// mode can keep scanning and report every problem in a file at once.
  Fail(@err.ErrorKind)
} derive(Eq)

///|
/// A token, and the exact text it was made of.
///
/// **Every code unit of the input belongs to exactly one token's `text`.**
/// Concatenating them reproduces the source byte for byte, whitespace and
/// comments included. That total coverage is not a nicety — it is what makes
/// the raw-text metadata, and therefore round-tripping, possible at all, so it
/// has its own test.
pub(all) struct Token {
  kind : TokenKind
  text : String
  /// What the reference calls the token's `raw`, when that is NOT the source
  /// text. It differs in exactly one place: a `#{...}` escape's raw is the
  /// datum RE-PRINTED, so `#{ foo }` has raw `#{foo}`. Keeping the two apart is
  /// what lets `text` stay the exact source -- and the total-coverage invariant
  /// stay true -- while raw-text metadata still reproduces what the reference
  /// would have reproduced.
  raw : String?
  /// The value an `#{...}` escape denotes, when that is not already in `kind`.
  /// An escape naming a symbol lexes as an `Identifier`, and its NAME is the
  /// symbol rather than the source text — `#{treelist-ref}` is the identifier
  /// `treelist-ref` — so the name has to travel somewhere.
  value : @sexp.Datum?
  span : @basic.Span
  /// For a paired at-opener like `|<<{`, the closer it demands: `}>>|`.
  /// Computed once here so the parser never re-derives the reverse-and-flip.
  partner : String?
}

///|
/// The name this token denotes: the escape's symbol where there is one, and the
/// source text otherwise.
pub fn Token::name(self : Token) -> String {
  match self.value {
    Some(Sym(name)) => name
    Some(Kw(name)) => name
    _ => self.text
  }
}

///|
/// The text the raw-text metadata should carry for this token.
pub fn Token::raw_text(self : Token) -> String {
  match self.raw {
    Some(r) => r
    None => self.text
  }
}

///|
/// The indentation column this token takes part in comparisons at.
///
/// Not simply `span.start.col`: a `|` counts as half a column further right
/// than where it sits. That convention is what lets a block's content and an
/// alternative's `|` be at the same visual column and still be ordered against
/// each other.
pub fn Token::column(self : Token) -> @column.Column {
  match self.kind {
    BarOperator => self.span.start.col.half_up()
    _ => self.span.start.col
  }
}

///|
pub fn Token::line(self : Token) -> Int {
  self.span.start.line
}

///|
pub fn Token::end_line(self : Token) -> Int {
  self.span.end.line
}

///|
/// Whether this token is whitespace or a comment — the things the parser skips
/// but the raw-text metadata keeps.
pub fn Token::is_trivia(self : Token) -> Bool {
  match self.kind {
    Whitespace | Comment => true
    _ => false
  }
}

///|
/// The two lexer states.
///
/// They differ in the number pattern and in nothing else: `Initial` reads `+2`
/// as a signed literal, `Continuing` — entered after an identifier, a literal,
/// a closer or a keyword — reads it as `+` applied to `2`. That single bit is
/// the whole of why `1+2` is addition and `1 +2` is two terms.
pub(all) enum LexMode {
  Initial
  Continuing
} derive(Eq)

///|
/// The two predicates that are the entire configurability of the notation.
///
/// `allow_operator` rejects an operator spelling outright; a variant that
/// forbids `<-` makes it a read error rather than an operator.
/// `indented_operator_continue` decides whether an indented line starting with
/// that operator continues the previous group.
pub(all) struct Variant {
  allow_operator : (String) -> Bool
  indented_operator_continue : (String) -> Bool
}

///|
pub let default_variant : Variant = {
  allow_operator: _ => true,
  indented_operator_continue: _ => true,
}

///|
/// The reference's name for this token kind.
///
/// Used by the token-parity oracle, so these strings are the reference's
/// symbols and not ours to tidy.
pub fn TokenKind::kind_name(self : TokenKind) -> String {
  match self {
    Identifier => "identifier"
    Keyword => "keyword"
    Literal(_) => "literal"
    Operator => "operator"
    BlockOperator => "block-operator"
    ContinueOperator => "continue-operator"
    BarOperator => "bar-operator"
    Opener => "opener"
    Closer => "closer"
    CommaOperator => "comma-operator"
    SemicolonOperator => "semicolon-operator"
    Comment => "comment"
    Whitespace => "whitespace"
    GroupComment => "group-comment"
    SExp(_) => "s-exp"
    At => "at"
    AtOpener => "at-opener"
    AtContent => "at-content"
    AtCloser => "at-closer"
    AtComment => "at-comment"
    SQuote => "squote"
    EndOfInput => "EOF"
    Fail(_) => "fail"
  }
}
