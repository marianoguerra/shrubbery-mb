///|
/// How many sequences may be open at once, by default.
///
/// One frame per bracket pair and per block, so this is what keeps the stack
/// finite on input that nests without end. Two numbers decide it, and they are
/// not close together:
///
///   * Real source nests nothing like this deep. The 610 Rhombus modules in
///     the corpus come nowhere near it.
///   * The smallest stack this library runs on does not go much further. On
///     the `wasm` backend, nested blocks overflow somewhere between 90 and 100
///     levels -- so the limit is not "20x what anyone writes", which would be
///     past the point where the check could still be reached. It is a little
///     under half of the smallest ceiling measured.
///
/// A consumer that knows its own stack can raise it: `parse` takes `max_depth`.
/// Anything that nests deeper than a person would write is data rather than
/// source, and a refusal it can catch beats a signal it cannot.
pub let default_max_depth : Int = 64

///|
/// Parse a sequence of groups: the top level, the inside of an opener-closer
/// pair, or the body of a block.
///
/// Consumes the closer when there is one. The shape of this function is the
/// reference's: a dispatch on the next token, with every arm either finishing
/// the sequence, consuming something and recurring, or parsing one group and
/// recurring for the rest.
fn Parser::parse_groups(
  self : Parser,
  start : Int,
  sg : GState,
) -> GroupsResult raise @err.ShrubberyError {
  let mut i = start
  let mut sg = sg
  if sg.depth > self.max_depth {
    // Refused here because this is where a new sequence begins, so it is the
    // frame whose absence keeps the stack finite.
    //
    // This one raises even in recovery mode, and it is the only kind that
    // does. Recovery means "record it and carry on", and there is nowhere to
    // carry on TO: the parser would return to the opener it could not descend
    // into, which has consumed nothing, and open it again. The first version
    // of this check recovered, and turned an overflow at 5000 nested brackets
    // into a slower overflow at 5000 nested brackets.
    let t = self.tok(if self.at_end(i) { i - 1 } else { i })
    let d = @err.Diagnostic::new(NestingTooDeep(limit=self.max_depth), t.span)
    self.diags.push(d)
    raise ShrubberyError(d)
  }
  // The reference recurs in tail position on every arm that continues the
  // sequence; a loop here says the same thing and keeps the stack shallow on a
  // file with thousands of top-level groups.
  for ;; {
    let done = () => {
      // A pending `#//` with no group to comment out is an error, but one that
      // is still only "pending at the end" may yet find a group in the caller.
      match sg.commenting {
        Some(c) => self.fail_no_comment_group(c)
        None => ()
      }
      (
        {
          groups: [],
          rest: i,
          end_line: sg.last_line,
          end_delta: sg.delta,
          end_token: None,
          tail_commenting: sg.tail_commenting,
          tail_raw: sg.raw,
        } : GroupsResult)
    }
    if self.at_end(i) {
      match sg.closer {
        Delim(expected, opener) =>
          self.fail(opener, DidNotFindMatching(expected~))
        _ => ()
      }
      return done()
    }
    let t = self.tok(i)
    let column = t.column()
    // Indentation matters only for a token that STARTS a line. A `|` on the
    // same line as a dedented closer still belongs to the enclosing construct,
    // which is what the second half of this test protects.
    let less_indented = sg.count &&
      sg.closer.is_column() &&
      (match sg.closer {
        Col(c) => self.col_lt(t, column, c)
        _ => false
      }) &&
      !line_eq_plus(t.line(), sg.last_line, sg.delta)
    let check_column = (t : @lexer.Token, column : @column.Column) => {
      if sg.check_column {
        match sg.column {
          Some(c) =>
            if !self.col_eq(t, column, c) {
              self.fail(t, WrongIndentation(missing_colon_hint=false))
            }
          None => ()
        }
      }
    }
    if t.kind is GroupComment {
      match sg.commenting {
        Some(c) => self.fail_no_comment_group(c)
        None => ()
      }
      let line = t.line()
      let a = self.next_of(
        i + 1,
        Some(line),
        sg.delta,
        sg.raw.push(t),
        sg.count,
      )
      if sg.count &&
        line_gt(line, sg.last_line) &&
        self.next_line(a.rest, a.last_line, sg.count) {
        // On its own line, so its column does not constrain anything.
        sg = {
          ..sg,
          last_line: a.last_line,
          delta: a.delta,
          tail_commenting: Some(t),
          raw: a.raw,
        }
        i = a.rest
        continue
      }
      if less_indented {
        return done()
      }
      check_column(t, column)
      sg = {
        ..sg,
        check_column: self.next_line(a.rest, a.last_line, sg.count),
        column: Some(sg.column.unwrap_or(column)),
        bar_column: None,
        last_line: a.last_line,
        delta: a.delta,
        tail_commenting: Some(t),
        raw: a.raw,
      }
      i = a.rest
      continue
    }
    if less_indented {
      return done()
    }
    match t.kind {
      Closer => {
        if sg.closer.is_column() {
          return done()
        }
        match sg.closer {
          Delim(expected, _) =>
            if expected != t.text {
              self.fail(t, ExpectedCloser(expected~, found=t.text))
            }
          _ => self.fail(t, UnexpectedCloser(found=t.text))
        }
        let raw = sg.raw.push(t)
        if sg.closer.is_delim() {
          match sg.commenting {
            Some(c) => self.fail_no_comment_group(c)
            None => ()
          }
          return {
            groups: [],
            rest: i + 1,
            end_line: Some(t.line()),
            end_delta: sg.delta,
            end_token: Some(t),
            tail_commenting: None,
            tail_raw: raw,
          }
        }
        // At the top level an extra closer is reported and then skipped, so
        // that the rest of the file is still parsed.
        sg = { ..sg, last_line: Some(t.line()), raw, }
        i = i + 1
        continue
      }
      Whitespace | Comment | ContinueOperator => {
        let a = self.next_of(i, sg.last_line, sg.delta, sg.raw, sg.count)
        sg = { ..sg, last_line: a.last_line, delta: a.delta, raw: a.raw, }
        i = a.rest
        continue
      }
      CommaOperator => {
        if sg.closer.is_column() {
          return done()
        }
        if !(sg.paren_immed.is_immed() && sg.comma_time) {
          self.fail(t, MisplacedComma(paren_immed=sg.paren_immed.is_immed()))
        }
        let a = self.next_of(
          i + 1,
          Some(t.line()),
          sg.delta,
          sg.raw.push(t),
          sg.count,
        )
        // A comma counts as whitespace for indentation, so what line it was on
        // does not matter -- which is what lets a leading `,` sit anywhere.
        let nl = self.next_line(a.rest, sg.last_line, sg.count)
        let bar_column = if nl || self.at_end(a.rest) {
          sg.column
        } else {
          Some(self.tok(a.rest).column())
        }
        sg = {
          ..sg,
          check_column: nl,
          bar_column,
          last_line: a.last_line,
          comma_time: false,
          delta: a.delta,
          raw: a.raw,
        }
        i = a.rest
        continue
      }
      SemicolonOperator => {
        if sg.block_mode is Inside {
          return done()
        }
        check_column(t, column)
        let a = self.next_of(
          i + 1,
          Some(t.line()),
          sg.delta,
          sg.raw.push(t),
          sg.count,
        )
        let next_t = self.peek(a.rest)
        let is_splice = match next_t {
          Some(nt) => nt.kind is Opener && nt.text == "\u{AB}"
          None => false
        }
        if is_splice {
          return self.parse_splice(t, a, sg)
        }
        if sg.paren_immed.is_immed() {
          self.fail(t, MisplacedSemicolon)
        }
        sg = {
          ..sg,
          check_column: self.next_line(a.rest, a.last_line, sg.count),
          column: Some(sg.column.unwrap_or(column)),
          bar_column: match next_t {
            Some(nt) => Some(nt.column())
            None => None
          },
          last_line: a.last_line,
          delta: a.delta,
          commenting: sg.tail_commenting,
          tail_commenting: None,
          block_mode: next_group_block_mode(sg.block_mode),
          raw: a.raw,
        }
        i = a.rest
        continue
      }
      _ => ()
    }
    if sg.comma_time && !(sg.paren_immed is AtArgs) {
      self.fail(t, MissingCommaBeforeGroup)
    }
    let starts_bar = !(sg.block_mode is Start) && t.kind is BarOperator
    if starts_bar {
      return self.parse_bar_group(t, i, sg, column)
    }
    return self.parse_one_group(t, i, sg, column, check_column)
  }
}

///|
/// The block mode a group sequence carries into its next group.
fn next_group_block_mode(mode : BlockMode) -> BlockMode {
  match mode {
    // Kept, so that a `|` may still follow.
    Opened(_) => mode
    _ => NoBlock
  }
}
