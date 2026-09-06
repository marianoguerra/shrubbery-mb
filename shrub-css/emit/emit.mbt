///|
/// A CSS syntax tree back to shrubbery notation.
///
/// The other half of the bridge, and the direction that makes the loop close:
/// CSS in, shrubbery out, lower it again and get the same tree.
///
/// This emits SOURCE TEXT rather than building a shrubbery `Node` tree. A tree
/// would have to carry spans and raw metadata that describe a file that does
/// not exist, and the printer would then be reconstructing text from metadata
/// it had just invented. Emitting text directly makes the claim checkable
/// instead: what comes out is parsed and lowered again, and compared.
///
/// What it does NOT promise is that `emit` inverts `lower` byte for byte. It
/// cannot: `1/2` and `1 / 2` are the same value, `+1` loses its sign to the
/// lexer, and a name may have arrived through either of two escapes. The
/// promise is one normalisation pass -- `emit ∘ lower` is idempotent -- and
/// that `lower ∘ emit` is the identity on trees this library can represent.

///|
/// A CSS stylesheet as shrubbery-CSS source.
pub fn stylesheet(sheet : @ast.Stylesheet) -> String {
  let e = { buf: StringBuilder(), depth: 0, }
  e.write_sheet(sheet)
  e.buf.to_string()
}

///|
/// One rule, for tests and for quoting a rule in a message.
pub fn rule(r : @ast.CssRule) -> String {
  let e = { buf: StringBuilder(), depth: 0, }
  e.write_rule(r)
  e.buf.to_string()
}

///|
/// One selector.
pub fn selector(s : @ast.Selector) -> String {
  let e = { buf: StringBuilder(), depth: 0, }
  e.write_selector(s)
  e.buf.to_string()
}

///|
/// A value list, the contents of one declaration.
pub fn value(vs : Array[@ast.ComponentValue]) -> String {
  let e = { buf: StringBuilder(), depth: 0, }
  e.write_value_list(vs[:])
  e.buf.to_string()
}

///|
priv struct Emitter {
  buf : StringBuilder
  mut depth : Int
}

///|
fn Emitter::put(self : Emitter, s : String) -> Unit {
  self.buf.write_string(s)
}

///|
fn Emitter::nl(self : Emitter) -> Unit {
  self.put("\n")
  for _ in 0..<self.depth {
    self.put("  ")
  }
}

// ------------------------------------------------------------------ document

///|
fn Emitter::write_sheet(self : Emitter, sheet : @ast.Stylesheet) -> Unit {
  let mut first = true
  for item in sheet.items {
    if !first {
      self.nl()
    }
    first = false
    match item {
      Rule(r) => self.write_rule(r)
      Comment(c) => self.write_comment(c)
      Bogus(b) => self.write_bogus(b)
    }
  }
  if !first {
    self.put("\n")
  }
}

///|
/// A CSS comment as a call.
///
/// Not as a shrubbery comment, which is the obvious thing and the wrong one: a
/// `//` or `/* */` in shrubbery is trivia, and trivia lives in the node's raw
/// metadata rather than in the tree. The lowering never reads metadata -- that
/// purity is what makes it total -- so a comment written as a comment would be
/// dropped on the way back, and a stylesheet would quietly lose every note in
/// it.
///
/// A comment is data in the CSS tree, so it is written as data here. `comment`
/// joins the same family as every other call.
fn Emitter::write_comment(self : Emitter, c : @ast.Comment) -> Unit {
  self.put("comment(")
  self.write_string(c.text)
  self.put(")")
}

///|
/// An unparsable region, carried across as a comment.
///
/// Its text is CSS, not shrubbery -- it came from a CSS parse -- so emitting it
/// bare would put CSS into a shrubbery file and break the next read. A comment
/// keeps it visible and inert, which is the most that can honestly be done
/// with it.
fn Emitter::write_bogus(self : Emitter, b : @ast.Bogus) -> Unit {
  self.put("// unreadable: ")
  for line in b.text.split("\n") {
    self.put(line.to_owned())
    break
  }
}

///|
/// A block: `:` then an indented body, or `«»` when there is nothing in it.
///
/// The empty case is not cosmetic. Shrubbery rejects a block with no groups,
/// so an empty CSS rule has to use the explicit delimiters or the output does
/// not parse.
fn Emitter::write_body(
  self : Emitter,
  items : ArrayView[@ast.BlockItem],
) -> Unit {
  if items.length() == 0 {
    self.put(": «»")
    return
  }
  self.put(":")
  self.depth = self.depth + 1
  for item in items {
    self.nl()
    match item {
      Decl(d) => self.write_decl(d)
      Rule(r) => self.write_rule(r)
      Comment(c) => self.write_comment(c)
      Bogus(b) => self.write_bogus(b)
    }
  }
  self.depth = self.depth - 1
}

///|
fn Emitter::write_decl_body(self : Emitter, b : @ast.DeclBlock) -> Unit {
  self.write_body(b.decls[:])
}

// --------------------------------------------------------------- declaration

///|
fn Emitter::write_decl(self : Emitter, d : @ast.Declaration) -> Unit {
  match d.property {
    Ident(n) =>
      match @names.kebab(n) {
        Some(s) => self.put(s)
        // A property name that cannot be a bare identifier takes the literal
        // escape rather than being mangled.
        None => {
          self.put("ident(")
          self.write_string(n)
          self.put(")")
        }
      }
    Custom(n) => self.put(custom_property(n))
  }
  self.put(": ")
  self.write_value_list(d.value[:])
  if d.important {
    if d.value.length() > 0 {
      self.put(" ")
    }
    self.put("important()")
  }
}

///|
/// `--brand-fg` as `--brand_fg`, keeping the sigil CSS itself uses.
fn custom_property(n : String) -> String {
  let body = if n.has_prefix("--") {
    n.clamped_view(start=2).to_owned()
  } else {
    n
  }
  match @names.kebab(body) {
    Some(s) => "--" + s
    None => "ident(" + quoted(n) + ")"
  }
}

// -------------------------------------------------------------------- values

///|
/// A declaration's value.
///
/// A top-level comma has to become a bracket, because shrubbery admits a comma
/// only inside one. Everything else is emitted in place.
fn Emitter::write_value_list(
  self : Emitter,
  vs : ArrayView[@ast.ComponentValue],
) -> Unit {
  if has_top_comma(vs) {
    self.put("[")
    self.write_comma_groups(vs)
    self.put("]")
  } else {
    self.write_values(vs)
  }
}

///|
fn has_top_comma(vs : ArrayView[@ast.ComponentValue]) -> Bool {
  for v in vs {
    if v is Comma {
      return true
    }
  }
  false
}

///|
/// Values split on commas, which become group separators.
fn Emitter::write_comma_groups(
  self : Emitter,
  vs : ArrayView[@ast.ComponentValue],
) -> Unit {
  let mut from = 0
  let mut first = true
  for i, v in vs {
    if v is Comma {
      if !first {
        self.put(", ")
      }
      first = false
      self.write_values(vs[from:i])
      from = i + 1
    }
  }
  if !first {
    self.put(", ")
  }
  self.write_values(vs[from:])
}

///|
/// A run of values with no top-level comma in it.
fn Emitter::write_values(
  self : Emitter,
  vs : ArrayView[@ast.ComponentValue],
) -> Unit {
  let mut first = true
  for i, v in vs {
    if !first {
      self.put(" ")
    }
    first = false
    // An identifier immediately before a group is indistinguishable from a
    // call: shrubbery does not record the space, so `not (x)` and `not(x)`
    // are the same nodes. The literal escape is not a call, so it keeps the
    // two apart -- and CSS does distinguish them, in `@supports` above all.
    let next_is_group = i + 1 < vs.length() && vs[i + 1] is Paren(_)
    match v {
      Ident(s) if next_is_group => {
        self.put("ident(")
        self.write_string(s)
        self.put(")")
      }
      _ => self.write_value(v)
    }
  }
}

///|
fn Emitter::write_value(self : Emitter, v : @ast.ComponentValue) -> Unit {
  match v {
    Ident(s) => self.write_ident_value(s)
    Str(s) => self.write_string(s)
    Num(n) => self.put(number(n))
    Dimension(n, u) =>
      match @names.unit_call(u) {
        Some(call) => {
          self.put(call)
          self.put("(")
          self.put(number(n))
          self.put(")")
        }
        // A unit this library does not know still round-trips, through the
        // escape that names it as a string.
        None => {
          self.put("dim(")
          self.put(number(n))
          self.put(", ")
          self.write_string(u)
          self.put(")")
        }
      }
    Percentage(n) => {
      self.put("percent(")
      self.put(number(n))
      self.put(")")
    }
    Hex(d) => {
      self.put("hex(")
      // A bare identifier only when the digits could be one AND survive the
      // number lexer: `f7f7f7` can, `007700` cannot -- it would be read as an
      // integer and lose its zeros.
      if hex_is_bare(d) {
        self.put(d)
      } else {
        self.write_string(d)
      }
      self.put(")")
    }
    Url(u) => {
      self.put("url(")
      self.write_string(u)
      self.put(")")
    }
    Function(f, args) => {
      self.put(call_name(f))
      self.put("(")
      self.write_comma_groups(args[:])
      self.put(")")
    }
    Paren(inner) => {
      self.put("(")
      self.write_comma_groups(inner[:])
      self.put(")")
    }
    Bracket(inner) => {
      self.put("[")
      self.write_comma_groups(inner[:])
      self.put("]")
    }
    Comma => self.put(",")
    Slash => self.put("/")
    // Most delimiters are operators in shrubbery too and pass straight
    // through. Three are not: `:` opens a block, `;` ends a group, and `,`
    // separates them -- so a value containing one (an IE `progid:` filter, a
    // `@custom-selector` prelude, YAML front matter) needs the escape, or the
    // emitted file would be structured by its own data.
    Delim(s) =>
      if s == ":" || s == ";" || s == "," {
        self.put("delim(")
        self.write_string(s)
        self.put(")")
      } else {
        self.put(s)
      }
    Bogus(_) => self.put("/* unreadable */")
  }
}

///|
/// An identifier in value position, including a dashed one.
fn Emitter::write_ident_value(self : Emitter, s : String) -> Unit {
  if s.has_prefix("--") {
    self.put(custom_property(s))
    return
  }
  match @names.kebab(s) {
    Some(k) => self.put(k)
    None => {
      self.put("ident(")
      self.write_string(s)
      self.put(")")
    }
  }
}

///|
/// A CSS function's name, escaped when it collides with a bridge word.
///
/// `percent`, `hex`, `px` and the rest are calls this syntax has claimed, so a
/// CSS function that happened to share one of those names would be read as the
/// wrong thing. There is no such function today; the guard exists so that if
/// one ever appears it is a spelling change here rather than a silent
/// misreading.
fn call_name(f : String) -> String {
  match @names.kebab(f) {
    Some(k) =>
      if @names.is_reserved_call(k) {
        "ident(" + quoted(f) + ")"
      } else {
        k
      }
    None => "ident(" + quoted(f) + ")"
  }
}

///|
/// A number, in a spelling shrubbery reads back as the same number.
///
/// A leading `+` is dropped, because the lexer drops it: `+1` reads as `1`, and
/// emitting the plus would produce a file that lowers to a different `repr`
/// than the one it came from. This is the one place the round trip normalises a
/// value rather than preserving it, and it is forced.
fn number(n : @ast.Number) -> String {
  if n.repr.has_prefix("+") {
    n.repr.clamped_view(start=1).to_owned()
  } else {
    n.repr
  }
}

///|
/// Whether hex digits can be written bare.
///
/// They can only if they start with a letter. `f7f7f7` is an identifier;
/// `007700` is an integer, and by the time anything reads it back the leading
/// zeros are gone -- which is exactly the failure the lowering refuses to
/// guess at, so the emitter must not create it.
fn hex_is_bare(d : String) -> Bool {
  if d.length() == 0 {
    return false
  }
  let c = d.unsafe_get(0).to_int().unsafe_to_char()
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
/// A double-quoted shrubbery string.
fn Emitter::write_string(self : Emitter, s : String) -> Unit {
  self.put(quoted(s))
}

///|
fn quoted(s : String) -> String {
  let b = StringBuilder()
  b.write_string("\"")
  for c in s {
    match c {
      '"' => b.write_string("\\\"")
      '\\' => b.write_string("\\\\")
      '\n' => b.write_string("\\n")
      '\r' => b.write_string("\\r")
      '\t' => b.write_string("\\t")
      _ => b.write_char(c)
    }
  }
  b.write_string("\"")
  b.to_string()
}
