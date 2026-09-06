///|
/// Media queries, `@supports` conditions, and the small prelude helpers.
///
/// `@media`, `@supports` and `@container` share one condition grammar, which is
/// why they share one parser here. lightningcss generalises the same way, and
/// it is worth copying: the three diverge only in what a leaf may be.

///|
/// What a leaf of a condition is allowed to be.
priv enum CondKind {
  /// `@media`, `@container`: a leaf is a feature test.
  Query
  /// `@supports`: a leaf may also be a declaration or `selector(...)`.
  Supports
} derive(Eq)

///|
fn Parser::parse_media_list(
  self : Parser,
  toks : ArrayView[@token.Token],
  start : Int,
) -> Array[@ast.MediaQuery] raise @err.CssError {
  let out : Array[@ast.MediaQuery] = []
  if only_trivia(toks) {
    return out
  }
  for part in split_top(toks, Comma) {
    out.push(self.parse_media_query(part, start))
  }
  out
}

///|
fn Parser::parse_media_query(
  self : Parser,
  toks : ArrayView[@token.Token],
  start : Int,
) -> @ast.MediaQuery raise @err.CssError {
  let c = { toks, pos: 0, }
  let mut qualifier : @ast.MediaQualifier? = None
  let mut media_type : String? = None
  let save = c.pos
  match c.next_meaningful() {
    Some(Ident(w)) => {
      let l = w.to_lower()
      if l == "only" {
        qualifier = Some(Only)
      } else if l == "not" {
        // `not` is a qualifier only when a media type follows it; otherwise it
        // negates a condition and belongs to the condition grammar.
        match c.next_meaningful() {
          Some(Ident(t)) if !is_logical(t) => {
            qualifier = Some(Not)
            media_type = Some(t)
          }
          _ => c.pos = save
        }
      } else if !is_logical(l) {
        media_type = Some(w)
      } else {
        c.pos = save
      }
    }
    _ => c.pos = save
  }
  if qualifier is Some(Only) {
    match c.next_meaningful() {
      Some(Ident(t)) => media_type = Some(t)
      _ => ()
    }
  }
  // What is left is the condition, minus a leading `and`.
  let mut rest = c.rest()
  match first_meaningful(rest) {
    Some(Ident(w)) if w.to_lower() == "and" =>
      rest = drop_first_meaningful(rest)
    _ => ()
  }
  let condition = if only_trivia(rest) {
    None
  } else {
    Some(self.parse_cond(rest, start, Query))
  }
  { qualifier, media_type, condition, }
}

///|
fn is_logical(w : String) -> Bool {
  let l = w.to_lower()
  l == "and" || l == "or" || l == "not"
}

///|
/// A `@supports` condition.
fn Parser::parse_condition(
  self : Parser,
  toks : ArrayView[@token.Token],
  start : Int,
) -> @ast.Condition raise @err.CssError {
  self.parse_cond(toks, start, Supports)
}

///|
fn Parser::parse_cond(
  self : Parser,
  toks : ArrayView[@token.Token],
  start : Int,
  kind : CondKind,
) -> @ast.Condition raise @err.CssError {
  if only_trivia(toks) {
    return Bogus(self.bogus_view(BadSupportsCondition, toks, start))
  }
  // `and` and `or` may not be mixed without parentheses, and CSS says so too,
  // so this is a diagnostic rather than a precedence decision.
  let ands = split_on_word(toks, "and")
  let ors = split_on_word(toks, "or")
  if ands.length() > 1 && ors.length() > 1 {
    self.error(MixedLogicalOps, span_of_view(toks, start))
    return Bogus(self.bogus_view(MixedLogicalOps, toks, start))
  }
  if ands.length() > 1 {
    let conds = []
    for part in ands {
      flatten_into(conds, self.parse_cond(part, start, kind), And)
    }
    return Operation(And, conds)
  }
  if ors.length() > 1 {
    let conds = []
    for part in ors {
      flatten_into(conds, self.parse_cond(part, start, kind), Or)
    }
    return Operation(Or, conds)
  }
  // A single term, possibly negated.
  match first_meaningful(toks) {
    Some(Ident(w)) if w.to_lower() == "not" => {
      let inner = drop_first_meaningful(toks)
      return Operation(Not, [self.parse_cond(inner, start, kind)])
    }
    _ => ()
  }
  self.parse_cond_leaf(toks, start, kind)
}

///|
/// Fold a nested operation of the same operator into its parent.
///
/// Keeping the tree flat is what makes the round-trip property an equality
/// rather than an equality-up-to-associativity, which would need a normaliser
/// in every test.
fn flatten_into(
  out : Array[@ast.Condition],
  c : @ast.Condition,
  op : @ast.LogicalOp,
) -> Unit {
  match c {
    Operation(o, inner) if o == op =>
      for x in inner {
        out.push(x)
      }
    _ => out.push(c)
  }
}

///|
fn Parser::parse_cond_leaf(
  self : Parser,
  toks : ArrayView[@token.Token],
  start : Int,
  kind : CondKind,
) -> @ast.Condition raise @err.CssError {
  let c = { toks, pos: 0, }
  match c.next_meaningful() {
    Some(LParen) => {
      let inner = c.take_group_paren()
      if !only_trivia(c.rest()) {
        // Something after the closing paren that is not a logical operator.
        return Unknown(values_of_view(toks))
      }
      // A parenthesised group is either a nested condition or a feature; a
      // nested one is recognised by containing a `(` or a logical word.
      if contains_group_or_logical(inner) {
        return self.parse_cond(inner, start, kind)
      }
      self.parse_feature(inner, start, kind)
    }
    Some(Function(f)) => {
      let args = c.take_group()
      let l = f.to_lower()
      if kind == Supports && l == "selector" {
        return SelectorFn(self.parse_selector_list(args, start))
      }
      Unknown(values_of_view(toks))
    }
    _ => Unknown(values_of_view(toks))
  }
}

///|
/// Whether a parenthesised body is itself a condition rather than a feature.
fn contains_group_or_logical(toks : ArrayView[@token.Token]) -> Bool {
  let mut depth = 0
  for t in toks {
    let k = t.kind
    if k == LParen {
      if depth == 0 {
        return true
      }
      depth = depth + 1
    } else if k.is_opener() {
      depth = depth + 1
    } else if k == RParen || k == RBracket {
      if depth > 0 {
        depth = depth - 1
      }
    } else if depth == 0 {
      match k {
        Ident(w) => if is_logical(w) { return true }
        _ => ()
      }
    }
  }
  false
}

///|
/// The four shapes a feature test comes in.
fn Parser::parse_feature(
  self : Parser,
  toks : ArrayView[@token.Token],
  start : Int,
  kind : CondKind,
) -> @ast.Condition raise @err.CssError {
  // `(display: grid)` inside `@supports` is a declaration, not a feature.
  if kind == Supports && has_top_colon(toks) {
    let sub = {
      src: self.src,
      toks: to_owned_with_eof(toks),
      pos: 0,
      diags: self.diags,
      strict: self.strict,
    }
    match sub.parse_declaration() {
      Some(d) => return Decl(d)
      None => return Unknown(values_of_view(toks))
    }
  }
  // `(name: value)`
  let colon = top_index(toks, Colon)
  if colon >= 0 {
    let name = match first_meaningful(toks[0:colon]) {
      Some(Ident(n)) => n
      _ => return Unknown(values_of_view(toks))
    }
    return Feature(Plain(name, values_of_view(toks[colon + 1:])))
  }
  // A range: one or two comparison operators around a name.
  let ops = range_ops(toks)
  match ops.length() {
    0 =>
      match first_meaningful(toks) {
        Some(Ident(n)) if only_one_meaningful(toks) => Feature(Boolean(n))
        _ => Unknown(values_of_view(toks))
      }
    1 => {
      let (at, op, width) = ops[0]
      let left = toks[0:at]
      let right = toks[at + width:]
      match first_meaningful(left) {
        Some(Ident(n)) if only_one_meaningful(left) =>
          Feature(Range(n, op, values_of_view(right)))
        _ =>
          // The name is on the right: `40rem >= width` means `width <= 40rem`.
          match first_meaningful(right) {
            Some(Ident(n)) if only_one_meaningful(right) =>
              Feature(Range(n, flip(op), values_of_view(left)))
            _ => Unknown(values_of_view(toks))
          }
      }
    }
    2 => {
      let (a1, op1, w1) = ops[0]
      let (a2, op2, w2) = ops[1]
      let lo = toks[0:a1]
      let mid = toks[a1 + w1:a2]
      let hi = toks[a2 + w2:]
      match first_meaningful(mid) {
        Some(Ident(n)) =>
          Feature(Interval(values_of_view(lo), op1, n, op2, values_of_view(hi)))
        _ => Unknown(values_of_view(toks))
      }
    }
    _ => {
      self.error(BadMediaQuery, span_of_view(toks, start))
      Unknown(values_of_view(toks))
    }
  }
}

///|
fn flip(op : @ast.RangeOp) -> @ast.RangeOp {
  match op {
    Lt => Gt
    Le => Ge
    Gt => Lt
    Ge => Le
    Eq => Eq
  }
}

///|
/// The comparison operators at the top level, with their index and token width.
///
/// `<=` is two delimiters, because the tokenizer does not fuse them -- outside
/// a media query those two characters are unrelated.
fn range_ops(toks : ArrayView[@token.Token]) -> Array[(Int, @ast.RangeOp, Int)] {
  let out : Array[(Int, @ast.RangeOp, Int)] = []
  let mut depth = 0
  let mut i = 0
  while i < toks.length() {
    let k = toks[i].kind
    if k.is_opener() {
      depth = depth + 1
    } else if k == RParen || k == RBracket {
      if depth > 0 {
        depth = depth - 1
      }
    } else if depth == 0 {
      let nxt = if i + 1 < toks.length() { toks[i + 1].kind } else { Eof }
      match k {
        Delim('<') =>
          if nxt == Delim('=') {
            out.push((i, Le, 2))
            i = i + 1
          } else {
            out.push((i, Lt, 1))
          }
        Delim('>') =>
          if nxt == Delim('=') {
            out.push((i, Ge, 2))
            i = i + 1
          } else {
            out.push((i, Gt, 1))
          }
        Delim('=') => out.push((i, Eq, 1))
        _ => ()
      }
    }
    i = i + 1
  }
  out
}

// ------------------------------------------------------------------ helpers

///|
fn only_trivia(toks : ArrayView[@token.Token]) -> Bool {
  for t in toks {
    if !t.is_trivia() {
      return false
    }
  }
  true
}

///|
fn only_one_meaningful(toks : ArrayView[@token.Token]) -> Bool {
  let mut n = 0
  for t in toks {
    if !t.is_trivia() {
      n = n + 1
    }
  }
  n == 1
}

///|
fn has_top_colon(toks : ArrayView[@token.Token]) -> Bool {
  top_index(toks, Colon) >= 0
}

///|
fn top_index(toks : ArrayView[@token.Token], what : @token.TokenKind) -> Int {
  let mut depth = 0
  for i, t in toks {
    let k = t.kind
    if k.is_opener() {
      depth = depth + 1
    } else if k == RParen || k == RBracket || k == RBrace {
      if depth > 0 {
        depth = depth - 1
      }
    } else if depth == 0 && k == what {
      return i
    }
  }
  -1
}

///|
fn split_top(
  toks : ArrayView[@token.Token],
  sep : @token.TokenKind,
) -> Array[ArrayView[@token.Token]] {
  let out : Array[ArrayView[@token.Token]] = []
  let mut from = 0
  let mut depth = 0
  for i, t in toks {
    let k = t.kind
    if k.is_opener() {
      depth = depth + 1
    } else if k == RParen || k == RBracket || k == RBrace {
      if depth > 0 {
        depth = depth - 1
      }
    } else if depth == 0 && k == sep {
      out.push(toks[from:i])
      from = i + 1
    }
  }
  out.push(toks[from:])
  out
}

///|
fn split_on_word(
  toks : ArrayView[@token.Token],
  word : String,
) -> Array[ArrayView[@token.Token]] {
  let out : Array[ArrayView[@token.Token]] = []
  let mut from = 0
  let mut depth = 0
  for i, t in toks {
    let k = t.kind
    if k.is_opener() {
      depth = depth + 1
    } else if k == RParen || k == RBracket || k == RBrace {
      if depth > 0 {
        depth = depth - 1
      }
    } else if depth == 0 {
      match k {
        Ident(w) =>
          if w.to_lower() == word {
            out.push(toks[from:i])
            from = i + 1
          }
        _ => ()
      }
    }
  }
  out.push(toks[from:])
  out
}

///|
fn drop_first_meaningful(
  toks : ArrayView[@token.Token],
) -> ArrayView[@token.Token] {
  for i, t in toks {
    if !t.is_trivia() {
      return toks[i + 1:]
    }
  }
  toks[toks.length():]
}

///|
fn Parser::bogus_view(
  self : Parser,
  kind : @kind.ErrorKind,
  toks : ArrayView[@token.Token],
  start : Int,
) -> @ast.Bogus raise @err.CssError {
  let sp = span_of_view(toks, start)
  self.bogus(kind, sp.start, sp.end)
}

///|
/// A token view, copied into an owned array with an `Eof` on the end.
///
/// Needed where a sub-parser has to run over a slice: `Parser` reads
/// `self.toks[self.pos]` unguarded and relies on `Eof` being there, which a
/// bare slice does not have.
fn to_owned_with_eof(toks : ArrayView[@token.Token]) -> Array[@token.Token] {
  let out = []
  for t in toks {
    out.push(t)
  }
  let at = if toks.length() == 0 { 0 } else { toks[toks.length() - 1].span.end }
  out.push({ kind: Eof, span: @span.Span::at(at), })
  out
}

// ------------------------------------------------------- ValCursor extras

///|
fn ValCursor::next_meaningful(self : ValCursor) -> @token.TokenKind? {
  while !self.at_end() {
    let t = self.toks[self.pos]
    self.pos = self.pos + 1
    if !t.is_trivia() {
      return Some(t.kind)
    }
  }
  None
}

///|
fn ValCursor::rest(self : ValCursor) -> ArrayView[@token.Token] {
  self.toks[self.pos:]
}

///|
/// Positioned just after a `Function` token: its arguments, up to the `)`.
fn ValCursor::take_group(self : ValCursor) -> ArrayView[@token.Token] {
  let from = self.pos
  let mut depth = 1
  while !self.at_end() {
    let k = self.toks[self.pos].kind
    if k.is_opener() {
      depth = depth + 1
    } else if k == RParen {
      depth = depth - 1
      if depth == 0 {
        let out = self.toks[from:self.pos]
        self.pos = self.pos + 1
        return out
      }
    }
    self.pos = self.pos + 1
  }
  self.toks[from:self.pos]
}

///|
/// Positioned just after a `LParen`.
fn ValCursor::take_group_paren(self : ValCursor) -> ArrayView[@token.Token] {
  self.take_group()
}

// --------------------------------------------------- small prelude readers

///|
fn split_container_name(
  toks : ArrayView[@token.Token],
) -> (String?, ArrayView[@token.Token]) {
  for i, t in toks {
    if t.is_trivia() {
      continue
    }
    match t.kind {
      // A bare leading identifier that is not a logical word is the container
      // name; anything else means the prelude is all condition.
      Ident(w) =>
        if is_logical(w) {
          return (None, toks)
        } else {
          return (Some(w), toks[i + 1:])
        }
      _ => return (None, toks)
    }
  }
  (None, toks)
}

///|
fn page_selectors(toks : ArrayView[@token.Token]) -> Array[String] {
  let out = []
  let buf = StringBuilder()
  for t in toks {
    match t.kind {
      Comma => {
        let s = buf.to_string()
        if s != "" {
          out.push(s)
        }
        buf.reset()
      }
      Ident(n) => buf.write_string(n)
      Colon => buf.write_string(":")
      Whitespace | Comment(_) => ()
      _ => ()
    }
  }
  let s = buf.to_string()
  if s != "" {
    out.push(s)
  }
  out
}

///|
fn layer_names(toks : ArrayView[@token.Token]) -> Array[@ast.LayerName] {
  let out : Array[@ast.LayerName] = []
  for part in split_top(toks, Comma) {
    let parts = layer_parts(part)
    if parts.length() > 0 {
      out.push({ parts, })
    }
  }
  out
}

///|
fn layer_parts(toks : ArrayView[@token.Token]) -> Array[String] {
  let out = []
  for t in toks {
    match t.kind {
      Ident(n) => out.push(n)
      _ => ()
    }
  }
  out
}

///|
fn namespace_parts(toks : ArrayView[@token.Token]) -> (String?, String?) {
  let c = { toks, pos: 0, }
  match c.next_meaningful() {
    Some(Str(u)) => (None, Some(u))
    Some(Url(u)) => (None, Some(u))
    Some(Ident(p)) =>
      match c.next_meaningful() {
        Some(Str(u)) => (Some(p), Some(u))
        Some(Url(u)) => (Some(p), Some(u))
        _ => (Some(p), None)
      }
    _ => (None, None)
  }
}

///|
/// `@scope (start) to (end)`, either half optional.
fn Parser::split_scope(
  self : Parser,
  toks : ArrayView[@token.Token],
  start : Int,
) -> (Array[@ast.Selector]?, Array[@ast.Selector]?) raise @err.CssError {
  let c = { toks, pos: 0, }
  let mut s : Array[@ast.Selector]? = None
  let mut e : Array[@ast.Selector]? = None
  while true {
    match c.next_meaningful() {
      None => break
      Some(LParen) => {
        let inner = c.take_group_paren()
        if s is None {
          s = Some(self.parse_selector_list(inner, start))
        } else {
          e = Some(self.parse_selector_list(inner, start))
        }
      }
      Some(Ident(_)) => ()
      Some(_) => ()
    }
  }
  (s, e)
}
