///|
/// Typed readings of a tree, on demand.
///
/// The markup tree is untyped by design: an attribute's value is a string,
/// because that is what it is in the source and because a parser that decided
/// `width` was a number would have nothing to say about `width="{{ w }}"`.
/// Asking what a value *means* is a separate question, answered here by a lens
/// -- a pure function computed when asked and stored nowhere.
///
/// That is the arrangement `css/value` already has, and the argument is the
/// same: coverage stays total, and the typed view is something a caller opts
/// into per question rather than something the parser must decide up front for
/// every attribute in existence.

///|
/// An attribute's value, by name, or `None` if the element does not have it.
///
/// The comparison includes the prefix, so `xlink:href` is asked for as
/// `"xlink:href"` and does not answer to `"href"`.
pub fn attr(e : @ast.Element, name : String) -> String? {
  for a in e.attrs {
    if a.name.text() == name {
      return Some(a.value.text())
    }
  }
  None
}

///|
/// Whether an element carries an attribute at all.
///
/// Separate from `attr` because `disabled` and `disabled=""` are both present
/// and only one of them has a value a caller could test.
pub fn has_attr(e : @ast.Element, name : String) -> Bool {
  for a in e.attrs {
    if a.name.text() == name {
      return true
    }
  }
  false
}

///|
/// An HTML boolean attribute: present is true, absent is false.
///
/// The value is deliberately ignored, because HTML ignores it:
/// `disabled="false"` is a disabled control, and a lens that read the string
/// would disagree with every browser.
pub fn as_bool(e : @ast.Element, name : String) -> Bool {
  has_attr(e, name)
}

///|
/// An attribute as an integer, if it is one.
pub fn as_int(e : @ast.Element, name : String) -> Int? {
  match attr(e, name) {
    None => None
    Some(v) => parse_int(v)
  }
}

///|
fn parse_int(v : String) -> Int? {
  let n = v.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut negative = false
  let first = v.unsafe_get(0).to_int()
  if first == 45 || first == 43 {
    negative = first == 45
    i = 1
  }
  if i >= n {
    return None
  }
  let mut value = 0
  while i < n {
    let d = v.unsafe_get(i).to_int() - 48
    if d < 0 || d > 9 {
      return None
    }
    value = value * 10 + d
    i = i + 1
  }
  Some(if negative { -value } else { value })
}

///|
/// The classes on an element, split the way HTML splits them.
///
/// On ASCII whitespace, and with empty runs dropped, which is what makes
/// `class="  a  b "` two classes rather than five.
pub fn class_list(e : @ast.Element) -> Array[String] {
  let out : Array[String] = []
  match attr(e, "class") {
    None => out
    Some(v) => {
      let n = v.length()
      let mut start = 0
      let mut i = 0
      while i <= n {
        let at_end = i == n
        let c = if at_end {
          ' '
        } else {
          v.unsafe_get(i).to_int().unsafe_to_char()
        }
        if c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u{0C}' {
          if i > start {
            out.push(v.clamped_view(start~, end=i).to_owned())
          }
          start = i + 1
        }
        i = i + 1
      }
      out
    }
  }
}

///|
/// All the text under a node, concatenated.
///
/// Raw text is included, which is the choice the DOM's `textContent` makes and
/// the one that surprises people: the body of a `<script>` is text, and a
/// caller extracting the words on a page has to skip it deliberately. Comments
/// are not included, which is the same choice.
pub fn text_content(n : @ast.Node) -> String {
  let buf = StringBuilder()
  collect_text(n, buf)
  buf.to_string()
}

///|
fn collect_text(n : @ast.Node, buf : StringBuilder) -> Unit {
  match n {
    Text(t) => buf.write_string(t.text)
    RawText(r) => buf.write_string(r.text)
    Cdata(t, _) => buf.write_string(t)
    Element(e) =>
      for c in e.children {
        collect_text(c, buf)
      }
    _ => ()
  }
}

///|
/// Every element under a node, in document order, including the node itself.
///
/// Materialised rather than lazy. A lazy walk would be nicer and would need an
/// iterator protocol threaded through a recursive structure for a saving that
/// only shows on documents nobody has.
pub fn elements(n : @ast.Node) -> Array[@ast.Element] {
  let out : Array[@ast.Element] = []
  collect_elements(n, out)
  out
}

///|
fn collect_elements(n : @ast.Node, out : Array[@ast.Element]) -> Unit {
  match n {
    Element(e) => {
      out.push(e)
      for c in e.children {
        collect_elements(c, out)
      }
    }
    _ => ()
  }
}

///|
/// The first element under a node with this `id`.
///
/// `id` is the one attribute a document is supposed to have at most one of,
/// which is why this returns the first rather than a list -- and why finding a
/// second is a fact about the document rather than about this function.
pub fn by_id(doc : @ast.Document, id : String) -> @ast.Element? {
  for child in doc.children {
    for e in elements(child) {
      if attr(e, "id") == Some(id) {
        return Some(e)
      }
    }
  }
  None
}

///|
/// Every element under a document with this tag name.
pub fn by_tag(doc : @ast.Document, name : String) -> Array[@ast.Element] {
  let out : Array[@ast.Element] = []
  for child in doc.children {
    for e in elements(child) {
      if e.name.name == name {
        out.push(e)
      }
    }
  }
  out
}

///|
/// What the default stylesheet would make of this element.
///
/// A lens over `names`, exposed here so that a caller asking about layout does
/// not have to know that the table is in a different package -- and because the
/// answer depends on the namespace, which the table does not take.
pub fn display_of(e : @ast.Element) -> @names.Display {
  match e.name.ns {
    Html => @names.display_of(e.name.name)
    _ => Inline
  }
}

///|
/// Whether this element is one that cannot have children.
pub fn is_void(e : @ast.Element) -> Bool {
  e.name.ns == Html && @names.is_void(e.name.name)
}
