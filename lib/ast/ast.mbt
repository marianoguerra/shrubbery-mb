///|
/// A parsed shrubbery.
///
/// The shape mirrors the reference's S-expression representation exactly,
/// because that representation IS the interface: it is what `#{...}` escapes
/// speak, what the parse oracle compares, and what a language built on this
/// notation will pattern-match. A more strongly typed tree -- one where a
/// group's optional block and alternatives were separate fields, so that the
/// grammar's two structural laws were unrepresentable rather than merely true
/// -- was the alternative, and it would have made the parser port a translation
/// rather than a transcription of a mutual recursion with fourteen threaded
/// state fields. The laws are stated below and checked by the oracle instead.
///
/// The laws, for the record:
///
///   * `Block` appears only as the last item of a `Group`, or as the
///     second-to-last with `Alts` after it.
///   * `Alts` appears only as the last item of a `Group`, and contains only
///     `Block`s.
///   * A `Group` is never empty.
pub(all) enum Shrub {
  /// An identifier, including the `#%` internal form and `#{...}` escapes that
  /// named a symbol.
  Id(String)
  /// `~name`.
  Kw(String)
  /// An operator. Prints as `(op name)`, and the metadata lives on this node
  /// rather than on the `op` wrapper the reference writes.
  Op(String)
  /// A number, string, byte string, boolean, character or `#void`.
  Lit(@sexp.Datum)
  /// A value spliced in by something built on this notation, opaque here.
  Parsed(@sexp.Datum)
  Group(Array[Node])
  Block(Array[Node])
  Alts(Array[Node])
  Parens(Array[Node])
  Brackets(Array[Node])
  Braces(Array[Node])
  Quotes(Array[Node])
  /// A whole document: the result of parsing in `top` mode.
  Multi(Array[Node])
}

///|
/// One node: what it is, where it came from, and how to write it back.
pub(all) struct Node {
  it : Shrub
  span : @basic.Span
  meta : @raw.Meta
}

///|
pub fn Node::new(
  it : Shrub,
  span : @basic.Span,
  meta? : @raw.Meta = @raw.Meta::new(),
) -> Node {
  { it, span, meta, }
}

///|
/// The children of a compound node, or an empty array for a leaf.
pub fn Node::children(self : Node) -> Array[Node] {
  match self.it {
    Group(xs)
    | Block(xs)
    | Alts(xs)
    | Parens(xs)
    | Brackets(xs)
    | Braces(xs)
    | Quotes(xs)
    | Multi(xs) => xs
    _ => []
  }
}

///|
/// The reference's tag for this node, for messages and for the oracle.
pub fn Shrub::tag(self : Shrub) -> String {
  match self {
    Id(_) => "identifier"
    Kw(_) => "keyword"
    Op(_) => "op"
    Lit(_) => "literal"
    Parsed(_) => "parsed"
    Group(_) => "group"
    Block(_) => "block"
    Alts(_) => "alts"
    Parens(_) => "parens"
    Brackets(_) => "brackets"
    Braces(_) => "braces"
    Quotes(_) => "quotes"
    Multi(_) => "multi"
  }
}

///|
/// The canonical text form, for comparing our parse against the reference's.
///
/// This is the S-expression the reference produces, written with `@sexp`'s
/// escaping so that both sides of the comparison are all-ASCII and an encoding
/// difference in transit cannot look like a parse difference.
pub fn Node::canonical(self : Node) -> String {
  let buf = StringBuilder()
  self.write_canonical(buf)
  buf.to_string()
}

///|
pub fn Node::write_canonical(self : Node, buf : StringBuilder) -> Unit {
  match self.it {
    Id(name) => @sexp.Datum::Sym(name).write_canonical(buf)
    Kw(name) => @sexp.Datum::Kw(name).write_canonical(buf)
    Op(name) => {
      buf.write_string("(op ")
      @sexp.Datum::Sym(name).write_canonical(buf)
      buf.write_char(')')
    }
    Lit(d) => d.write_canonical(buf)
    Parsed(d) => {
      buf.write_string("(parsed ")
      d.write_canonical(buf)
      buf.write_char(')')
    }
    _ => {
      buf.write_char('(')
      buf.write_string(self.it.tag())
      for child in self.children() {
        buf.write_char(' ')
        child.write_canonical(buf)
      }
      buf.write_char(')')
    }
  }
}

///|
/// The source text this node came from, rebuilt from its metadata.
///
/// Emission order is the field order of `@raw.Meta` and is load-bearing --
/// prefix, inner prefix, raw, then children or `opaque_content`, then tail,
/// inner suffix, suffix -- with `opaque_raw` superseding the middle three.
pub fn Node::write_source(self : Node, buf : StringBuilder) -> Unit {
  let m = self.meta
  m.prefix.write_to(buf)
  m.inner_prefix.write_to(buf)
  if !m.opaque_raw.is_empty() {
    m.opaque_raw.write_to(buf)
  } else {
    m.raw.write_to(buf)
    if !m.opaque_content.is_empty() {
      m.opaque_content.write_to(buf)
    } else {
      for child in self.children() {
        child.write_source(buf)
      }
    }
    m.tail.write_to(buf)
  }
  m.inner_suffix.write_to(buf)
  m.suffix.write_to(buf)
}

///|
/// The source text this node came from.
pub fn Node::to_source(self : Node) -> String {
  let buf = StringBuilder()
  self.write_source(buf)
  buf.to_string()
}
