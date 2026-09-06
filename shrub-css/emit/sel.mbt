///|
/// Selectors, back to shrubbery.
///
/// Compound parts are separated by a space. That is not a choice about
/// readability: `a` followed by `class(b)` written together would lex as the
/// single identifier `aclass`, so the space is load-bearing -- and harmless,
/// because juxtaposition inside a run is a compound and whitespace carries no
/// meaning of its own.

///|
fn Emitter::write_selector_list(
  self : Emitter,
  sels : ArrayView[@ast.Selector],
) -> Unit {
  match sels {
    [only] => self.write_selector(only)
    _ => {
      // More than one is a list, and a comma may only live inside a bracket.
      self.put("[")
      let mut first = true
      for s in sels {
        if !first {
          self.put(", ")
        }
        first = false
        self.write_selector(s)
      }
      self.put("]")
    }
  }
}

///|
fn Emitter::write_selector(self : Emitter, s : @ast.Selector) -> Unit {
  match s {
    Simple(c) => self.write_compound(c)
    Complex(left, comb, right) => {
      self.write_selector(left)
      self.put(" ~")
      self.put(@names.combinator_keyword(from_ast_combinator(comb)))
      self.put(" ")
      self.write_compound(right)
    }
    Relative(comb, inner) => {
      self.put("~")
      self.put(@names.combinator_keyword(from_ast_combinator(comb)))
      self.put(" ")
      self.write_selector(inner)
    }
    // There is no honest shrubbery spelling for a selector that did not parse.
    // Emitting a plausible one -- `any()`, say -- would quietly change what the
    // stylesheet matches, so this emits something that is deliberately not a
    // selector and fails loudly when the file is read back.
    Bogus(b) => {
      self.put("unreadable(")
      self.write_string(b.text)
      self.put(")")
    }
  }
}

///|
fn from_ast_combinator(c : @ast.Combinator) -> @names.Combinator {
  match c {
    Descendant => Descendant
    Child => Child
    NextSibling => NextSibling
    SubsequentSibling => SubsequentSibling
    Column => Column
  }
}

///|
fn Emitter::write_compound(self : Emitter, c : @ast.Compound) -> Unit {
  let parts : Array[String] = []
  let mut ns : @ast.NsPrefix? = None
  match c.type_sel {
    Some(Named(p, n)) => {
      ns = p
      parts.push(type_name(n))
    }
    Some(Universal(p)) => {
      ns = p
      parts.push("any()")
    }
    None => if c.quals.length() == 0 { parts.push("any()") }
  }
  // A namespace binds to its type selector, and the surface writes it after
  // the name -- the lowering applies it backwards to whatever it follows.
  match ns {
    Some(p) => parts.push(ns_call(p))
    None => ()
  }
  for q in c.quals {
    parts.push(qualifier(q))
  }
  let mut first = true
  for p in parts {
    if !first {
      self.put(" ")
    }
    first = false
    self.put(p)
  }
}

///|
/// A type selector's name, escaped where a bare identifier would be read as
/// something else.
///
/// An at-rule's name is the case that matters: `media:` in statement position
/// is the at-rule, so an element genuinely called `media` needs `tag(media)`.
fn type_name(n : String) -> String {
  match @names.kebab(n) {
    Some(k) =>
      if @names.is_at_rule(n) || @names.is_reserved_call(k) {
        "tag(" + k + ")"
      } else {
        k
      }
    None => "tag(" + quoted(n) + ")"
  }
}

///|
fn ns_call(p : @ast.NsPrefix) -> String {
  match p {
    None_ => "ns()"
    Any => "ns(any())"
    Named(n) =>
      match @names.kebab(n) {
        Some(k) => "ns(" + k + ")"
        None => "ns(" + quoted(n) + ")"
      }
  }
}

///|
fn qualifier(q : @ast.Qualifier) -> String {
  match q {
    Class(n) => "class(" + name_or_string(n) + ")"
    Id(n) => "id(" + name_or_string(n) + ")"
    Nesting => "parent()"
    Attr(a) => attr(a)
    Pseudo(p) => pseudo(p)
    Element(e) => "element(" + pseudo_element(e) + ")"
    Bogus(b) => "unreadable(" + quoted(b.text) + ")"
  }
}

///|
/// A name as a bare identifier where it can be, and as a string where it
/// cannot -- which is what the literal escape is for.
fn name_or_string(n : String) -> String {
  match @names.kebab(n) {
    Some(k) => k
    None => quoted(n)
  }
}

///|
fn attr(a : @ast.AttrSelector) -> String {
  let b = StringBuilder()
  b.write_string("has_attr(")
  match a.ns {
    Some(p) => {
      b.write_string(ns_call(p))
      b.write_string(" ")
    }
    None => ()
  }
  b.write_string(name_or_string(a.name))
  match a.matcher {
    None => ()
    Some((op, v)) => {
      b.write_string(" ")
      b.write_string(op.text())
      b.write_string(" ")
      match v {
        Str(s) => b.write_string(quoted(s))
        Ident(s) => b.write_string(name_or_string(s))
      }
    }
  }
  match a.case_ {
    Default => ()
    Insensitive => b.write_string(" ~i")
    Sensitive => b.write_string(" ~s")
  }
  b.write_string(")")
  b.to_string()
}

///|
fn pseudo(p : @ast.PseudoClass) -> String {
  match p {
    Simple(n) => name_or_string(n) + "()"
    Sub(n, sels) => {
      let inner = { buf: StringBuilder(), depth: 0, }
      let mut first = true
      for s in sels {
        if !first {
          inner.put(", ")
        }
        first = false
        inner.write_selector(s)
      }
      name_or_string(n) + "(" + inner.buf.to_string() + ")"
    }
    Nth(n, anb, of_) => {
      let b = StringBuilder()
      b.write_string(name_or_string(n))
      b.write_string("(")
      b.write_string(anb_text(anb))
      match of_ {
        None => ()
        Some(sels) => {
          b.write_string(" of ")
          let inner = { buf: StringBuilder(), depth: 0, }
          let mut first = true
          for s in sels {
            if !first {
              inner.put(", ")
            }
            first = false
            inner.write_selector(s)
          }
          b.write_string(inner.buf.to_string())
        }
      }
      b.write_string(")")
      b.to_string()
    }
    Lang(langs) => {
      let b = StringBuilder()
      b.write_string("lang(")
      let mut first = true
      for l in langs {
        if !first {
          b.write_string(", ")
        }
        first = false
        b.write_string(name_or_string(l))
      }
      b.write_string(")")
      b.to_string()
    }
    Dir(d) => "dir(" + name_or_string(d) + ")"
    Unknown(n, args) => {
      let inner = { buf: StringBuilder(), depth: 0, }
      inner.write_comma_groups(args[:])
      name_or_string(n) + "(" + inner.buf.to_string() + ")"
    }
  }
}

///|
fn pseudo_element(e : @ast.PseudoElement) -> String {
  match e {
    Simple(n) => name_or_string(n)
    Sub(n, sels) => {
      let inner = { buf: StringBuilder(), depth: 0, }
      let mut first = true
      for s in sels {
        if !first {
          inner.put(", ")
        }
        first = false
        inner.write_selector(s)
      }
      name_or_string(n) + "(" + inner.buf.to_string() + ")"
    }
    Fn(n, args) => {
      let inner = { buf: StringBuilder(), depth: 0, }
      inner.write_comma_groups(args[:])
      name_or_string(n) + "(" + inner.buf.to_string() + ")"
    }
  }
}

///|
/// `An+B`, spaced so that the number never runs into the `n`.
///
/// `2n` is a lexical error in shrubbery -- a number may not be followed by a
/// letter -- so the space is required, not stylistic. This is the last place
/// that rule still shows, now that dimensions are calls.
fn anb_text(anb : @ast.AnB) -> String {
  if anb.a == 0 {
    return anb.b.to_string()
  }
  let b = StringBuilder()
  if anb.a == 1 {
    b.write_string("n")
  } else if anb.a == -1 {
    b.write_string("- n")
  } else {
    b.write_string(anb.a.to_string())
    b.write_string(" n")
  }
  if anb.b > 0 {
    b.write_string(" + ")
    b.write_string(anb.b.to_string())
  } else if anb.b < 0 {
    b.write_string(" - ")
    b.write_string((-anb.b).to_string())
  }
  b.to_string()
}
