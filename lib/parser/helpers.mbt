///|
/// Everything the three mutually recursive functions share.
priv struct Parser {
  toks : Array[@lexer.Token]
  /// Collected diagnostics. In recovery mode a failure is recorded here and
  /// parsing continues; otherwise the first one is raised.
  diags : Array[@err.Diagnostic]
  recover : Bool
  /// How deep the grammar may recur before it refuses. See
  /// `default_max_depth`.
  max_depth : Int
}

///|
/// Report a failure.
///
/// In recovery mode this records and returns, and the caller carries on --
/// which is what an editor wants, and what makes a file with three mistakes
/// report three. Otherwise it raises, and the first mistake is the answer.
fn Parser::fail(
  self : Parser,
  t : @lexer.Token,
  kind : @err.ErrorKind,
) -> Unit raise @err.ShrubberyError {
  let d = @err.Diagnostic::new(kind, t.span)
  self.diags.push(d)
  if !self.recover {
    raise ShrubberyError(d)
  }
}

///|
/// The mixed-tabs failure, raised where a comparison turns out to have no
/// answer. Passed as a thunk in the reference; here the comparison is checked
/// at each site, which is the same thing written out.
fn Parser::incomparable(
  self : Parser,
  t : @lexer.Token,
) -> Unit raise @err.ShrubberyError {
  self.fail(t, IncomparableIndentation)
}

///|
fn Parser::at_end(self : Parser, i : Int) -> Bool {
  i >= self.toks.length()
}

///|
fn Parser::tok(self : Parser, i : Int) -> @lexer.Token {
  self.toks[i]
}

///|
fn Parser::peek(self : Parser, i : Int) -> @lexer.Token? {
  if i < self.toks.length() {
    Some(self.toks[i])
  } else {
    None
  }
}

///|
/// `a > b`, where an unknown line is never greater.
fn line_gt(a : Int, b : Int?) -> Bool {
  match b {
    Some(v) => a > v
    None => false
  }
}

///|
/// `a == b + n`, where an unknown line matches nothing.
fn line_eq_plus(a : Int, b : Int?, n : Int) -> Bool {
  match b {
    Some(v) => a == v + n
    None => false
  }
}

///|
/// Compare two columns, turning "no answer" into the diagnostic that says so.
fn Parser::col_cmp(
  self : Parser,
  t : @lexer.Token,
  a : @column.Column,
  b : @column.Column,
) -> @column.ColumnOrder raise @err.ShrubberyError {
  let order = a.cmp(b)
  if order is Incomparable {
    self.incomparable(t)
  }
  order
}

///|
fn Parser::col_lt(
  self : Parser,
  t : @lexer.Token,
  a : @column.Column,
  b : @column.Column,
) -> Bool raise @err.ShrubberyError {
  self.col_cmp(t, a, b) is Lt
}

///|
fn Parser::col_gt(
  self : Parser,
  t : @lexer.Token,
  a : @column.Column,
  b : @column.Column,
) -> Bool raise @err.ShrubberyError {
  self.col_cmp(t, a, b) is Gt
}

///|
fn Parser::col_eq(
  self : Parser,
  t : @lexer.Token,
  a : @column.Column,
  b : @column.Column,
) -> Bool raise @err.ShrubberyError {
  self.col_cmp(t, a, b) is Eq
}

///|
/// What `next_of` and its variants answer.
priv struct Advance {
  rest : Int
  last_line : Int?
  delta : Int
  raw : RawList
}

///|
/// Skip whitespace and comments, and apply `\` continuations.
///
/// A `\` joins the next line to this one, which the reference records as a
/// line-span delta rather than by rewriting positions: the column of a token
/// on the continued line is still its own column, but its LINE counts as the
/// original. That is why a continued line does not have to be indented.
fn Parser::next_of(
  self : Parser,
  start : Int,
  last_line : Int?,
  delta : Int,
  raw : RawList,
  count : Bool,
) -> Advance raise @err.ShrubberyError {
  let mut i = start
  let mut ll = last_line
  let mut d = delta
  let mut r = raw
  for ;; {
    if self.at_end(i) {
      return { rest: i, last_line: Some(ll.unwrap_or(0)), delta: d, raw: r, }
    }
    let t = self.tok(i)
    match t.kind {
      Whitespace | Comment => {
        r = r.push(t)
        i = i + 1
      }
      ContinueOperator => {
        let line = t.line()
        // Only whitespace and comments may follow a `\` on its line.
        let mut j = i + 1
        let mut jr = r.push(t)
        while !self.at_end(j) && self.tok(j).is_trivia() {
          jr = jr.push(self.tok(j))
          j = j + 1
        }
        if !self.at_end(j) && (!count || self.tok(j).line() == line) {
          if count {
            self.fail(t, ContinuationFollowedByToken)
          }
          // With counting off, or after reporting, treat it as whitespace.
          i = j
          r = jr
        } else {
          // A line with only whitespace after the `\` does not count as the
          // next line, so any number of them may sit between the two halves.
          let continues = !count || ll is None || line_eq_plus(line, ll, 0)
          ll = if continues { None } else { ll }
          d = d + 1
          i = j
          r = jr
        }
      }
      _ => {
        let line = t.line()
        let new_delta = if !count || ll is None || line_eq_plus(line, ll, 0) {
          d
        } else {
          0
        }
        return {
          rest: i,
          last_line: Some(ll.unwrap_or(line)),
          delta: new_delta,
          raw: r,
        }
      }
    }
  }
}

///|
/// Whether the token at `i` starts a line after `last_line`.
fn Parser::next_line(
  self : Parser,
  i : Int,
  last_line : Int?,
  count : Bool,
) -> Bool {
  count && !self.at_end(i) && line_gt(self.tok(i).line(), last_line)
}

///|
/// Two tokens that must be on one line, such as `:` and the `«` after it.
fn Parser::check_same_line(
  self : Parser,
  t : @lexer.Token,
  next_t : @lexer.Token,
  count : Bool,
) -> Unit raise @err.ShrubberyError {
  if count && t.line() != next_t.line() {
    self.fail(next_t, NotOnSameLine(preceding=t.text))
  }
}

///|
fn Parser::fail_no_comment_group(
  self : Parser,
  t : @lexer.Token,
) -> Unit raise @err.ShrubberyError {
  self.fail(t, NoGroupForTermComment)
}

///|
/// `next_of`, then collect a `#//` that is alone on its line.
fn Parser::next_of_commenting(
  self : Parser,
  start : Int,
  last_line : Int?,
  delta : Int,
  raw : RawList,
  count : Bool,
) -> (@lexer.Token?, Advance) raise @err.ShrubberyError {
  let a = self.next_of(start, last_line, delta, raw, count)
  if self.at_end(a.rest) {
    return (None, a)
  }
  let (commenting, _use_t, use_i, ll, d, r) = self.own_line_group_comment(
    a.rest,
    a.last_line,
    a.delta,
    a.raw,
    count,
  )
  (commenting, { rest: use_i, last_line: ll, delta: d, raw: r, })
}

///|
/// `next_of`, then recognise an immediate `«`.
fn Parser::next_of_opener(
  self : Parser,
  start : Int,
  last_line : Int?,
  delta : Int,
  raw : RawList,
  count : Bool,
) -> (@lexer.Token?, Advance) raise @err.ShrubberyError {
  let a = self.next_of(start, last_line, delta, raw, count)
  if self.at_end(a.rest) {
    return (None, a)
  }
  let t = self.tok(a.rest)
  if t.kind is Opener && t.text == "\u{AB}" {
    (
      Some(t),
      {
        rest: a.rest + 1,
        last_line: Some(t.line()),
        delta: a.delta,
        raw: a.raw.push(t),
      },
    )
  } else {
    (None, a)
  }
}

///|
/// Gather `#//`s that sit alone on their line.
///
/// A `#//` alone on a line does not take part in indentation — it comments out
/// whatever group comes next, wherever that is — while one with more on its
/// line determines that group's column. Deciding which is what this does, and
/// it has to look ahead past whitespace to find out.
///
/// Returns the pending comment, the token now at the front, the index of that
/// token, and the advanced line, delta and raw.
fn Parser::own_line_group_comment(
  self : Parser,
  start : Int,
  line : Int?,
  delta : Int,
  raw : RawList,
  count : Bool,
) -> (@lexer.Token?, @lexer.Token, Int, Int?, Int, RawList) raise @err.ShrubberyError {
  let mut commenting : @lexer.Token? = None
  let mut i = start
  let mut ll = line
  let mut d = delta
  let mut r = raw
  for ;; {
    if self.at_end(i) {
      // Caller checks; there is no token to hand back, so hand back the index.
      return (commenting, self.toks[self.toks.length() - 1], i, ll, d, r)
    }
    let t = self.tok(i)
    if !(t.kind is GroupComment) {
      return (commenting, t, i, ll, d, r)
    }
    match commenting {
      Some(prev) => self.fail_no_comment_group(prev)
      None => ()
    }
    if count && line_gt(t.line(), ll) {
      let a = self.next_of(i + 1, ll, d, r.push(t), count)
      if self.at_end(a.rest) {
        self.fail_no_comment_group(t)
        return (Some(t), t, a.rest, a.last_line, a.delta, a.raw)
      }
      if self.next_line(a.rest, Some(t.line()), count) {
        commenting = Some(t)
        i = a.rest
        ll = a.last_line
        d = a.delta
        r = a.raw
        continue
      }
      // Not on its own line after all: leave it where it is so that it counts
      // toward the next group's indentation.
      return (commenting, t, i, ll, d, r)
    }
    return (commenting, t, i, ll, d, r)
  }
}

///|
/// Consume whitespace and comments that stay on this line.
///
/// "Stay on this line" is decided by looking for a newline in the text, not by
/// comparing line numbers, because the question is whether the comment belongs
/// to the term before it or to whatever comes next.
fn Parser::suffix_comments(
  self : Parser,
  start : Int,
  line : Int?,
  delta : Int,
) -> (RawList, Int, Int?, Int) {
  let mut i = start
  let mut acc : RawList = RNil
  while !self.at_end(i) {
    let t = self.tok(i)
    match t.kind {
      Whitespace | Comment =>
        if t.text.contains("\n") || t.text.contains("\r") {
          break
        } else {
          acc = acc.push(t)
          i = i + 1
        }
      _ => break
    }
  }
  (acc, i, line, delta)
}
