///|
/// An opener-closer pair: `()`, `[]`, `{}`, `'…'`, and the `«»` that an `@`
/// splice uses.
fn Parser::parse_opener(
  self : Parser,
  t : @lexer.Token,
  i : Int,
  s : PState,
) -> GroupResult raise @err.ShrubberyError {
  self.check_block_mode(t, s)
  let at_initial = match s.at_mode {
    Some(am) => am.initial
    None => false
  }
  let (closer_text, kind, paren_immed) : (String, OpenerKind, ParenImmed) = match
    t.text {
    "(" =>
      (
        ")",
        KParens,
        // Immediately inside an `@` argument list, groups may be separated by
        // newlines instead of commas.
        if s.at_mode is Some(_) && !at_initial {
          AtArgs
        } else {
          Normal
        },
      )
    "{" => ("}", KBraces, Normal)
    "[" => ("]", KBrackets, Normal)
    "'" => ("'", KQuotes, NotImmed)
    "\u{AB}" =>
      if at_initial {
        ("\u{BB}", KAt, Normal)
      } else {
        self.fail(t, MisplacedGuillemet)
        ("\u{BB}", KAt, Normal)
      }
    _ => (")", KParens, Normal)
  }
  let pre_raw = s.raw
  let (group_commenting, a0) = self.next_of_commenting(
    i + 1,
    Some(t.line()),
    s.delta,
    RNil,
    s.count,
  )
  // `'«…»'` is a different `«»`: it disambiguates nested quotes and does NOT
  // turn off line sensitivity. The guillemets are not preserved.
  let quote_nested = kind is KQuotes &&
    group_commenting is None &&
    !self.at_end(a0.rest) &&
    self.tok(a0.rest).kind is Opener &&
    self.tok(a0.rest).text == "\u{AB}"
  let (a, use_closer) = if quote_nested {
    let g = self.tok(a0.rest)
    (
      self.next_of(a0.rest + 1, a0.last_line, a0.delta, a0.raw.push(g), s.count),
      "\u{BB}",
    )
  } else {
    (a0, closer_text)
  }
  let sub_column = if self.at_end(a.rest) {
    t.column().next()
  } else {
    self.tok(a.rest).column()
  }
  let inner = self.parse_groups(a.rest, {
    count: s.count,
    closer: Delim(use_closer, t),
    paren_immed,
    column: Some(sub_column),
    bar_column: None,
    check_column: s.count,
    bar_closes: false,
    bar_closes_line: None,
    // A group immediately inside an opener may not start with `|`.
    block_mode: Start,
    can_empty: true,
    comma_time: false,
    sequence_mode: if kind is KAt {
      OneOnly
    } else {
      AnyNumber
    },
    last_line: a.last_line,
    delta: a.delta,
    commenting: group_commenting,
    tail_commenting: None,
    raw: a.raw,
    variant: s.variant,
  })
  // Two closers need something after them.
  let (rest_i, close_line, close_delta, end_t, group_tail_raw) = if quote_nested {
    let b = self.next_of(
      inner.rest,
      inner.end_line,
      inner.end_delta,
      inner.tail_raw,
      s.count,
    )
    if !self.at_end(b.rest) &&
      self.tok(b.rest).kind is Closer &&
      self.tok(b.rest).text == "'" {
      let q = self.tok(b.rest)
      (b.rest + 1, b.last_line, b.delta, Some(q), b.raw.push(q))
    } else {
      match inner.end_token {
        Some(e) => self.fail(e, ExpectedQuoteAfterGuillemet)
        None => ()
      }
      (b.rest, b.last_line, b.delta, inner.end_token, b.raw)
    }
  } else if (match s.at_mode {
      Some(am) => am.splice
      None => false
    }) {
    // `@(«…»)`: the `(` was dropped when the splice was recognised, so the `)`
    // is consumed here.
    let post = self.peek(inner.rest)
    let ok = match post {
      Some(p) => p.kind is Closer && p.text == ")"
      None => false
    }
    if !ok {
      match inner.end_token {
        Some(e) => self.fail(e, ExpectedParenAfterGuillemet)
        None => ()
      }
    }
    match post {
      Some(p) =>
        (
          inner.rest + 1,
          inner.end_line,
          inner.end_delta,
          Some(p),
          inner.tail_raw.push(p),
        )
      None =>
        (
          inner.rest,
          inner.end_line,
          inner.end_delta,
          inner.end_token,
          inner.tail_raw,
        )
    }
  } else {
    (
      inner.rest,
      inner.end_line,
      inner.end_delta,
      inner.end_token,
      inner.tail_raw,
    )
  }
  let (suffix_raw, suffix_i, suffix_line, suffix_delta) = self.suffix_comments(
    rest_i, close_line, close_delta,
  )
  let cont = self.continue_at(
    s.at_mode,
    closer_text == ")",
    suffix_i,
    suffix_line,
    suffix_delta,
    s.count,
    s.variant,
  )
  let rest = self.parse_group(cont.rest, {
    ..s,
    line: cont.line,
    delta: cont.delta,
    block_mode: NoBlock,
    bar_closes_line: next_block_close_line(
      s.bar_closes_line,
      Some(t.line()),
      cont.line,
    ),
    raw: RNil,
    at_mode: cont.at_mode,
  })
  let children = to_group_nodes(inner.groups)
  let node = @ast.Node::new(
    match kind {
      KParens | KAt => Parens(children)
      KBrackets => Brackets(children)
      KBraces => Braces(children)
      KQuotes => Quotes(children)
    },
    span_of(t, end_t),
  )
  node.meta.prefix = pre_raw.to_raw()
  node.meta.raw = Str(t.raw_text())
  node.meta.tail = group_tail_raw.to_raw()
  node.meta.suffix = suffix_raw.to_raw()
  let items = [node]
  for x in rest.items {
    items.push(x)
  }
  let adjusted = (cont.adjust)(items)
  if kind is KAt {
    let (spliced, tail) = self.splice_at(t, adjusted, rest.tail_raw)
    return { ..rest, items: spliced, tail_raw: tail, }
  }
  { ..rest, items: adjusted, }
}

///|
priv enum OpenerKind {
  KParens
  KBrackets
  KBraces
  KQuotes
  /// The `«»` of an `@` splice, which becomes `parens` and is then spliced
  /// away.
  KAt
}
