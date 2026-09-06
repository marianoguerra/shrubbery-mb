///|
/// Escaping, which is the part of a markup printer that has to be right.
///
/// A formatter that mislays a space produces an ugly diff. A printer that lets
/// a value out of the node it was put in produces an injection, so the rule
/// here is deliberately blunter than the specification's minimum: `&` is always
/// escaped, in every context, rather than only when the characters after it
/// could form a reference. The specification's "ambiguous ampersand" rule is
/// correct and context-dependent -- `&notit;` resolves in text and does not in
/// an attribute value -- and a printer that implemented it would be right in
/// two ways it could get wrong in three.
///
/// The cost of the blunt rule is nil, because a text node that had a literal
/// `&` in the source carries its own spelling in `Text::raw` and never reaches
/// this function.

///|
/// Character data, as it may appear between tags.
///
/// `<` and `&` must be escaped; `>` need not be, and is anyway, because a bare
/// `>` after a `]]` is a CDATA-end sequence in foreign content and because a
/// reader scanning for tags should not find a shape that is not one.
pub fn escape_text(s : String) -> String {
  let buf = StringBuilder()
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.unsafe_get(i).to_int().unsafe_to_char()
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      _ => write_visible(buf, c)
    }
    i = i + 1
  }
  buf.to_string()
}

///|
/// An attribute value, as it may appear between double quotes.
///
/// `<` and `>` are left alone: they cannot end a quoted value, and escaping
/// them would make every `srcdoc` and every inline SVG data URI unreadable.
pub fn escape_attr(s : String) -> String {
  let buf = StringBuilder()
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.unsafe_get(i).to_int().unsafe_to_char()
    match c {
      '&' => buf.write_string("&amp;")
      '"' => buf.write_string("&quot;")
      _ => write_visible(buf, c)
    }
    i = i + 1
  }
  buf.to_string()
}

///|
/// One character, named if it is one a reader could not see.
///
/// This is the encode half of the bargain `Text::raw` makes on the decode side.
/// A non-breaking space that goes out as a raw byte is indistinguishable from
/// an ordinary space in every editor, so the next person to touch the file
/// cannot tell that the line they are looking at will not wrap. Naming it costs
/// five bytes and makes the file say what it means.
fn write_visible(buf : StringBuilder, c : Char) -> Unit {
  if @names.is_invisible(c) {
    match @names.reference_for_invisible(c) {
      Some(name) => {
        buf.write_char('&')
        buf.write_string(name)
        buf.write_char(';')
      }
      None => {
        buf.write_string("&#x")
        buf.write_string(hex_upper(c.to_int()))
        buf.write_char(';')
      }
    }
  } else {
    buf.write_char(c)
  }
}

///|
fn hex_upper(n : Int) -> String {
  if n == 0 {
    return "0"
  }
  let digits = "0123456789ABCDEF"
  let buf = StringBuilder()
  let mut v = n
  let out : Array[Char] = []
  while v > 0 {
    out.push(digits.unsafe_get(v % 16).to_int().unsafe_to_char())
    v = v / 16
  }
  let mut i = out.length() - 1
  while i >= 0 {
    buf.write_char(out[i])
    i = i - 1
  }
  buf.to_string()
}

///|
/// Whether an attribute value may be written without quotes.
///
/// Only `Minified` asks. The trailing-slash case is the one that is easy to
/// miss and impossible to see: `<a href=/x/>` is a link to `/x/` in the source
/// and a self-closing tag with `href=/x` to a parser, so a value ending in `/`
/// keeps its quotes however short it is.
pub fn may_go_unquoted(v : String) -> Bool {
  let n = v.length()
  if n == 0 {
    return false
  }
  if v.has_suffix("/") {
    return false
  }
  let mut i = 0
  while i < n {
    let c = v.unsafe_get(i).to_int().unsafe_to_char()
    match c {
      ' '
      | '\t'
      | '\n'
      | '\r'
      | '\u{0C}'
      | '"'
      | '\''
      | '`'
      | '='
      | '<'
      | '>'
      | '&' => return false
      _ => if @names.is_invisible(c) { return false }
    }
    i = i + 1
  }
  true
}

///|
/// Whether a raw-text body can be printed at all.
///
/// It cannot if it contains the element's own end tag, because raw text ends at
/// the first `</name` and nothing escapes it -- not a backslash, not a
/// reference, nothing. A printer's only honest answers are to refuse or to
/// change the text, and changing the text of a script is how a formatter
/// becomes a security bug. So this returns `false`, `write` reports
/// `UnprintableRawText`, and the bytes go out unchanged so that at least
/// nothing was invented.
pub fn raw_text_is_printable(body : String, tag : String) -> Bool {
  let needle = "</" + tag
  !body.to_lower().contains(needle)
}
