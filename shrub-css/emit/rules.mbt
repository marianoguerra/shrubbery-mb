///|
/// Rules and at-rules, back to shrubbery.
///
/// Every at-rule is a call whose name is the at-rule's own, so this is mostly
/// a matter of putting the prelude back into parentheses that CSS had already
/// half written.

///|
fn Emitter::write_rule(self : Emitter, r : @ast.CssRule) -> Unit {
  match r {
    Style(s) => {
      self.write_selector_list(s.selectors[:])
      self.write_body(s.body[:])
    }
    Media(m) => {
      self.put("media(")
      self.write_media_queries(m.queries[:])
      self.put(")")
      self.write_body(m.body[:])
    }
    Supports(s) => {
      self.put("supports(")
      self.write_condition(s.condition)
      self.put(")")
      self.write_body(s.body[:])
    }
    Container(c) => {
      self.put("container(")
      match c.name {
        Some(n) => {
          self.put(name_or_string(n))
          self.put(", ")
        }
        None => ()
      }
      self.write_condition(c.condition)
      self.put(")")
      self.write_body(c.body[:])
    }
    Layer(l) => {
      self.put("layer(")
      let mut first = true
      for n in l.names {
        if !first {
          self.put(", ")
        }
        first = false
        self.write_layer_name(n)
      }
      self.put(")")
      match l.body {
        Some(body) => self.write_body(body[:])
        None => ()
      }
    }
    Keyframes(k) => {
      self.put("keyframes(")
      match k.name {
        Ident(n) => self.put(name_or_string(n))
        Str(s) => self.write_string(s)
      }
      self.put(")")
      self.write_frames(k.frames[:])
    }
    FontFace(b) => {
      self.put("font_face()")
      self.write_decl_body(b)
    }
    Page(p) => {
      self.put("page(")
      let mut first = true
      for s in p.selectors {
        if !first {
          self.put(", ")
        }
        first = false
        self.write_page_selector(s)
      }
      self.put(")")
      self.write_body(p.body[:])
    }
    Property(p) => {
      self.put("property(")
      self.put(custom_property(p.name))
      self.put(")")
      self.write_decl_body(p.decls)
    }
    Import(i) => {
      self.put("import(")
      self.write_string(i.url)
      match i.layer {
        None => ()
        Some(None) => self.put(", layer")
        Some(Some(n)) => {
          self.put(", layer(")
          self.write_layer_name(n)
          self.put(")")
        }
      }
      match i.supports {
        None => ()
        Some(c) => {
          self.put(", supports(")
          self.write_condition(c)
          self.put(")")
        }
      }
      if i.media.length() > 0 {
        self.put(", ")
        self.write_media_queries(i.media[:])
      }
      self.put(")")
    }
    Charset(cs, _) => {
      self.put("charset(")
      self.write_string(cs)
      self.put(")")
    }
    Namespace(n) => {
      self.put("namespace(")
      match n.prefix {
        Some(p) => {
          self.put(name_or_string(p))
          self.put(", ")
        }
        None => ()
      }
      self.write_string(n.url)
      self.put(")")
    }
    Scope(s) => {
      self.put("scope(")
      match s.start {
        Some(sels) => self.write_selector_list(sels[:])
        None => ()
      }
      match s.end {
        Some(sels) => {
          self.put(" ~to ")
          self.write_selector_list(sels[:])
        }
        None => ()
      }
      self.put(")")
      self.write_body(s.body[:])
    }
    StartingStyle(body, _) => {
      self.put("starting_style()")
      self.write_body(body[:])
    }
    CounterStyle(name, b) => {
      self.put("counter_style(")
      self.put(name_or_string(name))
      self.put(")")
      self.write_decl_body(b)
    }
    Unknown(u) => {
      self.put(name_or_string(u.name))
      self.put("(")
      self.write_comma_groups(u.prelude[:])
      self.put(")")
      match u.block {
        Some(body) => self.write_body(body[:])
        None => ()
      }
    }
    Bogus(b) => self.write_bogus(b)
  }
}

///|
fn Emitter::write_layer_name(self : Emitter, n : @ast.LayerName) -> Unit {
  let mut first = true
  for part in n.parts {
    if !first {
      self.put(".")
    }
    first = false
    self.put(name_or_string(part))
  }
}

///|
/// `@page :first` is `page(first())`: a pseudo-page is a pseudo, so it is a
/// call like every other one.
fn Emitter::write_page_selector(self : Emitter, s : String) -> Unit {
  let body = if s.has_prefix(":") {
    s.clamped_view(start=1).to_owned()
  } else {
    s
  }
  self.put(name_or_string(body))
  self.put("()")
}

///|
fn Emitter::write_frames(
  self : Emitter,
  frames : ArrayView[@ast.KeyframeBlock],
) -> Unit {
  if frames.length() == 0 {
    self.put(": «»")
    return
  }
  self.put(":")
  self.depth = self.depth + 1
  for f in frames {
    self.nl()
    match f.selectors {
      [only] => self.write_keyframe_selector(only)
      _ => {
        self.put("[")
        let mut first = true
        for s in f.selectors {
          if !first {
            self.put(", ")
          }
          first = false
          self.write_keyframe_selector(s)
        }
        self.put("]")
      }
    }
    self.write_decl_body(f.decls)
  }
  self.depth = self.depth - 1
}

///|
fn Emitter::write_keyframe_selector(
  self : Emitter,
  s : @ast.KeyframeSelector,
) -> Unit {
  match s {
    From => self.put("from")
    To => self.put("to")
    Percentage(n) => {
      self.put("percent(")
      self.put(number(n))
      self.put(")")
    }
  }
}

// ----------------------------------------------------------------- conditions

///|
fn Emitter::write_media_queries(
  self : Emitter,
  qs : ArrayView[@ast.MediaQuery],
) -> Unit {
  let mut first = true
  for q in qs {
    if !first {
      self.put(", ")
    }
    first = false
    self.write_media_query(q)
  }
}

///|
fn Emitter::write_media_query(self : Emitter, q : @ast.MediaQuery) -> Unit {
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
      self.put(name_or_string(t))
      wrote = true
    }
    None => ()
  }
  match q.condition {
    Some(c) => {
      if wrote {
        self.put(" and ")
      }
      self.write_condition(c)
    }
    None => ()
  }
}

///|
fn Emitter::write_condition(self : Emitter, c : @ast.Condition) -> Unit {
  match c {
    Feature(f) => self.write_feature(f)
    Decl(d) => {
      self.put("(")
      // Inside a condition a declaration is written with `=`, not `:`, because
      // a `:` there opens a block -- legal, but one step from the semicolon
      // hazard, so it is not the canonical spelling.
      match d.property {
        Ident(n) => self.put(name_or_string(n))
        Custom(n) => self.put(custom_property(n))
      }
      self.put(" = ")
      self.write_values(d.value[:])
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
    Bogus(b) => {
      self.put("unreadable(")
      self.write_string(b.text)
      self.put(")")
    }
  }
}

///|
/// An operand, parenthesised exactly when it is itself an operation -- which is
/// where the two logical operators would otherwise mix without saying so.
fn Emitter::write_operand(self : Emitter, c : @ast.Condition) -> Unit {
  match c {
    Operation(_, _) => {
      self.put("(")
      self.write_condition(c)
      self.put(")")
    }
    _ => self.write_condition(c)
  }
}

///|
fn Emitter::write_feature(self : Emitter, f : @ast.Feature) -> Unit {
  self.put("(")
  match f {
    Boolean(n) => self.put(name_or_string(n))
    Plain(n, vs) => {
      self.put(name_or_string(n))
      self.put(" = ")
      self.write_values(vs[:])
    }
    Range(n, op, vs) => {
      self.put(name_or_string(n))
      self.put(" ")
      self.put(op.text())
      self.put(" ")
      self.write_values(vs[:])
    }
    Interval(lo, op1, n, op2, hi) => {
      self.write_values(lo[:])
      self.put(" ")
      self.put(op1.text())
      self.put(" ")
      self.put(name_or_string(n))
      self.put(" ")
      self.put(op2.text())
      self.put(" ")
      self.write_values(hi[:])
    }
  }
  self.put(")")
}
