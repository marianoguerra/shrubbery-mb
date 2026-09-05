///|
/// What `continue_at` answers: how to rewrite the items so far, and where to
/// carry on.
priv struct AtContinue {
  /// Rearranges the command, its arguments and its text into a call. The
  /// identity when there is no `@` form in play.
  adjust : (Array[@ast.Node]) -> Array[@ast.Node] raise @err.ShrubberyError
  at_mode : AtMode?
  rest : Int
  line : Int?
  delta : Int
}

///|
/// After a term inside an `@` form, look for what continues it.
///
/// `@f(a){b}` is one call: the command, then an argument list, then braced text
/// that becomes one more argument. This is where those three pieces are folded
/// together, which is why it runs after every term rather than at the `@`.
fn Parser::continue_at(
  self : Parser,
  am : AtMode?,
  after_paren : Bool,
  start : Int,
  line : Int?,
  delta : Int,
  count : Bool,
  variant : @lexer.Variant,
  depth : Int,
) -> AtContinue raise @err.ShrubberyError {
  let mode = match am {
    None => return { adjust: g => g, at_mode: None, rest: start, line, delta, }
    Some(m) => m
  }
  let next = self.peek(start)
  let is_arg_opener = (!after_paren || mode.initial) &&
    (match next {
      Some(t) => t.kind is Opener && (t.text == "(" || t.text == "[")
      None => false
    })
  if is_arg_opener {
    let t = next.unwrap()
    if t.text == "[" {
      // Taken as an argument list for consistency with S-expression `@`, and
      // rejected here rather than at the bracket, so the message is about the
      // mistake rather than about a stray bracket.
      self.fail(t, AtArgCannotStartBracket)
    }
    return {
      adjust: g => {
        if g.length() >= 2 && g[1].it is Parens(_) {
          at_call(mode, g[0], g[1], g[2:].to_owned())
        } else {
          g
        }
      },
      at_mode: Some(AtMode::new(stop_at_at=mode.stop_at_at)),
      rest: start,
      line,
      delta,
    }
  }
  let is_text = match next {
    Some(t) => t.kind is AtOpener
    None => false
  }
  if !is_text {
    return {
      adjust: g => {
        let out = []
        for x in mode.rev_prefix {
          out.push(x)
        }
        for x in g {
          out.push(x)
        }
        out
      },
      at_mode: if mode.stop_at_at {
        Some(AtMode::new(stop_at_at=true))
      } else {
        None
      },
      rest: start,
      line,
      delta,
    }
  }
  // One or more `{...}` bodies, each becoming a bracketed sequence of content.
  let init_t = next.unwrap()
  let args = []
  let mut i = start + 1
  let mut cur_line = line
  let mut cur_delta = delta
  let mut opener = init_t
  for ;; {
    let seq = self.parse_text_sequence(
      i,
      cur_line,
      cur_delta,
      Some(opener),
      count,
      variant,
      depth,
    )
    let group = @ast.Node::new(Group([seq.node]), seq.node.span)
    args.push(group)
    i = seq.rest
    cur_line = seq.line
    cur_delta = seq.delta
    // Another `{` immediately after the `}` is another text argument.
    if !self.at_end(i) && self.tok(i).kind is AtOpener {
      opener = self.tok(i)
      i = i + 1
      continue
    }
    break
  }
  let parens = @ast.Node::new(Parens(args), span_over(args, init_t.span))
  {
    adjust: g => {
      if g.length() == 0 {
        g
      } else if !after_paren || mode.initial || mode.rev_prefix.length() > 0 {
        at_call(mode, g[0], parens, g[1:].to_owned())
      } else {
        // The argument list is already there -- `@f(a){b}` -- so the text
        // becomes one MORE argument in it rather than a second parenthesised
        // group beside it.
        //
        // Its raw text has to be taken apart to match: the `(` becomes the new
        // node's prefix and the `)` moves onto the FIRST text argument, so that
        // `@f(a){b}` still prints its closer where it was written rather than
        // after the braces.
        let existing = g[0]
        let combined = existing.children()
        for a in args {
          combined.push(a)
        }
        if args.length() > 0 {
          let first = args[0]
          first.meta.prefix = existing.meta.tail
            .combine(existing.meta.suffix)
            .combine(first.meta.prefix)
        }
        let node = @ast.Node::new(Parens(combined), existing.span)
        node.meta.prefix = existing.meta.prefix
          .combine(existing.meta.inner_prefix)
          .combine(existing.meta.raw)
        let out = [node]
        for x in g[1:] {
          out.push(x)
        }
        out
      }
    },
    at_mode: Some(AtMode::new(stop_at_at=mode.stop_at_at)),
    rest: i,
    line: cur_line,
    delta: cur_delta,
  }
}

///|
/// Build `command(arg, ..., [text])` out of the pieces.
fn at_call(
  mode : AtMode,
  rator : @ast.Node,
  parens : @ast.Node,
  rest : Array[@ast.Node],
) -> Array[@ast.Node] {
  let out = []
  if !mode.initial {
    // `@{text}` with no command: the `@` itself is not a term, so it is
    // dropped and its text folded into the argument list's prefix, leaving
    // just the arguments.
    parens.meta.prefix = rator.meta.prefix
      .combine(rator.meta.raw)
      .combine(parens.meta.prefix)
    out.push(parens)
    for x in rest {
      out.push(x)
    }
    return out
  }
  // `rev_prefix` is in source order -- `a`, `.`, `b`, `.` for `@a.b.c` -- and
  // the command it belongs to comes after it.
  for x in mode.rev_prefix {
    out.push(x)
  }
  out.push(rator)
  out.push(parens)
  for x in rest {
    out.push(x)
  }
  out
}

///|
/// What `parse_text_sequence` answers.
priv struct TextSequence {
  node : @ast.Node
  rest : Int
  line : Int?
  delta : Int
}

///|
/// Read the body of a `{...}`, escapes and all, into a bracketed sequence.
fn Parser::parse_text_sequence(
  self : Parser,
  start : Int,
  line : Int?,
  delta : Int,
  opener_t : @lexer.Token?,
  count : Bool,
  variant : @lexer.Variant,
  depth : Int,
) -> TextSequence raise @err.ShrubberyError {
  let content : Array[ContentPiece] = []
  let mut i = start
  let mut cur_line = line
  let mut cur_delta = delta
  for ;; {
    if self.at_end(i) {
      match opener_t {
        Some(ot) => self.fail(ot, MissingCloserForAtContent)
        None => ()
      }
      break
    }
    let t = self.tok(i)
    match t.kind {
      AtCloser => break
      AtContent => {
        content.push(CText(t))
        i = i + 1
      }
      At | AtComment => {
        let comment = t.kind is AtComment
        // An `@//` inside a body is an `@` as far as the grammar goes; only
        // what becomes of the result differs. The reference renames the token;
        // calling the `@` arm directly says the same thing without rewriting
        // the stream.
        let g = self.parse_at(t, i, {
          // The body is a nesting level of its own: an `@` inside it opens
          // another sequence on top of this one.
          depth: depth + 1,
          count,
          line: Some(t.line()),
          column: Some(t.column()),
          bar_column: None,
          operator_column: None,
          bar_closes: false,
          bar_closes_line: None,
          block_mode: NoBlock,
          can_empty: false,
          delta: 0,
          raw: RNil,
          at_mode: Some(AtMode::new(initial=true, stop_at_next_at=true)),
          variant,
        })
        if comment {
          // The `@//` is already inside the group: `keep` made it the element's
          // own raw, and folding a call's operator into its argument list put
          // it in front of them. Prepending it again would print it twice.
          content.push(CComment(group_source(g.items)))
        } else {
          content.push(
            CGroup(@ast.Node::new(Group(g.items), span_over(g.items, t.span))),
          )
        }
        i = g.rest
        cur_line = g.end_line
        cur_delta = g.end_delta
      }
      Comment => {
        content.push(CComment(Str(t.raw_text())))
        i = i + 1
      }
      _ => break
    }
  }
  let closer = self.peek(i)
  let (prefix_raw, pieces, suffix_raw) = adjust_content_space(content)
  let span = match (opener_t, closer) {
    (Some(o), Some(c)) => span_of(o, Some(c))
    (Some(o), None) => o.span
    (None, Some(c)) => c.span
    (None, None) => @basic.Span::at(@basic.start)
  }
  let node = @ast.Node::new(Brackets(pieces), span)
  match opener_t {
    Some(o) => node.meta.raw = Str(o.raw_text())
    None => ()
  }
  // The whitespace the conversion took off the FRONT belongs in front of the
  // first piece of content, not at the end of the body. With no content left
  // there is nowhere else for it to go, so it joins the tail.
  if pieces.length() > 0 {
    pieces[0].meta.prefix = prefix_raw.combine(pieces[0].meta.prefix)
  }
  let lead : @raw.Raw = if pieces.length() > 0 { Empty } else { prefix_raw }
  let closer_raw : @raw.Raw = match closer {
    Some(c) => Str(c.raw_text())
    None => Empty
  }
  node.meta.tail = lead.combine(suffix_raw).combine(closer_raw)
  let end_line = match closer {
    Some(c) => Some(c.line())
    None => cur_line
  }
  {
    node,
    rest: if closer is Some(_) {
      i + 1
    } else {
      i
    },
    line: end_line,
    delta: if end_line == cur_line {
      cur_delta
    } else {
      0
    },
  }
}

///|
/// One piece of a text body before whitespace is adjusted.
priv enum ContentPiece {
  CText(@lexer.Token)
  CGroup(@ast.Node)
  CComment(@raw.Raw)
}

///|
/// `@(«...»)`: splice the command in with no parentheses around it.
fn Parser::splice_at(
  self : Parser,
  t : @lexer.Token,
  g : Array[@ast.Node],
  tail_raw : RawList,
) -> (Array[@ast.Node], RawList) raise @err.ShrubberyError {
  if g.length() == 0 {
    return (g, tail_raw)
  }
  let at_node = g[0]
  let groups = at_node.children()
  if groups.length() == 0 {
    self.fail(t, EmptyGroupAfterAt)
    return (g, tail_raw)
  }
  let inner = groups[0].children()
  let rest = g[1:].to_owned()
  if rest.length() > 0 && inner.length() > 0 {
    let last = inner[inner.length() - 1]
    match last.it {
      Block(_) | Alts(_) => self.fail(t, BlockAfterMidGroupAt)
      _ => ()
    }
  }
  let out = []
  for x in inner {
    out.push(x)
  }
  for x in rest {
    out.push(x)
  }
  if out.length() > 0 {
    out[0].meta.prefix = at_node.meta.prefix
      .combine(at_node.meta.inner_prefix)
      .combine(at_node.meta.raw)
      .combine(out[0].meta.prefix)
  }
  // The `»` and whatever followed it: onto the term after the splice if there
  // is one, and otherwise into the raw the caller carries forward.
  let closing = at_node.meta.tail.combine(at_node.meta.suffix)
  if rest.length() > 0 {
    rest[0].meta.prefix = closing.combine(rest[0].meta.prefix)
    (out, tail_raw)
  } else {
    // The closer comes BEFORE whatever else was trailing, not after it.
    (out, RNil.push_text(closing).then(tail_raw))
  }
}
