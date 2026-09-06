///|
/// The vocabulary: what each name in the shrubbery surface means in markup.
///
/// These tables are the syntax. The whole design rests on three laws -- an
/// element is a call and its children are its block, its attributes are its
/// arguments, and text is a string literal -- and the tables are where the
/// edges of those laws are decided: which names are taken, which spellings are
/// reachable, and what to write when one is not.
///
/// Data rather than code, so that a reader can check the mapping at a glance
/// and a disagreement about one entry is a one-line change.

// ------------------------------------------------------ identifier spelling

///|
/// A shrubbery identifier as a markup name: `_` becomes `-`.
///
/// The transform is needed because `-` is an operator in shrubbery, so
/// `data-id` lexes as three tokens and the tree cannot tell it from
/// `data - id`.
///
/// A name that already contains a `-` is passed through untouched. That is not
/// a special case for tidiness: the only way a `-` can reach an identifier is
/// through a `#{...}` escape, which the lexer resolves to the symbol's own
/// name, and a name written that way was written literally on purpose.
pub fn unkebab(s : String) -> String {
  if s.contains("-") {
    s
  } else {
    s.replace_all(old="_", new="-")
  }
}

///|
/// A markup name as a shrubbery identifier, or `None` if it cannot be one.
///
/// `None` in three cases, and each sends the caller to the literal escape --
/// `element("...")`, `attr("...", "...")`:
///
///   * the name contains a `_`, because `unkebab` would then not invert and
///     `side_bar` would come back as `side-bar`;
///   * the name is not spellable as an identifier at all -- `xlink:href`,
///     `2col`, an empty name;
///   * the name is one this syntax has taken for something else.
///
/// Returning an option rather than guessing is what makes the escape reachable
/// instead of hypothetical.
pub fn kebab(s : String) -> String? {
  if s.contains("_") {
    return None
  }
  let candidate = s.replace_all(old="-", new="_")
  if !is_identifier(candidate) {
    return None
  }
  if is_reserved_call(candidate) {
    return None
  }
  Some(candidate)
}

///|
/// Whether a string can be written as a bare shrubbery identifier.
///
/// ASCII-only, deliberately. Shrubbery admits far more than this -- letters in
/// every script, and emoji sequences -- but a bridge that tried to decide which
/// of those the lexer would accept would be reimplementing the lexer's Unicode
/// tables in order to guess. Being narrow here costs a quoted escape on a name
/// nobody writes and cannot be wrong.
pub fn is_identifier(s : String) -> Bool {
  let n = s.length()
  if n == 0 {
    return false
  }
  let first = s.unsafe_get(0).to_int().unsafe_to_char()
  if !is_alpha(first) && first != '_' {
    return false
  }
  let mut i = 1
  while i < n {
    let c = s.unsafe_get(i).to_int().unsafe_to_char()
    if !is_alpha(c) && !is_digit(c) && c != '_' {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

// ----------------------------------------------------------- reserved calls

///|
/// A call name this syntax has taken for something that is not an element.
///
/// Nine of them, and the list is short on purpose: every entry is a name a page
/// can no longer use for an element without the escape, and SVG really does
/// have a `<text>`. The alternative -- a sigil, a keyword, a different bracket
/// -- would buy those nine names back and cost the one rule that makes the
/// syntax learnable, which is that a thing is a call.
pub fn is_reserved_call(name : String) -> Bool {
  match name {
    "doctype"
    | "comment"
    | "text"
    | "raw"
    | "cdata"
    | "element"
    | "attr"
    | "frag"
    | "bogus" => true
    _ => false
  }
}

///|
/// How to write an element whose name has no bare spelling.
pub fn element_escape(name : String) -> String {
  "element(" + quote(name) + ")"
}

///|
/// A string literal, in shrubbery's spelling.
///
/// Shrubbery takes JSON's escapes, so this is the same routine every emitter
/// needs and it lives here because both `emit` and any future consumer of these
/// tables need it to be the same one.
pub fn quote(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.unsafe_get(i).to_int().unsafe_to_char()
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ =>
        if c.to_int() < 0x20 {
          buf.write_string("\\u{")
          buf.write_string(hex(c.to_int()))
          buf.write_char('}')
        } else {
          buf.write_char(c)
        }
    }
    i = i + 1
  }
  buf.write_char('"')
  buf.to_string()
}

///|
fn hex(n : Int) -> String {
  if n == 0 {
    return "0"
  }
  let digits = "0123456789ABCDEF"
  let out : Array[Char] = []
  let mut v = n
  while v > 0 {
    out.push(digits.unsafe_get(v % 16).to_int().unsafe_to_char())
    v = v / 16
  }
  let buf = StringBuilder()
  let mut i = out.length() - 1
  while i >= 0 {
    buf.write_char(out[i])
    i = i - 1
  }
  buf.to_string()
}
