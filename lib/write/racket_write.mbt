///|
/// Racket's `write` for a flonum.
///
/// MoonBit's own `to_string` already produces the shortest round-tripping
/// digits, and agrees with Racket on every value in the corpus. What it does
/// NOT agree on is presentation: Racket forces a `.0` on an integral value,
/// switches to exponent notation outside `[1e-4, 1e14)`, and writes the
/// exponent's sign. So the digits are taken from MoonBit and laid out again
/// here.
pub fn double_to_string(d : Double) -> String {
  if d != d {
    return "+nan.0"
  }
  if d == @double.infinity {
    return "+inf.0"
  }
  if d == @double.neg_infinity {
    return "-inf.0"
  }
  let text = d.to_string()
  let signed_text = text.has_prefix("-")
  // The sign of a zero is in the bit pattern, not in the digits: MoonBit
  // renders negative zero as `0`, and Racket writes it as `-0.0`. So the sign
  // is decided separately from whether there is one to strip.
  let negative = signed_text || (d == 0.0 && d.reinterpret_as_uint64() != 0UL)
  let body = if signed_text {
    text.clamped_view(start=1).to_owned()
  } else {
    text
  }
  let (digits, exp10) = decompose(body)
  let out = StringBuilder()
  if negative {
    out.write_char('-')
  }
  if digits == "0" {
    // Racket writes negative zero as `-0.0`; the sign is part of the value.
    out.write_string("0.0")
    return out.to_string()
  }
  if exp10 >= -4 && exp10 <= 13 {
    write_positional(out, digits, exp10)
  } else {
    write_exponential(out, digits, exp10)
  }
  out.to_string()
}

///|
/// The significant digits, and the power of ten the first one stands for.
///
/// `body` is MoonBit's rendering of a non-negative finite double, in any of the
/// forms it produces: `3.14`, `0.000001`, `100000000000000000000`, `1e+100`.
fn decompose(body : String) -> (String, Int) {
  let mut mant = body
  let mut exp = 0
  match find_char(body, 'e') {
    Some(i) => {
      mant = body.clamped_view(end=i).to_owned()
      let tail = body.clamped_view(start=i + 1).to_owned()
      exp = parse_signed_int(tail)
    }
    None => ()
  }
  let point = match find_char(mant, '.') {
    Some(i) => i
    None => mant.length()
  }
  let all = StringBuilder()
  for c in mant {
    if c != '.' {
      all.write_char(c)
    }
  }
  let mut digits = all.to_string()
  let mut before = point
  // Leading zeros are not significant, and each one moves the point.
  let mut lead = 0
  while lead < digits.length() - 1 && digits.get_char(lead) is Some('0') {
    lead = lead + 1
    before = before - 1
  }
  digits = digits.clamped_view(start=lead).to_owned()
  // Trailing zeros are not significant either.
  let mut end = digits.length()
  while end > 1 && digits.get_char(end - 1) is Some('0') {
    end = end - 1
  }
  digits = digits.clamped_view(end~).to_owned()
  if digits == "0" {
    return ("0", 0)
  }
  (digits, before - 1 + exp)
}

///|
fn find_char(s : String, c : Char) -> Int? {
  for i in 0..<s.length() {
    if s.get_char(i) is Some(x) && x == c {
      return Some(i)
    }
  }
  None
}

///|
fn parse_signed_int(s : String) -> Int {
  let mut i = 0
  let mut neg = false
  if s.get_char(0) is Some('-') {
    neg = true
    i = 1
  } else if s.get_char(0) is Some('+') {
    i = 1
  }
  let mut v = 0
  while i < s.length() {
    match s.get_char(i) {
      Some(c) if c >= '0' && c <= '9' => v = v * 10 + (c.to_int() - 48)
      _ => break
    }
    i = i + 1
  }
  if neg {
    -v
  } else {
    v
  }
}

///|
/// `1.0`, `10.0`, `0.0001` — always with a point and at least one digit after.
fn write_positional(out : StringBuilder, digits : String, exp10 : Int) -> Unit {
  if exp10 >= 0 {
    let int_len = exp10 + 1
    for i in 0..<int_len {
      if i < digits.length() {
        out.write_char(digits.get_char(i).unwrap())
      } else {
        out.write_char('0')
      }
    }
    out.write_char('.')
    if digits.length() > int_len {
      out.write_string(digits.clamped_view(start=int_len).to_owned())
    } else {
      out.write_char('0')
    }
  } else {
    out.write_string("0.")
    for _ in 0..<(-exp10 - 1) {
      out.write_char('0')
    }
    out.write_string(digits)
  }
}

///|
/// `1e+14`, `1.5e-7` — a point only when there is more than one digit.
fn write_exponential(out : StringBuilder, digits : String, exp10 : Int) -> Unit {
  out.write_char(digits.get_char(0).unwrap())
  if digits.length() > 1 {
    out.write_char('.')
    out.write_string(digits.clamped_view(start=1).to_owned())
  }
  out.write_char('e')
  if exp10 >= 0 {
    out.write_char('+')
  } else {
    out.write_char('-')
  }
  let mag = if exp10 < 0 { -exp10 } else { exp10 }
  out.write_string(mag.to_string())
}

///|
/// Racket's `write` for a string.
///
/// Named escapes where there is one, `\uXXXX` for the other non-printing
/// characters, and everything else as itself -- including non-ASCII, which
/// Racket does not escape.
pub fn string_to_string(s : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in s {
    let u = c.to_int()
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\u{7}' => out.write_string("\\a")
      '\u{8}' => out.write_string("\\b")
      '\t' => out.write_string("\\t")
      '\n' => out.write_string("\\n")
      '\u{B}' => out.write_string("\\v")
      '\u{C}' => out.write_string("\\f")
      '\r' => out.write_string("\\r")
      '\u{1B}' => out.write_string("\\e")
      _ =>
        if @unicode.is_string_literal_plain(c) {
          out.write_char(c)
        } else if u > 0xFFFF {
          out.write_string("\\U")
          out.write_string(pad_upper_hex(u, 8))
        } else {
          out.write_string("\\u")
          out.write_string(pad_upper_hex(u, 4))
        }
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
fn pad_upper_hex(v : Int, width : Int) -> String {
  let hex = v.to_string(radix=16).to_upper()
  let out = StringBuilder()
  for _ in 0..<(width - hex.length()) {
    out.write_char('0')
  }
  out.write_string(hex)
  out.to_string()
}

///|
/// Racket's `write` for a byte string.
///
/// Octal for anything not printable, and padded to three digits only when the
/// next character is an octal digit -- `#"\0001"` is byte zero then `1`, which
/// `#"\01"` would not be.
pub fn bytes_to_string(b : Bytes) -> String {
  let out = StringBuilder()
  out.write_string("#\"")
  for i in 0..<b.length() {
    let v = b[i].to_int()
    let next_is_octal = i + 1 < b.length() &&
      b[i + 1].to_int() >= 48 &&
      b[i + 1].to_int() <= 55
    match v {
      0x22 => out.write_string("\\\"")
      0x5C => out.write_string("\\\\")
      0x07 => out.write_string("\\a")
      0x08 => out.write_string("\\b")
      0x09 => out.write_string("\\t")
      0x0A => out.write_string("\\n")
      0x0B => out.write_string("\\v")
      0x0C => out.write_string("\\f")
      0x0D => out.write_string("\\r")
      0x1B => out.write_string("\\e")
      _ =>
        if v >= 0x20 && v < 0x7F {
          out.write_char(v.unsafe_to_char())
        } else {
          out.write_char('\\')
          let oct = v.to_string(radix=8)
          if next_is_octal {
            for _ in 0..<(3 - oct.length()) {
              out.write_char('0')
            }
          }
          out.write_string(oct)
        }
    }
  }
  out.write_char('"')
  out.to_string()
}
