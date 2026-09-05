///|
/// `; «...»`: a group sequence written without line or column sensitivity,
/// spliced into the enclosing sequence.
fn Parser::parse_splice(
  self : Parser,
  t : @lexer.Token,
  a : Advance,
  sg : GState,
) -> GroupsResult raise @err.ShrubberyError {
  let next_t = self.tok(a.rest)
  self.check_same_line(t, next_t, sg.count)
  let (group_commenting, b) = self.next_of_commenting(
    a.rest + 1,
    a.last_line,
    a.delta,
    a.raw.push(next_t),
    sg.count,
  )
  let inner = self.parse_groups(b.rest, {
    count: false,
    closer: Delim("\u{BB}", next_t),
    paren_immed: NotImmed,
    column: None,
    bar_column: None,
    check_column: false,
    bar_closes: false,
    bar_closes_line: None,
    block_mode: NoBlock,
    can_empty: false,
    comma_time: false,
    sequence_mode: AnyNumber,
    last_line: b.last_line,
    delta: b.delta,
    commenting: group_commenting,
    tail_commenting: None,
    raw: b.raw,
    variant: sg.variant,
  })
  if sg.paren_immed.is_immed() && inner.groups.length() != 1 {
    self.fail(t, MultiGroupSpliceNotAllowed)
  }
  let more = self.parse_groups(inner.rest, {
    ..sg,
    comma_time: sg.paren_immed.is_immed(),
    check_column: self.next_line(inner.rest, inner.end_line, sg.count),
    column: Some(sg.column.unwrap_or(t.column())),
    bar_column: None,
    last_line: inner.end_line,
    delta: inner.end_delta,
    commenting: None,
    tail_commenting: None,
    block_mode: next_group_block_mode(sg.block_mode),
    can_empty: false,
    raw: inner.tail_raw,
  })
  let groups = inner.groups
  for g in more.groups {
    groups.push(g)
  }
  { ..more, groups, }
}

///|
/// A group that begins with `|`: one alternative of a sequence.
fn Parser::parse_bar_group(
  self : Parser,
  t : @lexer.Token,
  i : Int,
  sg : GState,
  column : @column.Column,
) -> GroupsResult raise @err.ShrubberyError {
  let line = t.line()
  // A `|` that belongs to an enclosing construct ends this sequence rather
  // than starting an alternative here.
  if sg.bar_closes || line_eq_plus(line, sg.bar_closes_line, sg.delta) {
    return {
      groups: [],
      rest: i,
      end_line: sg.last_line,
      end_delta: sg.delta,
      end_token: None,
      tail_commenting: sg.tail_commenting,
      tail_raw: sg.raw,
    }
  }
  let in_block = sg.block_mode is Inside
  let after_colon = sg.block_mode.opened_by_colon() is Some(_)
  if !in_block && !after_colon {
    match sg.block_mode.opened_by_colon() {
      Some(colon) => self.fail(colon, UnnecessaryColonBeforeBar)
      None => self.fail(t, MisplacedBar)
    }
    // In recovery mode, treat it as an ordinary group so parsing continues.
    return self.parse_one_group(t, i, sg, column, (_, _) => ())
  }
  let same_line = !sg.count ||
    sg.last_line is None ||
    line_eq_plus(line, sg.last_line, 0)
  if sg.check_column {
    let ok = match sg.block_mode {
      Opened(_, parent) => self.col_eq(t, column, parent.half_next())
      _ =>
        same_line ||
        (match sg.column {
          Some(c) => self.col_eq(t, column, c)
          None => true
        })
    }
    if !ok {
      self.fail(t, WrongIndentation(missing_colon_hint=false))
    }
  }
  if !(sg.block_mode is Opened(_)) {
    // A `|` may not start left of the column its group started at, even when
    // it continues a line -- otherwise a later line could belong either to the
    // alternative or to whatever encloses it.
    match sg.column {
      Some(parent) =>
        if sg.count && self.col_lt(t, column, parent) {
          self.fail(t, AltBeforeGroupColumn)
        }
      None => ()
    }
  }
  let pre_raw = sg.raw
  let commenting = match sg.commenting {
    Some(c) => Some(c)
    None => sg.tail_commenting
  }
  let block = self.parse_block(
    Some(t),
    i + 1,
    count=sg.count,
    line=Some(line),
    closer=Col(column.next()),
    bar_closes=!sg.count,
    bar_closes_line=if sg.count { Some(line - sg.delta) } else { None },
    delta=sg.delta,
    raw=if commenting is Some(_) { RNil } else { pre_raw },
    variant=sg.variant,
  )
  let rest = self.parse_groups(block.rest, {
    ..sg,
    column: if same_line {
      sg.column
    } else {
      Some(column)
    },
    bar_column: None,
    check_column: self.next_line(block.rest, block.end_line, sg.count),
    last_line: block.end_line,
    delta: block.end_delta,
    comma_time: sg.paren_immed.is_immed(),
    commenting: None,
    tail_commenting: block.tail_commenting,
    raw: match commenting {
      Some(_) =>
        pre_raw.push_text(group_source(block.items)).append(block.tail_raw)
      None => block.tail_raw
    },
  })
  match commenting {
    Some(_) => rest
    None => {
      // `parse_block` answers with the block as a single item; it becomes the
      // alternative, and `tag_as_block` will collect the run of them.
      let bar_block = if block.items.length() > 0 {
        Some(block.items[0])
      } else {
        None
      }
      let groups = [
        (
          {
            items: block.items,
            bar: bar_block,
            span: span_over(block.items, t.span),
            meta: @raw.Meta::new(),
          } : PendingGroup),
      ]
      for g in rest.groups {
        groups.push(g)
      }
      { ..rest, groups, }
    }
  }
}

///|
/// An ordinary group, then the rest of the sequence.
fn Parser::parse_one_group(
  self : Parser,
  t : @lexer.Token,
  i : Int,
  sg : GState,
  column : @column.Column,
  check_column : (@lexer.Token, @column.Column) -> Unit raise @err.ShrubberyError,
) -> GroupsResult raise @err.ShrubberyError {
  check_column(t, column)
  let use_column = sg.column.unwrap_or(column)
  let line = t.line()
  let pre_raw = sg.raw
  let commenting = match sg.commenting {
    Some(c) => Some(c)
    None => sg.tail_commenting
  }
  if sg.sequence_mode is NoMore && commenting is None {
    self.fail(t, SecondGroupAfterAt)
  }
  let g = self.parse_group(i, {
    count: sg.count,
    line: Some(line),
    column: Some(use_column),
    bar_column: sg.bar_column,
    operator_column: None,
    bar_closes: sg.bar_closes,
    bar_closes_line: sg.bar_closes_line,
    block_mode: sg.block_mode,
    can_empty: sg.can_empty,
    delta: sg.delta,
    raw: RNil,
    at_mode: None,
    variant: sg.variant,
  })
  let rest = self.parse_groups(g.rest, {
    ..sg,
    column: Some(use_column),
    check_column: self.next_line(g.rest, g.end_line, sg.count),
    last_line: g.end_line,
    comma_time: sg.paren_immed.is_immed(),
    bar_closes_line: next_block_close_line(
      sg.bar_closes_line,
      Some(line),
      g.end_line,
    ),
    bar_column: None,
    delta: g.end_delta,
    commenting: None,
    tail_commenting: g.tail_commenting,
    raw: match commenting {
      Some(_) => pre_raw.push_text(group_source(g.items)).append(g.tail_raw)
      None => g.tail_raw
    },
    sequence_mode: if commenting is None && sg.sequence_mode is OneOnly {
      NoMore
    } else {
      sg.sequence_mode
    },
  })
  match commenting {
    Some(_) => rest
    None => {
      let meta = @raw.Meta::new()
      meta.prefix = pre_raw.to_raw()
      let groups = [
        (
          { items: g.items, bar: None, span: span_over(g.items, t.span), meta, } :
          PendingGroup),
      ]
      for x in rest.groups {
        groups.push(x)
      }
      { ..rest, groups, }
    }
  }
}

///|
/// The source text of a group's items, for rendering a commented-out group
/// back into the raw text around it.
fn group_source(items : Array[@ast.Node]) -> @raw.Raw {
  let buf = StringBuilder()
  for n in items {
    n.write_source(buf)
  }
  Str(buf.to_string())
}

///|
/// A block that ends on the line a `|` was waiting for moves that expectation
/// to the block's own last line.
fn next_block_close_line(bcl : Int?, pre_line : Int?, post_line : Int?) -> Int? {
  match (bcl, pre_line) {
    (Some(a), Some(b)) => if a == b { post_line } else { bcl }
    _ => bcl
  }
}
