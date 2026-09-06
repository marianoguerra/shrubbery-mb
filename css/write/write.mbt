///|
/// The printer: a CSS syntax tree back to CSS text.
///
/// Three modes, one traversal. The alternative -- a Wadler-style layout
/// document, the way `shrubbery`'s own printer works -- would be over-built
/// here: CSS has no expression nesting to break intelligently across lines, and
/// its whole layout question is "one declaration per line, indented by depth".
/// A layout engine earns its keep when there are genuine choices to search
/// over; here there are none, and the direct traversal is both shorter and
/// exactly predictable.
///
/// This package depends on `ast` and `span` and nothing else -- not on the
/// parser, not on `error-report`. Building a tree in memory and printing it is
/// a complete use of this library on its own.

///|
/// How much whitespace to spend.
pub(all) enum Style {
  /// One declaration per line, two-space indent. What a person reads.
  Pretty
  /// One rule per line, declarations inline. What a diff reads.
  Compact
  /// No whitespace that can be dropped, no trailing semicolons.
  Minified
} derive(Eq)

///|
priv struct Printer {
  buf : StringBuilder
  style : Style
  mut depth : Int
}

///|
/// Render a stylesheet.
pub fn stylesheet(sheet : @ast.Stylesheet, style? : Style = Pretty) -> String {
  let p = { buf: StringBuilder(), style, depth: 0, }
  p.write_stylesheet(sheet)
  p.buf.to_string()
}

///|
/// Render one rule, for tests and for error messages that quote a rule.
pub fn rule(r : @ast.CssRule, style? : Style = Pretty) -> String {
  let p = { buf: StringBuilder(), style, depth: 0, }
  p.write_rule(r)
  p.buf.to_string()
}

///|
/// Render one declaration.
pub fn declaration(d : @ast.Declaration, style? : Style = Pretty) -> String {
  let p = { buf: StringBuilder(), style, depth: 0, }
  p.write_decl(d)
  p.buf.to_string()
}

///|
/// Render one selector.
pub fn selector(s : @ast.Selector, style? : Style = Pretty) -> String {
  let p = { buf: StringBuilder(), style, depth: 0, }
  p.write_selector(s)
  p.buf.to_string()
}

///|
/// Render a value list, the contents of one declaration.
pub fn value(
  vs : Array[@ast.ComponentValue],
  style? : Style = Pretty,
) -> String {
  let p = { buf: StringBuilder(), style, depth: 0, }
  p.write_values(vs[:])
  p.buf.to_string()
}

// ------------------------------------------------------------------ mechanics

///|
fn Printer::put(self : Printer, s : String) -> Unit {
  self.buf.write_string(s)
}

///|
fn Printer::is_min(self : Printer) -> Bool {
  self.style == Minified
}

///|
/// A space that only a readable mode spends.
fn Printer::sp(self : Printer) -> Unit {
  if !self.is_min() {
    self.put(" ")
  }
}

///|
/// A line break, or nothing at all when the mode has no lines.
fn Printer::nl(self : Printer) -> Unit {
  match self.style {
    Pretty => {
      self.put("\n")
      for _ in 0..<self.depth {
        self.put("  ")
      }
    }
    Compact => self.put(" ")
    Minified => ()
  }
}

///|
/// The separator between two rules at the same level.
fn Printer::rule_sep(self : Printer) -> Unit {
  match self.style {
    Pretty => {
      self.put("\n")
      for _ in 0..<self.depth {
        self.put("  ")
      }
    }
    Compact => self.put("\n")
    Minified => ()
  }
}

// ------------------------------------------------------------------ stylesheet

///|
fn Printer::write_stylesheet(self : Printer, sheet : @ast.Stylesheet) -> Unit {
  let mut first = true
  for item in sheet.items {
    if !first {
      self.rule_sep()
    }
    first = false
    match item {
      Rule(r) => self.write_rule(r)
      Comment(c) => self.write_comment(c)
      Bogus(b) => self.put(b.text)
    }
  }
  if !self.is_min() && !first {
    self.put("\n")
  }
}

///|
fn Printer::write_comment(self : Printer, c : @ast.Comment) -> Unit {
  self.put("/*")
  self.put(c.text)
  self.put("*/")
}

///|
/// A `{ ... }` body: the one place indentation is decided.
fn Printer::write_body(
  self : Printer,
  items : ArrayView[@ast.BlockItem],
) -> Unit {
  self.sp()
  self.put("{")
  if items.length() == 0 {
    self.put("}")
    return
  }
  self.depth = self.depth + 1
  let mut prev_needs_semi = false
  let mut first = true
  for item in items {
    if !first && prev_needs_semi {
      self.put(";")
    }
    first = false
    self.nl()
    prev_needs_semi = match item {
      Decl(d) => {
        self.write_decl(d)
        true
      }
      Rule(r) => {
        self.write_rule(r)
        false
      }
      Comment(c) => {
        self.write_comment(c)
        false
      }
      Bogus(b) => {
        self.put(b.text)
        false
      }
    }
  }
  // A trailing `;` after the last declaration is optional in CSS and costs a
  // byte, so only the readable modes spend it -- and they spend it because
  // adding a declaration after it should be a one-line diff, not two.
  if prev_needs_semi && !self.is_min() {
    self.put(";")
  }
  self.depth = self.depth - 1
  self.nl()
  self.put("}")
}

///|
fn Printer::write_decl_body(self : Printer, b : @ast.DeclBlock) -> Unit {
  self.write_body(b.decls[:])
}

// ----------------------------------------------------------------- declaration

///|
fn Printer::write_decl(self : Printer, d : @ast.Declaration) -> Unit {
  self.put(d.property.text())
  self.put(":")
  self.sp()
  self.write_values(d.value[:])
  if d.important {
    self.sp()
    self.put("!important")
  }
}

///|
/// Values, with the spacing CSS actually requires.
///
/// The only subtlety is that a `,` binds to what precedes it and a `/` sits
/// between its operands, so neither can take the plain "one space between
/// items" rule. Everything else does.
fn Printer::write_values(
  self : Printer,
  vs : ArrayView[@ast.ComponentValue],
) -> Unit {
  let mut i = 0
  while i < vs.length() {
    let v = vs[i]
    if i > 0 {
      match v {
        Comma => ()
        Slash => self.sp()
        _ =>
          match vs[i - 1] {
            Comma => self.sp()
            Slash => self.sp()
            _ => self.put(" ")
          }
      }
    }
    self.write_value(v)
    i = i + 1
  }
}

///|
fn Printer::write_value(self : Printer, v : @ast.ComponentValue) -> Unit {
  match v {
    Ident(s) => self.put(s)
    Str(s) => self.write_quoted(s)
    Num(n) => self.put(n.repr)
    Dimension(n, u) => {
      self.put(n.repr)
      self.put(u)
    }
    Percentage(n) => {
      self.put(n.repr)
      self.put("%")
    }
    Hex(d) => {
      self.put("#")
      self.put(d)
    }
    Url(u) => {
      self.put("url(")
      self.write_quoted(u)
      self.put(")")
    }
    Function(name, args) => {
      self.put(name)
      self.put("(")
      self.write_values(args[:])
      self.put(")")
    }
    Paren(inner) => {
      self.put("(")
      self.write_values(inner[:])
      self.put(")")
    }
    Bracket(inner) => {
      self.put("[")
      self.write_values(inner[:])
      self.put("]")
    }
    Comma => self.put(",")
    Slash => self.put("/")
    Delim(s) => self.put(s)
    Bogus(b) => self.put(b.text)
  }
}

///|
/// A double-quoted CSS string.
///
/// Double quotes always, because picking whichever quote appears less often in
/// the body would make the output depend on the content in a way that is
/// invisible until a diff shows it.
fn Printer::write_quoted(self : Printer, s : String) -> Unit {
  self.put("\"")
  for c in s {
    match c {
      '"' => self.put("\\\"")
      '\\' => self.put("\\\\")
      '\n' => self.put("\\A ")
      '\r' => self.put("\\D ")
      _ => self.buf.write_char(c)
    }
  }
  self.put("\"")
}

// -------------------------------------------------------------------- selectors

///|
fn Printer::write_selector_list(
  self : Printer,
  sels : ArrayView[@ast.Selector],
) -> Unit {
  let mut first = true
  for s in sels {
    if !first {
      self.put(",")
      self.sp()
    }
    first = false
    self.write_selector(s)
  }
}

///|
fn Printer::write_selector(self : Printer, s : @ast.Selector) -> Unit {
  match s {
    Simple(c) => self.write_compound(c)
    Complex(left, comb, right) => {
      self.write_selector(left)
      self.write_combinator(comb)
      self.write_compound(right)
    }
    Relative(comb, inner) => {
      // A leading combinator keeps its trailing space but never a leading one.
      match comb {
        Descendant => ()
        _ => {
          self.put(comb_text(comb))
          self.sp()
        }
      }
      self.write_selector(inner)
    }
    Bogus(b) => self.put(b.text)
  }
}

///|
/// The descendant combinator IS a space, so it cannot be dropped in minified
/// output the way the others can.
fn Printer::write_combinator(self : Printer, c : @ast.Combinator) -> Unit {
  match c {
    Descendant => self.put(" ")
    _ => {
      self.sp()
      self.put(comb_text(c))
      self.sp()
    }
  }
}

///|
fn comb_text(c : @ast.Combinator) -> String {
  match c {
    Descendant => " "
    Child => ">"
    NextSibling => "+"
    SubsequentSibling => "~"
    Column => "||"
  }
}

///|
fn Printer::write_compound(self : Printer, c : @ast.Compound) -> Unit {
  match c.type_sel {
    Some(t) => self.write_type_selector(t)
    None =>
      // A compound with no type and no qualifiers is the universal selector
      // spelled implicitly; it has to print as something.
      if c.quals.length() == 0 {
        self.put("*")
      }
  }
  for q in c.quals {
    self.write_qualifier(q)
  }
}

///|
fn Printer::write_type_selector(self : Printer, t : @ast.TypeSelector) -> Unit {
  match t {
    Universal(ns) => {
      self.write_ns(ns)
      self.put("*")
    }
    Named(ns, name) => {
      self.write_ns(ns)
      self.put(name)
    }
  }
}

///|
fn Printer::write_ns(self : Printer, ns : @ast.NsPrefix?) -> Unit {
  match ns {
    None => ()
    Some(None_) => self.put("|")
    Some(Any) => self.put("*|")
    Some(Named(n)) => {
      self.put(n)
      self.put("|")
    }
  }
}

///|
fn Printer::write_qualifier(self : Printer, q : @ast.Qualifier) -> Unit {
  match q {
    Class(n) => {
      self.put(".")
      self.put(n)
    }
    Id(n) => {
      self.put("#")
      self.put(n)
    }
    Nesting => self.put("&")
    Attr(a) => self.write_attr(a)
    Pseudo(p) => self.write_pseudo_class(p)
    Element(e) => self.write_pseudo_element(e)
    Bogus(b) => self.put(b.text)
  }
}

///|
fn Printer::write_attr(self : Printer, a : @ast.AttrSelector) -> Unit {
  self.put("[")
  self.write_ns(a.ns)
  self.put(a.name)
  match a.matcher {
    None => ()
    Some((op, v)) => {
      self.put(op.text())
      match v {
        Str(s) => self.write_quoted(s)
        Ident(s) => self.put(s)
      }
      match a.case_ {
        Default => ()
        Insensitive => self.put(" i")
        Sensitive => self.put(" s")
      }
    }
  }
  self.put("]")
}

///|
fn Printer::write_pseudo_class(self : Printer, p : @ast.PseudoClass) -> Unit {
  self.put(":")
  match p {
    Simple(n) => self.put(n)
    Sub(n, sels) => {
      self.put(n)
      self.put("(")
      self.write_selector_list(sels[:])
      self.put(")")
    }
    Nth(n, anb, of_) => {
      self.put(n)
      self.put("(")
      self.write_anb(anb)
      match of_ {
        None => ()
        Some(sels) => {
          self.put(" of ")
          self.write_selector_list(sels[:])
        }
      }
      self.put(")")
    }
    Lang(langs) => {
      self.put("lang(")
      let mut first = true
      for l in langs {
        if !first {
          self.put(",")
          self.sp()
        }
        first = false
        self.put(l)
      }
      self.put(")")
    }
    Dir(d) => {
      self.put("dir(")
      self.put(d)
      self.put(")")
    }
    Unknown(n, args) => {
      self.put(n)
      if args.length() > 0 {
        self.put("(")
        self.write_values(args[:])
        self.put(")")
      }
    }
  }
}

///|
/// `An+B`, in the shortest spelling that means the same thing.
fn Printer::write_anb(self : Printer, anb : @ast.AnB) -> Unit {
  if anb.a == 0 {
    self.put(anb.b.to_string())
    return
  }
  if anb.a == 1 {
    self.put("n")
  } else if anb.a == -1 {
    self.put("-n")
  } else {
    self.put(anb.a.to_string())
    self.put("n")
  }
  if anb.b > 0 {
    self.put("+")
    self.put(anb.b.to_string())
  } else if anb.b < 0 {
    self.put("-")
    self.put((-anb.b).to_string())
  }
}

///|
fn Printer::write_pseudo_element(
  self : Printer,
  e : @ast.PseudoElement,
) -> Unit {
  // Always `::`, even for the four legacy single-colon spellings. The tree
  // records that this is an element, not which colon count the source used,
  // and `::` is correct for all of them.
  self.put("::")
  match e {
    Simple(n) => self.put(n)
    Sub(n, sels) => {
      self.put(n)
      self.put("(")
      self.write_selector_list(sels[:])
      self.put(")")
    }
    Fn(n, args) => {
      self.put(n)
      self.put("(")
      self.write_values(args[:])
      self.put(")")
    }
  }
}
