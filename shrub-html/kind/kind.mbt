///|
/// What went wrong in the bridge, as a closed set.
///
/// Separate from `html/kind` because these are different problems: those are
/// about markup that could not be read, these are about notation that could be
/// read and does not mean what it says. A consumer matching on a code should be
/// able to tell the two apart without parsing the string, which is what two
/// namespaces buy.
///
/// This package has no dependencies, for the reason `html/kind` has none: a
/// kind is a name, and naming a problem must not link a renderer.
pub(all) enum ErrorKind {
  /// A `<div>` in the source: someone is writing HTML rather than notation.
  /// Recognised specifically, because the message can then say what to type.
  SigilTag(String)
  /// A call name this syntax has taken: `text()`, `comment()`.
  ReservedCall(String)
  /// A bare identifier where a child was expected. `p` is not `p()`.
  BareTermInBlock(String)
  /// Something in an argument list that is not an attribute.
  AttrNotDeclaration
  /// An attribute value that is not a literal or an identifier.
  BadAttrValue
  /// Children given to an element that cannot have any.
  ChildrenOnVoid(String)
  /// `element()`, `attr()` or `comment()` with the wrong arguments.
  BadEscapeCall(String)
  /// A block on something that is not an element.
  BlockOnNonElement
  /// A `|` alternative, which markup has nothing to mean by.
  AltsUnsupported
  /// A `{...}` or `'...'` group, likewise.
  BracesUnsupported
  /// A run whose last item opened a block, so everything after it went inside.
  /// The one construct that parses cleanly and means the wrong thing.
  TrailingRunAfterBlock
  /// A markup name that is not spellable and was not escaped.
  NameNotSpellable(String)
  /// Anything else this bridge does not implement. Carries what it was.
  Unsupported(String)
} derive(Eq, Debug)

///|
/// A stable identifier for this kind.
///
/// Written out rather than derived from the variant name, so that renaming a
/// variant is a local edit and not a silent break of everything downstream that
/// matched on the string.
pub fn ErrorKind::code(self : ErrorKind) -> String {
  let name = match self {
    SigilTag(_) => "sigil_tag"
    ReservedCall(_) => "reserved_call"
    BareTermInBlock(_) => "bare_term_in_block"
    AttrNotDeclaration => "attr_not_declaration"
    BadAttrValue => "bad_attr_value"
    ChildrenOnVoid(_) => "children_on_void"
    BadEscapeCall(_) => "bad_escape_call"
    BlockOnNonElement => "block_on_non_element"
    AltsUnsupported => "alts_unsupported"
    BracesUnsupported => "braces_unsupported"
    TrailingRunAfterBlock => "trailing_run_after_block"
    NameNotSpellable(_) => "name_not_spellable"
    Unsupported(_) => "unsupported"
  }
  "shrubhtml::" + name
}

///|
/// Whether this kind is a hard error or something a tolerant lowering may
/// carry.
///
/// One warning, and it is the interesting one: a run whose last item opened a
/// block is legal notation that almost certainly means something other than
/// what was intended, so it is worth saying and not worth refusing.
pub fn ErrorKind::is_warning(self : ErrorKind) -> Bool {
  match self {
    TrailingRunAfterBlock => true
    _ => false
  }
}
