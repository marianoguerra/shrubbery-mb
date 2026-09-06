///|
/// The scanner.
///
/// A hand-written cursor over a `String`, following the WHATWG tokenizer
/// closely enough that a reader can check one against the other, and departing
/// from it in exactly one direction: it produces markup tokens rather than
/// driving a tree builder, so it has no insertion modes and no way to be told
/// what namespace it is in.
///
/// Indices are UTF-16 code units throughout, which is what a MoonBit `String`
/// is indexed in and what `@span.Span` measures. Every character the scanner
/// makes a decision about is ASCII, so a surrogate pair simply falls into the
/// "text" bucket a unit at a time and comes out whole.

///|
/// The replacement character, which the specification substitutes for NUL.
const REPLACEMENT : Char = '\u{FFFD}'

///|
priv struct Scanner {
  src : String
  len : Int
  mut pos : Int
  /// The name of the last start tag emitted. This is the specification's
  /// "appropriate end tag token" check, and it is the only piece of state the
  /// tokenizer needs from the document it is tokenizing.
  mut last_start : String
  problems : Array[(@kind.ErrorKind, @span.Span)]
}

///|
/// Tokenize a whole document, ending with exactly one `Eof`.
pub fn tokenize(src : String) -> Scanned {
  let s = { src, len: src.length(), pos: 0, last_start: "", problems: [], }
  let out = []
  while true {
    let t = s.next()
    let done = t.kind == Eof
    out.push(t)
    if done {
      break
    }
  }
  { tokens: out, problems: s.problems, }
}

///|
/// Tokenize, keeping only the tokens.
pub fn tokens(src : String) -> Array[Token] {
  tokenize(src).tokens
}

// ------------------------------------------------------------------- cursor

///|
/// The character at `i`, or NUL past the end.
///
/// NUL is safe as a sentinel because a real NUL in the input is replaced with
/// U+FFFD as it is read, so one can never appear as data.
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
fn Scanner::slice(self : Scanner, start : Int, end : Int) -> String {
  self.src.clamped_view(start~, end~).to_owned()
}

///|
fn Scanner::tok(self : Scanner, start : Int, kind : TokenKind) -> Token {
  { kind, span: @span.Span::new(start, self.pos), }
}

///|
fn Scanner::note(
  self : Scanner,
  kind : @kind.ErrorKind,
  span : @span.Span,
) -> Unit {
  self.problems.push((kind, span))
}

///|
/// Whether the input at `i` matches `what`, ASCII-case-insensitively.
fn Scanner::matches_ci(self : Scanner, i : Int, what : String) -> Bool {
  let n = what.length()
  if i + n > self.len {
    return false
  }
  let mut k = 0
  while k < n {
    if lower(self.at(i + k)) !=
      lower(what.unsafe_get(k).to_int().unsafe_to_char()) {
      return false
    }
    k = k + 1
  }
  true
}

// --------------------------------------------------------------- predicates

///|
fn lower(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn is_ws(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u{0C}'
}

///|
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
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
/// A character that may appear in a tag or attribute name.
///
/// Wider than the specification's, deliberately: it admits `:` and everything
/// above U+007F, so that `xlink:href` and a custom element with an accented
/// name arrive as one name rather than as a name and some text. The parser
/// splits the prefix off; the scanner has no reason to.
fn is_name_char(c : Char) -> Bool {
  !is_ws(c) &&
  c != '/' &&
  c != '>' &&
  c != '=' &&
  c != '<' &&
  c != '\u{0}' &&
  c != '"' &&
  c != '\''
}

// --------------------------------------------------------------- the stream

///|
fn Scanner::next(self : Scanner) -> Token {
  if self.pos >= self.len {
    return self.tok(self.pos, Eof)
  }
  // A raw-text or escapable-raw-text body runs to its own end tag and is
  // scanned as one piece. The check is here rather than in the tag branch
  // because the body follows the tag it belongs to, and `last_start` is what
  // remembers which tag that was.
  if self.last_start != "" {
    let tag = self.last_start
    self.last_start = ""
    if @names.is_raw_text(tag) {
      return self.raw_text_body(tag)
    }
    if @names.is_escapable_raw_text(tag) {
      return self.escapable_body(tag)
    }
  }
  if self.peek() == '<' {
    return self.markup()
  }
  self.text()
}

///|
/// Everything up to the next `<`, with character references resolved.
fn Scanner::text(self : Scanner) -> Token {
  let start = self.pos
  let buf = StringBuilder()
  let mut decoded = false
  while self.pos < self.len && self.peek() != '<' {
    let c = self.peek()
    if c == '&' {
      match self.reference(true) {
        Some(text) => {
          buf.write_string(text)
          decoded = true
          continue
        }
        None => ()
      }
    }
    if c == '\u{0}' {
      self.note(
        UnexpectedNullCharacter,
        @span.Span::new(self.pos, self.pos + 1),
      )
      buf.write_char(REPLACEMENT)
      decoded = true
      self.pos = self.pos + 1
      continue
    }
    buf.write_char(c)
    self.pos = self.pos + 1
  }
  let raw = if decoded { Some(self.slice(start, self.pos)) } else { None }
  self.tok(start, Text(buf.to_string(), raw))
}

///|
/// A `<`, and whatever follows it.
fn Scanner::markup(self : Scanner) -> Token {
  let start = self.pos
  let c1 = self.at(self.pos + 1)
  if c1 == '!' {
    if self.matches_ci(self.pos + 2, "--") {
      return self.comment()
    }
    if self.matches_ci(self.pos + 2, "doctype") {
      return self.doctype()
    }
    if self.matches_ci(self.pos + 2, "[CDATA[") {
      return self.cdata()
    }
    return self.bogus_comment(2)
  }
  if c1 == '/' {
    if is_alpha(self.at(self.pos + 2)) {
      return self.end_tag()
    }
    if self.at(self.pos + 2) == '>' {
      // `</>` is dropped entirely, per the specification.
      self.pos = self.pos + 3
      self.note(MissingTagName, @span.Span::new(start, self.pos))
      return self.tok(start, Text("", None))
    }
    self.note(InvalidFirstCharacterOfTagName, @span.Span::new(start, start + 3))
    return self.bogus_comment(2)
  }
  if is_alpha(c1) {
    return self.start_tag()
  }
  if c1 == '?' {
    // The `?` is part of the comment's data, per the specification, so that
    // `<?php ... ?>` comes back as it went in.
    return self.bogus_comment(1)
  }
  // A `<` that begins nothing: literal text, per the specification.
  self.pos = self.pos + 1
  self.tok(start, Text("<", None))
}

// ------------------------------------------------------------------- tags

///|
fn Scanner::start_tag(self : Scanner) -> Token {
  let start = self.pos
  self.pos = self.pos + 1
  let name_start = self.pos
  while self.pos < self.len && is_name_char(self.peek()) {
    self.pos = self.pos + 1
  }
  let name = self.slice(name_start, self.pos).to_lower()
  let attrs : Array[RawAttr] = []
  let mut self_closing = false
  while true {
    while self.pos < self.len && is_ws(self.peek()) {
      self.pos = self.pos + 1
    }
    if self.pos >= self.len {
      self.note(EofInTag, @span.Span::new(start, self.pos))
      break
    }
    let c = self.peek()
    if c == '>' {
      self.pos = self.pos + 1
      break
    }
    if c == '/' {
      if self.at(self.pos + 1) == '>' {
        self_closing = true
        self.pos = self.pos + 2
        break
      }
      self.note(UnexpectedSolidusInTag, @span.Span::new(self.pos, self.pos + 1))
      self.pos = self.pos + 1
      continue
    }
    if c == '=' && attrs.length() == 0 {
      self.note(
        UnexpectedEqualsSignBeforeAttributeName,
        @span.Span::new(self.pos, self.pos + 1),
      )
      self.pos = self.pos + 1
      continue
    }
    match self.attribute() {
      Some(a) => {
        let mut seen = false
        for existing in attrs {
          if existing.name == a.name {
            seen = true
          }
        }
        if seen {
          self.note(DuplicateAttribute(a.name), a.span)
        } else {
          attrs.push(a)
        }
      }
      // Nothing consumed: step over the character so recovery makes progress.
      None => self.pos = self.pos + 1
    }
  }
  if !self_closing &&
    (@names.is_raw_text(name) || @names.is_escapable_raw_text(name)) {
    self.last_start = name
  }
  self.tok(start, StartTag(name, attrs, self_closing))
}

///|
fn Scanner::end_tag(self : Scanner) -> Token {
  let start = self.pos
  self.pos = self.pos + 2
  let name_start = self.pos
  while self.pos < self.len && is_name_char(self.peek()) {
    self.pos = self.pos + 1
  }
  let name = self.slice(name_start, self.pos).to_lower()
  // Attributes on an end tag are a parse error and are dropped, which is what
  // the specification says and what makes `</div class="x">` harmless.
  while self.pos < self.len && self.peek() != '>' {
    self.pos = self.pos + 1
  }
  if self.pos < self.len {
    self.pos = self.pos + 1
  } else {
    self.note(EofInTag, @span.Span::new(start, self.pos))
  }
  self.tok(start, EndTag(name))
}

///|
fn Scanner::attribute(self : Scanner) -> RawAttr? {
  let start = self.pos
  while self.pos < self.len && is_name_char(self.peek()) {
    self.pos = self.pos + 1
  }
  if self.pos == start {
    return None
  }
  let name = self.slice(start, self.pos).to_lower()
  while self.pos < self.len && is_ws(self.peek()) {
    self.pos = self.pos + 1
  }
  if self.peek() != '=' {
    return Some({
      name,
      value: None,
      raw: None,
      span: @span.Span::new(start, self.pos),
    })
  }
  self.pos = self.pos + 1
  while self.pos < self.len && is_ws(self.peek()) {
    self.pos = self.pos + 1
  }
  let (value, raw) = self.attribute_value()
  Some({
    name,
    value: Some(value),
    raw,
    span: @span.Span::new(start, self.pos),
  })
}

///|
fn Scanner::attribute_value(self : Scanner) -> (String, String?) {
  let quote = self.peek()
  let quoted = quote == '"' || quote == '\''
  if quoted {
    self.pos = self.pos + 1
  }
  let start = self.pos
  let buf = StringBuilder()
  let mut decoded = false
  while self.pos < self.len {
    let c = self.peek()
    if quoted && c == quote {
      break
    }
    if !quoted && (is_ws(c) || c == '>') {
      break
    }
    if !quoted && (c == '"' || c == '\'' || c == '<' || c == '=' || c == '`') {
      self.note(
        UnexpectedCharacterInUnquotedAttributeValue,
        @span.Span::new(self.pos, self.pos + 1),
      )
    }
    if c == '&' {
      match self.reference(false) {
        Some(text) => {
          buf.write_string(text)
          decoded = true
          continue
        }
        None => ()
      }
    }
    if c == '\u{0}' {
      self.note(
        UnexpectedNullCharacter,
        @span.Span::new(self.pos, self.pos + 1),
      )
      buf.write_char(REPLACEMENT)
      decoded = true
      self.pos = self.pos + 1
      continue
    }
    buf.write_char(c)
    self.pos = self.pos + 1
  }
  let raw = if decoded { Some(self.slice(start, self.pos)) } else { None }
  if quoted && self.pos < self.len {
    self.pos = self.pos + 1
  }
  (buf.to_string(), raw)
}

// -------------------------------------------------------------- raw bodies

///|
/// Everything up to `</tag`, verbatim.
///
/// ASCII-case-insensitively, and inside a JavaScript string literal just the
/// same -- there is no escape, which is why the printer has to refuse a body
/// that contains one rather than trying to write it back.
fn Scanner::raw_text_body(self : Scanner, tag : String) -> Token {
  let start = self.pos
  let close = "</" + tag
  while self.pos < self.len && !self.matches_ci(self.pos, close) {
    self.pos = self.pos + 1
  }
  if self.pos >= self.len {
    self.note(EofInRawText(tag), @span.Span::new(start, self.pos))
  }
  self.tok(start, RawText(self.slice(start, self.pos)))
}

///|
/// Everything up to `</tag`, with character references resolved.
fn Scanner::escapable_body(self : Scanner, tag : String) -> Token {
  let start = self.pos
  let close = "</" + tag
  let buf = StringBuilder()
  let mut decoded = false
  while self.pos < self.len && !self.matches_ci(self.pos, close) {
    if self.peek() == '&' {
      match self.reference(true) {
        Some(text) => {
          buf.write_string(text)
          decoded = true
          continue
        }
        None => ()
      }
    }
    buf.write_char(self.peek())
    self.pos = self.pos + 1
  }
  if self.pos >= self.len {
    self.note(EofInRawText(tag), @span.Span::new(start, self.pos))
  }
  let raw = if decoded { Some(self.slice(start, self.pos)) } else { None }
  self.tok(start, Text(buf.to_string(), raw))
}

// -------------------------------------------------------- declarations

///|
fn Scanner::comment(self : Scanner) -> Token {
  let start = self.pos
  self.pos = self.pos + 4
  // `<!-->` and `<!--->` close immediately, per the specification.
  if self.matches_ci(self.pos, ">") || self.matches_ci(self.pos, "->") {
    let end = if self.peek() == '>' { self.pos + 1 } else { self.pos + 2 }
    self.pos = end
    self.note(AbruptClosingOfEmptyComment, @span.Span::new(start, self.pos))
    return self.tok(start, Comment(""))
  }
  let body_start = self.pos
  while self.pos < self.len && !self.matches_ci(self.pos, "-->") {
    if self.matches_ci(self.pos, "--!>") {
      let body = self.slice(body_start, self.pos)
      self.pos = self.pos + 4
      self.note(IncorrectlyClosedComment, @span.Span::new(start, self.pos))
      return self.tok(start, Comment(body))
    }
    if self.matches_ci(self.pos, "<!--") && self.pos > body_start {
      self.note(NestedComment, @span.Span::new(self.pos, self.pos + 4))
    }
    self.pos = self.pos + 1
  }
  let body = self.slice(body_start, self.pos)
  if self.pos >= self.len {
    self.note(EofInComment, @span.Span::new(start, self.pos))
  } else {
    self.pos = self.pos + 3
  }
  self.tok(start, Comment(body))
}

///|
/// A `<!x`, a `<?php`, a `</ `: not a tag, and read as a comment.
///
/// The specification calls this a bogus comment and so does the diagnostic. It
/// is a warning rather than an error because it is how a browser reads the same
/// bytes, and a library that rejected what every browser accepts would be
/// describing a language nobody writes.
fn Scanner::bogus_comment(self : Scanner, skip : Int) -> Token {
  let start = self.pos
  self.pos = self.pos + skip
  let body_start = self.pos
  while self.pos < self.len && self.peek() != '>' {
    self.pos = self.pos + 1
  }
  let body = self.slice(body_start, self.pos)
  if self.pos < self.len {
    self.pos = self.pos + 1
  }
  self.note(BogusComment, @span.Span::new(start, self.pos))
  self.tok(start, Comment(body))
}

///|
fn Scanner::cdata(self : Scanner) -> Token {
  let start = self.pos
  self.pos = self.pos + 9
  let body_start = self.pos
  while self.pos < self.len && !self.matches_ci(self.pos, "]]>") {
    self.pos = self.pos + 1
  }
  let body = self.slice(body_start, self.pos)
  if self.pos < self.len {
    self.pos = self.pos + 3
  }
  self.tok(start, Cdata(body))
}

///|
fn Scanner::doctype(self : Scanner) -> Token {
  let start = self.pos
  self.pos = self.pos + 9
  while self.pos < self.len && is_ws(self.peek()) {
    self.pos = self.pos + 1
  }
  let name_start = self.pos
  while self.pos < self.len && !is_ws(self.peek()) && self.peek() != '>' {
    self.pos = self.pos + 1
  }
  let name = self.slice(name_start, self.pos).to_lower()
  let mut public_id : String? = None
  let mut system_id : String? = None
  while self.pos < self.len && self.peek() != '>' {
    if is_ws(self.peek()) {
      self.pos = self.pos + 1
      continue
    }
    if self.matches_ci(self.pos, "public") {
      self.pos = self.pos + 6
      public_id = self.doctype_quoted()
      system_id = self.doctype_quoted()
      continue
    }
    if self.matches_ci(self.pos, "system") {
      self.pos = self.pos + 6
      system_id = self.doctype_quoted()
      continue
    }
    self.note(MalformedDoctype, @span.Span::new(self.pos, self.pos + 1))
    self.pos = self.pos + 1
  }
  if self.pos < self.len {
    self.pos = self.pos + 1
  } else {
    self.note(EofInDoctype, @span.Span::new(start, self.pos))
  }
  self.tok(start, Doctype(name, public_id, system_id))
}

///|
fn Scanner::doctype_quoted(self : Scanner) -> String? {
  while self.pos < self.len && is_ws(self.peek()) {
    self.pos = self.pos + 1
  }
  let quote = self.peek()
  if quote != '"' && quote != '\'' {
    return None
  }
  self.pos = self.pos + 1
  let start = self.pos
  while self.pos < self.len && self.peek() != quote && self.peek() != '>' {
    self.pos = self.pos + 1
  }
  let body = self.slice(start, self.pos)
  if self.pos < self.len && self.peek() == quote {
    self.pos = self.pos + 1
  }
  Some(body)
}

// -------------------------------------------------------- character refs

///|
/// A character reference at the cursor, or `None` if the `&` is literal.
///
/// `in_text` is the one place the two contexts differ, and the difference is
/// real: `&notit;` is `¬it;` in character data and stays literal in an
/// attribute value, because resolving it there would rewrite every query
/// string that happens to contain `&not`. The specification's rule is stated in
/// terms of what follows the match; this states it in terms of where we are,
/// which is the same rule and easier to check.
fn Scanner::reference(self : Scanner, in_text : Bool) -> String? {
  let start = self.pos
  if self.at(start + 1) == '#' {
    return self.numeric_reference()
  }
  // Longest match wins: `&notin;` is one reference and `&not` followed by
  // `in;` is another, and only the length says which.
  let limit = @names.longest_reference
  let mut len = limit
  if start + 1 + len > self.len {
    len = self.len - start - 1
  }
  while len > 0 {
    let candidate = self.slice(start + 1, start + 1 + len)
    match @names.named_reference(candidate) {
      Some(value) => {
        let has_semi = candidate.has_suffix(";")
        if !has_semi {
          if !in_text {
            // In an attribute value a reference without `;` followed by an
            // alphanumeric or `=` is not a reference at all.
            let after = self.at(start + 1 + len)
            if after == '=' || is_digit(after) || is_alpha(after) {
              return None
            }
          }
          self.note(
            MissingSemicolonAfterCharacterReference,
            @span.Span::new(start, start + 1 + len),
          )
        }
        self.pos = start + 1 + len
        return Some(value)
      }
      None => len = len - 1
    }
  }
  None
}

///|
fn Scanner::numeric_reference(self : Scanner) -> String? {
  let start = self.pos
  let hex = lower(self.at(start + 2)) == 'x'
  let digits_start = if hex { start + 3 } else { start + 2 }
  let mut i = digits_start
  while i < self.len &&
        (if hex { is_hex(self.at(i)) } else { is_digit(self.at(i)) }) {
    i = i + 1
  }
  if i == digits_start {
    self.note(
      AbsenceOfDigitsInNumericCharacterReference,
      @span.Span::new(start, i),
    )
    return None
  }
  let mut value = 0
  let mut k = digits_start
  while k < i {
    let c = self.at(k)
    let d = if is_digit(c) { c.to_int() - 48 } else { lower(c).to_int() - 87 }
    // Saturate rather than overflow: `&#99999999999;` is out of range either
    // way, and an Int that wrapped could land back on a valid code point.
    if value <= 0x110000 {
      value = value * (if hex { 16 } else { 10 }) + d
    }
    k = k + 1
  }
  self.pos = i
  if self.pos < self.len && self.peek() == ';' {
    self.pos = self.pos + 1
  } else {
    self.note(
      MissingSemicolonAfterCharacterReference,
      @span.Span::new(start, self.pos),
    )
  }
  Some(scalar_of(value, self, @span.Span::new(start, self.pos)))
}

///|
/// A numeric reference's value, as a character.
///
/// Three corrections, all the specification's and all load-bearing on real
/// pages: NUL and out-of-range values become U+FFFD, surrogates are not
/// characters, and the C1 range is remapped through Windows-1252 -- which is
/// why `&#147;` is a curly quote on half the web and a control character
/// nowhere.
fn scalar_of(value : Int, s : Scanner, span : @span.Span) -> String {
  if value == 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF) {
    s.note(CharacterReferenceOutsideUnicodeRange, span)
    return REPLACEMENT.to_string()
  }
  if value >= 0x80 && value <= 0x9F {
    return windows_1252(value).to_string()
  }
  value.unsafe_to_char().to_string()
}

///|
fn windows_1252(value : Int) -> Char {
  match value {
    0x80 => '\u{20AC}'
    0x82 => '\u{201A}'
    0x83 => '\u{0192}'
    0x84 => '\u{201E}'
    0x85 => '\u{2026}'
    0x86 => '\u{2020}'
    0x87 => '\u{2021}'
    0x88 => '\u{02C6}'
    0x89 => '\u{2030}'
    0x8A => '\u{0160}'
    0x8B => '\u{2039}'
    0x8C => '\u{0152}'
    0x8E => '\u{017D}'
    0x91 => '\u{2018}'
    0x92 => '\u{2019}'
    0x93 => '\u{201C}'
    0x94 => '\u{201D}'
    0x95 => '\u{2022}'
    0x96 => '\u{2013}'
    0x97 => '\u{2014}'
    0x98 => '\u{02DC}'
    0x99 => '\u{2122}'
    0x9A => '\u{0161}'
    0x9B => '\u{203A}'
    0x9C => '\u{0153}'
    0x9E => '\u{017E}'
    0x9F => '\u{0178}'
    _ => value.unsafe_to_char()
  }
}
