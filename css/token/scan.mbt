///|
/// The tokenizer.
///
/// A hand-written scanner over a `String`, following the CSS Syntax Level 3
/// algorithms closely enough that a reader can check one against the other. The
/// shape -- a `priv struct` with a mutable cursor, a cached length, and a NUL
/// sentinel instead of an `Option` on the hot path -- is lifted from
/// `mizchi/css`, which is the only prior art for this in MoonBit and had
/// already paid for those decisions.
///
/// Indices are UTF-16 code units throughout, which is what a MoonBit `String`
/// is indexed in and what `@span.Span` measures. Astral characters therefore
/// occupy two units; nothing here needs to know that, because every character
/// it makes a decision about is ASCII, and a surrogate pair simply falls into
/// the "identifier character" bucket as a unit.
///
/// The tokenizer never fails. Malformed input produces `BadStr` or `BadUrl`,
/// which are tokens, so the parser decides what a failure means rather than
/// having that decided for it two layers down.

///|
/// The replacement character, which the specification substitutes for NUL and
/// for unpaired surrogates.
const REPLACEMENT : Char = '\u{FFFD}'

///|
priv struct Scanner {
  src : String
  len : Int
  mut pos : Int
}

///|
/// Tokenize a whole stylesheet, ending with exactly one `Eof`.
pub fn tokenize(src : String) -> Array[Token] {
  let s = { src, len: src.length(), pos: 0, }
  let out = []
  while true {
    let t = s.next()
    let done = t.kind == Eof
    out.push(t)
    if done {
      break
    }
  }
  out
}

// ------------------------------------------------------------------- cursor

///|
/// The character at `i`, or NUL past the end.
///
/// NUL is safe as a sentinel because the specification already requires a real
/// NUL in the input to be replaced by U+FFFD before tokenizing, so one can
/// never appear as data.
fn Scanner::at(self : Scanner, i : Int) -> Char {
  if i >= self.len || i < 0 {
    '\u{0}'
  } else {
    self.src.unsafe_get(i).to_int().unsafe_to_char()
  }
}

///|
fn Scanner::peek(self : Scanner) -> Char {
  self.at(self.pos)
}

///|
fn Scanner::peek2(self : Scanner) -> Char {
  self.at(self.pos + 1)
}

///|
fn Scanner::peek3(self : Scanner) -> Char {
  self.at(self.pos + 2)
}

///|
fn Scanner::slice(self : Scanner, start : Int, end : Int) -> String {
  self.src.clamped_view(start~, end~).to_owned()
}

///|
fn Scanner::tok(self : Scanner, start : Int, kind : TokenKind) -> Token {
  { kind, span: @span.Span::new(start, self.pos), }
}

// --------------------------------------------------------------- predicates

///|
fn is_ws(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u{0C}'
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_hex(c : Char) -> Bool {
  is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
/// An identifier-start character.
///
/// Everything at or above U+0080 counts, which is how the specification admits
/// non-ASCII identifiers without a Unicode table -- and it means a surrogate
/// pair is admitted one unit at a time, with the same result.
fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c >= '\u{80}'
}

///|
fn is_ident_char(c : Char) -> Bool {
  is_ident_start(c) || is_digit(c) || c == '-'
}

///|
/// Whether `\` at `i` begins a valid escape. A backslash before a newline does
/// not: that is a line continuation inside a string and an error outside one.
fn Scanner::is_valid_escape_at(self : Scanner, i : Int) -> Bool {
  self.at(i) == '\\' && self.at(i + 1) != '\n' && self.at(i + 1) != '\r'
}

///|
/// Whether an identifier starts at `i`. The three-character lookahead is the
/// specification's, and it is what makes `-` ambiguous between a negative
/// number, a `--custom-property` and the identifier `-webkit-x`.
fn Scanner::starts_ident_at(self : Scanner, i : Int) -> Bool {
  let c = self.at(i)
  if c == '-' {
    let d = self.at(i + 1)
    is_ident_start(d) || d == '-' || self.is_valid_escape_at(i + 1)
  } else if is_ident_start(c) {
    true
  } else {
    self.is_valid_escape_at(i)
  }
}

///|
/// Whether a number starts at `i`.
fn Scanner::starts_number_at(self : Scanner, i : Int) -> Bool {
  let c = self.at(i)
  if c == '+' || c == '-' {
    is_digit(self.at(i + 1)) ||
    (self.at(i + 1) == '.' && is_digit(self.at(i + 2)))
  } else if c == '.' {
    is_digit(self.at(i + 1))
  } else {
    is_digit(c)
  }
}

// ------------------------------------------------------------------ dispatch

///|
fn Scanner::next(self : Scanner) -> Token {
  let start = self.pos
  let c = self.peek()
  if self.pos >= self.len {
    return self.tok(start, Eof)
  }
  if is_ws(c) {
    while is_ws(self.peek()) {
      self.pos = self.pos + 1
    }
    return self.tok(start, Whitespace)
  }
  match c {
    '/' =>
      if self.peek2() == '*' {
        self.scan_comment(start)
      } else {
        self.pos = self.pos + 1
        self.tok(start, Delim('/'))
      }
    '"' | '\'' => self.scan_string(start, c)
    '#' => {
      self.pos = self.pos + 1
      if is_ident_char(self.peek()) || self.is_valid_escape_at(self.pos) {
        let kind = if self.starts_ident_at(self.pos) {
          HashKind::Id
        } else {
          Unrestricted
        }
        let name = self.consume_name()
        self.tok(start, Hash(name, kind))
      } else {
        self.tok(start, Delim('#'))
      }
    }
    '(' => {
      self.pos = self.pos + 1
      self.tok(start, LParen)
    }
    ')' => {
      self.pos = self.pos + 1
      self.tok(start, RParen)
    }
    '[' => {
      self.pos = self.pos + 1
      self.tok(start, LBracket)
    }
    ']' => {
      self.pos = self.pos + 1
      self.tok(start, RBracket)
    }
    '{' => {
      self.pos = self.pos + 1
      self.tok(start, LBrace)
    }
    '}' => {
      self.pos = self.pos + 1
      self.tok(start, RBrace)
    }
    ',' => {
      self.pos = self.pos + 1
      self.tok(start, Comma)
    }
    ':' => {
      self.pos = self.pos + 1
      self.tok(start, Colon)
    }
    ';' => {
      self.pos = self.pos + 1
      self.tok(start, Semicolon)
    }
    '@' => {
      self.pos = self.pos + 1
      if self.starts_ident_at(self.pos) {
        let name = self.consume_name()
        self.tok(start, AtKeyword(name))
      } else {
        self.tok(start, Delim('@'))
      }
    }
    '\\' =>
      if self.is_valid_escape_at(self.pos) {
        self.scan_ident_like(start)
      } else {
        self.pos = self.pos + 1
        self.tok(start, Delim('\\'))
      }
    '<' =>
      if self.at(self.pos + 1) == '!' &&
        self.at(self.pos + 2) == '-' &&
        self.at(self.pos + 3) == '-' {
        self.pos = self.pos + 4
        self.tok(start, Cdo)
      } else {
        self.pos = self.pos + 1
        self.tok(start, Delim('<'))
      }
    '+' | '.' =>
      if self.starts_number_at(self.pos) {
        self.scan_numeric(start)
      } else {
        self.pos = self.pos + 1
        self.tok(start, Delim(c))
      }
    '-' =>
      if self.starts_number_at(self.pos) {
        self.scan_numeric(start)
      } else if self.peek2() == '-' && self.peek3() == '>' {
        self.pos = self.pos + 3
        self.tok(start, Cdc)
      } else if self.starts_ident_at(self.pos) {
        self.scan_ident_like(start)
      } else {
        self.pos = self.pos + 1
        self.tok(start, Delim('-'))
      }
    _ =>
      if is_digit(c) {
        self.scan_numeric(start)
      } else if self.starts_ident_at(self.pos) {
        self.scan_ident_like(start)
      } else {
        self.pos = self.pos + 1
        self.tok(start, Delim(c))
      }
  }
}

// ------------------------------------------------------------------ scanners

///|
fn Scanner::scan_comment(self : Scanner, start : Int) -> Token {
  self.pos = self.pos + 2
  let body_start = self.pos
  while self.pos < self.len {
    if self.peek() == '*' && self.peek2() == '/' {
      let body = self.slice(body_start, self.pos)
      self.pos = self.pos + 2
      return self.tok(start, Comment(body))
    }
    self.pos = self.pos + 1
  }
  // Unterminated: the specification says to consume to the end of input and
  // carry on. The parser learns about it from the span reaching EOF, not from
  // a distinct token, because a comment is trivia either way.
  self.tok(start, Comment(self.slice(body_start, self.pos)))
}

///|
fn Scanner::scan_string(self : Scanner, start : Int, quote : Char) -> Token {
  self.pos = self.pos + 1
  let buf = StringBuilder()
  while true {
    if self.pos >= self.len {
      return self.tok(start, Str(buf.to_string()))
    }
    let c = self.peek()
    if c == quote {
      self.pos = self.pos + 1
      return self.tok(start, Str(buf.to_string()))
    }
    if c == '\n' || c == '\r' {
      // A raw newline ends the string badly; the newline itself is NOT
      // consumed, so the next token is whitespace and the parser can still see
      // where the line broke.
      return self.tok(start, BadStr)
    }
    if c == '\\' {
      let n = self.at(self.pos + 1)
      if self.pos + 1 >= self.len {
        self.pos = self.pos + 1
      } else if n == '\n' || n == '\r' {
        // A escaped newline is a line continuation: it contributes nothing.
        self.pos = self.pos + 2
        if n == '\r' && self.peek() == '\n' {
          self.pos = self.pos + 1
        }
      } else {
        self.pos = self.pos + 1
        buf.write_char(self.consume_escape())
      }
    } else {
      buf.write_char(c)
      self.pos = self.pos + 1
    }
  }
  self.tok(start, Str(buf.to_string()))
}

///|
/// A `\` has been consumed; read what it escapes.
fn Scanner::consume_escape(self : Scanner) -> Char {
  let c = self.peek()
  if is_hex(c) {
    let mut value = 0
    let mut n = 0
    while n < 6 && is_hex(self.peek()) {
      value = value * 16 + hex_value(self.peek())
      self.pos = self.pos + 1
      n = n + 1
    }
    // Exactly one whitespace character after the digits is part of the escape.
    if is_ws(self.peek()) {
      if self.peek() == '\r' && self.peek2() == '\n' {
        self.pos = self.pos + 1
      }
      self.pos = self.pos + 1
    }
    if value == 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF) {
      REPLACEMENT
    } else {
      value.unsafe_to_char()
    }
  } else if self.pos >= self.len {
    REPLACEMENT
  } else {
    self.pos = self.pos + 1
    c
  }
}

///|
fn hex_value(c : Char) -> Int {
  if is_digit(c) {
    c.to_int() - 48
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 87
  } else {
    c.to_int() - 55
  }
}

///|
/// An identifier's characters, with escapes resolved.
///
/// Fast path first: scan forward assuming no escapes and take one slice. Only
/// when a `\` shows up does this fall back to building a string character by
/// character. Escapes are rare enough in real stylesheets that the slow path
/// almost never runs, and common enough that it has to be correct.
fn Scanner::consume_name(self : Scanner) -> String {
  let start = self.pos
  while self.pos < self.len {
    let c = self.peek()
    if is_ident_char(c) {
      self.pos = self.pos + 1
    } else if self.is_valid_escape_at(self.pos) {
      // Restart in the slow path, from the beginning of the name.
      self.pos = start
      return self.consume_name_escaped()
    } else {
      break
    }
  }
  self.slice(start, self.pos)
}

///|
fn Scanner::consume_name_escaped(self : Scanner) -> String {
  let buf = StringBuilder()
  while self.pos < self.len {
    let c = self.peek()
    if is_ident_char(c) {
      buf.write_char(c)
      self.pos = self.pos + 1
    } else if self.is_valid_escape_at(self.pos) {
      self.pos = self.pos + 1
      buf.write_char(self.consume_escape())
    } else {
      break
    }
  }
  buf.to_string()
}

///|
fn Scanner::scan_ident_like(self : Scanner, start : Int) -> Token {
  let name = self.consume_name()
  if self.peek() == '(' {
    self.pos = self.pos + 1
    // `url(` is special only when its body is unquoted; with a quote it is an
    // ordinary function call and the string tokenizes normally.
    if name.to_lower() == "url" {
      let mut i = self.pos
      while is_ws(self.at(i)) {
        i = i + 1
      }
      let c = self.at(i)
      if c != '"' && c != '\'' {
        return self.scan_url(start)
      }
    }
    return self.tok(start, Function(name))
  }
  self.tok(start, Ident(name))
}

///|
/// The body of an unquoted `url(`.
fn Scanner::scan_url(self : Scanner, start : Int) -> Token {
  while is_ws(self.peek()) {
    self.pos = self.pos + 1
  }
  let buf = StringBuilder()
  while true {
    if self.pos >= self.len {
      return self.tok(start, Url(buf.to_string()))
    }
    let c = self.peek()
    if c == ')' {
      self.pos = self.pos + 1
      return self.tok(start, Url(buf.to_string()))
    }
    if is_ws(c) {
      while is_ws(self.peek()) {
        self.pos = self.pos + 1
      }
      if self.peek() == ')' {
        self.pos = self.pos + 1
        return self.tok(start, Url(buf.to_string()))
      }
      if self.pos >= self.len {
        return self.tok(start, Url(buf.to_string()))
      }
      self.consume_bad_url()
      return self.tok(start, BadUrl)
    }
    if c == '"' || c == '\'' || c == '(' {
      self.consume_bad_url()
      return self.tok(start, BadUrl)
    }
    if c == '\\' {
      if self.is_valid_escape_at(self.pos) {
        self.pos = self.pos + 1
        buf.write_char(self.consume_escape())
      } else {
        self.consume_bad_url()
        return self.tok(start, BadUrl)
      }
    } else {
      buf.write_char(c)
      self.pos = self.pos + 1
    }
  }
  self.tok(start, Url(buf.to_string()))
}

///|
/// Discard the remnants of a bad url, up to and including the `)`.
fn Scanner::consume_bad_url(self : Scanner) -> Unit {
  while self.pos < self.len {
    let c = self.peek()
    if c == ')' {
      self.pos = self.pos + 1
      return
    }
    if self.is_valid_escape_at(self.pos) {
      self.pos = self.pos + 1
      let _ = self.consume_escape()
    } else {
      self.pos = self.pos + 1
    }
  }
}

///|
/// A number, and whatever makes it a dimension or a percentage.
fn Scanner::scan_numeric(self : Scanner, start : Int) -> Token {
  let (repr, value, is_int) = self.consume_number()
  if self.starts_ident_at(self.pos) {
    let unit = self.consume_name()
    return self.tok(start, Dimension(repr, value, is_int, unit))
  }
  if self.peek() == '%' {
    self.pos = self.pos + 1
    return self.tok(start, Percentage(repr, value))
  }
  self.tok(start, Number(repr, value, is_int))
}

///|
/// The number itself, returning its source spelling alongside its value.
///
/// The spelling is kept because CSS treats `1`, `1.0` and `+1` as the same
/// number and a person treats them as three different pieces of text. A
/// formatter that normalised them would rewrite lines it was not asked to
/// touch.
fn Scanner::consume_number(self : Scanner) -> (String, Double, Bool) {
  let start = self.pos
  let mut is_int = true
  if self.peek() == '+' || self.peek() == '-' {
    self.pos = self.pos + 1
  }
  while is_digit(self.peek()) {
    self.pos = self.pos + 1
  }
  if self.peek() == '.' && is_digit(self.peek2()) {
    is_int = false
    self.pos = self.pos + 2
    while is_digit(self.peek()) {
      self.pos = self.pos + 1
    }
  }
  let e = self.peek()
  if e == 'e' || e == 'E' {
    let sign = self.peek2()
    let after = if sign == '+' || sign == '-' { self.peek3() } else { sign }
    if is_digit(after) {
      is_int = false
      self.pos = self.pos + (if sign == '+' || sign == '-' { 3 } else { 2 })
      while is_digit(self.peek()) {
        self.pos = self.pos + 1
      }
    }
  }
  let repr = self.slice(start, self.pos)
  // A malformed number cannot reach here -- `starts_number_at` gated it -- so
  // the only way the parse can fail is overflow, and 0 is a better answer than
  // a crash inside a tokenizer that is not allowed to fail.
  let value = @string.parse_double(repr) catch { _ => 0.0 }
  (repr, value, is_int)
}
