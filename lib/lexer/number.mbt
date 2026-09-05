///|
/// A run of digits with single `_` separators between them — never leading,
/// never trailing, never doubled.
fn Scanner::scan_uinteger(
  self : Scanner,
  from : Int,
  digit : (Char) -> Bool,
) -> Int? {
  match self.at(from) {
    Some(c) if digit(c) => ()
    _ => return None
  }
  let mut i = from + 1
  while i < self.src.length() {
    match self.at(i) {
      Some(c) if digit(c) => i = i + 1
      Some('_') =>
        match self.at(i + 1) {
          Some(c) if digit(c) => i = i + 2
          _ => break
        }
      _ => break
    }
  }
  Some(i)
}

///|
/// `e` or `E`, an optional sign, and digits.
fn Scanner::scan_exponent(self : Scanner, from : Int) -> Int? {
  match self.at(from) {
    Some('e') | Some('E') => ()
    _ => return None
  }
  let after_sign = match self.at(from + 1) {
    Some('+') | Some('-') => from + 2
    _ => from + 1
  }
  self.scan_uinteger(after_sign, is_digit)
}

///|
/// The longest number starting at `from`, per the current mode.
///
/// The two modes differ only here. `Initial` admits a leading sign and a
/// leading `.`; `Continuing` — which the scanner enters after an identifier, a
/// literal, a closer or a keyword — admits neither, so that `1+2` is three
/// tokens while `1 +2` is two.
fn Scanner::scan_number(self : Scanner, from : Int) -> Int? {
  let signed = self.mode is Initial
  let body = match self.at(from) {
    Some('+') | Some('-') if signed => from + 1
    _ => from
  }
  // A radix prefix wins over the decimal reading of its leading `0`.
  if self.has(body, "0x") {
    match self.scan_uinteger(body + 2, is_hex) {
      Some(e) => return Some(e)
      None => ()
    }
  }
  if self.has(body, "0o") {
    match self.scan_uinteger(body + 2, is_octal) {
      Some(e) => return Some(e)
      None => ()
    }
  }
  if self.has(body, "0b") {
    match self.scan_uinteger(body + 2, is_binary) {
      Some(e) => return Some(e)
      None => ()
    }
  }
  match self.scan_uinteger(body, is_digit) {
    Some(int_end) => {
      // `123.` needs something after the dot to be part of the number here;
      // a bare trailing dot is decided later, by `maybe_trailing_dot`.
      if self.at(int_end) is Some('.') {
        match self.scan_uinteger(int_end + 1, is_digit) {
          Some(frac_end) =>
            return Some(
              match self.scan_exponent(frac_end) {
                Some(e) => e
                None => frac_end
              },
            )
          None =>
            match self.scan_exponent(int_end + 1) {
              Some(e) => return Some(e)
              None => ()
            }
        }
      }
      Some(
        match self.scan_exponent(int_end) {
          Some(e) => e
          None => int_end
        },
      )
    }
    None =>
      // `.5` — only in `Initial`, and never after a term.
      if signed && self.at(body) is Some('.') {
        match self.scan_uinteger(body + 1, is_digit) {
          Some(frac_end) =>
            Some(
              match self.scan_exponent(frac_end) {
                Some(e) => e
                None => frac_end
              },
            )
          None => None
        }
      } else {
        None
      }
  }
}

///|
/// How far a `bad-number` reaches: digits followed by alphanumerics, or by a
/// `.` and alphanumerics.
///
/// This is what makes `1x` an error rather than `1` beside `x`, and `1.2.3` an
/// error rather than `1.2` beside `.3`. Returns `from` when the number is
/// properly delimited.
fn Scanner::scan_bad_number_tail(self : Scanner, from : Int) -> Int {
  let mut i = from
  while i < self.src.length() {
    match self.at(i) {
      Some(c) if is_non_delim(c) => i = self.step(i)
      Some('.') =>
        match self.at(i + 1) {
          Some(c) if is_non_delim(c) => i = self.step(i + 1)
          _ => break
        }
      _ => break
    }
  }
  i
}

///|
/// Whether the lexeme is digits and separators only, with an optional sign.
///
/// The precondition for both post-passes: only an integer may grow a trailing
/// `.` or a `/denominator`.
fn is_decimal_integer(s : String) -> Bool {
  let mut i = 0
  if s.length() > 0 && (s.at(0) == 43 || s.at(0) == 45) {
    i = 1
  }
  if i >= s.length() {
    return false
  }
  while i < s.length() {
    let c = s.get_char(i)
    match c {
      Some(ch) => if !(@unicode.is_numeric(ch) || ch == '_') { return false }
      None => return false
    }
    i = i + 1
  }
  true
}

///|
/// Decide between a number and the operators that could be hiding in it.
fn Scanner::scan_number_or_operator(
  self : Scanner,
  start : @basic.Pos,
  from : Int,
) -> Token {
  let num = self.scan_number(from)
  match num {
    Some(num_end) => {
      // `bad-number` is a separate rule in the reference and wins on length, so
      // a number that runs into alphanumerics is an error rather than a number
      // beside an identifier.
      let bad_end = self.scan_bad_number_tail(num_end)
      if bad_end > num_end {
        return self.finish(start, bad_end, Fail(ReadError), mode=Continuing)
      }
      return self.finish_number(start, from, num_end)
    }
    None => ()
  }
  match self.scan_identifier(from) {
    Some(e) => return self.finish(start, e, Identifier, mode=Continuing)
    None => ()
  }
  // The operator scan comes BEFORE the `:` and `|` cases, because the reference
  // takes the longest match: `::` is an operator even though `:` alone is the
  // block operator, and `||` likewise. `scan_operator` declines a bare `:` or
  // `|` for exactly this reason, so the fallthrough below is what handles them.
  match self.scan_operator(from) {
    Some(e) => {
      let text = self.src.clamped_view(start=from, end=e).to_owned()
      return if (self.variant.allow_operator)(text) {
        self.finish(start, e, Operator)
      } else {
        self.finish(start, e, Fail(ReadError))
      }
    }
    None => ()
  }
  match self.at(from) {
    Some(':') => return self.finish(start, from + 1, BlockOperator)
    Some('|') => return self.finish(start, from + 1, BarOperator)
    _ => ()
  }
  // Nothing here can start a token. Extend to the next delimiter so the report
  // covers the whole unreadable run rather than one character of it.
  self.finish(start, self.extend_error(from), Fail(ReadError))
}

///|
/// Widen a failure to the next whitespace or structural character.
fn Scanner::extend_error(self : Scanner, from : Int) -> Int {
  let mut i = self.step(from)
  while i < self.src.length() {
    match self.at(i) {
      Some(c) =>
        if @unicode.is_whitespace(c) ||
          is_reserved_punct(c) ||
          is_opchar(c) ||
          is_non_delim(c) {
          break
        } else {
          i = self.step(i)
        }
      None => break
    }
  }
  i
}

///|
/// Apply the two post-passes and build the literal.
fn Scanner::finish_number(
  self : Scanner,
  start : @basic.Pos,
  from : Int,
  num_end : Int,
) -> Token {
  let lexeme = self.src.clamped_view(start=from, end=num_end).to_owned()
  // A trailing `.` joins the number only when it could not be starting a
  // multi-character operator: `1.` is one point zero, `1.+2` is `1`, `.+`, `2`.
  if self.at(num_end) is Some('.') && !self.multi_char_operator_at(num_end) {
    let with_dot = num_end + 1
    if is_decimal_integer(lexeme) {
      return self.finish(
        start,
        with_dot,
        Literal(Flo(parse_decimal_as_double(lexeme))),
        mode=Continuing,
      )
    }
    // `1.2.` — the reference counts the dot as part of the error.
    return self.finish(start, with_dot, Fail(ReadError), mode=Continuing)
  }
  if is_decimal_integer(lexeme) {
    match self.scan_fraction(num_end) {
      Some((den_end, den)) => {
        let n = parse_integer(lexeme)
        return self.finish(
          start,
          den_end,
          Literal(@sexp.Datum::of_ratio(n, parse_integer(den))),
          mode=Continuing,
        )
      }
      None => ()
    }
  }
  self.finish(start, num_end, Literal(parse_number(lexeme)), mode=Continuing)
}

///|
/// `/` and a non-zero denominator not followed by `.`.
///
/// The last condition is what keeps `1/2.0` from becoming the rational a half
/// beside `.0`: a `.` after the digits means the denominator was meant to be a
/// decimal, so the `/` is division and not a fraction bar.
fn Scanner::scan_fraction(self : Scanner, from : Int) -> (Int, String)? {
  if !(self.at(from) is Some('/')) {
    return None
  }
  match self.scan_uinteger(from + 1, is_digit) {
    Some(e) => {
      if self.at(e) is Some('.') {
        return None
      }
      let den = self.src.clamped_view(start=from + 1, end=e).to_owned()
      let mut nonzero = false
      for c in den {
        if c != '0' && c != '_' {
          nonzero = true
        }
      }
      if nonzero {
        Some((e, den))
      } else {
        None
      }
    }
    None => None
  }
}
