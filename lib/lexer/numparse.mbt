///|
/// Strip the `_` separators. They are notation, not value.
fn strip_underscores(s : String) -> String {
  if !s.contains_char('_') {
    return s
  }
  let buf = StringBuilder()
  for c in s {
    if c != '_' {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// An integer lexeme, with optional sign and separators, as an exact integer.
fn parse_integer(lexeme : String) -> @bigint.BigInt {
  let s = strip_underscores(lexeme)
  let (neg, body) = split_sign(s)
  let v = @bigint.BigInt::from_string(body)
  if neg {
    -v
  } else {
    v
  }
}

///|
fn split_sign(s : String) -> (Bool, String) {
  if s.length() == 0 {
    return (false, s)
  }
  match s.get_char(0) {
    Some('+') => (false, s.clamped_view(start=1).to_owned())
    Some('-') => (true, s.clamped_view(start=1).to_owned())
    _ => (false, s)
  }
}

///|
/// A number lexeme as the value it denotes.
///
/// Exactness is preserved the way Racket preserves it: an integer, in any
/// radix, is exact; anything with a `.` or an exponent is a flonum. Turning
/// `123456789012345678901234567890` into a `Double` would silently lose digits
/// the reference keeps.
fn parse_number(lexeme : String) -> @sexp.Datum {
  let s = strip_underscores(lexeme)
  let (neg, body) = split_sign(s)
  let radix = if body.has_prefix("0x") {
    16
  } else if body.has_prefix("0o") {
    8
  } else if body.has_prefix("0b") {
    2
  } else {
    10
  }
  if radix != 10 {
    let digits = body.clamped_view(start=2).to_owned()
    let v = @bigint.BigInt::from_string(digits, radix~)
    return Int_(if neg { -v } else { v })
  }
  if body.contains_char('.') ||
    body.contains_char('e') ||
    body.contains_char('E') {
    let d = parse_double(body)
    return Flo(if neg { -d } else { d })
  }
  let v = @bigint.BigInt::from_string(body)
  Int_(if neg { -v } else { v })
}

///|
/// A decimal-integer lexeme read as a flonum — the `1.` case, where the
/// trailing dot has already been decided but not yet appended.
fn parse_decimal_as_double(lexeme : String) -> Double {
  let s = strip_underscores(lexeme)
  let (neg, body) = split_sign(s)
  let d = parse_double(body)
  if neg {
    -d
  } else {
    d
  }
}

///|
/// Read an unsigned decimal, possibly with a fraction and an exponent.
///
/// Hand-rolled rather than `@strconv.parse_double`, because the lexemes that
/// reach here include forms that a general parser may reject or accept
/// differently — a bare `1.`, a `.5`, an `E` exponent — and the answer has to
/// be the one Racket's reader gives. Falls back on the standard parser for the
/// shapes it handles identically.
fn parse_double(body : String) -> Double {
  // Normalise `1.` to `1.0` and `.5` to `0.5`; both are what Racket reads them
  // as, and both are shapes a strict parser may refuse.
  let buf = StringBuilder()
  if body.has_prefix(".") {
    buf.write_char('0')
  }
  for i in 0..<body.length() {
    let c = body.get_char(i)
    match c {
      Some(ch) => {
        buf.write_char(ch)
        if ch == '.' && (i + 1 == body.length() || is_exponent_at(body, i + 1)) {
          buf.write_char('0')
        }
      }
      None => ()
    }
  }
  let text = buf.to_string()
  // Unreachable for a lexeme the scanner accepted; answering with a NaN rather
  // than raising keeps a malformed literal from taking down a parse that would
  // otherwise report it properly.
  @string.parse_double(text) catch {
    _ => @double.not_a_number
  }
}

///|
fn is_exponent_at(s : String, i : Int) -> Bool {
  match s.get_char(i) {
    Some('e') | Some('E') => true
    _ => false
  }
}
