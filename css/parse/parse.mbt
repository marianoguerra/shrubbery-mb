///|
/// The parser: CSS text to a CSS syntax tree.
///
/// Tolerant by default, which is not a convenience but a requirement. Real
/// stylesheets contain vendor hacks, at-rules newer than any given parser, and
/// the residue of preprocessors. The CSS specification says what to do with all
/// of it -- skip a bad declaration to the next `;`, skip a bad rule to the end
/// of its block, keep going -- and following that is what lets this library be
/// handed Bootstrap and give back a stylesheet rather than an error.
///
/// Strict mode turns the first `Error`-severity diagnostic into a raise. It
/// exists for the caller who is checking their own file rather than consuming
/// someone else's, and for the round-trip property: whatever this library
/// prints must parse strictly.
///
/// Nothing here fabricates. When a construct cannot be read, its source text
/// goes into a `Bogus` node, so the printer can echo it and a stylesheet does
/// not quietly lose the one line the parser did not understand.

///|
/// A parse: the tree, and everything noticed on the way.
pub struct Parsed {
  sheet : @ast.Stylesheet
  diagnostics : Array[@err.Diagnostic]
}

///|
pub fn Parsed::sheet(self : Parsed) -> @ast.Stylesheet {
  self.sheet
}

///|
pub fn Parsed::diagnostics(self : Parsed) -> Array[@err.Diagnostic] {
  self.diagnostics
}

///|
/// Whether anything of `Error` severity was found. Warnings do not count: an
/// unknown at-rule is kept, not failed.
pub fn Parsed::has_errors(self : Parsed) -> Bool {
  for d in self.diagnostics {
    if d.is_error() {
      return true
    }
  }
  false
}

///|
priv struct Parser {
  src : String
  toks : Array[@token.Token]
  mut pos : Int
  diags : Array[@err.Diagnostic]
  strict : Bool
}

///|
/// Parse a stylesheet.
///
/// In strict mode the first error is raised instead of recorded; in tolerant
/// mode this never raises, and `Parsed::has_errors` is how a caller asks.
pub fn parse(
  src : String,
  strict? : Bool = false,
) -> Parsed raise @err.CssError {
  let p = { src, toks: @token.tokenize(src), pos: 0, diags: [], strict, }
  let items = []
  while !p.at_eof() {
    p.skip_trivia_collecting(items)
    if p.at_eof() {
      break
    }
    match p.peek() {
      // `<!--` and `-->` are legal noise at the top level and mean nothing.
      Cdo | Cdc => p.pos = p.pos + 1
      RBrace | RParen | RBracket => {
        let t = p.cur()
        p.error(UnexpectedCloser(closer_text(t.kind)), t.span)
        p.pos = p.pos + 1
      }
      _ =>
        match p.parse_rule(top=true) {
          Some(r) => items.push(@ast.TopItem::Rule(r))
          None => ()
        }
    }
  }
  let span = @span.Span::new(0, src.length())
  { sheet: { items, span, }, diagnostics: p.diags, }
}

///|
/// Parse and raise on the first error, whatever the mode.
///
/// A convenience for the caller who wants a `Stylesheet` and not a pair.
pub fn parse_strict(src : String) -> @ast.Stylesheet raise @err.CssError {
  parse(src, strict=true).sheet
}

// -------------------------------------------------------------------- cursor

///|
fn Parser::cur(self : Parser) -> @token.Token {
  self.toks[self.pos]
}

///|
fn Parser::peek(self : Parser) -> @token.TokenKind {
  self.toks[self.pos].kind
}

///|
fn Parser::at_eof(self : Parser) -> Bool {
  self.peek() == Eof
}

///|
/// Skip whitespace and comments, discarding both.
fn Parser::skip_trivia(self : Parser) -> Unit {
  while self.toks[self.pos].is_trivia() {
    self.pos = self.pos + 1
  }
}

///|
/// Skip trivia, but keep comments as items.
///
/// Only used where a comment has somewhere to go -- between rules, and between
/// declarations. Inside a value a comment is a token separator and nothing
/// more, so there it is dropped.
fn Parser::skip_trivia_collecting(
  self : Parser,
  items : Array[@ast.TopItem],
) -> Unit {
  while self.toks[self.pos].is_trivia() {
    match self.peek() {
      Comment(body) =>
        items.push(Comment({ text: body, span: self.cur().span, }))
      _ => ()
    }
    self.pos = self.pos + 1
  }
}

///|
fn Parser::skip_trivia_collecting_block(
  self : Parser,
  items : Array[@ast.BlockItem],
) -> Unit {
  while self.toks[self.pos].is_trivia() {
    match self.peek() {
      Comment(body) =>
        items.push(Comment({ text: body, span: self.cur().span, }))
      _ => ()
    }
    self.pos = self.pos + 1
  }
}

///|
fn Parser::text_between(self : Parser, from : Int, to : Int) -> String {
  @span.Span::new(from, to).slice(self.src)
}

///|
fn closer_text(k : @token.TokenKind) -> String {
  match k {
    RBrace => "}"
    RParen => ")"
    RBracket => "]"
    _ => "?"
  }
}

// --------------------------------------------------------------- diagnostics

///|
/// Record a problem. In strict mode this raises instead.
fn Parser::error(
  self : Parser,
  kind : @kind.ErrorKind,
  span : @span.Span,
) -> Unit raise @err.CssError {
  let d = @err.Diagnostic::of_kind(kind, span)
  self.diags.push(d)
  if self.strict && d.is_error() {
    d.raise_()
  }
}

///|
/// Record a problem and build the `Bogus` that stands in its place.
fn Parser::bogus(
  self : Parser,
  kind : @kind.ErrorKind,
  from : Int,
  to : Int,
) -> @ast.Bogus raise @err.CssError {
  let span = @span.Span::new(from, to)
  self.error(kind, span)
  @ast.Bogus::new(kind, span, text=self.text_between(from, to))
}

// ------------------------------------------------------------------ recovery

///|
/// Discard the remnants of a bad declaration: up to a `;`, or to the `}` that
/// closes the block this is inside, whichever comes first. The `}` is left for
/// the caller, because it is theirs.
fn Parser::recover_declaration(self : Parser) -> Unit {
  let mut depth = 0
  while !self.at_eof() {
    let k = self.peek()
    if depth == 0 {
      match k {
        Semicolon => {
          self.pos = self.pos + 1
          return
        }
        RBrace => return
        _ => ()
      }
    }
    if k.is_opener() {
      depth = depth + 1
    } else if k == RBrace || k == RParen || k == RBracket {
      if depth > 0 {
        depth = depth - 1
      }
    }
    self.pos = self.pos + 1
  }
}
