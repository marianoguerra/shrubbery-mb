///|
/// Original source text, as a tree.
///
/// A tree rather than a string because the parser splices pieces together on
/// nearly every step -- a comment moves from one node's prefix to another's
/// suffix, a commented-out group is rendered into the text around it -- and a
/// `String` would make each of those a copy. It is flattened once, by a
/// preorder walk, when something finally asks for the text.
pub(all) enum Raw {
  Empty
  Str(String)
  Cons(Raw, Raw)
} derive(Eq)

///|
/// The reference's `combine-shrubbery-raw`: joins two, and answers with the
/// other one when either is empty.
pub fn Raw::combine(self : Raw, other : Raw) -> Raw {
  match (self, other) {
    (Empty, _) => other
    (_, Empty) => self
    _ => Cons(self, other)
  }
}

///|
pub fn Raw::is_empty(self : Raw) -> Bool {
  match self {
    Empty => true
    Str(s) => s == ""
    Cons(a, b) => a.is_empty() && b.is_empty()
  }
}

///|
pub fn Raw::write_to(self : Raw, buf : StringBuilder) -> Unit {
  match self {
    Empty => ()
    Str(s) => buf.write_string(s)
    Cons(a, b) => {
      a.write_to(buf)
      b.write_to(buf)
    }
  }
}

///|
pub fn Raw::to_text(self : Raw) -> String {
  let buf = StringBuilder()
  self.write_to(buf)
  buf.to_string()
}

///|
/// The nine raw-text properties a node can carry.
///
/// **The field order is the emission order**, and it is load-bearing: prefix,
/// inner prefix, raw, then either the children or `opaque_content`, then tail,
/// inner suffix, suffix. Anything that emits these in a different order
/// round-trips wrongly on exactly the inputs that have comments in the awkward
/// places, and on nothing else.
pub(all) struct Meta {
  /// Whitespace and comments before the term, belonging to whatever encloses
  /// it. The parser uses this only when the text cannot instead be a preceding
  /// term's suffix.
  mut prefix : Raw
  /// Like `prefix`, but sticking to the term rather than shifting left. The
  /// parser uses it for exactly one thing: the `@` before an at-form.
  mut inner_prefix : Raw
  /// The term's own text; for a compound, its opener.
  mut raw : Raw
  /// Stands in for the children's text, hiding them.
  mut opaque_content : Raw
  /// Supersedes `raw` and `opaque_content` both. Set by macro expansion
  /// downstream, never by the parser.
  mut opaque_raw : Raw
  /// Text after the children but belonging to the compound: its closer.
  mut tail : Raw
  /// Like `suffix`, but sticking to the term. The parser never sets it.
  mut inner_suffix : Raw
  /// Whitespace and comments after the term.
  mut suffix : Raw
  /// A span for a compound tag, which would otherwise only have the derived
  /// one its children imply.
  mut srcloc : @basic.Span?
}

///|
pub fn Meta::new() -> Meta {
  {
    prefix: Empty,
    inner_prefix: Empty,
    raw: Empty,
    opaque_content: Empty,
    opaque_raw: Empty,
    tail: Empty,
    inner_suffix: Empty,
    suffix: Empty,
    srcloc: None,
  }
}

///|
/// Whether anything at all is recorded here.
pub fn Meta::is_empty(self : Meta) -> Bool {
  self.prefix.is_empty() &&
  self.inner_prefix.is_empty() &&
  self.raw.is_empty() &&
  self.opaque_content.is_empty() &&
  self.opaque_raw.is_empty() &&
  self.tail.is_empty() &&
  self.inner_suffix.is_empty() &&
  self.suffix.is_empty()
}
