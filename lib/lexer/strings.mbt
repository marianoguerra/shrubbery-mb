///|
/// A string literal, decoded.
///
/// A literal newline inside a string is an error, not a continuation: shrubbery
/// has no `\<newline>` escape, so a run-away quote is caught at the end of its
/// line rather than swallowing the rest of the file.
fn Scanner::scan_string(
  self : Scanner,
  start : @basic.Pos,
  from : Int,
) -> Token {
  let buf = StringBuilder()
  let mut i = from + 1
  while i < self.src.length() {
    match self.at(i) {
      Some('"') =>
        return self.finish(
          start,
          i + 1,
          Literal(Str(buf.to_string())),
          mode=Continuing,
        )
      Some('\n') | Some('\r') => break
      Some('\\') =>
        match self.decode_escape(i, unicode=true) {
          Some((next, code)) => {
            append_code(buf, code)
            i = next
          }
          None => break
        }
      Some(c) => {
        buf.write_char(c)
        i = self.step(i)
      }
      None => break
    }
  }
  self.finish(start, self.scan_bad_string(from), Fail(ReadError))
}

///|
/// `#"..."`, decoded to bytes.
fn Scanner::scan_byte_string(
  self : Scanner,
  start : @basic.Pos,
  from : Int,
) -> Token {
  let out = []
  let mut i = from + 2
  while i < self.src.length() {
    match self.at(i) {
      Some('"') =>
        return self.finish(
          start,
          i + 1,
          Literal(Bs(Bytes::from_array(out))),
          mode=Continuing,
        )
      Some('\n') | Some('\r') => break
      Some('\\') =>
        match self.decode_escape(i, unicode=false) {
          Some((next, code)) => {
            // The grammar restricts a byte-string element to 0x00..0xFF, so a
            // wider value cannot arrive here.
            out.push((code & 0xFF).to_byte())
            i = next
          }
          None => break
        }
      Some(c) => {
        out.push((c.to_int() & 0xFF).to_byte())
        i = self.step(i)
      }
      None => break
    }
  }
  self.finish(start, self.scan_bad_string(from), Fail(ReadError))
}

///|
/// How far a malformed string reaches: to a closing quote if one turns up on
/// this line, and to the end of the line otherwise.
fn Scanner::scan_bad_string(self : Scanner, from : Int) -> Int {
  let mut i = if self.at(from) is Some('#') { from + 2 } else { from + 1 }
  while i < self.src.length() {
    match self.at(i) {
      Some('\n') | Some('\r') => return i
      Some('"') => return i + 1
      Some('\\') =>
        match self.at(i + 1) {
          Some('\n') | Some('\r') | None => return i + 1
          _ => i = self.step(i + 1)
        }
      _ => i = self.step(i)
    }
  }
  i
}

///|
/// One escape sequence at `i`, returning where it ends and the code point.
///
/// `\u` and `\U` are string-only: a byte string has no code points to name.
/// A `\u` high surrogate followed by a `\u` low surrogate is combined, which is
/// how Racket reads a pair and the only way to write an astral character with
/// four hex digits.
fn Scanner::decode_escape(
  self : Scanner,
  i : Int,
  unicode~ : Bool,
) -> (Int, Int)? {
  let c = match self.at(i + 1) {
    Some(c) => c
    None => return None
  }
  match c {
    '"' => Some((i + 2, 0x22))
    '\\' => Some((i + 2, 0x5C))
    '\'' => Some((i + 2, 0x27))
    'a' => Some((i + 2, 0x07))
    'b' => Some((i + 2, 0x08))
    't' => Some((i + 2, 0x09))
    'n' => Some((i + 2, 0x0A))
    'v' => Some((i + 2, 0x0B))
    'f' => Some((i + 2, 0x0C))
    'r' => Some((i + 2, 0x0D))
    'e' => Some((i + 2, 0x1B))
    'x' => self.hex_escape(i + 2, 1, 2)
    'u' =>
      if !unicode {
        None
      } else {
        match self.hex_escape(i + 2, 1, 4) {
          Some((next, hi)) =>
            // A surrogate pair, written as two escapes, is one character.
            if hi >= 0xD800 && hi <= 0xDBFF && self.has(next, "\\u") {
              match self.hex_escape(next + 2, 1, 4) {
                Some((after, lo)) if lo >= 0xDC00 && lo <= 0xDFFF =>
                  Some((after, 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)))
                _ => Some((next, hi))
              }
            } else {
              Some((next, hi))
            }
          None => None
        }
      }
    'U' => if !unicode { None } else { self.hex_escape(i + 2, 1, 6) }
    _ =>
      if is_octal(c) {
        let mut n = 0
        let mut k = 0
        let mut j = i + 1
        while k < 3 {
          match self.at(j) {
            Some(d) if is_octal(d) => {
              n = n * 8 + (d.to_int() - 48)
              j = j + 1
              k = k + 1
            }
            _ => break
          }
        }
        Some((j, n))
      } else {
        None
      }
  }
}

///|
fn Scanner::hex_escape(
  self : Scanner,
  from : Int,
  min : Int,
  max : Int,
) -> (Int, Int)? {
  let mut n = 0
  let mut k = 0
  let mut i = from
  while k < max {
    match self.at(i) {
      Some(d) if is_hex(d) => {
        n = n * 16 + hex_value(d)
        i = i + 1
        k = k + 1
      }
      _ => break
    }
  }
  if k < min {
    None
  } else {
    Some((i, n))
  }
}

///|
/// Append a decoded code point.
///
/// A lone surrogate cannot be a `Char`, so it is written as its raw code unit;
/// the grammar admits one — it "does not constrain to avoid surrogates" — and
/// dropping it would lose text the raw metadata still has to reproduce.
fn append_code(buf : StringBuilder, code : Int) -> Unit {
  if code >= 0xD800 && code <= 0xDFFF {
    buf.write_string(String::from_array([code.unsafe_to_char()]))
  } else {
    buf.write_char(code.unsafe_to_char())
  }
}
