///|
/// Where an `@` form is in its own little grammar.
///
/// The names are the reference's. `Initial` through `OpContinue` are the part
/// before the braces, where ordinary shrubbery tokens are read and the mode
/// only decides what may come next; `Open`, `Inside`, `Escape` and `Close` are
/// the braced text, where the scanner is reading characters rather than tokens.
pub(all) enum AtMode {
  /// After `@` with no immediate `{`: read a command term.
  Initial
  /// After the command, reading a parenthesised argument list.
  Args
  /// `@(«...»)`: splice as-is, and take no arguments even if `(` follows.
  NoArgs
  /// Inside an `a.b.c` chain, where no space is allowed between the parts.
  OpContinue
  /// The next characters are the opener and `{`.
  Open
  /// In the braced text.
  Inside
  /// In the braced text, and an escape starts here.
  Escape
  /// At the final `}`.
  Close
} derive(Eq)

///|
/// One `@` form being scanned.
priv struct AtFrame {
  mut mode : AtMode
  /// The characters before `{`: `""` for a plain `@{`, `"|<<"` for `@|<<{`.
  /// The closer is this reversed and flipped, so the text can carry a nested
  /// `@` form of its own without either being confused for the other.
  opener : String
  /// Whether the whole form is a `@//` comment.
  comment : Bool
  /// Bracket nesting while reading the command and arguments.
  openers : Array[String]
  /// Brace nesting inside the text.
  mut depth : Int
}

///|
/// `<` and `>`, `[` and `]`, `(` and `)` swap; everything else is its own
/// mirror. A closer is the opener reversed with each character flipped, so
/// `|<<{` closes with `}>>|`.
fn flip_bracket(c : Char) -> Char {
  match c {
    '<' => '>'
    '>' => '<'
    '[' => ']'
    ']' => '['
    '(' => ')'
    ')' => '('
    _ => c
  }
}

///|
fn opener_to_closer(opener : String) -> String {
  let buf = StringBuilder()
  let chars = []
  for c in opener {
    chars.push(c)
  }
  for i = chars.length() - 1; i >= 0; i = i - 1 {
    buf.write_char(flip_bracket(chars[i]))
  }
  buf.to_string()
}

///|
/// The opener prefix starting at `i`, if one does.
///
/// `{` alone gives `""`. A `|` followed by ASCII symbols or punctuation and
/// then `{` gives that prefix. Anything else gives nothing.
///
/// ASCII-only, deliberately: the prefix has to be typed twice, once as itself
/// and once mirrored, and restricting it keeps the mirroring total.
fn Scanner::peek_at_opener(self : Scanner, i : Int) -> String? {
  match self.at(i) {
    Some('{') => Some("")
    Some('|') => {
      let buf = StringBuilder()
      buf.write_char('|')
      let mut j = i + 1
      while j < self.src.length() {
        match self.at(j) {
          Some('{') => return Some(buf.to_string())
          Some(c) =>
            if c.to_int() < 128 &&
              (@unicode.is_symbolic(c) || @unicode.is_punctuation(c)) {
              buf.write_char(c)
              j = j + 1
            } else {
              return None
            }
          None => return None
        }
      }
      None
    }
    _ => None
  }
}

///|
/// Whether `opener` followed by `c` sits at `i`.
fn Scanner::peek_at_prefixed(
  self : Scanner,
  i : Int,
  opener : String,
  c : Char,
) -> Bool {
  if !self.has(i, opener) {
    return false
  }
  self.at(i + opener.length()) is Some(x) && x == c
}

///|
/// Whether the closer for `opener` sits at `i`.
fn Scanner::peek_at_closer(self : Scanner, i : Int, opener : String) -> Bool {
  if !(self.at(i) is Some('}')) {
    return false
  }
  self.has(i + 1, opener_to_closer(opener))
}

///|
fn Scanner::at_top(self : Scanner) -> AtFrame? {
  if self.at_stack.length() == 0 {
    None
  } else {
    Some(self.at_stack[self.at_stack.length() - 1])
  }
}

///|
/// `@` at the top of a term, or inside braced text after the escape prefix.
///
/// `@//` is a comment: a braced one when an opener follows, and otherwise a
/// line comment that also swallows the newline and the next line's indentation
/// — without that, commenting out a line of text would leave its line break
/// behind and change the text around it.
fn Scanner::scan_at(self : Scanner, start : @basic.Pos, from : Int) -> Token {
  if self.has(from, "@//") {
    match self.peek_at_opener(from + 3) {
      Some(opener) => {
        self.at_stack.push({
          mode: Open,
          opener,
          comment: true,
          openers: [],
          depth: 0,
        })
        return self.finish(start, from + 3, AtComment)
      }
      None =>
        return self.finish(
          start,
          self.scan_at_line_comment(from + 3),
          AtComment,
        )
    }
  }
  let opener = self.peek_at_opener(from + 1)
  self.at_stack.push({
    mode: if opener is Some(_) {
      Open
    } else {
      Initial
    },
    opener: opener.unwrap_or(""),
    comment: false,
    openers: [],
    depth: 0,
  })
  self.finish(start, from + 1, At)
}

///|
/// A `@//` line comment: to the end of the line, then the newline, then the
/// leading whitespace of the next line.
fn Scanner::scan_at_line_comment(self : Scanner, from : Int) -> Int {
  let mut i = from
  while i < self.src.length() {
    match self.at(i) {
      Some('\n') | Some('\r') => break
      _ => i = self.step(i)
    }
  }
  match self.at(i) {
    Some('\r') => i = if self.has(i, "\r\n") { i + 2 } else { i + 1 }
    Some('\n') => i = i + 1
    _ => return i
  }
  while i < self.src.length() {
    match self.at(i) {
      Some(' ') | Some('\t') => i = i + 1
      _ => break
    }
  }
  i
}

///|
/// Emit the opener token and enter the text.
fn Scanner::at_open(self : Scanner, frame : AtFrame) -> Token {
  let start = self.here()
  let end = self.idx + frame.opener.length() + 1
  frame.mode = Inside
  frame.depth = 0
  self.finish(start, end, AtOpener)
}

///|
/// Emit the closer token and leave the form.
///
/// A second opener may follow immediately — `@x{a}{b}` is one call with two
/// text arguments — so the frame is reused rather than popped when it does.
fn Scanner::at_close(self : Scanner, frame : AtFrame) -> Token {
  let start = self.here()
  let closer = opener_to_closer(frame.opener)
  let end = self.idx + 1 + closer.length()
  match self.peek_at_opener(end) {
    Some(next) if next == frame.opener || frame.opener == "" =>
      // Only a repeat of the same opener continues this form; a different one
      // would be a new form and is left for the next token.
      if next == frame.opener {
        frame.mode = Open
      } else {
        let _ = self.at_stack.pop()
      }
    _ => {
      let _ = self.at_stack.pop()
    }
  }
  self.finish(start, end, AtCloser, partner=Some("}" + closer))
}

///|
/// Emit the escape's `@` and start a nested form.
fn Scanner::at_escape(self : Scanner, frame : AtFrame) -> Token {
  let start = self.here()
  let from = self.idx + frame.opener.length()
  // Back to reading text once the nested form finishes.
  frame.mode = Inside
  if self.has(from, "@//") {
    match self.peek_at_opener(from + 3) {
      Some(opener) => {
        self.at_stack.push({
          mode: Open,
          opener,
          comment: true,
          openers: [],
          depth: 0,
        })
        return self.finish(start, from + 3, AtComment)
      }
      None =>
        return self.finish(start, self.scan_at_line_comment(from + 3), Comment)
    }
  }
  let opener = self.peek_at_opener(from + 1)
  self.at_stack.push({
    mode: if opener is Some(_) {
      Open
    } else {
      Initial
    },
    opener: opener.unwrap_or(""),
    comment: frame.comment,
    openers: [],
    depth: 0,
  })
  self.finish(start, from + 1, At)
}

///|
/// Read braced text up to the next thing that is not text.
///
/// The content is broken at every newline, at every escape and at the closer,
/// which is what lets the parser rebuild lines and strip their shared
/// indentation later. A newline becomes a content token of its own.
///
/// Nested `{` and `}` inside the text are literal and only track depth, so a
/// balanced brace in prose does not end the form.
fn Scanner::at_inside(self : Scanner, frame : AtFrame) -> Token {
  let start = self.here()
  let opener = frame.opener
  let mut i = self.idx
  while i < self.src.length() {
    match self.at(i) {
      Some('\n') | Some('\r') =>
        // A newline alone is its own token; text before it ends here.
        if i == self.idx {
          let e = if self.has(i, "\r\n") { i + 2 } else { i + 1 }
          return self.finish(start, e, AtContent)
        } else {
          return self.finish(start, i, AtContent)
        }
      _ =>
        if self.peek_at_closer(i, opener) {
          if frame.depth == 0 {
            frame.mode = Close
            return self.finish(start, i, AtContent)
          }
          frame.depth = frame.depth - 1
          i = i + 1 + opener_to_closer(opener).length()
        } else if self.peek_at_prefixed(i, opener, '@') {
          frame.mode = Escape
          return self.finish(start, i, AtContent)
        } else if self.peek_at_prefixed(i, opener, '{') {
          frame.depth = frame.depth + 1
          i = i + opener.length() + 1
        } else {
          i = self.step(i)
        }
    }
  }
  // End of input inside the text: hand back what there is and let the parser
  // report the missing closer, which it can do with a span.
  frame.mode = Close
  self.finish(start, i, AtContent)
}

///|
/// Update the command-and-arguments state after one ordinary token.
///
/// This is the half of the `@` grammar that reads shrubbery rather than text:
/// `@f(x)[y]{z}` is one form, and what decides that is whether each bracket
/// closed and whether the very next character continues it. A space anywhere
/// ends the form, which is why every test here is on the immediately following
/// character.
fn Scanner::after_at_token(self : Scanner, frame : AtFrame, t : Token) -> Token {
  let mut token = t
  match t.kind {
    Opener | SExp(_) => {
      if frame.mode is Initial &&
        frame.openers.length() == 1 &&
        frame.openers[0] == "(" &&
        t.text == "\u{AB}" {
        // `@(«...»)` splices its command and takes no arguments.
        frame.mode = NoArgs
      }
      frame.openers.push(if t.kind is SExp(_) { "{" } else { t.text })
    }
    Closer =>
      if frame.openers.length() > 0 &&
        closes(frame.openers[frame.openers.length() - 1], t.text) {
        let _ = frame.openers.pop()
      } else {
        token = { ..t, kind: Fail(InvalidAfterAt), }
      }
    _ => ()
  }
  if frame.openers.length() > 0 {
    return token
  }
  // At a term boundary: decide whether the form continues, and how.
  match self.peek_at_opener(self.idx) {
    Some(op) if !(frame.mode is NoArgs) => {
      let f = self.at_stack[self.at_stack.length() - 1]
      self.at_stack[self.at_stack.length() - 1] = {
        ..f,
        opener: op,
        mode: Open,
      }
      return token
    }
    _ => ()
  }
  if frame.mode is Initial &&
    t.kind is Identifier &&
    self.peek_operator_then_identifier(self.idx) {
    frame.mode = OpContinue
    return token
  }
  if frame.mode is OpContinue {
    frame.mode = Initial
    return token
  }
  if !(frame.mode is Args) && !(frame.mode is NoArgs) {
    match self.at(self.idx) {
      // `[` is taken as an argument list for consistency with S-expression `@`,
      // and rejected by the parser with a message about it. Refusing it here
      // instead would report a stray bracket rather than the mistake.
      Some('(') | Some('[') => {
        frame.mode = Args
        frame.openers.clear()
        return token
      }
      _ => ()
    }
  }
  let _ = self.at_stack.pop()
  token
}

///|
/// Whether an operator and then an identifier follow, with no space between.
///
/// This is what makes `@a.b.c` one command rather than `@a` followed by text.
fn Scanner::peek_operator_then_identifier(self : Scanner, i : Int) -> Bool {
  match self.scan_operator(i) {
    Some(e) => self.scan_identifier(e) is Some(_)
    None => false
  }
}

///|
fn closes(opener : String, closer : String) -> Bool {
  match opener {
    "(" => closer == ")"
    "[" => closer == "]"
    "{" => closer == "}"
    "\u{AB}" => closer == "\u{BB}"
    "'" => closer == "'"
    _ => false
  }
}
