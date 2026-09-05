///|
/// A half-open range of a source file.
///
/// **The unit is UTF-16 code units** -- the same unit `String::length`,
/// `String::at` and `String::get_view` use, so slicing a source is direct and
/// carries no hidden conversion. That choice is deliberate and it is the one
/// thing about this library that will surprise someone: most diagnostic
/// libraries in other languages count bytes, because that is what their
/// strings are made of. Here the strings are UTF-16, so bytes would be the
/// converted unit rather than the native one.
///
/// A producer that counts something else -- code points, as Racket's
/// `port-next-location` does, or bytes, as a UTF-8 lexer does -- converts once,
/// at the boundary, with `Source::span_of_chars` or `Source::span_of_bytes`.
/// Converting at the boundary is cheap; converting inside the renderer, on
/// every label of every report, is not.
pub(all) struct Span {
  /// Offset of the first code unit.
  start : Int
  /// Number of code units. Zero is legal and means an insertion point.
  len : Int
} derive(Eq, Compare, Hash, Debug, ToJson)

///|
/// The span `[start, end)`.
pub fn Span::of_range(start : Int, end : Int) -> Span {
  { start, len: if end > start { end - start } else { 0 }, }
}

///|
/// An insertion point: an empty span at `offset`.
pub fn Span::at(offset : Int) -> Span {
  { start: offset, len: 0, }
}

///|
/// Offset one past the last code unit.
pub fn Span::end(self : Span) -> Int {
  self.start + self.len
}

///|
pub fn Span::is_empty(self : Span) -> Bool {
  self.len == 0
}

///|
/// Whether the two spans share at least one code unit.
///
/// Two empty spans at the same offset do NOT overlap: an insertion point has no
/// extent, so nothing can be inside it. That matters because the renderer uses
/// this to decide which labels may share an underline row, and two insertion
/// carets at the same column are exactly the case that should sit side by side.
pub fn Span::overlaps(self : Span, other : Span) -> Bool {
  self.start < other.end() && other.start < self.end()
}

///|
/// The smallest span covering both operands.
pub fn Span::merge(self : Span, other : Span) -> Span {
  let start = if self.start < other.start { self.start } else { other.start }
  let end = if self.end() > other.end() { self.end() } else { other.end() }
  Span::of_range(start, end)
}
