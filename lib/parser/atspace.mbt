///|
/// One piece of a text body, while whitespace is being adjusted.
priv struct TextPiece {
  /// The text the piece DENOTES, after trimming.
  mut text : String
  /// The source text it ACCOUNTS FOR, which trimming does not touch.
  ///
  /// These come apart on every line of an indented `@` body: the datum is the
  /// line without its shared indentation, and the raw is the line as written.
  /// Keeping only one of them would either change what the text says or make
  /// the source unreconstructable.
  raw : @raw.Raw
  /// The port column where this piece starts, which is what makes the shared
  /// indentation of the FIRST line -- the one that shares a line with the
  /// opener -- comparable to the rest.
  col0 : Int
  span : @basic.Span
}

///|
priv enum Piece {
  PText(TextPiece)
  PComment(@raw.Raw)
  PGroup(@ast.Node)
}

///|
fn Piece::is_newline(self : Piece) -> Bool {
  match self {
    PText(p) => p.text == "\n"
    _ => false
  }
}

///|
fn Piece::is_blank_text(self : Piece) -> Bool {
  match self {
    PText(p) => {
      if p.text == "\n" {
        return false
      }
      for c in p.text {
        if !(c == ' ' || c == '\t' || c == '\u{B}' || c == '\u{C}' || c == '\r') {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// Turn the raw pieces of a `{...}` body into the content of a bracketed
/// sequence, and the raw text that falls off either end.
///
/// The eight steps of the specification, in order. What they add up to: a text
/// body reads the way it is written, so that
///
///     @a{
///       one
///       two
///     }
///
/// is the two lines and not the newlines and indentation around them, and
/// de-indenting the whole block does not change what it says.
fn adjust_content_space(
  content : Array[ContentPiece],
) -> (@raw.Raw, Array[@ast.Node], @raw.Raw) {
  let pieces : Array[Piece] = content.map(c => {
    match c {
      CText(t) =>
        PText({
          text: t.text,
          raw: Str(t.raw_text()),
          col0: t.span.start.col0,
          span: t.span,
        })
      CComment(r) => PComment(r)
      CGroup(n) => PGroup(n)
    }
  })
  // 2. Trailing whitespace on each line goes, except on the opener's line
  //    before non-whitespace and the closer's line after it.
  remove_trailing_spaces(pieces)
  // 3-4. The space and newline immediately inside each end go.
  let end2 = discard_immediate_space(pieces, from_end=true)
  let end1 = discard_immediate_newline(pieces, from_end=true)
  let start1 = discard_immediate_space(pieces, from_end=false)
  let start2 = discard_immediate_newline(pieces, from_end=false)
  // 7. Indentation shared by every non-empty line goes.
  let min_col = get_min_column(pieces)
  let trimmed = trim_shared_column(pieces, min_col, start2 is Some(_))
  // 8. Comments attach to the piece that follows them.
  let (nodes, trailing) = convert_content(trimmed)
  let prefix = raw_of(start1).combine(raw_of(start2))
  let suffix = trailing.combine(raw_of(end1)).combine(raw_of(end2))
  (prefix, nodes, suffix)
}

///|
fn raw_of(p : Piece?) -> @raw.Raw {
  match p {
    Some(PText(t)) => t.raw
    Some(PComment(r)) => r
    _ => Empty
  }
}

///|
/// Strip trailing whitespace from the text piece before each newline.
fn remove_trailing_spaces(pieces : Array[Piece]) -> Unit {
  for i in 0..<pieces.length() {
    if !pieces[i].is_newline() {
      continue
    }
    if i == 0 {
      continue
    }
    match pieces[i - 1] {
      PText(p) =>
        if p.text != "\n" {
          let mut end = p.text.length()
          while end > 0 {
            let c = p.text.get_char(end - 1)
            match c {
              Some(ch) if is_text_space(ch) => end = end - 1
              _ => break
            }
          }
          if end < p.text.length() {
            // Only the datum is trimmed; the raw still accounts for the
            // whitespace that was written.
            p.text = p.text.clamped_view(end~).to_owned()
          }
        }
      _ => ()
    }
  }
}

///|
fn is_text_space(c : Char) -> Bool {
  c == ' ' ||
  c == '\t' ||
  c == '\n' ||
  c == '\r' ||
  c == '\u{B}' ||
  c == '\u{C}'
}

///|
/// Drop a whitespace-only piece at one end when a newline is next to it.
fn discard_immediate_space(pieces : Array[Piece], from_end~ : Bool) -> Piece? {
  if pieces.length() < 2 {
    return None
  }
  let at = if from_end { pieces.length() - 1 } else { 0 }
  let neighbour = if from_end { at - 1 } else { at + 1 }
  if pieces[at].is_blank_text() && pieces[neighbour].is_newline() {
    let p = pieces[at]
    let _ = pieces.remove(at)
    Some(p)
  } else {
    None
  }
}

///|
/// Drop a newline at one end, unless it is all that is left.
fn discard_immediate_newline(pieces : Array[Piece], from_end~ : Bool) -> Piece? {
  if pieces.length() < 2 {
    return None
  }
  let at = if from_end { pieces.length() - 1 } else { 0 }
  if pieces[at].is_newline() {
    let p = pieces[at]
    let _ = pieces.remove(at)
    Some(p)
  } else {
    None
  }
}

///|
/// The least indentation of any non-empty line.
///
/// A line's indentation is its leading whitespace PLUS the port column it
/// starts at, so that the first line -- which starts wherever the opener left
/// off -- is measured on the same scale as the rest. A line holding anything
/// other than text starts at its own column and contributes that.
fn get_min_column(pieces : Array[Piece]) -> Int? {
  let mut min_col : Int? = None
  let mut saw_nl = true
  for p in pieces {
    if p.is_newline() {
      saw_nl = true
      continue
    }
    match p {
      PText(t) if saw_nl => {
        if t.text == "" {
          // Stripping trailing whitespace made the line blank.
          continue
        }
        let n = leading_space_count(t.text) + t.col0
        min_col = Some(
          match min_col {
            Some(m) => if n < m { n } else { m }
            None => n
          },
        )
        saw_nl = false
      }
      _ =>
        if saw_nl {
          min_col = Some(min_col.unwrap_or(0))
          saw_nl = false
        }
    }
  }
  min_col
}

///|
fn leading_space_count(s : String) -> Int {
  let mut i = 0
  while i < s.length() {
    match s.get_char(i) {
      Some(c) if is_text_space(c) => i = i + 1
      _ => break
    }
  }
  i
}

///|
/// Remove the shared indentation, splitting what is left of each line's
/// leading whitespace into a piece of its own.
fn trim_shared_column(
  pieces : Array[Piece],
  min_col : Int?,
  start_nl : Bool,
) -> Array[Piece] {
  let out : Array[Piece] = []
  let mut saw_nl = start_nl
  let min = min_col.unwrap_or(0)
  for p in pieces {
    if p.is_newline() {
      out.push(p)
      saw_nl = true
      continue
    }
    match p {
      PText(t) if saw_nl => {
        let n = leading_space_count(t.text)
        let add_back = if n - min > 0 { n - min } else { 0 }
        let rest = if n == 0 {
          t.text
        } else {
          t.text.clamped_view(start=n).to_owned()
        }
        let dropped = rest.length() == 0
        if add_back > 0 {
          out.push(
            PText({
              text: " ".repeat(add_back),
              // When the line had content, this whitespace is already part of
              // that content's raw and must not be counted twice; when the line
              // was nothing BUT indentation, this piece is all that is left to
              // carry it.
              raw: if dropped {
                t.raw
              } else {
                Empty
              },
              col0: t.col0,
              span: t.span,
            }),
          )
        } else if dropped {
          // A line that was nothing but shared indentation leaves its text
          // behind as a comment, so the source can still be rebuilt.
          out.push(PComment(t.raw))
        }
        if !dropped {
          out.push(
            PText({ text: rest, raw: t.raw, col0: t.col0 + n, span: t.span, }),
          )
        }
        saw_nl = false
      }
      PComment(_) => out.push(p)
      _ => {
        out.push(p)
        saw_nl = false
      }
    }
  }
  out
}

///|
/// Wrap each text run in a group, and hang comments off whatever follows them.
fn convert_content(pieces : Array[Piece]) -> (Array[@ast.Node], @raw.Raw) {
  let out : Array[@ast.Node] = []
  let mut pending : @raw.Raw = Empty
  for p in pieces {
    match p {
      PComment(r) => pending = pending.combine(r)
      PText(t) => {
        let leaf = @ast.Node::new(Lit(Str(t.text)), t.span)
        leaf.meta.raw = t.raw
        let node = @ast.Node::new(Group([leaf]), t.span)
        node.meta.prefix = pending
        pending = Empty
        out.push(node)
      }
      PGroup(n) => {
        n.meta.prefix = pending.combine(n.meta.prefix)
        pending = Empty
        out.push(n)
      }
    }
  }
  (out, pending)
}
