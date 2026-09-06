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
  /// The raw-text run the next call has to scan, if the tag just emitted opened
  /// one. This is the specification's "appropriate end tag token" check, and it
  /// is the only piece of state the tokenizer needs from the document it is
  /// tokenizing.
  mut pending : Start
  problems : Array[(@kind.ErrorKind, @span.Span)]
}

///|
/// Tokenize a whole document, ending with exactly one `Eof`.
pub fn tokenize(src : String, start? : Start = Markup) -> Scanned {
  let s = { src, len: src.length(), pos: 0, pending: start, problems: [], }
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
pub fn tokens(src : String, start? : Start = Markup) -> Array[Token] {
  tokenize(src, start~).tokens
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
/// The specification's input preprocessing, applied per run rather than to the
/// whole source: a CRLF pair and a lone CR both become a single LF.
///
/// Per run because doing it to the input up front would shift every offset
/// after every CRLF, and a diagnostic that points one character to the left of
/// the problem is worse than no diagnostic. The DECODED text is normalised and
/// the source spelling is kept in `raw`, which is the same bargain a character
/// reference already makes.
fn normalize_newlines(s : String) -> String {
  if !s.contains("\r") {
    return s
  }
  let buf = StringBuilder()
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.unsafe_get(i).to_int().unsafe_to_char()
    if c == '\r' {
      buf.write_char('\n')
      i = i + 1
      if i < n && s.unsafe_get(i).to_int() == 10 {
        i = i + 1
      }
      continue
    }
    buf.write_char(c)
    i = i + 1
  }
  buf.to_string()
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
/// A character that may appear in a tag name.
///
/// Almost anything: the specification's tag-name state sends `"`, `'`, `<` and
/// `=` to its "anything else" branch, which appends them. So `<a<b>` is one tag
/// whose name is `a<b`, and a scanner that stopped at the `<` would drop a
/// character the document has -- which is invisible until a conforming parser
/// is asked what it read.
///
/// `:` and everything above U+007F are in for the same reason, so that
/// `xlink:href` and a custom element with an accented name arrive as one name.
/// The parser splits the prefix off; the scanner has no reason to.
fn is_tag_name_char(c : Char) -> Bool {
  !is_ws(c) && c != '/' && c != '>'
}

///|
/// A character that may appear in an attribute name.
///
/// The same set less `=`, which is the one character that ends a name rather
/// than joining it. `"`, `'` and `<` are a parse error inside a name and are
/// still part of it -- `<div a<b>` has one attribute called `a<b`.
fn is_attr_name_char(c : Char) -> Bool {
  is_tag_name_char(c) && c != '='
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
  match self.pending {
    Markup => ()
    Raw(tag) => {
      self.pending = Markup
      return self.raw_text_body(tag)
    }
    Escapable(tag) => {
      self.pending = Markup
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
  let mut normalised = false
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
      // The data state EMITS a NUL, it does not replace it. Every other state
      // replaces it with U+FFFD, which is the sort of asymmetry only a
      // conformance suite finds.
      self.note(
        UnexpectedNullCharacter,
        @span.Span::new(self.pos, self.pos + 1),
      )
    }
    if self.newline_at(buf) {
      normalised = true
      continue
    }
    buf.write_char(c)
    self.pos = self.pos + 1
  }
  let raw = if decoded || normalised {
    Some(self.slice(start, self.pos))
  } else {
    None
  }
  self.tok(start, Text(buf.to_string(), raw))
}

///|
/// A CR at the cursor, written as the LF the specification preprocesses it to.
///
/// Inline in the scan rather than over the finished buffer, because a resolved
/// character reference must NOT be normalised: preprocessing happens to the
/// input stream and `&#13;` is resolved after it, so `&#013;` really is a
/// carriage return and a literal one really is not.
fn Scanner::newline_at(self : Scanner, buf : StringBuilder) -> Bool {
  if self.peek() != '\r' {
    return false
  }
  buf.write_char('\n')
  self.pos = self.pos + 1
  if self.pos < self.len && self.peek() == '\n' {
    self.pos = self.pos + 1
  }
  true
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
    if self.pos + 2 >= self.len {
      // `</` at end of input: the specification emits both characters.
      self.pos = self.len
      return self.tok(start, Text("</", None))
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
  while self.pos < self.len && is_tag_name_char(self.peek()) {
    self.pos = self.pos + 1
  }
  // NUL is a name character too, replaced with U+FFFD: `<a\u{0}>` is a tag
  // called `a\u{FFFD}`, not a tag called `a`.
  let name = self.nul_free(name_start, self.pos).to_lower()
  let attrs : Array[RawAttr] = []
  let mut self_closing = false
  while true {
    while self.pos < self.len && is_ws(self.peek()) {
      self.pos = self.pos + 1
    }
    if self.pos >= self.len {
      // A tag that never closed is not a tag. The specification discards it,
      // and so does this -- as a `Bogus` carrying the source it covered, so
      // that the printer echoes exactly what was there instead of inventing a
      // `>` the input did not have.
      self.note(EofInTag, @span.Span::new(start, self.pos))
      return self.tok(start, Bogus(EofInTag, self.slice(start, self.pos)))
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
    if c == '=' {
      // `<div =x>` is an attribute NAMED `=x`, per the specification: the `=`
      // is taken into the name rather than skipped. Skipping it silently
      // renames the attribute, which is the kind of difference only a
      // conforming parser notices.
      self.note(
        UnexpectedEqualsSignBeforeAttributeName,
        @span.Span::new(self.pos, self.pos + 1),
      )
      match self.attribute(lead_equals=true) {
        Some(a) => attrs.push(a)
        None => self.pos = self.pos + 1
      }
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
  if !self_closing {
    if @names.is_raw_text(name) {
      self.pending = Raw(name)
    } else if @names.is_escapable_raw_text(name) {
      self.pending = Escapable(name)
    }
  }
  self.tok(start, StartTag(name, attrs, self_closing))
}

///|
fn Scanner::end_tag(self : Scanner) -> Token {
  let start = self.pos
  self.pos = self.pos + 2
  let name_start = self.pos
  while self.pos < self.len && is_tag_name_char(self.peek()) {
    self.pos = self.pos + 1
  }
  let name = self.nul_free(name_start, self.pos).to_lower()
  // Attributes on an end tag are a parse error and are dropped, which is what
  // the specification says and what makes `</div class="x">` harmless.
  while self.pos < self.len && self.peek() != '>' {
    self.pos = self.pos + 1
  }
  if self.pos < self.len {
    self.pos = self.pos + 1
  } else {
    self.note(EofInTag, @span.Span::new(start, self.pos))
    return self.tok(start, Bogus(EofInTag, self.slice(start, self.pos)))
  }
  self.tok(start, EndTag(name))
}

///|
fn Scanner::attribute(self : Scanner, lead_equals? : Bool = false) -> RawAttr? {
  let start = self.pos
  if lead_equals {
    self.pos = self.pos + 1
  }
  while self.pos < self.len && is_attr_name_char(self.peek()) {
    self.pos = self.pos + 1
  }
  if self.pos == start {
    return None
  }
  let name = self.nul_free(start, self.pos).to_lower()
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
  let mut normalised = false
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
    if self.newline_at(buf) {
      normalised = true
      continue
    }
    buf.write_char(c)
    self.pos = self.pos + 1
  }
  let raw = if decoded || normalised {
    Some(self.slice(start, self.pos))
  } else {
    None
  }
  if quoted && self.pos < self.len {
    self.pos = self.pos + 1
  }
  (buf.to_string(), raw)
}

// -------------------------------------------------------------- raw bodies

///|
/// How deep inside a comment a `<script>` body is.
///
/// The specification gives script data five states, and the reason is one
/// construct: `<script><!-- <script> ... </script> --></script>`. Inside the
/// inner `<script>` the FIRST `</script>` does not end the element. A scanner
/// that stopped at it cuts the script in half, which no browser does -- and a
/// formatter that then rewrote the file would be handing back something that
/// does not run.
priv enum ScriptMode {
  /// Ordinary script data: the next `</script>` ends the element.
  Plain
  /// After a `<!--`: still ends at `</script>`, but a `<script` opens a level.
  Escaped
  /// After a nested `<script`: `</script>` closes the level, not the element.
  Double
} derive(Eq)

///|
/// A `<script>` body, with the escaped and double-escaped states.
fn Scanner::script_body(self : Scanner) -> Unit {
  let mut mode = ScriptMode::Plain
  while self.pos < self.len {
    if mode != Double && self.is_end_tag_at(self.pos, "script") {
      return
    }
    if mode == Plain && self.matches_ci(self.pos, "<!--") {
      mode = Escaped
      self.pos = self.pos + 4
      continue
    }
    if mode != Plain && self.matches_ci(self.pos, "-->") {
      mode = Plain
      self.pos = self.pos + 3
      continue
    }
    if mode == Escaped && self.opens_nested_script(self.pos) {
      mode = Double
      self.pos = self.pos + 7
      continue
    }
    if mode == Double && self.is_end_tag_at(self.pos, "script") {
      mode = Escaped
      self.pos = self.pos + 8
      continue
    }
    self.pos = self.pos + 1
  }
}

///|
/// `<script` followed by something that could end a tag.
fn Scanner::opens_nested_script(self : Scanner, i : Int) -> Bool {
  if !self.matches_ci(i, "<script") {
    return false
  }
  let c = self.at(i + 7)
  is_ws(c) || c == '/' || c == '>'
}

///|
/// Whether an end tag for `tag` actually begins here.
///
/// `</xmp` is only an end tag if what follows it could END one -- whitespace,
/// `/` or `>`. `foo</xmp<` is character data all the way through, and `foo</xmp`
/// at end of input is too. Stopping at the name alone loses the rest of the run,
/// which is invisible until something asks a conforming parser.
fn Scanner::is_end_tag_at(self : Scanner, i : Int, tag : String) -> Bool {
  if !self.matches_ci(i, "</" + tag) {
    return false
  }
  let after = i + 2 + tag.length()
  if after >= self.len {
    return false
  }
  let c = self.at(after)
  is_ws(c) || c == '/' || c == '>'
}

///|
/// Everything up to `</tag`, verbatim.
///
/// ASCII-case-insensitively, and inside a JavaScript string literal just the
/// same -- there is no escape, which is why the printer has to refuse a body
/// that contains one rather than trying to write it back.
fn Scanner::raw_text_body(self : Scanner, tag : String) -> Token {
  let start = self.pos
  if tag == "script" {
    self.script_body()
  } else {
    while self.pos < self.len && !self.is_end_tag_at(self.pos, tag) {
      self.pos = self.pos + 1
    }
  }
  if self.pos >= self.len {
    self.note(EofInRawText(tag), @span.Span::new(start, self.pos))
  }
  self.tok(start, RawText(normalize_newlines(self.slice(start, self.pos))))
}

///|
/// Everything up to `</tag`, with character references resolved.
fn Scanner::escapable_body(self : Scanner, tag : String) -> Token {
  let start = self.pos
  let buf = StringBuilder()
  let mut decoded = false
  let mut normalised = false
  while self.pos < self.len && !self.is_end_tag_at(self.pos, tag) {
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
    if self.newline_at(buf) {
      normalised = true
      continue
    }
    buf.write_char(self.peek())
    self.pos = self.pos + 1
  }
  if self.pos >= self.len {
    self.note(EofInRawText(tag), @span.Span::new(start, self.pos))
  }
  let raw = if decoded || normalised {
    Some(self.slice(start, self.pos))
  } else {
    None
  }
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
      let body = self.comment_body(body_start, self.pos)
      self.pos = self.pos + 4
      self.note(IncorrectlyClosedComment, @span.Span::new(start, self.pos))
      return self.tok(start, Comment(body))
    }
    if self.matches_ci(self.pos, "<!--") && self.pos > body_start {
      self.note(NestedComment, @span.Span::new(self.pos, self.pos + 4))
    }
    self.pos = self.pos + 1
  }
  let mut body = self.comment_body(body_start, self.pos)
  if self.pos >= self.len {
    // The dashes that took the machine into comment-end-dash and comment-end
    // are held back by those states, and at end of input they are never
    // appended: `<!----` is a comment whose data is empty, not `--`. At most
    // two, because a third would have fallen through and been appended.
    if body.has_suffix("--!") {
      // comment-end-bang holds `--!` back the same way comment-end holds `--`.
      body = body.clamped_view(end=body.length() - 3).to_owned()
    } else {
      let mut drop = 0
      while drop < 2 && body.has_suffix("-") {
        body = body.clamped_view(end=body.length() - 1).to_owned()
        drop = drop + 1
      }
    }
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
  let body = self.comment_body(body_start, self.pos)
  if self.pos < self.len {
    self.pos = self.pos + 1
  }
  self.note(BogusComment, @span.Span::new(start, self.pos))
  self.tok(start, Comment(body))
}

///|
/// A comment's data: newlines normalised and NUL replaced, which every state
/// but the data state does.
fn Scanner::comment_body(self : Scanner, from : Int, to : Int) -> String {
  let raw = normalize_newlines(self.slice(from, to))
  if !raw.contains("\u{0}") {
    return raw
  }
  self.note(UnexpectedNullCharacter, @span.Span::new(from, to))
  raw.replace_all(old="\u{0}", new=REPLACEMENT.to_string())
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
/// A doctype, and whether it forces quirks mode.
///
/// Written as the specification's states in sequence rather than as a loop over
/// the parts, because the force-quirks flag is set by the STATE a problem is met
/// in and not by the problem. Junk after a complete system identifier is
/// harmless -- `<!DOCTYPE a SYSTEM ''!` is a correct doctype with a parse error
/// -- while the same junk one state earlier forces quirks, and end of input
/// forces it everywhere except in the bogus state. A loop cannot tell those
/// apart, which is seventy-four cases of the html5lib suite.
fn Scanner::doctype(self : Scanner) -> Token {
  let start = self.pos
  self.pos = self.pos + 9
  let d = { start, name: "", public_id: None, system_id: None, quirks: false, }
  self.skip_ws()
  if self.pos >= self.len {
    return self.doctype_eof(d)
  }
  if self.peek() == '>' {
    // A doctype with no name at all.
    self.pos = self.pos + 1
    d.quirks = true
    return self.doctype_token(d)
  }
  let name_start = self.pos
  while self.pos < self.len && !is_ws(self.peek()) && self.peek() != '>' {
    self.pos = self.pos + 1
  }
  d.name = self.nul_free(name_start, self.pos).to_lower()
  self.skip_ws()
  if self.pos >= self.len {
    return self.doctype_eof(d)
  }
  if self.peek() == '>' {
    self.pos = self.pos + 1
    return self.doctype_token(d)
  }
  if self.matches_ci(self.pos, "public") {
    self.pos = self.pos + 6
    return self.doctype_public(d)
  }
  if self.matches_ci(self.pos, "system") {
    self.pos = self.pos + 6
    return self.doctype_system(d)
  }
  // Anything else after the name is an invalid sequence, and that one DOES
  // force quirks before falling into the bogus state.
  self.note(MalformedDoctype, @span.Span::new(self.pos, self.pos + 1))
  d.quirks = true
  self.skip_bogus_doctype()
  self.doctype_token(d)
}

///|
/// After the `PUBLIC` keyword.
fn Scanner::doctype_public(self : Scanner, d : Doctype) -> Token {
  self.skip_ws()
  if self.pos >= self.len {
    return self.doctype_eof(d)
  }
  if self.peek() == '>' {
    self.pos = self.pos + 1
    d.quirks = true
    return self.doctype_token(d)
  }
  if !self.at_quote() {
    self.note(MalformedDoctype, @span.Span::new(self.pos, self.pos + 1))
    d.quirks = true
    self.skip_bogus_doctype()
    return self.doctype_token(d)
  }
  let (public_id, done) = self.doctype_quoted(d)
  d.public_id = Some(public_id)
  if done {
    return self.doctype_token(d)
  }
  // A system identifier may follow, with or without whitespace between them.
  self.skip_ws()
  if self.pos >= self.len {
    return self.doctype_eof(d)
  }
  if self.peek() == '>' {
    self.pos = self.pos + 1
    return self.doctype_token(d)
  }
  if !self.at_quote() {
    self.note(MalformedDoctype, @span.Span::new(self.pos, self.pos + 1))
    d.quirks = true
    self.skip_bogus_doctype()
    return self.doctype_token(d)
  }
  let (system_id, done) = self.doctype_quoted(d)
  d.system_id = Some(system_id)
  if done {
    return self.doctype_token(d)
  }
  self.doctype_after_system(d)
}

///|
/// After the `SYSTEM` keyword.
fn Scanner::doctype_system(self : Scanner, d : Doctype) -> Token {
  self.skip_ws()
  if self.pos >= self.len {
    return self.doctype_eof(d)
  }
  if self.peek() == '>' {
    self.pos = self.pos + 1
    d.quirks = true
    return self.doctype_token(d)
  }
  if !self.at_quote() {
    self.note(MalformedDoctype, @span.Span::new(self.pos, self.pos + 1))
    d.quirks = true
    self.skip_bogus_doctype()
    return self.doctype_token(d)
  }
  let (system_id, done) = self.doctype_quoted(d)
  d.system_id = Some(system_id)
  if done {
    return self.doctype_token(d)
  }
  self.doctype_after_system(d)
}

///|
/// After a complete system identifier.
///
/// The one place where junk is harmless: it is a parse error and the doctype is
/// still correct. End of input here is not harmless, and end of input in the
/// bogus state that follows the junk is harmless again.
fn Scanner::doctype_after_system(self : Scanner, d : Doctype) -> Token {
  self.skip_ws()
  if self.pos >= self.len {
    return self.doctype_eof(d)
  }
  if self.peek() == '>' {
    self.pos = self.pos + 1
    return self.doctype_token(d)
  }
  self.note(MalformedDoctype, @span.Span::new(self.pos, self.pos + 1))
  self.skip_bogus_doctype()
  self.doctype_token(d)
}

///|
/// A quoted identifier, and whether the doctype ends here.
///
/// It ends here when the identifier was terminated by a `>` or by end of input
/// rather than by its own quote; both force quirks. The caller assigns the body
/// to the right field before returning, because only the caller knows which
/// keyword it came from -- guessing from which field is still empty gets
/// `<!DOCTYPE a SYSTEM"` wrong, and does so silently.
fn Scanner::doctype_quoted(self : Scanner, d : Doctype) -> (String, Bool) {
  let quote = self.peek()
  self.pos = self.pos + 1
  let start = self.pos
  while self.pos < self.len && self.peek() != quote && self.peek() != '>' {
    self.pos = self.pos + 1
  }
  let body = normalize_newlines(self.nul_free(start, self.pos))
  if self.pos >= self.len {
    d.quirks = true
    self.note(EofInDoctype, @span.Span::new(d.start, self.pos))
    return (body, true)
  }
  if self.peek() == '>' {
    self.pos = self.pos + 1
    d.quirks = true
    self.note(MalformedDoctype, @span.Span::new(d.start, self.pos))
    return (body, true)
  }
  self.pos = self.pos + 1
  (body, false)
}

///|
fn Scanner::doctype_eof(self : Scanner, d : Doctype) -> Token {
  self.note(EofInDoctype, @span.Span::new(d.start, self.pos))
  d.quirks = true
  self.doctype_token(d)
}

///|
/// The bogus doctype state: everything up to the next `>`, and end of input
/// here does NOT force quirks.
fn Scanner::skip_bogus_doctype(self : Scanner) -> Unit {
  while self.pos < self.len && self.peek() != '>' {
    self.pos = self.pos + 1
  }
  if self.pos < self.len {
    self.pos = self.pos + 1
  }
}

///|
fn Scanner::doctype_token(self : Scanner, d : Doctype) -> Token {
  self.tok(d.start, Doctype(d.name, d.public_id, d.system_id, d.quirks))
}

///|
fn Scanner::at_quote(self : Scanner) -> Bool {
  self.peek() == '"' || self.peek() == '\''
}

///|
fn Scanner::skip_ws(self : Scanner) -> Unit {
  while self.pos < self.len && is_ws(self.peek()) {
    self.pos = self.pos + 1
  }
}

///|
/// A slice with NUL replaced, which every state but the data state does.
fn Scanner::nul_free(self : Scanner, from : Int, to : Int) -> String {
  let raw = self.slice(from, to)
  if !raw.contains("\u{0}") {
    return raw
  }
  self.note(UnexpectedNullCharacter, @span.Span::new(from, to))
  raw.replace_all(old="\u{0}", new=REPLACEMENT.to_string())
}

///|
/// A doctype under construction.
priv struct Doctype {
  start : Int
  mut name : String
  mut public_id : String?
  mut system_id : String?
  mut quirks : Bool
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
