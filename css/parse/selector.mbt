///|
/// Selectors, from a rule's prelude tokens.
///
/// The prelude arrives as a token slice rather than being read from the main
/// cursor, because a rule's extent is decided by brace matching before anything
/// tries to understand it. That ordering is what makes recovery work: a
/// selector nobody can parse still has a known end, so the block after it can
/// be parsed normally instead of being swallowed.
///
/// Whitespace is significant here and nowhere else in CSS: it is the descendant
/// combinator. That is why the tokenizer keeps it.

///|
/// A comma-separated selector list.
fn Parser::parse_selector_list(
  self : Parser,
  toks : ArrayView[@token.Token],
  start : Int,
) -> Array[@ast.Selector] raise @err.CssError {
  let out : Array[@ast.Selector] = []
  let mut from = 0
  let mut depth = 0
  let mut i = 0
  while i < toks.length() {
    let k = toks[i].kind
    if k.is_opener() {
      depth = depth + 1
    } else if k == RParen || k == RBracket || k == RBrace {
      if depth > 0 {
        depth = depth - 1
      }
    } else if k == Comma && depth == 0 {
      out.push(self.parse_selector(toks[from:i], start))
      from = i + 1
    }
    i = i + 1
  }
  // A trailing comma leaves a run with nothing in it. That is an error, and it
  // is reported -- but it must not also become a `Bogus` SELECTOR, because
  // printing one emits the dangling comma again and the output stops being a
  // fixed point.
  let tail = toks[from:]
  if only_trivia_toks(tail) && out.length() > 0 {
    let sp = span_of_view(tail, start)
    self.error(BadSelector, sp)
  } else {
    out.push(self.parse_selector(tail, start))
  }
  if out.length() == 0 {
    out.push(Bogus(self.bogus(BadSelector, start, start)))
  }
  out
}

///|
fn only_trivia_toks(toks : ArrayView[@token.Token]) -> Bool {
  for t in toks {
    if !t.is_trivia() {
      return false
    }
  }
  true
}

///|
/// One selector: compounds joined by combinators.
fn Parser::parse_selector(
  self : Parser,
  toks : ArrayView[@token.Token],
  start : Int,
) -> @ast.Selector raise @err.CssError {
  let s = { toks, pos: 0, owner: self, }
  s.skip_ws()
  if s.at_end() {
    let sp = span_of_view(toks, start)
    return Bogus(self.bogus(BadSelector, sp.start, sp.end))
  }
  // A nested rule may open with a combinator: `> .child`.
  match s.read_combinator(leading=true) {
    Some(c) => {
      let inner = s.parse_rest(start)
      return Relative(c, inner)
    }
    None => ()
  }
  s.parse_rest(start)
}

///|
/// A cursor over one selector's tokens.
///
/// Separate from `Parser` because it moves through a slice rather than the
/// whole file, and giving it its own position keeps the two from being confused
/// -- a bug that would be invisible until a selector containing a function
/// desynchronised the main cursor.
priv struct SelCursor {
  toks : ArrayView[@token.Token]
  mut pos : Int
  owner : Parser
}

///|
fn SelCursor::at_end(self : SelCursor) -> Bool {
  self.pos >= self.toks.length()
}

///|
fn SelCursor::peek(self : SelCursor) -> @token.TokenKind {
  if self.at_end() {
    Eof
  } else {
    self.toks[self.pos].kind
  }
}

///|
fn SelCursor::peek_at(self : SelCursor, n : Int) -> @token.TokenKind {
  let i = self.pos + n
  if i >= self.toks.length() || i < 0 {
    Eof
  } else {
    self.toks[i].kind
  }
}

///|
fn SelCursor::skip_ws(self : SelCursor) -> Unit {
  while !self.at_end() && self.toks[self.pos].is_trivia() {
    self.pos = self.pos + 1
  }
}

///|
fn SelCursor::here(self : SelCursor) -> Int {
  if self.at_end() {
    if self.toks.length() == 0 {
      0
    } else {
      self.toks[self.toks.length() - 1].span.end
    }
  } else {
    self.toks[self.pos].span.start
  }
}

///|
fn span_of_view(toks : ArrayView[@token.Token], fallback : Int) -> @span.Span {
  if toks.length() == 0 {
    @span.Span::at(fallback)
  } else {
    @span.Span::new(toks[0].span.start, toks[toks.length() - 1].span.end)
  }
}

///|
fn SelCursor::parse_rest(
  self : SelCursor,
  start : Int,
) -> @ast.Selector raise @err.CssError {
  let mut acc : @ast.Selector = Simple(self.parse_compound(start))
  while true {
    match self.read_combinator() {
      None => break
      Some(c) => {
        if self.at_end() {
          let at = self.here()
          let b = self.owner.bogus(DanglingCombinator, at, at)
          return Complex(acc, c, {
            type_sel: None,
            quals: [Bogus(b)],
            span: @span.Span::at(at),
          })
        }
        acc = Complex(acc, c, self.parse_compound(start))
      }
    }
  }
  acc
}

///|
/// A combinator, if one is next.
///
/// `leading` distinguishes the start of a nested relative selector, where a
/// bare space means nothing, from a position between compounds, where it means
/// descendant.
fn SelCursor::read_combinator(
  self : SelCursor,
  leading? : Bool = false,
) -> @ast.Combinator? {
  let save = self.pos
  let mut saw_ws = false
  while !self.at_end() && self.toks[self.pos].is_trivia() {
    saw_ws = true
    self.pos = self.pos + 1
  }
  if self.at_end() {
    self.pos = save
    return None
  }
  let c : @ast.Combinator? = match self.peek() {
    Delim('>') => {
      self.pos = self.pos + 1
      Some(Child)
    }
    Delim('+') => {
      self.pos = self.pos + 1
      Some(NextSibling)
    }
    Delim('~') =>
      // `~` alone is the sibling combinator; `~=` only ever appears inside
      // `[ ]`, which this loop never sees at the top level.
      if self.peek_at(1) == Delim('=') {
        None
      } else {
        self.pos = self.pos + 1
        Some(SubsequentSibling)
      }
    Delim('|') =>
      if self.peek_at(1) == Delim('|') {
        self.pos = self.pos + 2
        Some(Column)
      } else {
        None
      }
    _ => None
  }
  match c {
    Some(_) => {
      self.skip_ws()
      c
    }
    None =>
      if saw_ws && !leading {
        Some(Descendant)
      } else {
        self.pos = save
        None
      }
  }
}

///|
/// One element's worth: an optional type selector, then qualifiers.
fn SelCursor::parse_compound(
  self : SelCursor,
  start : Int,
) -> @ast.Compound raise @err.CssError {
  let from = self.here()
  let quals : Array[@ast.Qualifier] = []
  let mut type_sel : @ast.TypeSelector? = None
  // A namespace prefix binds to the type selector, so it has to be read first
  // -- and `a|b` is only a namespace when the `|` is not `||` and not `|=`.
  let ns = self.read_ns_prefix()
  match self.peek() {
    Ident(name) => {
      self.pos = self.pos + 1
      type_sel = Some(Named(ns, name))
    }
    Delim('*') => {
      self.pos = self.pos + 1
      type_sel = Some(Universal(ns))
    }
    _ =>
      match ns {
        // A prefix with nothing to qualify.
        Some(_) => {
          let at = self.here()
          quals.push(Bogus(self.owner.bogus(BadSelector, at, at)))
        }
        None => ()
      }
  }
  while !self.at_end() {
    match self.peek() {
      Delim('.') =>
        match self.peek_at(1) {
          Ident(n) => {
            self.pos = self.pos + 2
            quals.push(Class(n))
          }
          _ => {
            let at = self.here()
            self.pos = self.pos + 1
            quals.push(Bogus(self.owner.bogus(BadSelector, at, at + 1)))
          }
        }
      Hash(n, k) => {
        self.pos = self.pos + 1
        if k == Id {
          quals.push(Id(n))
        } else {
          let at = self.here()
          quals.push(Bogus(self.owner.bogus(BadSelector, at, at)))
        }
      }
      Delim('&') => {
        self.pos = self.pos + 1
        quals.push(Nesting)
      }
      LBracket => quals.push(self.parse_attr(start))
      Colon => quals.push(self.parse_pseudo(start))
      _ => break
    }
  }
  { type_sel, quals, span: @span.Span::new(from, self.here()), }
}

///|
/// A namespace prefix, if the `|` here is one.
fn SelCursor::read_ns_prefix(self : SelCursor) -> @ast.NsPrefix? {
  match self.peek() {
    Delim('|') =>
      if self.peek_at(1) == Delim('|') {
        None
      } else {
        self.pos = self.pos + 1
        Some(None_)
      }
    Delim('*') =>
      if self.peek_at(1) == Delim('|') && self.peek_at(2) != Delim('|') {
        self.pos = self.pos + 2
        Some(Any)
      } else {
        None
      }
    Ident(n) =>
      if self.peek_at(1) == Delim('|') &&
        self.peek_at(2) != Delim('|') &&
        self.peek_at(2) != Delim('=') {
        self.pos = self.pos + 2
        Some(Named(n))
      } else {
        None
      }
    _ => None
  }
}

///|
/// `[attr]`, `[attr=value]`, `[attr^="v" i]`.
fn SelCursor::parse_attr(
  self : SelCursor,
  start : Int,
) -> @ast.Qualifier raise @err.CssError {
  let from = self.here()
  self.pos = self.pos + 1
  self.skip_ws()
  let ns = self.read_ns_prefix()
  let name = match self.peek() {
    Ident(n) => {
      self.pos = self.pos + 1
      n
    }
    _ => return self.attr_bogus(from, start)
  }
  self.skip_ws()
  if self.peek() == RBracket {
    self.pos = self.pos + 1
    return Attr({ ns, name, matcher: None, case_: Default, })
  }
  // The match operators are a delim pair; the tokenizer does not fuse them,
  // because outside `[ ]` those characters mean unrelated things.
  let op : @ast.AttrOp? = match (self.peek(), self.peek_at(1)) {
    (Delim('='), _) => {
      self.pos = self.pos + 1
      Some(Exact)
    }
    (Delim('~'), Delim('=')) => {
      self.pos = self.pos + 2
      Some(Includes)
    }
    (Delim('|'), Delim('=')) => {
      self.pos = self.pos + 2
      Some(DashMatch)
    }
    (Delim('^'), Delim('=')) => {
      self.pos = self.pos + 2
      Some(Prefix)
    }
    (Delim('$'), Delim('=')) => {
      self.pos = self.pos + 2
      Some(Suffix)
    }
    (Delim('*'), Delim('=')) => {
      self.pos = self.pos + 2
      Some(Substring)
    }
    _ => None
  }
  let op = match op {
    Some(o) => o
    None => return self.attr_bogus(from, start)
  }
  self.skip_ws()
  let value : @ast.AttrValue = match self.peek() {
    Str(s) => {
      self.pos = self.pos + 1
      Str(s)
    }
    Ident(s) => {
      self.pos = self.pos + 1
      Ident(s)
    }
    Number(r, _, _) => {
      self.pos = self.pos + 1
      Ident(r)
    }
    _ => return self.attr_bogus(from, start)
  }
  self.skip_ws()
  let case_ : @ast.AttrCase = match self.peek() {
    Ident(f) =>
      if f.to_lower() == "i" {
        self.pos = self.pos + 1
        Insensitive
      } else if f.to_lower() == "s" {
        self.pos = self.pos + 1
        Sensitive
      } else {
        Default
      }
    _ => Default
  }
  self.skip_ws()
  if self.peek() == RBracket {
    self.pos = self.pos + 1
    Attr({ ns, name, matcher: Some((op, value)), case_, })
  } else {
    self.attr_bogus(from, start)
  }
}

///|
/// Give up on an attribute selector, consuming through its `]` so that the rest
/// of the compound still parses.
fn SelCursor::attr_bogus(
  self : SelCursor,
  from : Int,
  start : Int,
) -> @ast.Qualifier raise @err.CssError {
  ignore(start)
  while !self.at_end() && self.peek() != RBracket {
    self.pos = self.pos + 1
  }
  if !self.at_end() {
    self.pos = self.pos + 1
  }
  Bogus(self.owner.bogus(BadAttributeSelector, from, self.here()))
}

///|
/// `:hover`, `::before`, `:not(...)`, `:nth-child(2n+1 of .x)`.
fn SelCursor::parse_pseudo(
  self : SelCursor,
  start : Int,
) -> @ast.Qualifier raise @err.CssError {
  let from = self.here()
  self.pos = self.pos + 1
  let is_element = if self.peek() == Colon {
    self.pos = self.pos + 1
    true
  } else {
    false
  }
  match self.peek() {
    Ident(name) => {
      self.pos = self.pos + 1
      let lower = name.to_lower()
      if is_element || is_legacy_element(lower) {
        Element(Simple(name))
      } else {
        Pseudo(Simple(name))
      }
    }
    Function(name) => {
      self.pos = self.pos + 1
      let args = self.take_group()
      let lower = name.to_lower()
      if is_element {
        if takes_selector_list(lower) {
          Element(Sub(name, self.owner.parse_selector_list(args, start)))
        } else {
          Element(Fn(name, self.owner.values_of(args)))
        }
      } else if takes_selector_list(lower) {
        Pseudo(Sub(name, self.owner.parse_selector_list(args, start)))
      } else if is_nth(lower) {
        self.parse_nth(name, args, from, start)
      } else if lower == "dir" {
        match first_ident(args) {
          Some(d) => Pseudo(Dir(d))
          None => Pseudo(Unknown(name, self.owner.values_of(args)))
        }
      } else if lower == "lang" {
        Pseudo(Lang(idents_of(args)))
      } else {
        Pseudo(Unknown(name, self.owner.values_of(args)))
      }
    }
    _ => {
      let at = self.here()
      Bogus(self.owner.bogus(BadPseudoClass(""), from, at))
    }
  }
}

///|
/// The tokens of the group that a `Function` token opened, up to its `)`.
fn SelCursor::take_group(self : SelCursor) -> ArrayView[@token.Token] {
  let from = self.pos
  let mut depth = 1
  while !self.at_end() {
    let k = self.peek()
    if k.is_opener() {
      depth = depth + 1
    } else if k == RParen {
      depth = depth - 1
      if depth == 0 {
        let out = self.toks[from:self.pos]
        self.pos = self.pos + 1
        return out
      }
    } else if k == RBracket || k == RBrace {
      if depth > 0 {
        depth = depth - 1
      }
    }
    self.pos = self.pos + 1
  }
  self.toks[from:self.pos]
}

///|
/// The four pseudo-elements CSS still spells with one colon, for compatibility
/// with stylesheets written before `::` existed.
fn is_legacy_element(name : String) -> Bool {
  name == "before" ||
  name == "after" ||
  name == "first-line" ||
  name == "first-letter"
}

///|
fn takes_selector_list(name : String) -> Bool {
  name == "is" ||
  name == "where" ||
  name == "not" ||
  name == "has" ||
  name == "matches" ||
  name == "any" ||
  name == "host" ||
  name == "host-context" ||
  name == "slotted" ||
  name == "current"
}

///|
fn is_nth(name : String) -> Bool {
  name == "nth-child" ||
  name == "nth-last-child" ||
  name == "nth-of-type" ||
  name == "nth-last-of-type" ||
  name == "nth-col" ||
  name == "nth-last-col"
}

///|
fn first_ident(toks : ArrayView[@token.Token]) -> String? {
  for t in toks {
    match t.kind {
      Ident(s) => return Some(s)
      _ => ()
    }
  }
  None
}

///|
fn idents_of(toks : ArrayView[@token.Token]) -> Array[String] {
  let out = []
  for t in toks {
    match t.kind {
      Ident(s) => out.push(s)
      Str(s) => out.push(s)
      _ => ()
    }
  }
  out
}
