///|
/// Everything that starts with `#`.
///
/// The order here is the order of decreasing length, because the reference's
/// lexer takes the longest match: `#//` before `#/`, `#true` before `#`.
fn Scanner::scan_hash(self : Scanner, start : @basic.Pos, from : Int) -> Token {
  if self.has(from, "#//") {
    return self.finish(start, from + 3, GroupComment)
  }
  if self.has(from, "#\"") {
    return self.scan_byte_string(start, from)
  }
  // `#!` opens a script line, but only when followed by a space or `/`.
  // Anything else after `#!` is an error, and the reference makes the error
  // token stop at the first whitespace.
  if self.has(from, "#!") {
    match self.at(from + 2) {
      Some(' ') | Some('/') =>
        return self.finish(start, self.scan_script(from), Comment)
      _ => {
        let mut i = from + 2
        while i < self.src.length() {
          match self.at(i) {
            Some(c) if !@unicode.is_whitespace(c) => i = self.step(i)
            _ => break
          }
        }
        return self.finish(start, i, Fail(ReadError))
      }
    }
  }
  // The constant words. Each is subject to the delimiter rule, which the
  // `bad-hash` tail below enforces by reaching further than the word does.
  let word = self.hash_word(from)
  match word {
    Some((e, datum)) =>
      if self.hash_tail(from) <= e {
        return self.finish(start, e, Literal(datum), mode=Continuing)
      }
    None => ()
  }
  match self.scan_identifier(from) {
    Some(e) => return self.finish(start, e, Identifier, mode=Continuing)
    None => ()
  }
  match self.at(from + 1) {
    Some(c) if is_escopchar(c) => {
      let e = self.absorb_slash(from + 2)
      let text = self.src.clamped_view(start=from, end=e).to_owned()
      return if (self.variant.allow_operator)(text) {
        self.finish(start, e, Operator)
      } else {
        self.finish(start, e, Fail(ReadError))
      }
    }
    _ => ()
  }
  // `bad-hash`: `#` and any alphanumeric run after it.
  self.finish(start, self.hash_tail(from), Fail(ReadError))
}

///|
/// One of the `#` constants, if the source has it here.
fn Scanner::hash_word(self : Scanner, from : Int) -> (Int, @sexp.Datum)? {
  if self.has(from, "#true") {
    Some((from + 5, Bool_(true)))
  } else if self.has(from, "#false") {
    Some((from + 6, Bool_(false)))
  } else if self.has(from, "#void") {
    Some((from + 5, Void))
  } else if self.has(from, "#neginf") {
    Some((from + 7, Flo(@double.neg_infinity)))
  } else if self.has(from, "#inf") {
    Some((from + 4, Flo(@double.infinity)))
  } else if self.has(from, "#nan") {
    Some((from + 4, Flo(@double.not_a_number)))
  } else {
    None
  }
}

///|
/// How far `#` plus alphanumerics reaches — the extent of a `bad-hash`, and the
/// delimiter check for the constants.
fn Scanner::hash_tail(self : Scanner, from : Int) -> Int {
  let mut i = from + 1
  while i < self.src.length() {
    match self.at(i) {
      Some(c) if is_non_delim(c) => i = self.step(i)
      _ => break
    }
  }
  i
}

///|
/// `#!` to the end of the line, with a trailing `\` continuing onto the next.
fn Scanner::scan_script(self : Scanner, from : Int) -> Int {
  let mut i = from + 2
  while i < self.src.length() {
    match self.at(i) {
      Some('\\') =>
        match self.at(i + 1) {
          Some('\n') => i = i + 2
          Some('\r') => i = if self.has(i + 1, "\r\n") { i + 3 } else { i + 2 }
          _ => i = self.step(i)
        }
      Some('\n') | Some('\r') => break
      _ => i = self.step(i)
    }
  }
  i
}
