///|
/// A `plain-identifier`: an alphabetic, `_` or emoji start, then any number of
/// those plus numerics.
///
/// Emoji are matched as SEQUENCES, longest first. `👨‍👩‍👦` is one identifier
/// character; stopping at the first `👨` would leave zero-width joiners loose,
/// and those are not identifier characters at all.
fn Scanner::scan_plain_identifier(self : Scanner, from : Int) -> Int? {
  let e = self.emoji_or(from, c => @unicode.is_alphabetic(c) || c == '_')
  if e == from {
    return None
  }
  let mut i = e
  while i < self.src.length() {
    let n = self.emoji_or(i, c => {
      @unicode.is_alphabetic(c) || @unicode.is_numeric(c) || c == '_'
    })
    if n == i {
      break
    }
    i = n
  }
  Some(i)
}

///|
/// One identifier character at `from`: an emoji sequence if one starts here,
/// otherwise a single character satisfying `pred`. Returns `from` if neither.
fn Scanner::emoji_or(self : Scanner, from : Int, pred : (Char) -> Bool) -> Int {
  let n = @unicode.emoji_sequence_at(self.src, from)
  if n > 0 {
    return from + n
  }
  match self.at(from) {
    Some(c) => if pred(c) { self.step(from) } else { from }
    None => from
  }
}

///|
/// An identifier, with the optional `#%` prefix for internal names.
fn Scanner::scan_identifier(self : Scanner, from : Int) -> Int? {
  if self.has(from, "#%") {
    match self.scan_plain_identifier(from + 2) {
      Some(e) => Some(e)
      None => None
    }
  } else {
    self.scan_plain_identifier(from)
  }
}

///|
/// The longest operator starting at `from`, or `None`.
///
/// Four rules, all of which exist to keep operators out of the way of something
/// else:
///
///   * `//` and `/*` may not appear inside one, or an operator would swallow a
///     comment.
///   * A multi-character operator may not end in `:`, or `x+:` would be
///     ambiguous with `x+` before a block. All-colon operators are the
///     exception, so `::` still works.
///   * A multi-character operator may not end in `/` — but a `/` NOT followed
///     by `/` or `*` is absorbed afterwards, so `+/` is an operator when what
///     comes next could not have started a comment.
///   * A bare `~`, `|` or `:` is not an operator; each is its own token.
fn Scanner::scan_operator(self : Scanner, from : Int) -> Int? {
  // `#` plus one of `' , : ; |` is a two-character operator of its own; `#` is
  // not an operator character, so nothing longer can be built from it.
  match self.at(from) {
    Some('#') =>
      match self.at(from + 1) {
        Some(c) if is_escopchar(c) =>
          return Some(self.absorb_slash(self.step(from + 1)))
        _ => return None
      }
    _ => ()
  }
  let mut end = from
  let mut all_colons = true
  while end < self.src.length() {
    let c = match self.at(end) {
      Some(c) => c
      None => break
    }
    if !is_opchar(c) {
      break
    }
    // Stop before a comment opener rather than trimming back to it later: the
    // run may not CONTAIN `//` or `/*` at all.
    if c == '/' {
      match self.at(end + 1) {
        Some('/') | Some('*') => break
        _ => ()
      }
    }
    if c != ':' {
      all_colons = false
    }
    end = self.step(end)
  }
  if end == from {
    return None
  }
  if all_colons {
    // `:` alone is the block operator; `::` and longer are operators.
    return if end - from == 1 { None } else { Some(end) }
  }
  // Trim a trailing `:` or `/`, repeatedly: `+::` is `+` then `::`.
  let mut e = end
  while e - from > 1 {
    match self.at(e - 1) {
      Some(':') | Some('/') => e = e - 1
      _ => break
    }
  }
  if e - from == 1 {
    let c = self.at(from).unwrap()
    if c == '~' || c == '|' || c == ':' {
      return None
    }
  }
  Some(self.absorb_slash(e))
}

///|
/// Take a following `/` into the operator when it cannot start a comment.
///
/// This is why `+/ 2` divides and `+// 2` is `+` and a comment.
fn Scanner::absorb_slash(self : Scanner, end : Int) -> Int {
  match self.at(end) {
    Some('/') =>
      match self.at(end + 1) {
        Some('/') | Some('*') => end
        _ => end + 1
      }
    _ => end
  }
}

///|
/// Whether a multi-character operator starts at `from`.
///
/// The lookahead behind the trailing-dot rule: `1.` is the number one when
/// nothing follows, and `1` then `.+` when `.+` is an operator.
fn Scanner::multi_char_operator_at(self : Scanner, from : Int) -> Bool {
  match self.scan_operator(from) {
    Some(e) => self.src.char_length(start_offset=from, end_offset=e) > 1
    None => false
  }
}
