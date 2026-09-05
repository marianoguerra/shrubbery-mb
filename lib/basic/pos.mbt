///|
/// A position in a source file.
///
/// Four numbers, in three different units, and keeping them apart is the first
/// thing this port has to get right:
///
///   * `line` and `pos` are what Racket's `port-next-location` reports, in CODE
///     POINTS. They are what `raw-srcloc` carries, and what the oracle compares,
///     so they cannot be approximated by anything cheaper.
///   * `idx` is a UTF-16 code-unit index. It exists to slice a MoonBit `String`
///     and to hand a span to `error-report`, and it is never reported.
///   * `col` is the INDENTATION column, which is a partial order rather than a
///     number — see `@column.Column`. It is not `pos` minus the line start:
///     tabs and grapheme clusters both make it something else.
pub(all) struct Pos {
  /// 1-based.
  line : Int
  /// 1-based code points from the start of the source.
  pos : Int
  /// 0-based UTF-16 code units from the start of the source. Slicing only.
  idx : Int
  /// The indentation column.
  col : @column.Column
} derive(Eq)

///|
pub let start : Pos = { line: 1, pos: 1, idx: 0, col: @column.zero, }

///|
/// A half-open range of a source file.
pub(all) struct Span {
  start : Pos
  end : Pos
} derive(Eq)

///|
/// An empty span at `p`, for an error that has no extent — an unexpected end of
/// input, or a missing closer.
pub fn Span::at(p : Pos) -> Span {
  { start: p, end: p, }
}

///|
/// The smallest span covering both.
pub fn Span::merge(self : Span, other : Span) -> Span {
  let start = if self.start.idx <= other.start.idx {
    self.start
  } else {
    other.start
  }
  let end = if self.end.idx >= other.end.idx { self.end } else { other.end }
  { start, end, }
}

///|
/// Length in UTF-16 code units — the unit `error-report` spans are in.
pub fn Span::units(self : Span) -> Int {
  self.end.idx - self.start.idx
}

///|
/// `line:col`, 1-based on both, for a message.
pub fn Pos::to_display(self : Pos) -> String {
  "\{self.line}:\{self.col.to_display()}"
}
