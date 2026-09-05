///|
/// Parse a block: the body of a `:` or of one `|` alternative.
///
/// Answers with the ITEMS to append to the enclosing group -- normally the
/// block itself, possibly followed by the alternatives that ended it, and then
/// whatever `parse_group` found after the closer. That flattening is what makes
/// `a: b | c | d` one group with a block and an `alts` rather than a nest.
fn Parser::parse_block(
  self : Parser,
  t : @lexer.Token?,
  start : Int,
  count~ : Bool,
  line~ : Int?,
  closer~ : Closer,
  bar_closes? : Bool = false,
  bar_closes_line? : Int? = None,
  drop_empty? : Bool = false,
  delta~ : Int,
  raw~ : RawList,
  variant~ : @lexer.Variant,
  group_commenting? : @lexer.Token? = None,
  parent_column? : @column.Column? = None,
  block_mode? : BlockMode? = None,
  can_empty? : Bool = false,
  could_empty_if_start? : Bool = false,
  depth~ : Int,
) -> GroupResult raise @err.ShrubberyError {
  let (opener_t, oa) = self.next_of_opener(start, line, delta, RNil, count)
  match (t, opener_t) {
    (Some(tt), Some(ot)) => self.check_same_line(tt, ot, count)
    _ => ()
  }
  // Inside `«»` lines and columns stop mattering, which is the whole point of
  // writing one.
  let inside_count = count && opener_t is None
  let (commenting, a) = match group_commenting {
    Some(c) => (Some(c), oa)
    None =>
      self.next_of_commenting(
        oa.rest,
        oa.last_line,
        oa.delta,
        oa.raw,
        inside_count,
      )
  }
  let mode = match block_mode {
    Some(m) => m
    None =>
      match t {
        Some(tt) => Opened(tt, parent_column.unwrap_or(@column.zero))
        None => NoBlock
      }
  }
  let fail_empty = () => {
    match t {
      Some(tt) =>
        self.fail(tt, EmptyBlock(after=tt.text, could_empty_if_start~))
      None => ()
    }
  }
  if self.at_end(a.rest) {
    match opener_t {
      Some(ot) => self.fail(ot, ExpectedGuillemetClose)
      None => if !can_empty { fail_empty() }
    }
    let fallback = match t {
      Some(tt) => tt.span
      None => @basic.Span::at(@basic.start)
    }
    let (head, alts) = tag_as_block([], fallback)
    let items = [head]
    for x in alts {
      items.push(x)
    }
    attach_block_raw(head, t, raw, Empty)
    return {
      items,
      rest: a.rest,
      end_line: line,
      end_delta: a.delta,
      tail_commenting: commenting,
      tail_raw: a.raw,
    }
  }
  let next_t = self.tok(a.rest)
  let content_column = next_t.column()
  let inner = self.parse_groups(a.rest, {
    depth: depth + 1,
    count: inside_count,
    closer: match opener_t {
      Some(ot) => Delim("\u{BB}", ot)
      None => closer
    },
    paren_immed: NotImmed,
    column: Some(content_column),
    bar_column: None,
    check_column: inside_count,
    bar_closes: opener_t is None && bar_closes,
    bar_closes_line: if opener_t is None && inside_count {
      bar_closes_line
    } else {
      None
    },
    block_mode: mode,
    can_empty: false,
    comma_time: false,
    sequence_mode: AnyNumber,
    last_line: a.last_line,
    delta: a.delta,
    commenting,
    tail_commenting: None,
    raw: a.raw,
    variant,
  })
  if !can_empty &&
    inner.groups.length() == 0 &&
    t is Some(_) &&
    opener_t is None {
    fail_empty()
  }
  // Comments at the block's OWN indentation stay with it; everything else that
  // trails belongs to whatever encloses the block, so the split has to happen
  // BEFORE the outward tail is decided or the same comments are written twice.
  let (outward, block_suffix) = self.keep_same_indentation_comments(
    Some(content_column),
    inner.tail_raw,
  )
  let used_closer = opener_t is Some(_) || closer.is_delim()
  // After a `»` the group may take nothing more but alternatives, which is
  // what `End` mode enforces.
  let post = if used_closer {
    self.parse_group(inner.rest, {
      depth,
      count,
      line: inner.end_line,
      column: parent_column,
      bar_column: None,
      operator_column: None,
      bar_closes,
      bar_closes_line,
      block_mode: End,
      can_empty: false,
      delta: inner.end_delta,
      raw: RNil,
      at_mode: None,
      variant,
    })
  } else {
    (
      {
        items: [],
        rest: inner.rest,
        end_line: inner.end_line,
        end_delta: inner.end_delta,
        tail_commenting: inner.tail_commenting,
        tail_raw: outward,
      } : GroupResult)
  }
  let fallback = match t {
    Some(tt) => tt.span
    None => next_t.span
  }
  let (head, alts) = tag_as_block(inner.groups, fallback)
  let drop = inner.groups.length() == 0 && drop_empty
  let items = []
  if !drop {
    attach_block_raw(
      head,
      t,
      raw,
      (if used_closer { outward.to_raw() } else { Empty }).combine(
        block_suffix.to_raw(),
      ),
    )
    items.push(head)
    for x in alts {
      items.push(x)
    }
  }
  for x in post.items {
    items.push(x)
  }
  {
    items,
    rest: post.rest,
    end_line: post.end_line,
    end_delta: post.end_delta,
    tail_commenting: post.tail_commenting,
    tail_raw: if drop {
      raw.then(post.tail_raw)
    } else {
      post.tail_raw
    },
  }
}

///|
/// Split the raw that trails a block's content into the part that belongs to
/// the block and the part that belongs to whatever encloses it.
///
/// A comment sitting at the block's OWN indentation is part of the block -- it
/// reads as a note about its last group -- while one further left belongs
/// outside. The reference notes that reversing twice here is quadratic if
/// blocks are nested N deep with N comments after them; that is not a file
/// anyone writes.
fn Parser::keep_same_indentation_comments(
  self : Parser,
  column : @column.Column?,
  tail : RawList,
) -> (RawList, RawList) raise @err.ShrubberyError {
  let col = match column {
    Some(c) => c
    None => return (tail, RNil)
  }
  // Walk from the START of the trailing run, which is the far end of this
  // reversed list.
  let items = []
  let mut cur = tail
  while cur is RCons(item, rest) {
    items.push(item)
    cur = rest
  }
  items.rev_in_place()
  let mut split = 0
  let mut i = 0
  while i < items.length() {
    match items[i] {
      RTok(t) =>
        if t.kind is Whitespace {
          i = i + 1
        } else if t.kind is Comment && self.col_eq(t, col, t.column()) {
          i = i + 1
          // This comment, and the whitespace that led to it, stay.
          split = i
        } else {
          break
        }
      _ => break
    }
  }
  let mut kept : RawList = RNil
  for x in items[split:] {
    kept = RCons(x, kept)
  }
  let mut suffix : RawList = RNil
  for x in items[0:split] {
    suffix = RCons(x, suffix)
  }
  (kept, suffix)
}

///|
/// Give a block the text of the `:` or `|` that opened it, the prefix before
/// it, and whatever trailed its content.
fn attach_block_raw(
  block : @ast.Node,
  t : @lexer.Token?,
  pre : RawList,
  tail : @raw.Raw,
) -> Unit {
  match t {
    Some(tok) => {
      let head : @raw.Raw = Str(tok.raw_text())
      block.meta.raw = head.combine(block.meta.raw)
    }
    None => ()
  }
  attach_prefix(block, pre)
  block.meta.tail = block.meta.tail.combine(tail)
}
