///|
/// Whether a name can be written as an identifier rather than escaped.
///
/// The reference's rule, which is NOT the notation's own: it admits Unicode
/// letters, `_` and digits, and nothing else -- so an emoji identifier, which
/// the notation accepts, is written as a `#{...}` escape. Following the
/// notation's rule here instead would produce output the reference does not,
/// which is the one thing this printer must not do.
fn is_plain_identifier(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let body = if s.has_prefix("#%") {
    s.clamped_view(start=2).to_owned()
  } else {
    s
  }
  if body.length() == 0 {
    return false
  }
  let mut first = true
  for c in body {
    let ok = if first {
      @unicode.is_letter(c) || c == '_'
    } else {
      @unicode.is_letter(c) || @unicode.is_numeric(c) || c == '_'
    }
    if !ok {
      return false
    }
    first = false
  }
  true
}

///|
/// An atom, written the way the reference writes it.
fn atom_text(shrub : @ast.Shrub) -> String {
  match shrub {
    Id(name) =>
      if is_plain_identifier(name) {
        name
      } else {
        escape_symbol(name)
      }
    Op(name) => name
    Kw(name) =>
      if is_plain_identifier(name) {
        "~" + name
      } else {
        "~#{" + racket_symbol(name) + "}"
      }
    Lit(d) => datum_text(d)
    Parsed(d) => datum_text(d)
    _ => ""
  }
}

///|
fn escape_symbol(name : String) -> String {
  "#{" + racket_symbol(name) + "}"
}

///|
/// Racket's `write` for a symbol: bars when the bare spelling would read as
/// something else, a backslash for a lone `|`, and as-is otherwise.
fn racket_symbol(name : String) -> String {
  let out = StringBuilder()
  if symbol_needs_bars(name) {
    out.write_char('|')
    for c in name {
      if c == '|' || c == '\\' {
        out.write_char('\\')
      }
      out.write_char(c)
    }
    out.write_char('|')
    return out.to_string()
  }
  for c in name {
    if c == '|' {
      out.write_char('\\')
    }
    out.write_char(c)
  }
  out.to_string()
}

///|
fn symbol_needs_bars(name : String) -> Bool {
  if name.length() == 0 || name == "." {
    return true
  }
  if looks_numeric(name) {
    return true
  }
  for c in name {
    match c {
      ' ' | '\t' | '\n' | '\r' | '(' | ')' | '[' | ']' | '{' | '}' =>
        return true
      '"' | '\'' | '`' | ',' | ';' | '\\' => return true
      _ => ()
    }
  }
  false
}

///|
/// Whether the bare spelling would be read back as a number rather than a name.
fn looks_numeric(name : String) -> Bool {
  let mut i = 0
  if name.get_char(0) is Some('+') || name.get_char(0) is Some('-') {
    i = 1
  }
  if i >= name.length() {
    return false
  }
  let mut any = false
  while i < name.length() {
    match name.get_char(i) {
      Some(c) if c >= '0' && c <= '9' => any = true
      Some('.') | Some('/') => ()
      _ => return false
    }
    i = i + 1
  }
  any
}

///|
/// A literal, written the way the reference writes it.
fn datum_text(d : @sexp.Datum) -> String {
  match d {
    Str(s) => string_to_string(s)
    Bs(b) => bytes_to_string(b)
    Int_(n) => n.to_string()
    Rat(n, den) => n.to_string() + "/" + den.to_string()
    Flo(v) =>
      if v != v {
        "#nan"
      } else if v == @double.infinity {
        "#inf"
      } else if v == @double.neg_infinity {
        "#neginf"
      } else {
        double_to_string(v)
      }
    Bool_(v) => if v { "#true" } else { "#false" }
    Void => "#void"
    Sym(name) =>
      if is_plain_identifier(name) {
        name
      } else {
        escape_symbol(name)
      }
    Kw(name) =>
      if is_plain_identifier(name) {
        "~" + name
      } else {
        "~#{" + racket_symbol(name) + "}"
      }
    Ch(c) => "#{" + char_text(c) + "}"
    Rx(px, pattern) =>
      "#{" + (if px { "#px" } else { "#rx" }) + string_to_string(pattern) + "}"
    Nil => "#{()}"
    Pair(_) => "#{" + racket_list_text(d) + "}"
    Vec(xs) => {
      let out = StringBuilder()
      out.write_string("#{#(")
      for i in 0..<xs.length() {
        if i > 0 {
          out.write_char(' ')
        }
        out.write_string(datum_inner_text(xs[i]))
      }
      out.write_string(")}")
      out.to_string()
    }
    Other(text) => "#{" + text + "}"
  }
}

///|
/// A datum written INSIDE a `#{...}`, where Racket's own notation applies and
/// shrubbery's does not.
fn datum_inner_text(d : @sexp.Datum) -> String {
  match d {
    Sym(name) => racket_symbol(name)
    Kw(name) => "#:" + name
    Str(s) => string_to_string(s)
    Bs(b) => bytes_to_string(b)
    Int_(n) => n.to_string()
    Rat(n, den) => n.to_string() + "/" + den.to_string()
    Flo(v) => double_to_string(v)
    Bool_(v) => if v { "#t" } else { "#f" }
    Void => "#<void>"
    Ch(c) => char_text(c)
    Rx(px, pattern) =>
      (if px { "#px" } else { "#rx" }) + string_to_string(pattern)
    Nil => "()"
    Pair(_) => racket_list_text(d)
    Vec(xs) => {
      let out = StringBuilder()
      out.write_string("#(")
      for i in 0..<xs.length() {
        if i > 0 {
          out.write_char(' ')
        }
        out.write_string(datum_inner_text(xs[i]))
      }
      out.write_char(')')
      out.to_string()
    }
    Other(text) => text
  }
}

///|
fn racket_list_text(d : @sexp.Datum) -> String {
  let out = StringBuilder()
  out.write_char('(')
  let mut cur = d
  let mut first = true
  while cur is Pair(head, tail) {
    if !first {
      out.write_char(' ')
    }
    first = false
    out.write_string(datum_inner_text(head))
    cur = tail
  }
  if !(cur is Nil) {
    out.write_string(" . ")
    out.write_string(datum_inner_text(cur))
  }
  out.write_char(')')
  out.to_string()
}

///|
/// Racket's character syntax.
fn char_text(c : Char) -> String {
  let u = c.to_int()
  match c {
    '\u{0}' => "#\\nul"
    '\u{7}' => "#\\alarm"
    '\u{8}' => "#\\backspace"
    '\t' => "#\\tab"
    '\n' => "#\\newline"
    '\u{B}' => "#\\vtab"
    '\u{C}' => "#\\page"
    '\r' => "#\\return"
    ' ' => "#\\space"
    '\u{7F}' => "#\\rubout"
    _ =>
      if u < 0x20 {
        "#\\u" + pad_hex(u, 4)
      } else if u > 0xFFFF {
        "#\\U" + pad_hex(u, 8)
      } else {
        "#\\" + c.to_string()
      }
  }
}

///|
fn pad_hex(v : Int, width : Int) -> String {
  let hex = v.to_string(radix=16).to_upper()
  let out = StringBuilder()
  for _ in 0..<(width - hex.length()) {
    out.write_char('0')
  }
  out.write_string(hex)
  out.to_string()
}
