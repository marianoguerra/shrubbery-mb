///|
/// A markup tree back to shrubbery notation.
///
/// The direction that closes the loop: hand it markup and it hands back
/// notation that lowers to the same tree. It is a NORMALISATION rather than an
/// inverse, and what it normalises is exactly what the notation has no way to
/// say:
///
///   * `<br/>` comes back as `br()`, because a void element's slash is a house
///     style and there is no notation for a house style;
///   * an implied end tag becomes an explicit one, because the notation has no
///     end tags at all -- children are a block, and a block always closes;
///   * an unclosed element is closed, for the same reason.
///
/// Everything else round-trips: text and its whitespace, attribute order and
/// emptiness, comments, doctypes, CDATA, namespaces and their case.
///
/// One child per line, always. A run on one line is legal notation and reads
/// well when nothing in it has children, but a block runs to the end of its
/// line -- so an emitter that inlined a run would eventually write the one
/// construct that parses cleanly and means the wrong thing. Refusing to inline
/// costs a few lines and makes that unreachable from anything this emits.

///|
priv struct Emitter {
  buf : StringBuilder
  mut depth : Int
}

///|
/// Render a document as Shrubbery HTML.
pub fn document(doc : @ast.Document) -> String {
  let e = { buf: StringBuilder(), depth: 0, }
  for child in doc.children {
    e.line(child)
  }
  e.buf.to_string()
}

///|
/// Render one node, for a test or a diagnostic that quotes one.
pub fn node(n : @ast.Node) -> String {
  let e = { buf: StringBuilder(), depth: 0, }
  e.line(n)
  e.buf.to_string()
}

///|
/// Render one element.
pub fn element(el : @ast.Element) -> String {
  node(Element(el))
}

// ------------------------------------------------------------------ output

///|
fn Emitter::indent(self : Emitter) -> Unit {
  let mut i = 0
  while i < self.depth {
    self.buf.write_string("  ")
    i = i + 1
  }
}

///|
/// One node, on its own line, with its children indented under it.
fn Emitter::line(self : Emitter, n : @ast.Node) -> Unit {
  match n {
    // A whitespace-only text node between block children is layout in the
    // markup and nothing at all in the notation, where layout carries no
    // meaning. Keeping it would write `"\n  "` into the source as data.
    Text(t) => {
      if is_blank(t.text) {
        return
      }
      self.indent()
      self.buf.write_string(@names.quote(t.text))
      self.buf.write_char('\n')
    }
    RawText(r) => {
      self.indent()
      self.buf.write_string("raw(")
      self.buf.write_string(@names.quote(r.text))
      self.buf.write_string(")\n")
    }
    Comment(c) => {
      self.indent()
      self.buf.write_string("comment(")
      self.buf.write_string(@names.quote(c.text))
      self.buf.write_string(")\n")
    }
    Cdata(text, _) => {
      self.indent()
      self.buf.write_string("cdata(")
      self.buf.write_string(@names.quote(text))
      self.buf.write_string(")\n")
    }
    Doctype(d) => {
      self.indent()
      self.buf.write_string(doctype_call(d))
      self.buf.write_char('\n')
    }
    // A region the parser could not read is echoed verbatim, which `raw` is
    // exactly the notation for. The reason it was bogus is lost; the bytes are
    // not, and the bytes are what a reader needs to fix it.
    Bogus(b) => {
      self.indent()
      self.buf.write_string("raw(")
      self.buf.write_string(@names.quote(b.text))
      self.buf.write_string(")\n")
    }
    Element(el) => self.element_line(el)
  }
}

///|
fn Emitter::element_line(self : Emitter, el : @ast.Element) -> Unit {
  self.indent()
  self.buf.write_string(call_head(el))
  let children = kept_children(el)
  if children.length() == 0 {
    self.buf.write_char('\n')
    return
  }
  self.buf.write_string(":\n")
  self.depth = self.depth + 1
  for c in children {
    self.line(c)
  }
  self.depth = self.depth - 1
}

///|
/// The children worth writing down.
///
/// Whitespace-only text between block-level children is markup layout, and the
/// notation has no layout to put it in. Inside anything else every space is
/// data and every child is kept -- which is the same rule the printer applies
/// in the other direction, stated once more because the two sides have to
/// agree for the loop to close.
fn kept_children(el : @ast.Element) -> Array[@ast.Node] {
  let all_layout = children_are_layout(el)
  let out : Array[@ast.Node] = []
  for c in el.children {
    match c {
      Text(t) => if all_layout && is_blank(t.text) { continue }
      _ => ()
    }
    out.push(c)
  }
  out
}

///|
fn children_are_layout(el : @ast.Element) -> Bool {
  if el.name.ns != Html {
    return false
  }
  match @hnames.display_of(el.name.name) {
    Block | None_ => ()
    _ => return false
  }
  for c in el.children {
    match c {
      Text(t) => if !is_blank(t.text) { return false }
      Element(child) =>
        if child.name.ns != Html {
          return false
        } else {
          match @hnames.display_of(child.name.name) {
            Block | None_ => ()
            _ => return false
          }
        }
      Bogus(_) => return false
      _ => ()
    }
  }
  true
}

///|
fn is_blank(s : String) -> Bool {
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.unsafe_get(i).to_int().unsafe_to_char()
    if c != ' ' && c != '\t' && c != '\n' && c != '\r' && c != '\u{0C}' {
      return false
    }
    i = i + 1
  }
  true
}

// ------------------------------------------------------------------- calls

///|
/// `name(attr: "value", flag)`, without the block.
fn call_head(el : @ast.Element) -> String {
  let buf = StringBuilder()
  match @names.kebab(el.name.name) {
    Some(spelled) => {
      buf.write_string(spelled)
      buf.write_char('(')
    }
    // A name with no bare spelling -- one containing `_`, one this syntax has
    // taken, one that is not an identifier at all -- goes through the literal
    // escape. `element("text")` is how an SVG `<text>` is written.
    None => {
      buf.write_string("element(")
      buf.write_string(@names.quote(el.name.name))
      if el.attrs.length() > 0 {
        buf.write_string(", ")
      }
    }
  }
  let mut first = @names.kebab(el.name.name) is Some(_)
  for a in el.attrs {
    if !first {
      buf.write_string(", ")
    }
    first = false
    buf.write_string(attribute(a))
  }
  buf.write_char(')')
  buf.to_string()
}

///|
fn attribute(a : @ast.Attribute) -> String {
  let written = a.name.text()
  match @names.kebab(written) {
    Some(spelled) =>
      match a.value {
        Empty => spelled
        Value(v, _) => spelled + ": " + @names.quote(v)
      }
    None =>
      match a.value {
        Empty => "attr(" + @names.quote(written) + ")"
        Value(v, _) =>
          "attr(" + @names.quote(written) + ", " + @names.quote(v) + ")"
      }
  }
}

///|
fn doctype_call(d : @ast.Doctype) -> String {
  match (d.public_id, d.system_id) {
    (Some(p), Some(s)) =>
      "doctype(" + @names.quote(p) + ", " + @names.quote(s) + ")"
    (None, None) =>
      if d.name == "html" {
        "doctype()"
      } else {
        "doctype(" + @names.quote(d.name) + ")"
      }
    // A doctype with only one identifier has no shorter spelling than the pair,
    // and inventing a third form for a shape nothing on the web uses would be
    // one more thing for the lowering to have to know.
    (Some(p), None) =>
      "doctype(" + @names.quote(p) + ", " + @names.quote("") + ")"
    (None, Some(s)) =>
      "doctype(" + @names.quote("") + ", " + @names.quote(s) + ")"
  }
}
