///|
/// The display width of a character, in terminal columns.
///
/// Three answers: 0 for a combining mark or a zero-width control, 2 for an East
/// Asian Wide or Fullwidth character and for the emoji blocks, 1 otherwise.
/// Without this, a caret under a line containing CJK or an emoji lands short by
/// one column for every wide character before it, which is precisely the case
/// where a reader most needs the caret to be right.
///
/// The table below is a compact approximation covering the blocks that occur in
/// practice. It is deliberately not the full `EastAsianWidth.txt`: this library
/// has no dependencies and will not carry a 500-line generated table for a
/// long tail nobody's source code contains. Replace it with a generated table
/// if a real input ever proves it wrong -- and add that input to the tests when
/// you do.
pub fn char_width(c : Char) -> Int {
  let u = c.to_int()
  if u < 0x0300 {
    // Fast path: everything below the first combining block is width 1, except
    // the C0 controls, which a renderer should have escaped before reaching us.
    return if u < 0x20 { 0 } else { 1 }
  }
  if is_zero_width(u) {
    0
  } else if is_wide(u) {
    2
  } else {
    1
  }
}

///|
fn is_zero_width(u : Int) -> Bool {
  (u >= 0x0300 && u <= 0x036F) ||
  (u >= 0x0483 && u <= 0x0489) ||
  (u >= 0x0591 && u <= 0x05BD) ||
  (u >= 0x0610 && u <= 0x061A) ||
  (u >= 0x064B && u <= 0x065F) ||
  (u >= 0x06D6 && u <= 0x06DC) ||
  (u >= 0x0730 && u <= 0x074A) ||
  (u >= 0x07EB && u <= 0x07F3) ||
  (u >= 0x0900 && u <= 0x0903) ||
  (u >= 0x093A && u <= 0x093C) ||
  (u >= 0x0941 && u <= 0x0948) ||
  (u >= 0x0951 && u <= 0x0957) ||
  (u >= 0x0E31 && u <= 0x0E31) ||
  (u >= 0x0E34 && u <= 0x0E3A) ||
  (u >= 0x0EB4 && u <= 0x0EBC) ||
  (u >= 0x1AB0 && u <= 0x1AFF) ||
  (u >= 0x1DC0 && u <= 0x1DFF) ||
  (u >= 0x200B && u <= 0x200F) ||
  (u >= 0x2028 && u <= 0x202E) ||
  (u >= 0x20D0 && u <= 0x20F0) ||
  (u >= 0xFE00 && u <= 0xFE0F) ||
  (u >= 0xFE20 && u <= 0xFE2F) ||
  u == 0xFEFF ||
  (u >= 0xE0100 && u <= 0xE01EF)
}

///|
fn is_wide(u : Int) -> Bool {
  (u >= 0x1100 && u <= 0x115F) ||
  (u >= 0x2E80 && u <= 0x303E) ||
  (u >= 0x3041 && u <= 0x33FF) ||
  (u >= 0x3400 && u <= 0x4DBF) ||
  (u >= 0x4E00 && u <= 0x9FFF) ||
  (u >= 0xA000 && u <= 0xA4CF) ||
  (u >= 0xA960 && u <= 0xA97F) ||
  (u >= 0xAC00 && u <= 0xD7A3) ||
  (u >= 0xF900 && u <= 0xFAFF) ||
  (u >= 0xFE10 && u <= 0xFE19) ||
  (u >= 0xFE30 && u <= 0xFE6F) ||
  (u >= 0xFF00 && u <= 0xFF60) ||
  (u >= 0xFFE0 && u <= 0xFFE6) ||
  (u >= 0x1F300 && u <= 0x1F64F) ||
  (u >= 0x1F900 && u <= 0x1F9FF) ||
  (u >= 0x20000 && u <= 0x2FFFD) ||
  (u >= 0x30000 && u <= 0x3FFFD)
}

///|
/// The display width of a string.
pub fn str_width(s : String) -> Int {
  let mut w = 0
  for c in s {
    w = w + char_width(c)
  }
  w
}

///|
/// Expand tabs to `tab_width` stops, and report where each code unit landed.
///
/// Returns the expanded line and a map from code-unit offset within the
/// ORIGINAL line to display column in the expanded one. The renderer needs
/// both: it prints the expanded text and positions carets with the map. Doing
/// it in one pass is what keeps the two from disagreeing -- and a caret one
/// column off a tab is the classic way a diagnostic renderer embarrasses
/// itself.
pub fn expand_tabs(line : String, tab_width : Int) -> (String, Array[Int]) {
  let buf = StringBuilder()
  // One entry per code unit, plus a final entry for the end of the line, so
  // that a span ending at end-of-line has a column to point at.
  let cols = Array::new(capacity=line.length() + 1)
  let mut col = 0
  let mut i = 0
  let n = line.length()
  while i < n {
    let c = line.get_char(i)
    match c {
      None => {
        // A lone surrogate. Emit it and move on: refusing to render a line
        // because it is not well-formed helps nobody diagnose why.
        cols.push(col)
        buf.write_char('\u{FFFD}')
        col = col + 1
        i = i + 1
      }
      Some(ch) => {
        let units = if ch.to_int() > 0xFFFF { 2 } else { 1 }
        cols.push(col)
        if units == 2 {
          cols.push(col)
        }
        if ch == '\t' {
          let advance = tab_width - col % tab_width
          for _ in 0..<advance {
            buf.write_char(' ')
          }
          col = col + advance
        } else {
          buf.write_char(ch)
          col = col + char_width(ch)
        }
        i = i + units
      }
    }
  }
  cols.push(col)
  (buf.to_string(), cols)
}
