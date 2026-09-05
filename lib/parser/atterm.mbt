///|
/// An `@` at the head of a term.
///
/// The `@` itself contributes nothing to the tree — it becomes the shape of
/// the call around what follows — so this arm's job is to decide what KIND of
/// form is starting and hand `parse_group` the right mode for it.
fn Parser::parse_at(
  self : Parser,
  t : @lexer.Token,
  i : Int,
  s : PState,
) -> GroupResult raise @err.ShrubberyError {
  self.check_block_mode(t, s)
  match s.at_mode {
    Some(am) if am.stop_at_at =>
      return {
        items: [],
        rest: i,
        end_line: s.line,
        end_delta: s.delta,
        tail_commenting: None,
        tail_raw: s.raw,
      }
    _ => ()
  }
  if self.at_end(i + 1) {
    self.fail(t, MissingTermAfterAt)
    return {
      items: [],
      rest: i + 1,
      end_line: s.line,
      end_delta: s.delta,
      tail_commenting: None,
      tail_raw: s.raw.push(t),
    }
  }
  let next_t = self.tok(i + 1)
  self.check_same_line(t, next_t, s.count)
  let stop_at_next_at = match s.at_mode {
    Some(am) => am.stop_at_next_at
    None => false
  }
  let raw_with_at = s.raw.push(t)
  match next_t.kind {
    Opener => {
      // `@(«...»)` splices its command and takes no arguments. The `(` is
      // dropped here and the `»` handler consumes the matching `)`.
      if next_t.text == "(" &&
        !self.at_end(i + 2) &&
        self.tok(i + 2).kind is Opener &&
        self.tok(i + 2).text == "\u{AB}" {
        return self.parse_group(i + 2, {
          ..s,
          raw: raw_with_at.push(next_t),
          at_mode: Some(
            AtMode::new(initial=true, splice=true, stop_at_at=stop_at_next_at),
          ),
        })
      }
      self.parse_group(i + 1, {
        ..s,
        raw: raw_with_at,
        at_mode: Some(AtMode::new(initial=true, stop_at_at=stop_at_next_at)),
      })
    }
    Identifier => {
      // `@a.b.c`: identifier and operator alternating, with no space between,
      // is one command. The pairs are collected here so that the call is built
      // around the whole chain rather than around its first name.
      let rev_prefix : Array[@ast.Node] = []
      let mut j = i + 1
      let mut raw = raw_with_at
      for ;; {
        if j + 2 < self.toks.length() &&
          self.tok(j + 1).kind is Operator &&
          is_identifier_like(self.tok(j + 2)) {
          let id = leaf_of(self.tok(j))
          id.meta.prefix = raw.to_raw()
          let op = leaf_of(self.tok(j + 1))
          // Source order: the chain reads `a . b . c`.
          rev_prefix.push(id)
          rev_prefix.push(op)
          j = j + 2
          raw = RNil
          continue
        }
        break
      }
      self.parse_group(j, {
        ..s,
        raw,
        at_mode: Some(
          AtMode::new(initial=true, rev_prefix~, stop_at_at=stop_at_next_at),
        ),
      })
    }
    Literal(_) | Operator | Keyword | SExp(_) =>
      self.parse_group(i + 1, {
        ..s,
        raw: raw_with_at,
        at_mode: Some(AtMode::new(initial=true, stop_at_at=stop_at_next_at)),
      })
    AtOpener =>
      self.keep(
        i,
        s,
        at_mode=Some(AtMode::new(stop_at_at=stop_at_next_at)),
        suffix=false,
      )
    Whitespace => {
      self.fail(next_t, WhitespaceAfterAt)
      {
        items: [],
        rest: i + 1,
        end_line: s.line,
        end_delta: s.delta,
        tail_commenting: None,
        tail_raw: raw_with_at,
      }
    }
    _ => {
      // A token the LEXER already rejected reports its own error rather than a
      // complaint about the `@`. The reference reads the term after an `@`
      // through the lexer, so `@` immediately before a `}` is a read error at
      // the `}`; only a token that lexed cleanly and is merely in the wrong
      // place is "invalid after `@`".
      match next_t.kind {
        Fail(kind) => self.fail(next_t, kind)
        _ => self.fail(next_t, InvalidAfterAt)
      }
      {
        items: [],
        rest: i + 1,
        end_line: s.line,
        end_delta: s.delta,
        tail_commenting: None,
        tail_raw: raw_with_at,
      }
    }
  }
}

///|
fn is_identifier_like(t : @lexer.Token) -> Bool {
  match t.kind {
    Identifier | Keyword => true
    _ => false
  }
}
