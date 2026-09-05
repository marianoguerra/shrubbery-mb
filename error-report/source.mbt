///|
/// Identifies one source file within a report. Opaque on purpose: it is handed
/// out by whatever cache the consumer uses and means nothing on its own.
pub(all) struct SourceId(Int) derive(Eq, Compare, Hash, Debug, ToJson)

///|
/// A source file, with the line index precomputed.
///
/// Building one is O(n) in the text, so build it once and share it. Every
/// offset in the API -- `line_starts`, and everything on `Span` -- is a UTF-16
/// code-unit offset into `text`.
pub struct Source {
  name : String
  text : String
  /// Offset of the first code unit of each line. Always starts with 0, so the
  /// length is the line count and `line_starts[i]` is the start of line `i+1`
  /// in 1-based numbering.
  line_starts : Array[Int]
}

///|
/// Index `text`, recognising all three line terminators.
///
/// A `\r\n` counts as one break, and a lone `\r` counts as a break too --
/// which is what a user staring at the file in an editor sees, and what the
/// language specifications that still admit a bare `\r` require. Getting this wrong shows up as every caret after
/// the first CRLF sitting one column to the right, which is subtle enough to
/// ship.
pub fn Source::new(name : String, text : String) -> Source {
  let line_starts = [0]
  let n = text.length()
  let mut i = 0
  while i < n {
    let c = text.at(i)
    if c == 0x0A {
      i = i + 1
      line_starts.push(i)
    } else if c == 0x0D {
      i = i + 1
      if i < n && text.at(i) == 0x0A {
        i = i + 1
      }
      line_starts.push(i)
    } else {
      i = i + 1
    }
  }
  { name, text, line_starts, }
}

///|
/// Number of lines. A file with no trailing newline still counts its last line;
/// a file that ends in a newline has a final empty line, which is what an
/// editor shows and where an end-of-file caret has to go.
pub fn Source::line_count(self : Source) -> Int {
  self.line_starts.length()
}

///|
/// The 0-based line containing `offset`, by binary search.
///
/// An offset past the end clamps to the last line rather than failing: a
/// diagnostic pointing just past the end of the file is a normal thing (an
/// unexpected end of input), not a caller error.
pub fn Source::line_of(self : Source, offset : Int) -> Int {
  let mut lo = 0
  let mut hi = self.line_starts.length() - 1
  while lo < hi {
    let mid = (lo + hi + 1) / 2
    if self.line_starts[mid] <= offset {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  lo
}

///|
/// The text of a 0-based line, without its terminator.
pub fn Source::line_text(self : Source, line : Int) -> String {
  if line < 0 || line >= self.line_starts.length() {
    return ""
  }
  let start = self.line_starts[line]
  let end = if line + 1 < self.line_starts.length() {
    self.line_starts[line + 1]
  } else {
    self.text.length()
  }
  // Strip the terminator: the index points past it, so walk back over at most
  // one `\n` and then at most one `\r`.
  let mut e = end
  if e > start && self.text.at(e - 1) == 0x0A {
    e = e - 1
  }
  if e > start && self.text.at(e - 1) == 0x0D {
    e = e - 1
  }
  self.text.clamped_view(start~, end=e).to_owned()
}

///|
/// 1-based line and 0-based column of `offset`, with the column in CODE POINTS.
///
/// The column is not the raw offset difference: a surrogate pair is one column
/// and two code units, so a caret under an emoji would otherwise land one
/// column late for every character after it on the line.
pub fn Source::line_col(self : Source, offset : Int) -> (Int, Int) {
  let line = self.line_of(offset)
  let start = self.line_starts[line]
  let end = if offset < start { start } else { offset }
  (line + 1, self.text.char_length(start_offset=start, end_offset=end))
}

///|
/// Convert a code-point offset into the code-unit offset this library uses.
///
/// The boundary function for a producer that counts code points, which most
/// hand-written lexers and every Racket port do. O(n) in the offset, so convert
/// once per span and not once per lookup.
pub fn Source::offset_of_char(self : Source, char_offset : Int) -> Int {
  match self.text.offset_of_nth_char(char_offset) {
    Some(i) => i
    // Past the end: clamp, for the same reason `line_of` clamps.
    None => self.text.length()
  }
}

///|
/// Build a span from code-point offsets.
pub fn Source::span_of_chars(self : Source, start : Int, end : Int) -> Span {
  Span::of_range(self.offset_of_char(start), self.offset_of_char(end))
}

///|
/// The text a span covers.
pub fn Source::slice(self : Source, span : Span) -> String {
  let n = self.text.length()
  let s = if span.start < 0 {
    0
  } else if span.start > n {
    n
  } else {
    span.start
  }
  let e0 = span.end()
  let e = if e0 < s { s } else if e0 > n { n } else { e0 }
  self.text.clamped_view(start=s, end=e).to_owned()
}

///|
/// Where a report's renderer gets its sources from.
///
/// The single extension point of this library, and deliberately the only one:
/// a consumer that reads from disk, or from an editor's unsaved buffers,
/// implements this and nothing else. `Sources` below is the in-memory
/// implementation, which is what most callers want.
pub(open) trait SourceCache {
  fn fetch(Self, SourceId) -> Source?
}

///|
/// An in-memory `SourceCache`.
pub struct Sources {
  entries : Array[Source]
}

///|
pub fn Sources::new() -> Sources {
  { entries: [], }
}

///|
/// Add a file and get the id to put in its labels.
pub fn Sources::add(self : Sources, name : String, text : String) -> SourceId {
  self.entries.push(Source::new(name, text))
  SourceId(self.entries.length() - 1)
}

///|
pub impl SourceCache for Sources with fn fetch(self, id) {
  let SourceId(i) = id
  if i >= 0 && i < self.entries.length() {
    Some(self.entries[i])
  } else {
    None
  }
}
