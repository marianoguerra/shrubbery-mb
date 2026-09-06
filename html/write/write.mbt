///|
/// The printer: a markup tree back to markup text.
///
/// Three modes, one traversal, exactly as the CSS printer does it, and for the
/// same reason: HTML has no expression nesting to break intelligently across
/// lines, so a Wadler-style layout engine would have nothing to search over.
///
/// What HTML has instead, and CSS does not, is whitespace that MEANS something.
/// A pretty-printer that adds a newline between two inline elements changes
/// what the page looks like. That is the whole of Prettier's
/// `htmlWhitespaceSensitivity`, and this takes the same three-valued option
/// under the same names, because it is the only widely deployed answer and
/// because a user who knows Prettier's flag already knows this one.
///
/// The default, `Css`, is conservative in a way worth stating: whitespace is
/// rearranged only where it is already insignificant -- inside a block-level
/// element all of whose children are themselves block-level or whitespace. Not
/// "inside a block element", which would collapse `<p>a <em>b</em></p>`; not
/// "wherever it looks safe", which is a guess. `Minified` obeys the same
/// restriction: a minifier that collapsed the runs inside a `<span>` would be
/// smaller and wrong.
///
/// This package depends on `ast`, `names` and `kind`, and nothing else -- not
/// on the parser, not on `error-report`. Building a tree in memory and printing
/// it is a complete use of this library on its own.

///|
/// How much whitespace to spend.
pub(all) enum Style {
  /// One node per line, two-space indent. What a person reads.
  Pretty
  /// One node per line, no indent. What a diff reads.
  Compact
  /// No whitespace that can be dropped without changing what renders.
  Minified
} derive(Eq)

///|
/// How much whitespace is allowed to move.
///
/// Prettier's option, and its three values. `Css` consults the default
/// `display` of each element; `Strict` treats every space as significant and
/// reformats nothing; `Ignore` treats none of them as significant and lays out
/// freely, which is right for generated markup and wrong for a page a person
/// wrote.
pub(all) enum Whitespace {
  Css
  Strict
  Ignore
} derive(Eq)

///|
priv struct Printer {
  buf : StringBuilder
  style : Style
  ws : Whitespace
  /// What could not be printed faithfully. Empty for every tree that came from
  /// a parse; non-empty only for a hand-built tree that asked for something
  /// markup cannot express.
  problems : Array[(@kind.ErrorKind, @span.Span)]
  mut depth : Int
  /// Whether the attribute written most recently went out without quotes.
  /// Read by the `/>` branch, which cannot be emitted straight after one.
  mut unquoted_last : Bool
}

///|
fn Printer::new(style : Style, ws : Whitespace) -> Printer {
  {
    buf: StringBuilder(),
    style,
    ws,
    problems: [],
    depth: 0,
    unquoted_last: false,
  }
}

///|
/// Render a document.
pub fn document(
  doc : @ast.Document,
  style? : Style = Pretty,
  whitespace? : Whitespace = Css,
) -> String {
  let (text, _) = document_checked(doc, style~, whitespace~)
  text
}

///|
/// Render a document, and say what could not be printed faithfully.
///
/// There is exactly one thing in that category and it is not a formatting
/// nicety: a `script` or `style` body containing the element's own end tag, or
/// a comment body containing `-->`. Raw text ends at the first `</name` and
/// nothing escapes it, so a printer's only honest answers are to refuse or to
/// silently change the text -- and silently changing the text of a script is
/// how a formatter becomes a security bug. This refuses: the bytes go out
/// unchanged, and the caller is told the tree cannot be printed.
pub fn document_checked(
  doc : @ast.Document,
  style? : Style = Pretty,
  whitespace? : Whitespace = Css,
) -> (String, Array[(@kind.ErrorKind, @span.Span)]) {
  let p = Printer::new(style, whitespace)
  p.write_top(doc.children, p.children_breakable(doc.children, true))
  let text = p.buf.to_string()
  // Only when there is not one already. A document whose last node is a text
  // run ending in a newline already has it, and adding a second would make the
  // next pass add a third: printing has to be a fixed point, not a ratchet.
  let out = if p.style != Minified &&
    text.length() > 0 &&
    !text.has_suffix("\n") {
    text + "\n"
  } else {
    text
  }
  (out, p.problems)
}

///|
/// Render one node, for a test or for a diagnostic that quotes one.
pub fn node(
  n : @ast.Node,
  style? : Style = Pretty,
  whitespace? : Whitespace = Css,
) -> String {
  let p = Printer::new(style, whitespace)
  p.write_node(n)
  p.buf.to_string()
}

///|
/// Render one element.
pub fn element(
  e : @ast.Element,
  style? : Style = Pretty,
  whitespace? : Whitespace = Css,
) -> String {
  node(Element(e), style~, whitespace~)
}

// ------------------------------------------------------------------ layout

///|
/// Whether whitespace between these children may be rearranged.
///
/// The rule is deliberately narrow. Every child has to be something whose
/// surrounding whitespace is already insignificant -- a block-level element, a
/// comment, a doctype, or a text node that is nothing but whitespace -- and one
/// inline child anywhere in the list turns the whole run verbatim. That is
/// stricter than Prettier, which will break inline content and reflow it, and
/// the difference is a deliberate trade: this library never has to be right
/// about how a browser collapses a run, because it never touches one.
///
/// `Bogus` is never layoutable. A region the parser could not read is a region
/// whose whitespace nobody can reason about.
fn Printer::children_breakable(
  self : Printer,
  children : Array[@ast.Node],
  container_is_block : Bool,
) -> Bool {
  match self.ws {
    Strict => false
    Ignore => container_is_block
    Css => {
      if !container_is_block {
        return false
      }
      for c in children {
        if !child_is_layoutable(c) {
          return false
        }
      }
      true
    }
  }
}

///|
fn child_is_layoutable(n : @ast.Node) -> Bool {
  match n {
    Text(t) => is_all_whitespace(t.text)
    Element(e) => {
      // An element with no end tag LEAKS: anything the parent writes after it
      // becomes part of its content, so a newline added here would be swallowed
      // and re-added on the next pass, and the file would grow every time it
      // was formatted. `<ul><li>a<li>b</ul>` therefore comes back on one line.
      match e.closing {
        Implied | Unclosed => return false
        _ => ()
      }
      match display_of_element(e) {
        Block | None_ => true
        _ => false
      }
    }
    Comment(_) | Doctype(_) => true
    // Raw text and CDATA are text, exactly: whitespace around them is content
    // and moving it changes what the script or the section says.
    RawText(_) | Cdata(_, _) => false
    Bogus(_) => false
  }
}

///|
/// An element's default display, which only HTML elements have.
///
/// Foreign content is laid out by SVG's or MathML's own rules and not by CSS's
/// default stylesheet, so every foreign element answers `Inline` -- which makes
/// the printer leave its whitespace exactly as written. That is the right
/// answer for the wrong-looking reason: whitespace inside `<text>` in SVG is
/// significant, and this library has no table that would say so.
fn display_of_element(e : @ast.Element) -> @names.Display {
  match e.name.ns {
    Html => @names.display_of(e.name.name)
    _ => Inline
  }
}

///|
fn is_all_whitespace(s : String) -> Bool {
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

///|
/// A line break and the current indentation, in whichever style is in force.
fn Printer::newline(self : Printer) -> Unit {
  match self.style {
    Minified => ()
    Compact => self.buf.write_char('\n')
    Pretty => {
      self.buf.write_char('\n')
      let mut i = 0
      while i < self.depth {
        self.buf.write_string("  ")
        i = i + 1
      }
    }
  }
}

///|
/// The document's own children, which have no enclosing tag.
///
/// Separate from `write_children` because there is no `</...>` to line up
/// under: nodes are separated rather than surrounded, so there is no leading
/// newline and no indentation to add.
fn Printer::write_top(
  self : Printer,
  children : Array[@ast.Node],
  breakable : Bool,
) -> Unit {
  if !breakable {
    for c in children {
      self.write_node(c)
    }
    return
  }
  let mut first = true
  for c in children {
    match c {
      Text(t) => if is_all_whitespace(t.text) { continue }
      _ => ()
    }
    if !first {
      self.newline()
    }
    self.write_node(c)
    first = false
  }
}

///|
/// An element's children. Answers whether they were laid out on lines, which
/// is what the caller needs in order to decide where its end tag goes -- and
/// an element with an IMPLIED end tag has none, so a trailing newline there
/// would be a blank line with nothing under it.
fn Printer::write_children(
  self : Printer,
  children : Array[@ast.Node],
  breakable : Bool,
) -> Bool {
  if !breakable {
    for c in children {
      self.write_node(c)
    }
    return false
  }
  self.depth = self.depth + 1
  let mut wrote = false
  for c in children {
    match c {
      Text(t) => if is_all_whitespace(t.text) { continue }
      _ => ()
    }
    self.newline()
    self.write_node(c)
    wrote = true
  }
  self.depth = self.depth - 1
  wrote
}

// ------------------------------------------------------------------- nodes

///|
fn Printer::write_node(self : Printer, n : @ast.Node) -> Unit {
  match n {
    Element(e) => self.write_element(e)
    Text(t) =>
      match t.raw {
        Some(raw) => self.buf.write_string(raw)
        None => self.buf.write_string(escape_text(t.text))
      }
    RawText(r) => self.buf.write_string(r.text)
    Comment(c) => {
      if c.text.contains("-->") {
        self.problems.push((UnprintableRawText("comment"), c.span))
      }
      self.buf.write_string("<!--")
      self.buf.write_string(c.text)
      self.buf.write_string("-->")
    }
    Doctype(d) => self.write_doctype(d)
    Cdata(text, _) => {
      self.buf.write_string("<![CDATA[")
      self.buf.write_string(text)
      self.buf.write_string("]]>")
    }
    Bogus(b) => self.buf.write_string(b.text)
  }
}

///|
fn Printer::write_element(self : Printer, e : @ast.Element) -> Unit {
  let tag = e.name.name
  self.buf.write_char('<')
  self.buf.write_string(tag)
  self.unquoted_last = false
  for a in e.attrs {
    self.write_attr(a)
  }
  match e.closing {
    SelfClosing => {
      if self.style == Minified && e.name.ns == Html {
        self.buf.write_char('>')
      } else {
        // An unquoted value runs up to the `>`, so `<circle r=1/>` is an
        // attribute whose value is `1/` and an element that never closes. The
        // space is one byte and the alternative is silently wrong markup.
        if self.unquoted_last {
          self.buf.write_char(' ')
        }
        self.buf.write_string("/>")
      }
      return
    }
    Void => {
      self.buf.write_char('>')
      return
    }
    _ => self.buf.write_char('>')
  }
  let mut broke = false
  if @names.is_raw_text(tag) || @names.is_escapable_raw_text(tag) {
    self.write_raw_body(e, tag)
  } else {
    let breakable = self.children_breakable(
      e.children,
      match display_of_element(e) {
        Block | None_ => true
        _ => false
      },
    )
    broke = self.write_children(e.children, breakable)
  }
  match e.closing {
    Explicit => {
      if broke {
        self.newline()
      }
      self.buf.write_string("</")
      self.buf.write_string(tag)
      self.buf.write_char('>')
    }
    // An implied end tag stays implied, and an unclosed element stays
    // unclosed. Materialising either would be a change the source did not ask
    // for, and both round-trip: reparsing what was printed gives the same
    // `Closing` back, which is what makes printing a fixed point.
    _ => ()
  }
}

///|
/// The body of a `script`, `style`, `title` or `textarea`.
///
/// `pre` is not here -- it is an ordinary element whose whitespace happens to
/// be significant, and `Display::Pre` already stops the printer touching it.
/// What is here is text that is not markup, where the only question is whether
/// it can be written down at all.
fn Printer::write_raw_body(
  self : Printer,
  e : @ast.Element,
  tag : String,
) -> Unit {
  for c in e.children {
    match c {
      RawText(r) => {
        if !raw_text_is_printable(r.text, tag) {
          self.problems.push((UnprintableRawText(tag), r.span))
        }
        self.buf.write_string(r.text)
      }
      Text(t) =>
        // Escapable raw text: `<title>a &amp; b</title>`. References resolve
        // here, so the text is escaped on the way out -- as TEXT, `<` included.
        // Escaping it as an attribute value instead leaves the `<` live, and a
        // `<title>` whose text contains `</title>` then ends its own element:
        // the same injection a `<script>` body would be, in the one raw-text
        // context that has an escape and can therefore be printed safely.
        match t.raw {
          Some(raw) => self.buf.write_string(raw)
          None => self.buf.write_string(escape_text(t.text))
        }
      other => self.write_node(other)
    }
  }
}

///|
fn Printer::write_attr(self : Printer, a : @ast.Attribute) -> Unit {
  self.buf.write_char(' ')
  self.buf.write_string(a.name.text())
  self.unquoted_last = false
  match a.value {
    Empty => ()
    Value(v, raw) => {
      self.buf.write_char('=')
      let body = match raw {
        Some(r) => r
        None => escape_attr(v)
      }
      if self.style == Minified && raw is None && may_go_unquoted(v) {
        self.buf.write_string(body)
        self.unquoted_last = true
      } else {
        self.buf.write_char('"')
        self.buf.write_string(body)
        self.buf.write_char('"')
      }
    }
  }
}

///|
fn Printer::write_doctype(self : Printer, d : @ast.Doctype) -> Unit {
  self.buf.write_string("<!DOCTYPE ")
  self.buf.write_string(d.name)
  match d.public_id {
    Some(p) => {
      self.buf.write_string(" PUBLIC \"")
      self.buf.write_string(p)
      self.buf.write_char('"')
      match d.system_id {
        Some(s) => {
          self.buf.write_string(" \"")
          self.buf.write_string(s)
          self.buf.write_char('"')
        }
        None => ()
      }
    }
    None =>
      match d.system_id {
        Some(s) => {
          self.buf.write_string(" SYSTEM \"")
          self.buf.write_string(s)
          self.buf.write_char('"')
        }
        None => ()
      }
  }
  self.buf.write_char('>')
}
