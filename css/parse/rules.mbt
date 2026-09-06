///|
/// Rules, declarations and values.

///|
/// One rule, at any level.
fn Parser::parse_rule(
  self : Parser,
  top? : Bool = false,
) -> @ast.CssRule? raise @err.CssError {
  match self.peek() {
    AtKeyword(name) => self.parse_at_rule(name)
    _ => self.parse_qualified_rule(top~)
  }
}

///|
/// A style rule: a prelude, then a block.
fn Parser::parse_qualified_rule(
  self : Parser,
  top? : Bool = false,
) -> @ast.CssRule? raise @err.CssError {
  ignore(top)
  let start = self.cur().span.start
  let prelude_start = self.pos
  let mut depth = 0
  while !self.at_eof() {
    let k = self.peek()
    if depth == 0 && k == LBrace {
      break
    }
    if k.is_opener() {
      depth = depth + 1
    } else if k == RParen || k == RBracket {
      if depth > 0 {
        depth = depth - 1
      }
    } else if k == RBrace {
      if depth > 0 {
        depth = depth - 1
      } else {
        // A `}` before any `{`: this prelude belongs to nothing.
        let b = self.bogus(BadSelector, start, self.cur().span.start)
        return Some(Bogus(b))
      }
    }
    self.pos = self.pos + 1
  }
  if self.at_eof() {
    let b = self.bogus(UnexpectedEof, start, self.cur().span.end)
    return Some(Bogus(b))
  }
  let prelude = self.toks[prelude_start:self.pos]
  let selectors = self.parse_selector_list(prelude, start)
  let body = self.parse_block()
  Some(
    Style({ selectors, body, span: @span.Span::new(start, self.prev_end()), }),
  )
}

///|
fn Parser::prev_end(self : Parser) -> Int {
  if self.pos > 0 {
    self.toks[self.pos - 1].span.end
  } else {
    0
  }
}

///|
/// The contents of a `{ ... }`, positioned on the `{`.
///
/// Declarations and nested rules interleave, and telling them apart is the one
/// genuine ambiguity: `a:hover { }` and `color: red;` both begin with an
/// identifier and a colon. The decision is made by lookahead, not by guessing
/// from the identifier -- scan forward at depth zero for the first of `{`, `;`
/// or `}`. A `{` first means a rule; anything else means a declaration. That is
/// what real CSS parsers do, and it is right even for a property nobody has
/// heard of.
fn Parser::parse_block(
  self : Parser,
) -> Array[@ast.BlockItem] raise @err.CssError {
  let items : Array[@ast.BlockItem] = []
  if self.peek() != LBrace {
    return items
  }
  let brace_start = self.cur().span.start
  self.pos = self.pos + 1
  while true {
    self.skip_trivia_collecting_block(items)
    if self.at_eof() {
      self.error(
        UnclosedBlock("{"),
        @span.Span::new(brace_start, brace_start + 1),
      )
      return items
    }
    if self.peek() == RBrace {
      self.pos = self.pos + 1
      return items
    }
    if self.peek() == Semicolon {
      self.pos = self.pos + 1
      continue
    }
    match self.peek() {
      AtKeyword(name) =>
        match self.parse_at_rule(name) {
          Some(r) => items.push(Rule(r))
          None => ()
        }
      _ =>
        if self.next_is_rule() {
          match self.parse_qualified_rule() {
            Some(r) => items.push(Rule(r))
            None => ()
          }
        } else {
          match self.parse_declaration() {
            Some(d) => items.push(Decl(d))
            None => ()
          }
        }
    }
  }
  items
}

///|
/// Lookahead: does a `{` come before the `;` or `}` that would end a
/// declaration?
fn Parser::next_is_rule(self : Parser) -> Bool {
  let mut i = self.pos
  let mut depth = 0
  while i < self.toks.length() {
    let k = self.toks[i].kind
    if k == Eof {
      return false
    }
    if depth == 0 {
      if k == LBrace {
        return true
      }
      if k == Semicolon || k == RBrace {
        return false
      }
    }
    if k.is_opener() {
      depth = depth + 1
    } else if k == RParen || k == RBracket || k == RBrace {
      if depth > 0 {
        depth = depth - 1
      }
    }
    i = i + 1
  }
  false
}

// ----------------------------------------------------------- declarations

///|
fn Parser::parse_declaration(
  self : Parser,
) -> @ast.Declaration? raise @err.CssError {
  let start = self.cur().span.start
  let name = match self.peek() {
    Ident(n) => n
    _ => {
      let bad_start = self.cur().span.start
      self.recover_declaration()
      self.error(BadDeclaration, @span.Span::new(bad_start, self.prev_end()))
      return None
    }
  }
  self.pos = self.pos + 1
  self.skip_trivia()
  if self.peek() != Colon {
    let here = self.cur().span
    self.error(ExpectedColon, here)
    self.recover_declaration()
    return None
  }
  self.pos = self.pos + 1
  let (value, important) = self.parse_value()
  if value.length() == 0 {
    self.error(EmptyValue, @span.Span::new(start, self.prev_end()))
  }
  let property : @ast.PropertyName = if name.has_prefix("--") {
    Custom(name)
  } else {
    Ident(name)
  }
  Some({
    property,
    value,
    important,
    span: @span.Span::new(start, self.prev_end()),
  })
}

///|
/// A declaration's value, up to the `;` or `}` that ends it.
///
/// Returns the components and whether `!important` was present. The flag is
/// separated here rather than left in the list because it is not a value: it
/// changes the cascade, and a consumer asking "what colour is this" should not
/// have to filter it out first.
fn Parser::parse_value(
  self : Parser,
) -> (Array[@ast.ComponentValue], Bool) raise @err.CssError {
  let vs : Array[@ast.ComponentValue] = []
  let mut important = false
  while !self.at_eof() {
    let k = self.peek()
    if k == Semicolon {
      self.pos = self.pos + 1
      break
    }
    if k == RBrace {
      break
    }
    if self.toks[self.pos].is_trivia() {
      self.pos = self.pos + 1
      continue
    }
    // `!important`, and nothing else a `!` may introduce.
    if k == Delim('!') {
      let bang = self.cur().span
      let save = self.pos
      self.pos = self.pos + 1
      self.skip_trivia()
      match self.peek() {
        Ident(w) if w.to_lower() == "important" => {
          self.pos = self.pos + 1
          if important {
            self.error(ImportantNotLast, bang)
          }
          important = true
          continue
        }
        _ => {
          self.pos = save
          self.error(BadBang, bang)
          self.pos = self.pos + 1
          vs.push(Delim("!"))
          continue
        }
      }
    }
    if important {
      // Anything after `!important` is not part of the value.
      let here = self.cur().span
      self.error(ImportantNotLast, here)
    }
    vs.push(self.parse_component_value())
  }
  trim_trailing(vs)
  (vs, important)
}

///|
/// Drop a trailing separator, which a value cannot end with.
fn trim_trailing(vs : Array[@ast.ComponentValue]) -> Unit {
  while vs.length() > 0 {
    match vs[vs.length() - 1] {
      Comma | Slash => {
        let _ = vs.pop()
      }
      _ => return
    }
  }
}

///|
/// One component value, recursing into functions and groups.
fn Parser::parse_component_value(
  self : Parser,
) -> @ast.ComponentValue raise @err.CssError {
  let t = self.cur()
  match t.kind {
    Ident(s) => {
      self.pos = self.pos + 1
      Ident(s)
    }
    Str(s) => {
      self.pos = self.pos + 1
      Str(s)
    }
    Url(u) => {
      self.pos = self.pos + 1
      Url(u)
    }
    BadUrl => {
      self.pos = self.pos + 1
      Bogus(self.bogus(BadUrl, t.span.start, t.span.end))
    }
    BadStr => {
      self.pos = self.pos + 1
      Bogus(self.bogus(UnterminatedString, t.span.start, t.span.end))
    }
    Number(r, v, i) => {
      self.pos = self.pos + 1
      Num({ repr: r, value: v, is_int: i, })
    }
    Percentage(r, v) => {
      self.pos = self.pos + 1
      Percentage({ repr: r, value: v, is_int: false, })
    }
    Dimension(r, v, i, u) => {
      self.pos = self.pos + 1
      Dimension({ repr: r, value: v, is_int: i, }, u)
    }
    Hash(d, _) => {
      self.pos = self.pos + 1
      Hex(d)
    }
    Comma => {
      self.pos = self.pos + 1
      Comma
    }
    Delim('/') => {
      self.pos = self.pos + 1
      Slash
    }
    Delim(c) => {
      self.pos = self.pos + 1
      Delim(c.to_string())
    }
    Function(name) => {
      self.pos = self.pos + 1
      // `url("...")` tokenizes as a function; fold it back so that quoted and
      // unquoted urls are the same node and a consumer never has to know which
      // spelling the source used.
      let args = self.parse_group(RParen)
      if name.to_lower() == "url" && args.length() == 1 {
        match args[0] {
          Str(s) => return Url(s)
          _ => ()
        }
      }
      Function(name, args)
    }
    LParen => {
      self.pos = self.pos + 1
      Paren(self.parse_group(RParen))
    }
    LBracket => {
      self.pos = self.pos + 1
      Bracket(self.parse_group(RBracket))
    }
    Colon => {
      self.pos = self.pos + 1
      Delim(":")
    }
    _ => {
      self.pos = self.pos + 1
      Bogus(self.bogus(Unexpected("a value"), t.span.start, t.span.end))
    }
  }
}

///|
/// The inside of a `(`, `[` or a function call, up to its closer.
fn Parser::parse_group(
  self : Parser,
  closer : @token.TokenKind,
) -> Array[@ast.ComponentValue] raise @err.CssError {
  let vs : Array[@ast.ComponentValue] = []
  while !self.at_eof() {
    if self.peek() == closer {
      self.pos = self.pos + 1
      trim_trailing(vs)
      return vs
    }
    // A `}` or a `;` ends the enclosing rule; a group must not eat it.
    if self.peek() == RBrace {
      break
    }
    if self.toks[self.pos].is_trivia() {
      self.pos = self.pos + 1
      continue
    }
    vs.push(self.parse_component_value())
  }
  trim_trailing(vs)
  vs
}
