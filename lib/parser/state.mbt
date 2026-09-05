///|
/// What ends a sequence of groups.
///
/// Four ways, and the reference unifies them into one field because the places
/// that ask "are we done?" do not care which: a delimiter to match, the end of
/// input, or a column that the next line must stay to the right of.
priv enum Closer {
  /// The top level: only the end of input ends it.
  Eof
  /// A delimiter, and the opener that is waiting for it.
  Delim(String, @lexer.Token)
  /// Dedenting to this column or past it ends the sequence.
  Col(@column.Column)
  /// A column closer that no column ever reaches, used where indentation is
  /// not being counted.
  Any
}

///|
/// Whether this closer is about indentation rather than a delimiter.
fn Closer::is_column(self : Closer) -> Bool {
  match self {
    Col(_) | Any => true
    _ => false
  }
}

///|
fn Closer::is_delim(self : Closer) -> Bool {
  self is Delim(_)
}

///|
/// Where a block came from, and what may follow it.
priv enum BlockMode {
  /// Not in one.
  NoBlock
  /// Immediately inside `|` alternatives: a `|` here starts a new one.
  Inside
  /// Immediately inside an opener, where a group may not start with `|`.
  Start
  /// After a `»` closed a block: nothing more may join the group but `|`.
  End
  /// In a block opened by this token, whose enclosing group started at this
  /// column. The token is kept for the "unnecessary `:` before `|`" message.
  Opened(@lexer.Token, @column.Column)
}

///|
fn BlockMode::opened_by_colon(self : BlockMode) -> @lexer.Token? {
  match self {
    Opened(t, _) => if t.kind is BlockOperator { Some(t) } else { None }
    _ => None
  }
}

///|
/// How many groups may follow, used only for `@«...»`, which admits one.
priv enum SequenceMode {
  AnyNumber
  OneOnly
  NoMore
}

///|
/// Raw text gathered but not yet attached to a node.
///
/// A reversed immutable list, because it is passed down every branch of a
/// mutual recursion that backtracks by simply not consuming, and a shared
/// mutable array would carry the effects of an abandoned branch.
priv enum RawList {
  RNil
  RCons(RawItem, RawList)
}

///|
priv enum RawItem {
  /// Whitespace, a comment, or any other token whose text is being kept.
  RTok(@lexer.Token)
  /// Text rendered from something dropped, such as a commented-out group.
  RText(@raw.Raw)
}

///|
fn RawList::push(self : RawList, t : @lexer.Token) -> RawList {
  RCons(RTok(t), self)
}

///|
fn RawList::push_text(self : RawList, r : @raw.Raw) -> RawList {
  RCons(RText(r), self)
}

///|
/// Flatten in source order. The list is reversed, so this reverses it back.
fn RawList::to_raw(self : RawList) -> @raw.Raw {
  let items = []
  let mut cur = self
  while cur is RCons(item, rest) {
    items.push(item)
    cur = rest
  }
  let mut out : @raw.Raw = Empty
  for i = items.length() - 1; i >= 0; i = i - 1 {
    let piece = match items[i] {
      RTok(t) => @raw.Raw::Str(t.raw_text())
      RText(r) => r
    }
    out = out.combine(piece)
  }
  out
}

///|
/// Flatten, splitting at an `@` token.
///
/// Everything from the `@` onwards belongs to the TERM rather than to whatever
/// encloses it -- that is the whole use the parser makes of `raw-inner-prefix`.
/// Without the split, the `@` of an `@x` inside a group would be shifted onto
/// the previous term's suffix and print in the wrong place.
fn RawList::to_raw_split_at(self : RawList) -> (@raw.Raw, @raw.Raw) {
  let items = []
  let mut cur = self
  while cur is RCons(item, rest) {
    items.push(item)
    cur = rest
  }
  let mut before : @raw.Raw = Empty
  let mut after : @raw.Raw = Empty
  let mut seen_at = false
  for i = items.length() - 1; i >= 0; i = i - 1 {
    let piece : @raw.Raw = match items[i] {
      RTok(t) => Str(t.raw_text())
      RText(r) => r
    }
    let is_at = match items[i] {
      RTok(t) => t.kind is At
      _ => false
    }
    if is_at {
      seen_at = true
    }
    if seen_at {
      after = after.combine(piece)
    } else {
      before = before.combine(piece)
    }
  }
  (before, after)
}

///|
/// The two runs joined, with `self` FIRST in source order.
///
/// The direction is in the name because both lists are stored reversed, and
/// getting it backwards is invisible until a comment turns up on the wrong side
/// of the thing it was written about.
fn RawList::then(self : RawList, later : RawList) -> RawList {
  let items = []
  let mut cur = later
  while cur is RCons(item, rest) {
    items.push(item)
    cur = rest
  }
  // `items` is latest-first; consing from the far end puts them back on top of
  // `self` in source order.
  let mut out = self
  for i = items.length() - 1; i >= 0; i = i - 1 {
    out = RCons(items[i], out)
  }
  out
}

///|
/// The state of parsing ONE group.
///
/// Immutable and rebuilt at every call, exactly as the reference rebuilds it
/// with `struct-copy`. A mutable version would make "leave the token in place"
/// silently wrong: a branch that backtracks would keep the changes it made on
/// the way down.
priv struct PState {
  /// Whether lines and columns matter. Turned off inside `«»`.
  count : Bool
  /// The line the group is on. `None` after a `\` continuation, which means
  /// "whatever line follows continues this one".
  line : Int?
  column : @column.Column?
  /// Where a `|` should line up, when that is not the group's own column.
  bar_column : @column.Column?
  /// The column of the operator that continued this group onto a new line.
  operator_column : @column.Column?
  bar_closes : Bool
  bar_closes_line : Int?
  block_mode : BlockMode
  can_empty : Bool
  /// Lines accumulated by `\` continuations. The reference also tracks a column
  /// here and has it commented out; it is always zero.
  delta : Int
  raw : RawList
  at_mode : AtMode?
  variant : @lexer.Variant
  /// How many sequences are open around this one. See `GState::depth`.
  depth : Int
}

///|
priv enum ParenImmed {
  NotImmed
  Normal
  /// Immediately inside an `@` argument list, where groups may be separated by
  /// newlines rather than commas.
  AtArgs
}

///|
fn ParenImmed::is_immed(self : ParenImmed) -> Bool {
  !(self is NotImmed)
}

///|
/// What an `@` form is expecting, while its command is being read.
priv struct AtMode {
  initial : Bool
  /// Identifier-operator pairs already read, for `@a.b.c`.
  rev_prefix : Array[@ast.Node]
  /// `@(«...»)`: the content splices with no surrounding parentheses.
  splice : Bool
  stop_at_at : Bool
  stop_at_next_at : Bool
}

///|
fn AtMode::new(
  initial? : Bool = false,
  rev_prefix? : Array[@ast.Node] = [],
  splice? : Bool = false,
  stop_at_at? : Bool = false,
  stop_at_next_at? : Bool = false,
) -> AtMode {
  { initial, rev_prefix, splice, stop_at_at, stop_at_next_at, }
}

///|
/// The state of parsing a SEQUENCE of groups: the top level, the inside of an
/// opener-closer pair, or the body of a block.
priv struct GState {
  count : Bool
  closer : Closer
  paren_immed : ParenImmed
  column : @column.Column?
  bar_column : @column.Column?
  /// Whether the next group must start at exactly `column`. Recomputed after
  /// each group: only a group that starts a new line has to line up.
  check_column : Bool
  bar_closes : Bool
  bar_closes_line : Int?
  block_mode : BlockMode
  can_empty : Bool
  /// Whether a `,` is expected before the next group.
  comma_time : Bool
  sequence_mode : SequenceMode
  /// `None` after a `\` continuation. See `PState::line`.
  last_line : Int?
  delta : Int
  /// A `#//` waiting for the group it comments out.
  commenting : @lexer.Token?
  /// A `#//` seen after the last group, which may yet find one.
  tail_commenting : @lexer.Token?
  raw : RawList
  variant : @lexer.Variant
  /// How many sequences are open around this one: one per bracket pair and one
  /// per block, which is one stack frame per level in a parser that recurs
  /// through the grammar. Bounded, so that input nested past anything a person
  /// writes is refused with a diagnostic rather than by running out of stack --
  /// which on the native backend is a signal, not an error a caller can catch.
  depth : Int
}

///|
/// A group still being assembled.
///
/// `bar` is set when the group came from a `|`, which `tag_as_block` needs to
/// know and the finished tree has no way to say. The reference marks it with a
/// temporary `bar` tag inside the group and strips it later; a field keeps the
/// public shape honest and the check typed.
priv struct PendingGroup {
  items : Array[@ast.Node]
  bar : @ast.Node?
  span : @basic.Span
  meta : @raw.Meta
}

///|
/// What `parse_groups` answers.
///
/// The reference returns seven values positionally; naming them is the one
/// change that makes the port readable, and it costs one allocation per group.
priv struct GroupsResult {
  groups : Array[PendingGroup]
  rest : Int
  end_line : Int?
  end_delta : Int
  /// The token that ended the sequence, when that was a closer. NOT consumed
  /// unless it was matched: `rest` may still point at it, which is the
  /// reference's "leave it in place" contract made explicit.
  end_token : @lexer.Token?
  tail_commenting : @lexer.Token?
  tail_raw : RawList
}

///|
/// What `parse_group` answers.
priv struct GroupResult {
  items : Array[@ast.Node]
  rest : Int
  end_line : Int?
  end_delta : Int
  tail_commenting : @lexer.Token?
  tail_raw : RawList
}
