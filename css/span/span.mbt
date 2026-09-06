///|
/// A half-open range of the source text, in UTF-16 code units.
///
/// Code units rather than code points, and rather than bytes, because that is
/// what a MoonBit `String` is indexed in and what `error-report` labels are
/// measured in. Choosing anything else would put a conversion on every slice
/// and every diagnostic; choosing this one puts it nowhere.
///
/// There is deliberately no line or column here. A span is a range, and a range
/// is enough to slice the source and to hand to a renderer, which computes line
/// and column from the text itself. Carrying them would mean keeping them
/// correct through every construction, for the benefit of nothing that cannot
/// recompute them.
pub(all) struct Span {
  start : Int
  end : Int
} derive(Eq, Debug)

///|
/// The empty span at offset 0, for a node that came from no source at all.
///
/// A hand-built tree needs *some* span, and a fabricated one that pointed
/// somewhere real would make a diagnostic lie about where a problem is. This
/// one is recognisable: `is_nowhere` is what a renderer checks before drawing a
/// caret.
pub let nowhere : Span = { start: 0, end: 0, }

///|
pub fn Span::new(start : Int, end : Int) -> Span {
  { start, end, }
}

///|
/// The empty span at one offset.
pub fn Span::at(offset : Int) -> Span {
  { start: offset, end: offset, }
}

///|
pub fn Span::len(self : Span) -> Int {
  self.end - self.start
}

///|
pub fn Span::is_empty(self : Span) -> Bool {
  self.end <= self.start
}

///|
/// Whether this is the placeholder for "no source".
pub fn Span::is_nowhere(self : Span) -> Bool {
  self.start == 0 && self.end == 0
}

///|
/// The smallest span covering both.
///
/// `nowhere` is absorbing in the useful direction: merging it with a real span
/// gives the real one back, so building a parent's span by folding over
/// children does not get dragged to offset 0 by one synthetic child.
pub fn Span::merge(self : Span, other : Span) -> Span {
  if self.is_nowhere() {
    other
  } else if other.is_nowhere() {
    self
  } else {
    {
      start: if self.start < other.start {
        self.start
      } else {
        other.start
      },
      end: if self.end > other.end {
        self.end
      } else {
        other.end
      },
    }
  }
}

///|
/// Whether `other` lies within this span.
pub fn Span::contains(self : Span, other : Span) -> Bool {
  self.start <= other.start && other.end <= self.end
}

///|
/// The text this span covers, clamped to the string's bounds.
///
/// Clamped rather than checked: a span that runs past the end of its source is
/// a bug, but a diagnostic that crashes while rendering another diagnostic is a
/// worse one.
pub fn Span::slice(self : Span, src : String) -> String {
  let s = if self.start < 0 { 0 } else { self.start }
  let e = if self.end < s { s } else { self.end }
  src.clamped_view(start=s, end=e).to_owned()
}
