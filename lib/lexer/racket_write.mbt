///|
/// Print a datum the way Racket's `write` would.
///
/// Needed because a `#{...}` escape's raw text is the datum re-printed, not the
/// source read: `#{ foo }` has raw `#{foo}`. Only the shapes an escape actually
/// carries are handled precisely; a flonum falls back to MoonBit's own
/// formatting, which is a known and narrow risk — reproducing Racket's
/// shortest-round-trip printer is a project of its own, and no corpus file puts
/// a flonum in an escape.
fn write_racket(d : @sexp.Datum) -> String {
  let buf = StringBuilder()
  write_racket_into(buf, d)
  buf.to_string()
}

///|
fn write_racket_into(buf : StringBuilder, d : @sexp.Datum) -> Unit {
  match d {
    Sym(name) => write_racket_symbol(buf, name)
    Kw(name) => {
      buf.write_string("#:")
      buf.write_string(name)
    }
    Str(s) => {
      buf.write_char('"')
      for c in s {
        match c {
          '"' => buf.write_string("\\\"")
          '\\' => buf.write_string("\\\\")
          '\n' => buf.write_string("\\n")
          '\r' => buf.write_string("\\r")
          '\t' => buf.write_string("\\t")
          _ => buf.write_char(c)
        }
      }
      buf.write_char('"')
    }
    Bs(b) => {
      buf.write_string("#\"")
      for i in 0..<b.length() {
        let v = b[i].to_int()
        if v >= 0x20 && v < 0x7F && v != 0x22 && v != 0x5C {
          buf.write_char(v.unsafe_to_char())
        } else {
          buf.write_string("\\")
          buf.write_string(v.to_string(radix=8))
        }
      }
      buf.write_char('"')
    }
    Ch(c) => write_racket_char(buf, c)
    Bool_(v) => buf.write_string(if v { "#t" } else { "#f" })
    Void => buf.write_string("#<void>")
    Int_(n) => buf.write_string(n.to_string())
    Rat(n, den) => {
      buf.write_string(n.to_string())
      buf.write_char('/')
      buf.write_string(den.to_string())
    }
    Flo(v) => buf.write_string(v.to_string())
    Nil => buf.write_string("()")
    Pair(_) => {
      buf.write_char('(')
      let mut cur = d
      let mut first = true
      while cur is Pair(head, tail) {
        if !first {
          buf.write_char(' ')
        }
        first = false
        write_racket_into(buf, head)
        cur = tail
      }
      if !(cur is Nil) {
        buf.write_string(" . ")
        write_racket_into(buf, cur)
      }
      buf.write_char(')')
    }
    Vec(xs) => {
      buf.write_string("#(")
      for i in 0..<xs.length() {
        if i > 0 {
          buf.write_char(' ')
        }
        write_racket_into(buf, xs[i])
      }
      buf.write_char(')')
    }
    Rx(px, pattern) => {
      buf.write_string(if px { "#px" } else { "#rx" })
      write_racket_into(buf, Str(pattern))
    }
    Other(text) => buf.write_string(text)
  }
}

///|
/// Racket's two ways of quoting a symbol, and when it uses which.
///
/// Bars wrap the whole name when it would otherwise read as something else --
/// a number, `.`, the empty symbol -- or when it contains whitespace, a
/// delimiter, or a backslash. Otherwise a bare `|` inside the name is escaped
/// with a backslash and the rest is printed as-is, so `|>` prints as `\|>`
/// rather than `|\||>|`.
fn write_racket_symbol(buf : StringBuilder, name : String) -> Unit {
  if symbol_needs_bars(name) {
    buf.write_char('|')
    for c in name {
      if c == '|' || c == '\\' {
        buf.write_char('\\')
      }
      buf.write_char(c)
    }
    buf.write_char('|')
    return
  }
  for c in name {
    if c == '|' {
      buf.write_char('\\')
    }
    buf.write_char(c)
  }
}

///|
/// Racket's character syntax: a name for the ones that have one, the character
/// itself when it is printable, and a hex escape otherwise.
fn write_racket_char(buf : StringBuilder, c : Char) -> Unit {
  buf.write_string("#\\")
  let u = c.to_int()
  match c {
    '\u{0}' => buf.write_string("nul")
    '\u{7}' => buf.write_string("alarm")
    '\u{8}' => buf.write_string("backspace")
    '\t' => buf.write_string("tab")
    '\n' => buf.write_string("newline")
    '\u{B}' => buf.write_string("vtab")
    '\u{C}' => buf.write_string("page")
    '\r' => buf.write_string("return")
    ' ' => buf.write_string("space")
    '\u{7F}' => buf.write_string("rubout")
    _ =>
      if u < 0x20 {
        buf.write_string("u")
        write_hex_padded(buf, u, 4)
      } else if u > 0xFFFF {
        buf.write_string("U")
        write_hex_padded(buf, u, 8)
      } else {
        buf.write_char(c)
      }
  }
}

///|
/// Uppercase, which is what Racket prints in a character escape: `#\\u001F`,
/// `#\\U0001FFFF`.
fn write_hex_padded(buf : StringBuilder, v : Int, width : Int) -> Unit {
  let hex = v.to_string(radix=16).to_upper()
  for _ in 0..<(width - hex.length()) {
    buf.write_char('0')
  }
  buf.write_string(hex)
}

///|
/// Whether Racket would print this symbol inside `|...|`.
///
/// It does so whenever reading the bare spelling back would not give the same
/// symbol: an empty name, one that looks like a number, or one containing a
/// character the reader treats specially.
fn symbol_needs_bars(name : String) -> Bool {
  if name.length() == 0 {
    return true
  }
  if racket_number(name) is Some(_) {
    return true
  }
  if name == "." {
    return true
  }
  for c in name {
    // `|` is NOT here: Racket escapes it with a backslash instead. `#` is not
    // here either -- `#%module-begin` prints bare.
    if is_racket_delim(c) || c == '\\' {
      return true
    }
  }
  false
}
