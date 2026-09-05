///|
/// `#{ ... }` and `~#{ ... }`: an escape to Racket's own notation.
///
/// The whole escape becomes ONE token — an identifier when the datum is a
/// symbol, a literal otherwise — and its raw text is the datum RE-PRINTED
/// rather than the source read, so `#{ foo }` has raw `#{foo}`. That is the
/// reference's behaviour and it is why `Token` keeps `raw` apart from `text`.
fn Scanner::scan_sexp_escape(
  self : Scanner,
  start : @basic.Pos,
  from : Int,
  keyword~ : Bool,
) -> Token {
  let open_len = if keyword { 3 } else { 2 }
  let mut i = from + open_len
  i = self.skip_racket_space(i)
  match self.read_datum(i) {
    None => self.finish(start, i, Fail(ExpectedSExp(keyword~)), mode=Continuing)
    Some((after, datum)) => {
      let mut j = self.skip_racket_space(after)
      match self.at(j) {
        Some('}') => {
          j = j + 1
          let printed = write_racket(datum)
          let raw = if keyword {
            "~#{" + printed + "}"
          } else {
            "#{" + printed + "}"
          }
          if keyword {
            match datum {
              Sym(name) =>
                self.finish(
                  start,
                  j,
                  Keyword,
                  raw=Some(raw),
                  value=Some(Sym(name)),
                  mode=Continuing,
                )
              _ =>
                self.finish(
                  start,
                  j,
                  Fail(ExpectedSExp(keyword=true)),
                  mode=Continuing,
                )
            }
          } else {
            match datum {
              // A pair is how a parsed shrubbery is represented, so admitting
              // one here would make two different things indistinguishable.
              Pair(_) =>
                self.finish(
                  start,
                  j,
                  Fail(SExpMustNotBePair),
                  raw=Some(raw),
                  mode=Continuing,
                )
              Sym(_) =>
                self.finish(
                  start,
                  j,
                  Identifier,
                  raw=Some(raw),
                  value=Some(datum),
                  mode=Continuing,
                )
              _ =>
                self.finish(
                  start,
                  j,
                  Literal(datum),
                  raw=Some(raw),
                  mode=Continuing,
                )
            }
          }
        }
        None =>
          self.finish(
            start,
            j,
            Fail(ExpectedSExpClose(keyword~)),
            mode=Continuing,
          )
        _ =>
          self.finish(
            start,
            j,
            Fail(ExpectedSExpOnlyWhitespace(keyword~)),
            mode=Continuing,
          )
      }
    }
  }
}

///|
fn Scanner::skip_racket_space(self : Scanner, from : Int) -> Int {
  let mut i = from
  while i < self.src.length() {
    match self.at(i) {
      Some(c) if @unicode.is_whitespace(c) => i = self.step(i)
      _ => break
    }
  }
  i
}

///|
/// A delimiter in Racket's reader: what ends a symbol or a number.
fn is_racket_delim(c : Char) -> Bool {
  if @unicode.is_whitespace(c) {
    return true
  }
  match c {
    '(' | ')' | '[' | ']' | '{' | '}' | '"' | '\'' | '`' | ',' | ';' => true
    _ => false
  }
}

///|
/// Read one Racket datum. Enough of the reader for what a shrubbery escape
/// actually contains.
///
/// The escape exists to name a Racket binding whose spelling shrubbery cannot
/// write — `treelist-ref`, `enabled?`, `version<?` — and that is what almost
/// every use in the corpus is. Lists, vectors, strings and characters are here
/// because the grammar admits them; anything stranger is kept verbatim as
/// `Other`, which round-trips and reports honestly rather than failing to lex.
fn Scanner::read_datum(self : Scanner, from : Int) -> (Int, @sexp.Datum)? {
  let c = match self.at(from) {
    Some(c) => c
    None => return None
  }
  match c {
    '"' => self.read_racket_string(from)
    '|' => self.read_bar_symbol(from)
    '(' | '[' => self.read_racket_list(from)
    '#' => self.read_hash_datum(from)
    _ =>
      if is_racket_delim(c) {
        None
      } else {
        self.read_symbol_or_number(from)
      }
  }
}

///|
fn Scanner::read_symbol_or_number(
  self : Scanner,
  from : Int,
) -> (Int, @sexp.Datum)? {
  let buf = StringBuilder()
  let mut escaped = false
  let mut i = from
  while i < self.src.length() {
    match self.at(i) {
      // A backslash escapes the next character, which is how `\|>` names the
      // symbol `|>` without bars around it.
      Some('\\') =>
        match self.at(i + 1) {
          Some(c) => {
            buf.write_char(c)
            escaped = true
            i = self.step(i + 1)
          }
          None => break
        }
      Some('|') => {
        // Bars inside a symbol quote a run of characters verbatim.
        escaped = true
        i = i + 1
        while i < self.src.length() {
          match self.at(i) {
            Some('|') => {
              i = i + 1
              break
            }
            Some(c) => {
              buf.write_char(c)
              i = self.step(i)
            }
            None => break
          }
        }
      }
      Some(c) if !is_racket_delim(c) => {
        buf.write_char(c)
        i = self.step(i)
      }
      _ => break
    }
  }
  if i == from {
    return None
  }
  let text = buf.to_string()
  if escaped {
    return Some((i, Sym(text)))
  }
  Some((i, racket_number(text) |> or_symbol(text)))
}

///|
fn or_symbol(d : @sexp.Datum?, text : String) -> @sexp.Datum {
  match d {
    Some(v) => v
    None => Sym(text)
  }
}

///|
/// A Racket number, if the text is one.
///
/// Exact integers and rationals become values; a complex literal becomes an
/// `Other` holding the text Racket would print for it, which is the source with
/// a bare imaginary unit spelled out — Racket writes `2+i` back as `2+1i`.
/// Modelling complex arithmetic to re-print two corpus lines would be a poor
/// trade; keeping the printed form is exact and costs a normalisation.
fn racket_number(text : String) -> @sexp.Datum? {
  match complex_form(text) {
    Some(normalized) => return Some(Other(normalized))
    None => ()
  }
  racket_real(text)
}

///|
/// `a+bi` and `a-bi`, with the imaginary magnitude normalised to Racket's
/// printed form.
fn complex_form(text : String) -> String? {
  if !(text.has_suffix("i") || text.has_suffix("I")) {
    return None
  }
  let body = text.clamped_view(end=text.length() - 1).to_owned()
  // The split is the last sign that is not the leading one.
  let mut split = -1
  for k in 1..<body.length() {
    match body.get_char(k) {
      Some('+') | Some('-') => split = k
      _ => ()
    }
  }
  if split <= 0 {
    return None
  }
  let real = body.clamped_view(end=split).to_owned()
  let sign = body.clamped_view(start=split, end=split + 1).to_owned()
  let imag = body.clamped_view(start=split + 1).to_owned()
  if racket_real(real) is None {
    return None
  }
  if imag == "" {
    return Some(real + sign + "1i")
  }
  if racket_real(imag) is None {
    return None
  }
  Some(real + sign + imag + "i")
}

///|
/// A real number: an exact integer or rational.
fn racket_real(text : String) -> @sexp.Datum? {
  let mut i = 0
  if text.length() > 0 && (text.at(0) == 43 || text.at(0) == 45) {
    i = 1
  }
  if i >= text.length() {
    return None
  }
  let mut slash = -1
  let mut k = i
  while k < text.length() {
    let c = text.get_char(k)
    match c {
      Some(ch) =>
        if ch == '/' && slash < 0 && k > i {
          slash = k
        } else if !is_digit(ch) {
          return None
        }
      None => return None
    }
    k = k + 1
  }
  if slash < 0 {
    Some(Int_(parse_integer(text)))
  } else if slash + 1 < text.length() {
    let num = text.clamped_view(end=slash).to_owned()
    let den = text.clamped_view(start=slash + 1).to_owned()
    Some(@sexp.Datum::of_ratio(parse_integer(num), parse_integer(den)))
  } else {
    None
  }
}

///|
fn Scanner::read_bar_symbol(self : Scanner, from : Int) -> (Int, @sexp.Datum)? {
  let buf = StringBuilder()
  let mut i = from + 1
  while i < self.src.length() {
    match self.at(i) {
      Some('|') => return Some((i + 1, Sym(buf.to_string())))
      Some(c) => {
        buf.write_char(c)
        i = self.step(i)
      }
      None => break
    }
  }
  None
}

///|
fn Scanner::read_racket_string(
  self : Scanner,
  from : Int,
) -> (Int, @sexp.Datum)? {
  let buf = StringBuilder()
  let mut i = from + 1
  while i < self.src.length() {
    match self.at(i) {
      Some('"') => return Some((i + 1, Str(buf.to_string())))
      Some('\\') =>
        match self.decode_escape(i, unicode=true) {
          Some((next, code)) => {
            append_code(buf, code)
            i = next
          }
          None => return None
        }
      Some(c) => {
        buf.write_char(c)
        i = self.step(i)
      }
      None => break
    }
  }
  None
}

///|
/// A list, only so that the "must not be a pair" rule has something to reject.
fn Scanner::read_racket_list(self : Scanner, from : Int) -> (Int, @sexp.Datum)? {
  let close = if self.at(from) is Some('[') { ']' } else { ')' }
  let items = []
  let mut i = self.skip_racket_space(from + 1)
  while i < self.src.length() {
    if self.at(i) is Some(c) && c == close {
      let mut d : @sexp.Datum = Nil
      for k = items.length() - 1; k >= 0; k = k - 1 {
        d = Pair(items[k], d)
      }
      return Some((i + 1, d))
    }
    match self.read_datum(i) {
      Some((next, item)) => {
        items.push(item)
        i = self.skip_racket_space(next)
      }
      None => return None
    }
  }
  None
}

///|
fn Scanner::read_hash_datum(self : Scanner, from : Int) -> (Int, @sexp.Datum)? {
  if self.has(from, "#true") {
    return Some((from + 5, Bool_(true)))
  }
  if self.has(from, "#false") {
    return Some((from + 6, Bool_(false)))
  }
  if self.has(from, "#t") {
    return Some((from + 2, Bool_(true)))
  }
  if self.has(from, "#f") {
    return Some((from + 2, Bool_(false)))
  }
  if self.has(from, "#\"") {
    return match self.read_racket_string(from + 1) {
      Some((e, Str(s))) => {
        let out = []
        for c in s {
          out.push((c.to_int() & 0xFF).to_byte())
        }
        Some((e, Bs(Bytes::from_array(out))))
      }
      _ => None
    }
  }
  if self.has(from, "#\\") {
    return self.read_racket_char(from)
  }
  // `#%name` is an ordinary symbol; Racket's reader has no `#%` dispatch.
  if self.has(from, "#%") {
    return self.read_symbol_or_number(from)
  }
  if self.has(from, "#rx\"") || self.has(from, "#px\"") {
    let px = self.at(from + 1) is Some('p')
    return match self.read_racket_string(from + 3) {
      Some((e, Str(pattern))) => Some((e, Rx(px, pattern)))
      _ => None
    }
  }
  if self.has(from, "#:") {
    let mut i = from + 2
    while i < self.src.length() {
      match self.at(i) {
        Some(c) if !is_racket_delim(c) => i = self.step(i)
        _ => break
      }
    }
    return Some(
      (i, Kw(self.src.clamped_view(start=from + 2, end=i).to_owned())),
    )
  }
  if self.has(from, "#(") {
    return match self.read_racket_list(from + 1) {
      Some((e, list)) => {
        let items = []
        let mut d = list
        while d is Pair(head, tail) {
          items.push(head)
          d = tail
        }
        Some((e, Vec(items)))
      }
      None => None
    }
  }
  // A regexp, a box, a hash table, or anything else the reader knows and this
  // one does not. Kept verbatim so it round-trips; the value is opaque, which
  // is honest — nothing downstream inspects it.
  let mut i = from
  let mut depth = 0
  while i < self.src.length() {
    match self.at(i) {
      Some('(') | Some('[') => {
        depth = depth + 1
        i = i + 1
      }
      Some(')') | Some(']') => {
        depth = depth - 1
        i = i + 1
      }
      Some('"') =>
        match self.read_racket_string(i) {
          Some((e, _)) => i = e
          None => return None
        }
      Some('}') if depth == 0 => break
      Some(c) if @unicode.is_whitespace(c) && depth == 0 => break
      Some(_) => i = self.step(i)
      None => break
    }
  }
  if i == from {
    None
  } else {
    Some((i, Other(self.src.clamped_view(start=from, end=i).to_owned())))
  }
}

///|
fn Scanner::read_racket_char(self : Scanner, from : Int) -> (Int, @sexp.Datum)? {
  let named = [
    ("space", ' '),
    ("newline", '\n'),
    ("tab", '\t'),
    ("nul", '\u{0}'),
    ("null", '\u{0}'),
    ("return", '\r'),
    ("backspace", '\u{8}'),
    ("linefeed", '\n'),
    ("page", '\u{C}'),
    ("rubout", '\u{7F}'),
    ("vtab", '\u{B}'),
    ("alarm", '\u{7}'),
  ]
  for entry in named {
    let (name, ch) = entry
    if self.has(from + 2, name) {
      return Some((from + 2 + name.length(), Ch(ch)))
    }
  }
  // `#\uXXXX` and `#\UXXXXXXXX`, but only when hex digits actually follow:
  // `#\u` on its own is the character `u`.
  match self.at(from + 2) {
    Some('u') =>
      match self.hex_escape(from + 3, 1, 4) {
        Some((e, code)) => return Some((e, Ch(code.unsafe_to_char())))
        None => ()
      }
    Some('U') =>
      match self.hex_escape(from + 3, 1, 8) {
        Some((e, code)) => return Some((e, Ch(code.unsafe_to_char())))
        None => ()
      }
    _ => ()
  }
  match self.at(from + 2) {
    Some(c) => Some((self.step(from + 2), Ch(c)))
    None => None
  }
}
