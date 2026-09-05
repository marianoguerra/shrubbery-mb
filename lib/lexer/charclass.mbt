///|
/// The characters that are never part of a larger token.
///
/// The specification's `special` set, minus the ones that are decided
/// elsewhere. `«` (Pi) and `»` (Pf) are punctuation and so have to be excluded
/// explicitly, or every guillemet would lex as an operator character.
fn is_reserved_punct(c : Char) -> Bool {
  match c {
    ',' | ';' | '#' | '\\' | '_' | '@' | '"' | '\'' => true
    '(' | ')' | '[' | ']' | '{' | '}' | '\u{AB}' | '\u{BB}' => true
    _ => false
  }
}

///|
/// A character an operator can be made of.
///
/// Unicode symbols and punctuation, minus the reserved set — and minus
/// single-code-point emoji, which are identifier characters. `:` and `|` ARE
/// operator characters: they are excluded only as complete operators, not as
/// parts of one, which is why `::` and `||` exist.
fn is_opchar(c : Char) -> Bool {
  if @unicode.is_symbolic(c) {
    !@unicode.is_one_char_emoji(c)
  } else if @unicode.is_punctuation(c) {
    !is_reserved_punct(c)
  } else {
    false
  }
}

///|
/// `#` followed by one of these is a two-character operator: `#'`, `#,`, `#:`,
/// `#;`, `#|`.
fn is_escopchar(c : Char) -> Bool {
  match c {
    '\'' | ',' | ':' | ';' | '|' => true
    _ => false
  }
}

///|
/// Alphanumeric or `_`: what a number or `#true` may not be followed by.
///
/// The specification's delimiter rule, stated in the negative: "Non-alphanumeric
/// characters other than `_` are delimiters", so `1x` is a lexical error rather
/// than a number beside an identifier.
fn is_non_delim(c : Char) -> Bool {
  @unicode.is_alphabetic(c) || @unicode.is_numeric(c) || c == '_'
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
fn is_octal(c : Char) -> Bool {
  c >= '0' && c <= '7'
}

///|
fn is_binary(c : Char) -> Bool {
  c == '0' || c == '1'
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
