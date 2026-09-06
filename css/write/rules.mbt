///|
/// Rules and at-rules.
///
/// Split from `write.mbt` only for size: it is the same printer, and the same
/// three modes.

///|
fn Printer::write_rule(self : Printer, r : @ast.CssRule) -> Unit {
  match r {
    Style(s) => {
      self.write_selector_list(s.selectors[:])
      self.write_body(s.body[:])
    }
    Media(m) => {
      self.put("@media")
      if m.queries.length() > 0 {
        self.put(" ")
        self.write_media_queries(m.queries[:])
      }
      self.write_body(m.body[:])
    }
    Supports(s) => {
      self.put("@supports ")
      self.write_condition(s.condition, top=true)
      self.write_body(s.body[:])
    }
    Container(c) => {
      self.put("@container")
      match c.name {
        Some(n) => {
          self.put(" ")
          self.put(n)
        }
        None => ()
      }
      self.put(" ")
      self.write_condition(c.condition, top=true)
      self.write_body(c.body[:])
    }
    Layer(l) => {
      self.put("@layer")
      if l.names.length() > 0 {
        self.put(" ")
        let mut first = true
        for n in l.names {
          if !first {
            self.put(",")
            self.sp()
          }
          first = false
          self.write_layer_name(n)
        }
      }
      match l.body {
        Some(body) => self.write_body(body[:])
        None => self.put(";")
      }
    }
    Keyframes(k) => {
      self.put("@keyframes ")
      match k.name {
        Ident(n) => self.put(n)
        Str(s) => self.write_quoted(s)
      }
      self.write_keyframes_body(k.frames[:])
    }
    FontFace(b) => {
      self.put("@font-face")
      self.write_decl_body(b)
    }
    Page(p) => {
      self.put("@page")
      if p.selectors.length() > 0 {
        self.put(" ")
        let mut first = true
        for s in p.selectors {
          if !first {
            self.put(",")
            self.sp()
          }
          first = false
          self.put(s)
        }
      }
      self.write_body(p.body[:])
    }
    Property(p) => {
      self.put("@property ")
      self.put(p.name)
      self.write_decl_body(p.decls)
    }
    Import(i) => {
      self.put("@import ")
      self.write_quoted(i.url)
      match i.layer {
        None => ()
        Some(None) => self.put(" layer")
        Some(Some(n)) => {
          self.put(" layer(")
          self.write_layer_name(n)
          self.put(")")
        }
      }
      match i.supports {
        None => ()
        Some(c) => {
          self.put(" supports(")
          self.write_condition(c, top=false)
          self.put(")")
        }
      }
      if i.media.length() > 0 {
        self.put(" ")
        self.write_media_queries(i.media[:])
      }
      self.put(";")
    }
    Charset(cs, _) => {
      self.put("@charset ")
      self.write_quoted(cs)
      self.put(";")
    }
    Namespace(n) => {
      self.put("@namespace ")
      match n.prefix {
        Some(p) => {
          self.put(p)
          self.put(" ")
        }
        None => ()
      }
      self.write_quoted(n.url)
      self.put(";")
    }
    Scope(s) => {
      self.put("@scope")
      match s.start {
        Some(sels) => {
          self.put(" (")
          self.write_selector_list(sels[:])
          self.put(")")
        }
        None => ()
      }
      match s.end {
        Some(sels) => {
          self.put(" to (")
          self.write_selector_list(sels[:])
          self.put(")")
        }
        None => ()
      }
      self.write_body(s.body[:])
    }
    StartingStyle(body, _) => {
      self.put("@starting-style")
      self.write_body(body[:])
    }
    CounterStyle(name, b) => {
      self.put("@counter-style ")
      self.put(name)
      self.write_decl_body(b)
    }
    Unknown(u) => {
      self.put("@")
      self.put(u.name)
      if u.prelude.length() > 0 {
        self.put(" ")
        self.write_values(u.prelude[:])
      }
      match u.block {
        Some(body) => self.write_body(body[:])
        None => self.put(";")
      }
    }
    Bogus(b) => self.put(b.text)
  }
}

///|
fn Printer::write_layer_name(self : Printer, n : @ast.LayerName) -> Unit {
  let mut first = true
  for part in n.parts {
    if !first {
      self.put(".")
    }
    first = false
    self.put(part)
  }
}

///|
/// `@keyframes` bodies are not `BlockItem` lists -- every entry is a keyframe,
/// so they get their own loop rather than being forced through the general one.
fn Printer::write_keyframes_body(
  self : Printer,
  frames : ArrayView[@ast.KeyframeBlock],
) -> Unit {
  self.sp()
  self.put("{")
  if frames.length() == 0 {
    self.put("}")
    return
  }
  self.depth = self.depth + 1
  for f in frames {
    self.nl()
    let mut first = true
    for s in f.selectors {
      if !first {
        self.put(",")
        self.sp()
      }
      first = false
      match s {
        From => self.put("from")
        To => self.put("to")
        Percentage(n) => {
          self.put(n.repr)
          self.put("%")
        }
      }
    }
    self.write_decl_body(f.decls)
  }
  self.depth = self.depth - 1
  self.nl()
  self.put("}")
}

// ----------------------------------------------------------------- conditions

///|
fn Printer::write_media_queries(
  self : Printer,
  qs : ArrayView[@ast.MediaQuery],
) -> Unit {
  let mut first = true
  for q in qs {
    if !first {
      self.put(",")
      self.sp()
    }
    first = false
    self.write_media_query(q)
  }
}

///|
fn Printer::write_media_query(self : Printer, q : @ast.MediaQuery) -> Unit {
  let mut wrote = false
  match q.qualifier {
    Some(Only) => {
      self.put("only")
      wrote = true
    }
    Some(Not) => {
      self.put("not")
      wrote = true
    }
    None => ()
  }
  match q.media_type {
    Some(t) => {
      if wrote {
        self.put(" ")
      }
      self.put(t)
      wrote = true
    }
    None => ()
  }
  match q.condition {
    Some(c) => {
      if wrote {
        self.put(" and ")
      }
      self.write_condition(c, top=true)
    }
    None => ()
  }
}

///|
/// A condition.
///
/// `top` says whether this position already supplies parentheses. A feature
/// always writes its own, so `@media (width > 40rem)` is right; a nested
/// operand of `and`/`or` needs them only when it is itself an operation, which
/// is the one place the printer has to think.
fn Printer::write_condition(
  self : Printer,
  c : @ast.Condition,
  top~ : Bool,
) -> Unit {
  ignore(top)
  match c {
    Feature(f) => self.write_feature(f)
    Decl(d) => {
      self.put("(")
      self.write_decl(d)
      self.put(")")
    }
    SelectorFn(sels) => {
      self.put("selector(")
      self.write_selector_list(sels[:])
      self.put(")")
    }
    Operation(Not, conds) => {
      self.put("not ")
      match conds {
        [only] => self.write_operand(only)
        _ =>
          // `not` is unary; more than one operand is a malformed tree rather
          // than a malformed stylesheet, so print them all and let the
          // round-trip test catch it rather than silently dropping any.
          for i, cc in conds {
            if i > 0 {
              self.put(" and ")
            }
            self.write_operand(cc)
          }
      }
    }
    Operation(op, conds) => {
      let sep = match op {
        And => " and "
        Or => " or "
        Not => " and "
      }
      let mut first = true
      for cc in conds {
        if !first {
          self.put(sep)
        }
        first = false
        self.write_operand(cc)
      }
    }
    Unknown(vs) => {
      self.put("(")
      self.write_values(vs[:])
      self.put(")")
    }
    Bogus(b) => self.put(b.text)
  }
}

///|
/// An operand of `and`/`or`/`not`: parenthesised exactly when it is itself an
/// operation, because CSS forbids mixing operators without parentheses and a
/// nested one has to say where it begins.
fn Printer::write_operand(self : Printer, c : @ast.Condition) -> Unit {
  match c {
    Operation(_, _) => {
      self.put("(")
      self.write_condition(c, top=false)
      self.put(")")
    }
    _ => self.write_condition(c, top=false)
  }
}

///|
fn Printer::write_feature(self : Printer, f : @ast.Feature) -> Unit {
  self.put("(")
  match f {
    Boolean(n) => self.put(n)
    Plain(n, vs) => {
      self.put(n)
      self.put(":")
      self.sp()
      self.write_values(vs[:])
    }
    Range(n, op, vs) => {
      self.put(n)
      self.sp()
      self.put(op.text())
      self.sp()
      self.write_values(vs[:])
    }
    Interval(lo, op1, n, op2, hi) => {
      self.write_values(lo[:])
      self.sp()
      self.put(op1.text())
      self.sp()
      self.put(n)
      self.sp()
      self.put(op2.text())
      self.sp()
      self.write_values(hi[:])
    }
  }
  self.put(")")
}
