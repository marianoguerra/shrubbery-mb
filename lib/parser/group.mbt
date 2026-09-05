///|
/// Parse ONE group: a run of terms, optionally ending in a block and then
/// alternatives.
///
/// Answers with the group's items rather than a node, because a block and its
/// alternatives are appended into the group by `parse_block` and the caller is
/// what knows where the group starts.
fn Parser::parse_group(
  self : Parser,
  start : Int,
  s : PState,
) -> GroupResult raise @err.ShrubberyError {
  let done = (i : Int, s : PState) => {
    (
      {
        items: [],
        rest: i,
        end_line: s.line,
        end_delta: s.delta,
        tail_commenting: None,
        tail_raw: s.raw,
      } : GroupResult)
  }
  let mut i = start
  let mut s = s
  for ;; {
    if self.at_end(i) {
      return done(i, s)
    }
    let t = self.tok(i)
    let line = t.line()
    if s.count && line_gt(line, s.line) {
      // A new line. Either it continues this group -- an operator, or a `|`
      // that opens alternatives -- or the group is over.
      match t.kind {
        Whitespace | Comment => {
          s = { ..s, line: Some(line), delta: 0, raw: s.raw.push(t), }
          i = i + 1
          continue
        }
        Closer | AtContent | AtCloser => return done(i, s)
        _ => ()
      }
      let (group_commenting, use_t, use_i, ll, d, r) = self.own_line_group_comment(
        i,
        s.line,
        s.delta,
        s.raw,
        s.count,
      )
      let column = use_t.column()
      let more_indented = match s.column {
        Some(c) => self.col_gt(use_t, column, c)
        None => false
      }
      if !more_indented {
        // Leaving the group comments in place is deliberate: not consuming
        // inspected tokens would normally be worrying, but they are parsed at
        // most once more.
        return done(i, s)
      }
      if use_t.kind is BarOperator {
        let want = s.bar_column.unwrap_or(s.column.unwrap_or(@column.zero))
        if !self.col_eq(use_t, column, want.half_next()) {
          self.fail(use_t, WrongIndentation(missing_colon_hint=false))
        }
        // Straight to `parse_block`, not through `parse_alts_block`: on this
        // path the `|` opens alternatives for a group that has already been
        // continued onto later lines, so neither the operator-column check nor
        // the "cannot start before the group's column" check applies -- the
        // column was just checked against the group's own, above.
        return self.parse_block(
          None,
          use_i,
          count=s.count,
          block_mode=Some(Inside),
          line=Some(use_t.line()),
          closer=if s.count { Col(column) } else { Any },
          bar_closes=false,
          bar_closes_line=None,
          drop_empty=true,
          delta=d,
          raw=r,
          group_commenting~,
          variant=s.variant,
        )
      }
      let continues_operator = use_t.kind is Operator &&
        (match s.operator_column {
          None => true
          Some(oc) => self.col_eq(use_t, column, oc)
        }) &&
        (s.variant.indented_operator_continue)(use_t.text)
      if continues_operator {
        match group_commenting {
          Some(c) => self.fail(c, MisplacedGroupComment)
          None => ()
        }
        s = { ..s, line: ll, delta: d, raw: r, }
        return self.keep(use_i, s, operator_column=Some(column))
      }
      if use_t.kind is Opener && use_t.text == "\u{AB}" {
        match group_commenting {
          Some(c) => self.fail(c, MisplacedGroupComment)
          None => ()
        }
        // Fall through so that the `«` is reported where it stands.
        s = { ..s, line: Some(line), }
        continue
      }
      self.fail(use_t, WrongIndentation(missing_colon_hint=true))
      return done(i, s)
    }
    // Same line.
    match t.kind {
      Closer | CommaOperator | SemicolonOperator | AtContent | AtCloser =>
        return done(i, s)
      Identifier | Keyword | Literal(_) | Operator | SExp(_) =>
        return self.keep(i, s)
      BlockOperator => {
        self.check_block_mode(t, s)
        let parent_column = s.bar_column.unwrap_or(
          s.column.unwrap_or(@column.zero),
        )
        return self.parse_block(
          Some(t),
          i + 1,
          count=s.count,
          line=Some(line),
          closer=if s.count { Col(parent_column.half_next()) } else { Any },
          delta=s.delta,
          raw=s.raw,
          bar_closes=s.bar_closes && s.bar_closes_line is None,
          bar_closes_line=s.bar_closes_line,
          can_empty=s.can_empty,
          could_empty_if_start=true,
          parent_column=Some(parent_column),
          variant=s.variant,
        )
      }
      BarOperator =>
        return self.parse_alts_block(
          t,
          i,
          s,
          delta=s.delta,
          raw=s.raw,
          done_at=i,
        )
      Opener => return self.parse_opener(t, i, s)
      Whitespace | Comment | ContinueOperator => {
        let a = self.next_of(i, s.line, s.delta, s.raw, s.count)
        s = { ..s, line: a.last_line, delta: a.delta, raw: a.raw, }
        i = a.rest
        continue
      }
      GroupComment => {
        // Misplaced, unless it is commenting out a `|` on the same line.
        let a = self.next_of(i + 1, Some(line), s.delta, s.raw.push(t), s.count)
        if !self.at_end(a.rest) &&
          self.tok(a.rest).kind is BarOperator &&
          !self.next_line(a.rest, a.last_line, s.count) {
          return self.parse_alts_block(
            self.tok(a.rest),
            a.rest,
            s,
            delta=a.delta,
            raw=a.raw,
            done_at=i,
            group_commenting=Some(t),
          )
        }
        self.fail(t, MisplacedGroupComment)
        i = i + 1
        continue
      }
      At => return self.parse_at(t, i, s)
      AtComment => {
        self.fail(t, AtCommentOutsideBody)
        return done(i, s)
      }
      AtOpener => return self.keep(i, s)
      Fail(kind) => {
        self.fail(t, kind)
        i = i + 1
        continue
      }
      _ => return done(i, s)
    }
  }
}

///|
/// Nothing may join a group after a `»` has closed its block.
fn Parser::check_block_mode(
  self : Parser,
  t : @lexer.Token,
  s : PState,
) -> Unit raise @err.ShrubberyError {
  if s.block_mode is End {
    self.fail(t, NoTermsAfterGuillemet)
  }
}

///|
/// Take one token as a term and carry on with the rest of the group.
fn Parser::keep(
  self : Parser,
  i : Int,
  s : PState,
  operator_column? : @column.Column? = None,
  at_mode? : AtMode? = None,
  suffix? : Bool = true,
) -> GroupResult raise @err.ShrubberyError {
  let t = self.tok(i)
  self.check_block_mode(t, s)
  // A `#{...}` escape can span lines, so where the token ENDS is decided by
  // where the next one starts rather than by the token's own line.
  let post_line = if i + 1 < self.toks.length() {
    self.tok(i + 1).line()
  } else {
    t.line()
  }
  // The default PRESERVES the state's operator column rather than clearing it:
  // a group continued by an operator on one line must be continued at the same
  // column on every later line, and forgetting it here would accept
  // `1 / + 2 / ⟨further right⟩ + 3` -- which the reference rejects.
  let operator_column = match operator_column {
    Some(_) => operator_column
    None => s.operator_column
  }
  let (suffix_raw, suffix_i, suffix_line, suffix_delta) = if suffix {
    self.suffix_comments(i + 1, Some(post_line), s.delta)
  } else {
    (RNil, i + 1, Some(post_line), s.delta)
  }
  let am = match at_mode {
    Some(_) => at_mode
    None => s.at_mode
  }
  let cont = self.continue_at(
    am,
    false,
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
    raw: RNil,
    block_mode: NoBlock,
    can_empty: false,
    operator_column,
    at_mode: cont.at_mode,
  })
  let elem = leaf_of(t)
  elem.meta.prefix = s.raw.to_raw()
  elem.meta.suffix = suffix_raw.to_raw()
  let items = [elem]
  for x in rest.items {
    items.push(x)
  }
  { ..rest, items: (cont.adjust)(items), }
}

///|
/// A `|` that opens or continues a sequence of alternatives.
/// `done_at` is where the CALLER was looking, which is not always where the
/// bar is: a `#//` before a `|` is inspected from one token earlier, and if
/// this decides the `|` belongs to an enclosing construct, the `#//` has to be
/// left in the stream for that construct to find. Returning the bar's position
/// instead silently swallows it.
fn Parser::parse_alts_block(
  self : Parser,
  t : @lexer.Token,
  i : Int,
  s : PState,
  delta~ : Int,
  raw~ : RawList,
  done_at~ : Int,
  group_commenting? : @lexer.Token? = None,
) -> GroupResult raise @err.ShrubberyError {
  let line = t.line()
  if s.bar_closes || line_eq_plus(line, s.bar_closes_line, s.delta) {
    return {
      items: [],
      rest: done_at,
      end_line: s.line,
      end_delta: s.delta,
      tail_commenting: None,
      tail_raw: s.raw,
    }
  }
  // No block-mode check here: a `|` is allowed after a `:`.
  match s.operator_column {
    Some(oc) =>
      if !self.col_eq(t, t.column(), oc.half_next()) {
        self.fail(t, WrongIndentation(missing_colon_hint=false))
      }
    None => ()
  }
  match s.column {
    Some(c) =>
      if s.count && self.col_lt(t, t.column(), c) {
        self.fail(t, AltBeforeGroupColumn)
      }
    None => ()
  }
  // The `|` is NOT consumed here. `parse_block` starts its group sequence AT
  // the bar, and the bar branch of `parse_groups` is what takes it -- which is
  // how the sequence comes to have the bar's own column, and how a second `|`
  // at that column is recognised as a sibling rather than as a mistake.
  self.parse_block(
    None,
    i,
    count=s.count,
    block_mode=Some(Inside),
    line=Some(line),
    closer=if s.count { Col(t.column()) } else { Any },
    bar_closes=false,
    bar_closes_line=None,
    drop_empty=true,
    delta~,
    raw~,
    group_commenting~,
    variant=s.variant,
  )
}
