///|
/// Turning a token slice into values, and the `An+B` micro-syntax.
///
/// Both are needed in two places -- inside a pseudo-class's arguments and
/// inside an at-rule's prelude -- which is why they read a slice rather than
/// the main cursor.

///|
/// A token slice as component values, dropping trivia.
///
/// This is the fallback path: it is what an unknown at-rule's prelude and an
/// unknown pseudo-class's arguments become. Nothing is interpreted, so nothing
/// can be interpreted wrongly, and the printer can put back what it was given.
fn Parser::values_of(
  self : Parser,
  toks : ArrayView[@token.Token],
) -> Array[@ast.ComponentValue] {
  ignore(self)
  values_of_view(toks)
}

///|
fn values_of_view(toks : ArrayView[@token.Token]) -> Array[@ast.ComponentValue] {
  let c = { toks, pos: 0, }
  let out = c.values_until(Eof)
  out
}

///|
priv struct ValCursor {
  toks : ArrayView[@token.Token]
  mut pos : Int
}

///|
fn ValCursor::at_end(self : ValCursor) -> Bool {
  self.pos >= self.toks.length()
}

///|
fn ValCursor::values_until(
  self : ValCursor,
  closer : @token.TokenKind,
) -> Array[@ast.ComponentValue] {
  let out : Array[@ast.ComponentValue] = []
  while !self.at_end() {
    let t = self.toks[self.pos]
    if t.kind == closer {
      self.pos = self.pos + 1
      trim_trailing(out)
      return out
    }
    if t.is_trivia() {
      self.pos = self.pos + 1
      continue
    }
    self.pos = self.pos + 1
    let v : @ast.ComponentValue = match t.kind {
      Ident(s) => Ident(s)
      Str(s) => Str(s)
      Url(u) => Url(u)
      Number(r, v, i) => Num({ repr: r, value: v, is_int: i, })
      Percentage(r, v) => Percentage({ repr: r, value: v, is_int: false, })
      Dimension(r, v, i, u) => Dimension({ repr: r, value: v, is_int: i, }, u)
      Hash(d, _) => Hex(d)
      Comma => Comma
      Colon => Delim(":")
      Semicolon => Delim(";")
      Delim('/') => Slash
      Delim(c) => Delim(c.to_string())
      Function(name) => {
        let args = self.values_until(RParen)
        if name.to_lower() == "url" && args.length() == 1 {
          match args[0] {
            Str(s) => Url(s)
            _ => Function(name, args)
          }
        } else {
          Function(name, args)
        }
      }
      LParen => Paren(self.values_until(RParen))
      LBracket => Bracket(self.values_until(RBracket))
      BadStr => Bogus(@ast.Bogus::new(UnterminatedString, t.span, text=""))
      BadUrl => Bogus(@ast.Bogus::new(BadUrl, t.span, text=""))
      _ => Bogus(@ast.Bogus::new(Unexpected("a value"), t.span, text=""))
    }
    out.push(v)
  }
  trim_trailing(out)
  out
}

// ------------------------------------------------------------------- An+B

///|
/// `An+B`, and the optional `of <selector-list>` after it.
///
/// The shapes are awkward because the tokenizer, correctly, does not know this
/// syntax exists: `2n+1` arrives as a dimension with unit `n` followed by the
/// number `+1`, while `2n - 1` arrives as a dimension, a delimiter and a
/// number. Both mean the same thing, so both are listed.
fn SelCursor::parse_nth(
  self : SelCursor,
  name : String,
  toks : ArrayView[@token.Token],
  from : Int,
  start : Int,
) -> @ast.Qualifier raise @err.CssError {
  // Split off an `of` clause first, so the formula sees only its own tokens.
  let mut of_at = -1
  let mut depth = 0
  for i, t in toks {
    let k = t.kind
    if k.is_opener() {
      depth = depth + 1
    } else if k == RParen || k == RBracket {
      if depth > 0 {
        depth = depth - 1
      }
    } else if depth == 0 {
      match k {
        Ident(w) => if w.to_lower() == "of" && of_at < 0 { of_at = i }
        _ => ()
      }
    }
  }
  let (formula, of_toks) = if of_at >= 0 {
    (toks[0:of_at], Some(toks[of_at + 1:]))
  } else {
    (toks, None)
  }
  match parse_anb(formula) {
    Some(anb) => {
      let of_ = match of_toks {
        Some(t) => Some(self.owner.parse_selector_list(t, start))
        None => None
      }
      Pseudo(Nth(name, anb, of_))
    }
    None => {
      let at = self.here()
      let _ = self.owner.bogus(BadAnB, from, at)
      Pseudo(Unknown(name, values_of_view(toks)))
    }
  }
}

///|
/// The formula itself.
fn parse_anb(toks : ArrayView[@token.Token]) -> @ast.AnB? {
  // Meaningful tokens only; whitespace never changes what a formula means.
  let ts : Array[@token.TokenKind] = []
  for t in toks {
    if !t.is_trivia() {
      ts.push(t.kind)
    }
  }
  match ts {
    [Ident(w)] => {
      let l = w.to_lower()
      if l == "odd" {
        Some({ a: 2, b: 1, })
      } else if l == "even" {
        Some({ a: 2, b: 0, })
      } else {
        // A bare `n`, `-n`, or `+n`.
        match n_coefficient(l) {
          Some(a) => Some({ a, b: 0, })
          None => None
        }
      }
    }
    [Number(_, v, true)] => Some({ a: 0, b: v.to_int(), })
    [Dimension(_, v, true, u)] =>
      if u.to_lower() == "n" {
        Some({ a: v.to_int(), b: 0, })
      } else {
        None
      }
    // `2n+1`, `2n-1` when the sign fused with the second number.
    [Dimension(_, v, true, u), Number(r, b, true)] =>
      if u.to_lower() == "n" && has_sign(r) {
        Some({ a: v.to_int(), b: b.to_int(), })
      } else {
        None
      }
    // `n+1`, `-n+3`.
    [Ident(w), Number(r, b, true)] =>
      match n_coefficient(w.to_lower()) {
        Some(a) if has_sign(r) => Some({ a, b: b.to_int(), })
        _ => None
      }
    // `2n - 1`, with the sign as its own delimiter.
    [Dimension(_, v, true, u), Delim(s), Number(_, b, true)] =>
      if u.to_lower() == "n" && (s == '+' || s == '-') {
        let bb = if s == '-' { -b.to_int() } else { b.to_int() }
        Some({ a: v.to_int(), b: bb, })
      } else {
        None
      }
    [Ident(w), Delim(s), Number(_, b, true)] =>
      match n_coefficient(w.to_lower()) {
        Some(a) if s == '+' || s == '-' => {
          let bb = if s == '-' { -b.to_int() } else { b.to_int() }
          Some({ a, b: bb, })
        }
        _ => None
      }
    _ => None
  }
}

///|
/// `n` is 1, `-n` is -1, `+n` is 1; anything else is not a coefficient.
fn n_coefficient(w : String) -> Int? {
  if w == "n" {
    Some(1)
  } else if w == "-n" {
    Some(-1)
  } else if w == "+n" {
    Some(1)
  } else {
    None
  }
}

///|
/// Whether a number's source spelling carried an explicit sign.
///
/// It has to, in `2n+1`: without a sign the `1` is a separate value and the
/// formula is malformed, which is exactly the distinction the tokenizer keeps
/// `repr` around for.
fn has_sign(repr : String) -> Bool {
  repr.has_prefix("+") || repr.has_prefix("-")
}
