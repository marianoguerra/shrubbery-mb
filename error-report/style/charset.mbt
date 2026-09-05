///|
/// The characters a renderer draws its frame with.
///
/// Two sets, because a terminal that cannot show box-drawing characters is
/// still a terminal someone has to read the output in. Swapping the set must
/// never change the LAYOUT -- every character here is one column wide, in both
/// sets -- so an ASCII rendering lines up exactly like a Unicode one and a
/// golden test can be written against either.
pub(all) struct CharSet {
  /// Horizontal rule, as in the header underline.
  hbar : Char
  /// Vertical rule down the gutter.
  vbar : Char
  /// Gutter corner opening the snippet.
  top_left : Char
  /// Gutter corner closing the snippet.
  bottom_left : Char
  /// Gutter tee, for a help or note line hanging off the frame.
  left_tee : Char
  /// Underline beneath a primary label.
  primary_underline : Char
  /// Underline beneath a secondary label.
  secondary_underline : Char
  /// Sits in the underline directly below a label that has a message, and the
  /// message's stem descends from it.
  stem_top : Char
  /// The stem itself, on the rows between an underline and its message.
  stem : Char
  /// The elbow turning a stem into its message.
  elbow : Char
  /// Left margin: first line of a span that continues onto later lines.
  multi_top : Char
  /// Left margin: a line in the middle of such a span.
  multi_mid : Char
  /// Left margin: the last line of such a span. Not a corner, because the
  /// span's message hangs on the row below it.
  multi_end : Char
  /// Ellipsis between two non-adjacent snippet lines.
  ellipsis : Char
}

///|
/// Box-drawing characters. The default.
pub let unicode_chars : CharSet = {
  hbar: '─',
  vbar: '│',
  top_left: '╭',
  bottom_left: '╰',
  left_tee: '├',
  primary_underline: '─',
  secondary_underline: '─',
  stem_top: '┬',
  stem: '│',
  elbow: '╰',
  multi_top: '╭',
  multi_mid: '│',
  multi_end: '├',
  ellipsis: '⋯',
}

///|
/// ASCII fallback. Same widths, so the layout is identical.
pub let ascii_chars : CharSet = {
  hbar: '-',
  vbar: '|',
  top_left: ',',
  bottom_left: '`',
  left_tee: '|',
  primary_underline: '^',
  secondary_underline: '-',
  stem_top: '|',
  stem: '|',
  elbow: '`',
  multi_top: '/',
  multi_mid: '|',
  multi_end: '+',
  ellipsis: '.',
}
