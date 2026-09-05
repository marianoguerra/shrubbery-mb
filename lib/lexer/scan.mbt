///|
/// The scanner's position in the source.
///
/// Hand-written rather than generated. The reference's rules are a maximal
/// munch over a `parser-tools/lex` table, and reproducing that mechanically
/// would mean reproducing the table; the rules are few enough, and their
/// interactions specific enough — the two number modes, the three post-peeks —
/// that writing them out is both shorter and easier to check against the
/// specification.
priv struct Scanner {
  src : String
  mut idx : Int
  mut pos : Int
  mut line : Int
  mut col : @column.Column
  mut mode : LexMode
  /// The `@` forms currently being scanned, innermost last. A stack rather than
  /// the reference's threaded status record: nothing here needs to resume a
  /// scan from the middle, which is the only reason that status exists.
  at_stack : Array[AtFrame]
  variant : Variant
}

///|
fn Scanner::here(self : Scanner) -> @basic.Pos {
  { line: self.line, pos: self.pos, idx: self.idx, col: self.col, }
}

///|
fn Scanner::at_end(self : Scanner) -> Bool {
  self.idx >= self.src.length()
}

///|
/// The character at code-unit offset `i`, or `None` past the end.
fn Scanner::at(self : Scanner, i : Int) -> Char? {
  if i < 0 || i >= self.src.length() {
    None
  } else {
    self.src.get_char(i)
  }
}

///|
/// The offset just past the character at `i`.
fn Scanner::step(self : Scanner, i : Int) -> Int {
  match self.at(i) {
    Some(c) => if c.to_int() > 0xFFFF { i + 2 } else { i + 1 }
    None => i + 1
  }
}

///|
/// Whether the source has `lit` at offset `i`.
fn Scanner::has(self : Scanner, i : Int, lit : String) -> Bool {
  let n = lit.length()
  if i + n > self.src.length() {
    return false
  }
  for k in 0..<n {
    if self.src.at(i + k) != lit.at(k) {
      return false
    }
  }
  true
}

///|
/// Build the token spanning `[start, end_idx)` and advance the scanner over it.
///
/// Line and column are advanced by walking the token's own text, which is
/// exactly what the reference does — and is why a grapheme cluster split across
/// two tokens counts as two columns in both implementations rather than one in
/// ours and two in theirs.
fn Scanner::finish(
  self : Scanner,
  start : @basic.Pos,
  end_idx : Int,
  kind : TokenKind,
  partner? : String? = None,
  raw? : String? = None,
  mode? : LexMode = Initial,
) -> Token {
  let text = self.src.clamped_view(start=start.idx, end=end_idx).to_owned()
  let (line_advance, col_advance) = @column.count_graphemes(text)
  self.idx = end_idx
  self.pos = start.pos + text.char_length()
  self.line = start.line + line_advance
  self.col = if line_advance == 0 {
    start.col.plus(col_advance)
  } else {
    col_advance
  }
  self.mode = mode
  { kind, text, raw, span: { start, end: self.here(), }, partner, }
}

///|
/// Scan the whole source.
///
/// The token stream is produced in full before parsing starts. The reference
/// interleaves them, but only because its lexer doubles as an editor's
/// incremental colourer; nothing in the grouping layer feeds back into
/// tokenisation, so there is nothing to interleave for.
pub fn lex_all(
  src : String,
  variant? : Variant = default_variant,
  start_column? : @column.Column = @column.zero,
) -> Array[Token] {
  let s = {
    src,
    idx: 0,
    pos: 1,
    line: 1,
    col: start_column,
    mode: Initial,
    at_stack: [],
    variant,
  }
  let out = []
  while !s.at_end() {
    let t = s.next_token()
    // The reference drops a zero-width `at-content`: a colouring lexer must
    // never return a token of no extent, and the parser would have to skip
    // them anyway. `@x{@y}` produces one between the opener and the escape.
    if t.kind is AtContent && t.text == "" {
      continue
    }
    out.push(t)
  }
  out.push(s.finish(s.here(), s.idx, EndOfInput))
  rewrite_quotes(out)
}

///|
fn Scanner::next_token(self : Scanner) -> Token {
  // Inside an `@` form, three of the modes read characters rather than tokens
  // and take over completely; the rest read one ordinary token and then decide
  // what the form does next.
  match self.at_top() {
    Some(frame) =>
      match frame.mode {
        Open => return self.at_open(frame)
        Inside => return self.at_inside(frame)
        Escape => return self.at_escape(frame)
        Close => return self.at_close(frame)
        _ => return self.after_at_token(frame, self.shrubbery_token())
      }
    None => ()
  }
  self.shrubbery_token()
}

///|
fn Scanner::shrubbery_token(self : Scanner) -> Token {
  let start = self.here()
  let i = self.idx
  let c = match self.at(i) {
    Some(c) => c
    None => return self.finish(start, i, EndOfInput)
  }
  // Whitespace first, and it is where the `continuing` state is dropped: that
  // is what makes `1 +2` two terms where `1+2` is three.
  if @unicode.is_whitespace(c) {
    return self.finish(start, self.scan_whitespace(i), Whitespace)
  }
  match c {
    '"' => self.scan_string(start, i)
    '(' | '[' | '{' | '\u{AB}' => self.finish(start, self.step(i), Opener)
    ')' | ']' | '}' | '\u{BB}' =>
      self.finish(start, self.step(i), Closer, mode=Continuing)
    '\'' => self.finish(start, self.step(i), SQuote)
    ',' => self.finish(start, self.step(i), CommaOperator)
    ';' => self.finish(start, self.step(i), SemicolonOperator)
    '\\' => self.finish(start, self.step(i), ContinueOperator)
    '#' => self.scan_hash(start, i)
    '~' => self.scan_tilde(start, i)
    '@' => self.scan_at(start, i)
    '/' =>
      if self.has(i, "//") {
        self.finish(start, self.scan_line_comment(i), Comment)
      } else if self.has(i, "/*") {
        self.scan_block_comment(start, i)
      } else {
        self.scan_number_or_operator(start, i)
      }
    _ => self.scan_number_or_operator(start, i)
  }
}

///|
/// A run of non-newline whitespace, or such a run and the line terminator that
/// ends it.
///
/// Stopping at the terminator is not cosmetic: interactive mode ends a form at
/// a blank line, and it can only see one if the newline is where a token ends.
fn Scanner::scan_whitespace(self : Scanner, start : Int) -> Int {
  let mut i = start
  while i < self.src.length() {
    match self.at(i) {
      Some('\n') => return i + 1
      Some('\r') => return if self.has(i, "\r\n") { i + 2 } else { i + 1 }
      Some(c) =>
        if @unicode.is_whitespace(c) {
          i = self.step(i)
        } else {
          break
        }
      None => break
    }
  }
  i
}

///|
/// `//` to the end of the line. The terminator itself is NOT consumed: it
/// belongs to the following whitespace token, which is what lets the parser see
/// where the line ended.
fn Scanner::scan_line_comment(self : Scanner, start : Int) -> Int {
  let mut i = start
  while i < self.src.length() {
    match self.at(i) {
      Some('\n') | Some('\r') => break
      _ => i = self.step(i)
    }
  }
  i
}

///|
/// `/* ... */`, nesting.
fn Scanner::scan_block_comment(
  self : Scanner,
  start : @basic.Pos,
  from : Int,
) -> Token {
  let mut i = from + 2
  let mut depth = 1
  while i < self.src.length() {
    if self.has(i, "/*") {
      depth = depth + 1
      i = i + 2
    } else if self.has(i, "*/") {
      depth = depth - 1
      i = i + 2
      if depth == 0 {
        return self.finish(start, i, Comment)
      }
    } else {
      i = self.step(i)
    }
  }
  // Unterminated: the reference produces a failure token covering the rest.
  self.finish(start, self.src.length(), Fail(ReadError))
}

///|
/// `~name` is a keyword and `~#{name}` is one written in Racket's notation.
///
/// Anything else falls through to the ordinary path, because `~` is an operator
/// CHARACTER even though it is not an operator by itself: `~&` is one, and
/// stopping here would split it. Only a lone `~` is a failure, and
/// `scan_operator` is what decides that.
fn Scanner::scan_tilde(self : Scanner, start : @basic.Pos, from : Int) -> Token {
  if self.has(from, "~#{") {
    return self.scan_sexp_escape(start, from, keyword=true)
  }
  match self.scan_plain_identifier(from + 1) {
    Some(e) => self.finish(start, e, Keyword, mode=Continuing)
    None => self.scan_number_or_operator(start, from)
  }
}
