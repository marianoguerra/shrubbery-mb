///|
/// A Racket datum: the value an atom of shrubbery notation denotes.
///
/// `Pair` and `Nil` exist because a `#{...}` escape can contain an improper
/// list. `Rat` exists because `1/2` is an exact rational and turning it into a
/// `Double` would lose the exactness the reference keeps.
pub(all) enum Datum {
  Sym(String)
  Kw(String)
  Str(String)
  Bs(Bytes)
  Ch(Char)
  Bool_(Bool)
  /// Racket's `(void)`, which shrubbery spells `#void`.
  Void
  Int_(@bigint.BigInt)
  /// Numerator and denominator, already in lowest terms with a positive
  /// denominator.
  Rat(@bigint.BigInt, @bigint.BigInt)
  Flo(Double)
  Nil
  Pair(Datum, Datum)
  Vec(Array[Datum])
} derive(Eq)

///|
/// A canonical text form, for comparing our parse against the reference's.
///
/// Deliberately NOT Racket's `write`. Reproducing Racket's flonum printing
/// byte for byte is a real piece of work — shortest-round-trip digits, the
/// forced `.0`, the exponent thresholds — and getting it wrong would show up
/// as a parse-parity failure that is really a formatting bug, which is the
/// worst kind of red herring to hand someone. So a flonum is written as its
/// IEEE-754 bits and the question does not arise. The oracle emits the same
/// form from the Racket side.
///
/// Where the reference's exact printing DOES matter is `write_shrubbery`, and
/// there it is the thing under test rather than the measuring instrument.
pub fn Datum::canonical(self : Datum) -> String {
  let buf = StringBuilder()
  self.write_canonical(buf)
  buf.to_string()
}

///|
pub fn Datum::write_canonical(self : Datum, buf : StringBuilder) -> Unit {
  match self {
    Sym(s) => {
      buf.write_char('|')
      write_escaped(buf, s)
      buf.write_char('|')
    }
    Kw(s) => {
      buf.write_string("#:|")
      write_escaped(buf, s)
      buf.write_char('|')
    }
    Str(s) => {
      buf.write_char('"')
      write_escaped(buf, s)
      buf.write_char('"')
    }
    Bs(b) => {
      buf.write_string("#\"")
      for i in 0..<b.length() {
        buf.write_string("\\x")
        write_hex2(buf, b[i].to_int())
      }
      buf.write_char('"')
    }
    Ch(c) => {
      buf.write_string("#\\u{")
      buf.write_string(c.to_int().to_string(radix=16))
      buf.write_char('}')
    }
    Bool_(v) => buf.write_string(if v { "#t" } else { "#f" })
    Void => buf.write_string("#<void>")
    Int_(n) => buf.write_string(n.to_string())
    Rat(n, d) => {
      buf.write_string(n.to_string())
      buf.write_char('/')
      buf.write_string(d.to_string())
    }
    Flo(d) =>
      // Every NaN is the same value as far as the notation is concerned, and
      // MoonBit's and Racket's differ in the payload bits. Writing the bits of
      // one would report a difference that is not one.
      if d != d {
        buf.write_string("#f64:nan")
      } else {
        buf.write_string("#f64:")
        let bits = d.reinterpret_as_uint64()
        let hex = bits.to_string(radix=16)
        for _ in 0..<(16 - hex.length()) {
          buf.write_char('0')
        }
        buf.write_string(hex)
      }
    Nil => buf.write_string("()")
    Pair(a, b) => {
      buf.write_char('(')
      a.write_canonical(buf)
      buf.write_string(" . ")
      b.write_canonical(buf)
      buf.write_char(')')
    }
    Vec(xs) => {
      buf.write_string("#(")
      for i in 0..<xs.length() {
        if i > 0 {
          buf.write_char(' ')
        }
        xs[i].write_canonical(buf)
      }
      buf.write_char(')')
    }
  }
}

///|
/// Escape so that the result is unambiguous ASCII: `\`, `"` and `|` get a
/// backslash, and everything outside printable ASCII becomes `\u{...}`.
///
/// All-ASCII on purpose. The comparison is against text produced by another
/// process, and an encoding difference anywhere between the two would otherwise
/// show up as a parse disagreement.
fn write_escaped(buf : StringBuilder, s : String) -> Unit {
  for c in s {
    let u = c.to_int()
    if c == '\\' || c == '"' || c == '|' {
      buf.write_char('\\')
      buf.write_char(c)
    } else if u >= 0x20 && u < 0x7F {
      buf.write_char(c)
    } else {
      buf.write_string("\\u{")
      buf.write_string(u.to_string(radix=16))
      buf.write_char('}')
    }
  }
}

///|
fn write_hex2(buf : StringBuilder, v : Int) -> Unit {
  let hex = v.to_string(radix=16)
  if hex.length() < 2 {
    buf.write_char('0')
  }
  buf.write_string(hex)
}

///|
/// An exact integer.
pub fn Datum::of_int(n : Int) -> Datum {
  Int_(@bigint.BigInt::from_int(n))
}

///|
/// An exact rational, reduced, with the sign on the numerator.
///
/// Reduces here rather than trusting the caller because the reference's reader
/// produces reduced rationals and the canonical form has to match: `2/4` and
/// `1/2` are the same number and must not compare as different parses.
pub fn Datum::of_ratio(num : @bigint.BigInt, den : @bigint.BigInt) -> Datum {
  let zero = @bigint.BigInt::from_int(0)
  let mut n = num
  let mut d = den
  if d < zero {
    n = -n
    d = -d
  }
  let g = gcd(if n < zero { -n } else { n }, d)
  if g > @bigint.BigInt::from_int(1) {
    n = n / g
    d = d / g
  }
  if d == @bigint.BigInt::from_int(1) {
    Int_(n)
  } else {
    Rat(n, d)
  }
}

///|
fn gcd(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let zero = @bigint.BigInt::from_int(0)
  let mut x = a
  let mut y = b
  while y != zero {
    let t = x % y
    x = y
    y = t
  }
  x
}
