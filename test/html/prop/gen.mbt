///|
/// Generators for markup trees.
///
/// Everything here produces a **normal** tree: no `Bogus`, no `Implied` or
/// `Unclosed` closings, no `raw` spellings, and no adjacent text nodes. That is
/// what lets the round-trip properties be stated as plain equality -- a
/// generator that produced denormal trees would need a normaliser in every
/// test, and the normaliser would then be the thing under test rather than the
/// library.
///
/// The one deliberate exception to "normal" is the CONTENT. Text is drawn from
/// a list of strings chosen to break an escaper, and attribute values from the
/// same list, because the property that matters most here is not that a tree
/// round-trips but that nothing in it can escape the node it was put in.
///
/// Size discipline is what makes it terminate: every recursive generator halves
/// its budget, and at zero the weighted alternatives are leaves only.

///|
/// Element names worth generating.
///
/// A fixed list rather than random letters, because the interesting names are
/// the ones that change how the parser and the printer behave: void, raw text,
/// escapable raw text, preformatted, block, inline, and one that needs the
/// literal escape on the way to shrubbery.
fn html_names() -> Array[String] {
  [
    "div", "p", "span", "em", "ul", "li", "table", "tr", "td", "pre", "section",
    "my-element", "side_bar",
  ]
}

///|
fn void_names() -> Array[String] {
  ["br", "img", "input", "hr", "meta"]
}

///|
fn svg_names() -> Array[String] {
  ["circle", "path", "linearGradient", "foreignObject", "g", "rect"]
}

///|
/// Attribute names, including the two that have no bare shrubbery spelling.
fn attr_names() -> Array[String] {
  ["class", "id", "data-id", "aria-label", "xlink:href", "side_bar", "title"]
}

///|
/// Strings chosen to break an escaper.
///
/// Every one of these has ended a node it was not supposed to end in some
/// parser: a raw end tag, a half-escaped reference, an attribute-quote break,
/// a CDATA terminator, a comment terminator, an invisible character, and an
/// astral pair. If `print` then `parse` gives any of them back changed, the
/// library has an injection.
fn hostile_text() -> Array[String] {
  [
    "plain", " leading and trailing ", "a & b", "&amp;", "&notaname;", "</p>", "</script>",
    "<!--", "-->", "]]>", "\"><img onerror=x>", "'", "a\u{A0}b", "a\u{200B}b", "line\nbreak",
    "🌿", "<", ">",
  ]
}

///|
fn gen_text(r : Rng) -> @ast.Node {
  Text({ text: r.pick(hostile_text()), raw: None, span: @span.nowhere, })
}

///|
/// An attribute. `Empty` is generated too, because `disabled` and
/// `disabled=""` are different nodes and only one of them can be unquoted.
fn gen_attr(r : Rng) -> @ast.Attribute {
  let written = r.pick(attr_names())
  let value : @ast.AttrValue = if r.below(5) == 0 {
    Empty
  } else {
    Value(r.pick(hostile_text()), None)
  }
  { name: split_prefix(written), value, span: @span.nowhere, }
}

///|
/// `xlink:href` as a prefix and a name, so that `AttrName::text` puts it back.
fn split_prefix(name : String) -> @ast.AttrName {
  let n = name.length()
  let mut i = 0
  while i < n {
    if name.unsafe_get(i).to_int() == 58 && i > 0 && i + 1 < n {
      return {
        prefix: Some(name.clamped_view(start=0, end=i).to_owned()),
        name: name.clamped_view(start=i + 1, end=n).to_owned(),
      }
    }
    i = i + 1
  }
  { prefix: None, name, }
}

///|
fn gen_attrs(r : Rng, size : Int) -> Array[@ast.Attribute] {
  let out : Array[@ast.Attribute] = []
  let n = r.below(if size > 3 { 3 } else { size + 1 })
  let mut i = 0
  while i < n {
    let a = gen_attr(r)
    // Duplicates are dropped by the parser, so a tree with one could not
    // round-trip. Generating them would be testing the parser's recovery
    // through a property that is about something else.
    let mut seen = false
    for existing in out {
      if existing.name.text() == a.name.text() {
        seen = true
      }
    }
    if !seen {
      out.push(a)
    }
    i = i + 1
  }
  out
}

///|
/// An element, in a namespace.
fn gen_element(
  r : Rng,
  size : Int,
  ns : @ast.Namespace,
  parent? : String = "",
) -> @ast.Node {
  match ns {
    Html => gen_html_element(r, size, parent)
    _ => gen_foreign_element(r, size, ns)
  }
}

///|
fn gen_html_element(r : Rng, size : Int, parent : String) -> @ast.Node {
  if size <= 0 || r.below(4) == 0 {
    let picked = r.pick(void_names())
    // `<hr>` closes an open `<p>`, so it is not a child of one. `<br>` closes
    // nothing and is the fallback.
    let name = if @names.implies_close(parent, picked) { "br" } else { picked }
    return Element({
      name: @ast.TagName::html(name),
      attrs: gen_attrs(r, size),
      children: [],
      closing: Void,
      span: @span.nowhere,
      name_span: @span.nowhere,
    })
  }
  let picked = r.pick(html_names())
  // A `<tr>` inside a `<tr>` is not a tree a parse can produce: the implied-end
  // table splits it into siblings, correctly, and generating one would make
  // every round-trip property fail for a reason that is about the generator.
  let name = if @names.implies_close(parent, picked) { "span" } else { picked }
  // Raw text and preformatted content are their own shapes, and a generator
  // that put ordinary children in a `<pre>` would be generating a tree the
  // printer is right to refuse to lay out.
  let children = if @names.is_preformatted(name) {
    [gen_text(r)]
  } else {
    gen_children(r, size / 2, Html, parent=name)
  }
  Element({
    name: @ast.TagName::html(name),
    attrs: gen_attrs(r, size),
    children,
    closing: Explicit,
    span: @span.nowhere,
    name_span: @span.nowhere,
  })
}

///|
fn gen_foreign_element(r : Rng, size : Int, ns : @ast.Namespace) -> @ast.Node {
  let name = r.pick(svg_names())
  let inner = if name == "foreignObject" { @ast.Namespace::Html } else { ns }
  let children = if size <= 0 || r.below(3) == 0 {
    []
  } else {
    gen_children(r, size / 2, inner)
  }
  let closing : @ast.Closing = if children.length() == 0 {
    SelfClosing
  } else {
    Explicit
  }
  Element({
    name: { ns, name, },
    attrs: gen_attrs(r, size),
    children,
    closing,
    span: @span.nowhere,
    name_span: @span.nowhere,
  })
}

///|
/// `<svg>` and its subtree, which is the only way into foreign content.
fn gen_svg_root(r : Rng, size : Int) -> @ast.Node {
  let children = if size <= 1 { [] } else { gen_children(r, size / 2, Svg) }
  Element({
    name: { ns: Svg, name: "svg", },
    attrs: gen_attrs(r, size),
    children,
    closing: if children.length() == 0 {
      SelfClosing
    } else {
      Explicit
    },
    span: @span.nowhere,
    name_span: @span.nowhere,
  })
}

///|
/// A run of children, with no two text nodes adjacent.
///
/// Adjacent text nodes are not a tree a parse can produce -- the tokenizer
/// gathers a run into one node -- so generating them would make every
/// round-trip property fail for a reason that is about the generator.
fn gen_children(
  r : Rng,
  size : Int,
  ns : @ast.Namespace,
  parent? : String = "",
) -> Array[@ast.Node] {
  let out : Array[@ast.Node] = []
  let n = 1 + r.below(if size > 3 { 3 } else { size + 1 })
  let mut i = 0
  let mut last_was_text = false
  while i < n {
    let node = gen_node(r, size, ns, allow_text=!last_was_text, parent~)
    last_was_text = node is Text(_)
    out.push(node)
    i = i + 1
  }
  out
}

///|
fn gen_node(
  r : Rng,
  size : Int,
  ns : @ast.Namespace,
  allow_text~ : Bool,
  parent? : String = "",
) -> @ast.Node {
  if size <= 0 {
    return if allow_text { gen_text(r) } else { gen_element(r, 0, ns, parent~) }
  }
  let alts : Array[(Int, Int)] = if allow_text {
    [(4, 0), (5, 1), (1, 2), (1, 3)]
  } else {
    [(6, 1), (1, 2), (1, 3)]
  }
  match r.weighted(alts) {
    0 => gen_text(r)
    2 =>
      Comment({ text: r.pick(["x", " a ", "-", "a - b"]), span: @span.nowhere, })
    3 =>
      match ns {
        Html => gen_element(r, size, Html, parent~)
        // CDATA is legal only in foreign content, so it is generated only
        // there -- in HTML it is a comment and the tree would not round-trip.
        other =>
          Cdata(r.pick(["x", "a < b", "1"]), @span.nowhere) |> ignore_ns(other)
      }
    _ =>
      // A foreign element is reachable only through its own root: a bare
      // `<linearGradient/>` in HTML is an HTML element with a lowercased name,
      // so generating one would be generating a tree no parse can produce.
      if r.below(6) == 0 && ns == Html {
        gen_svg_root(r, size)
      } else {
        gen_element(r, size, ns, parent~)
      }
  }
}

///|
/// A no-op that keeps the namespace match total without a wildcard binding
/// that the compiler would call unused.
fn ignore_ns(n : @ast.Node, ns : @ast.Namespace) -> @ast.Node {
  ignore(ns)
  n
}

///|
/// A whole document.
pub fn gen_document(r : Rng, size : Int) -> @ast.Document {
  let children : Array[@ast.Node] = []
  if r.bool() {
    children.push(
      Doctype({
        name: "html",
        public_id: None,
        system_id: None,
        span: @span.nowhere,
      }),
    )
  }
  for c in gen_children(r, size, Html) {
    children.push(c)
  }
  { children, span: @span.nowhere, }
}

// ------------------------------------------------------------------ shrinking

///|
/// Smaller documents that might still fail.
///
/// Three moves, cheapest first: drop a child, replace a child with one of its
/// own children, and simplify a text node. Together they take a twenty-node
/// counterexample down to the two or three nodes that actually matter, which is
/// the difference between a report someone reads and one they skip.
///
/// Every candidate is checked against the same tables the generator obeys.
/// Promoting a child is the move that needs it: lifting an `<li>` out of its
/// `<ul>` and into a `<p>` produces a tree no parse can give back, and a
/// shrinker that produced one would report a counterexample that is about the
/// shrinker rather than about the library.
pub fn shrink_document(doc : @ast.Document) -> Array[@ast.Document] {
  let out : Array[@ast.Document] = []
  for kids in shrink_nodes(doc.children, "", Html) {
    out.push({ children: kids, span: doc.span, })
  }
  out
}

///|
/// Whether a node may sit where it is about to be put.
fn fits(n : @ast.Node, parent : String, ns : @ast.Namespace) -> Bool {
  match n {
    Element(e) => e.name.ns == ns && !@names.implies_close(parent, e.name.name)
    // CDATA is a comment in HTML, so a tree with one there cannot round-trip.
    Cdata(_, _) => ns != Html
    _ => true
  }
}

///|
fn shrink_nodes(
  nodes : Array[@ast.Node],
  parent : String,
  ns : @ast.Namespace,
) -> Array[Array[@ast.Node]] {
  let out : Array[Array[@ast.Node]] = []
  let n = nodes.length()
  // Drop one.
  let mut i = 0
  while i < n {
    let kept : Array[@ast.Node] = []
    let mut k = 0
    while k < n {
      if k != i {
        kept.push(nodes[k])
      }
      k = k + 1
    }
    out.push(kept)
    i = i + 1
  }
  // Replace one with something smaller.
  i = 0
  while i < n {
    for smaller in shrink_node(nodes[i]) {
      if !fits(smaller, parent, ns) {
        continue
      }
      let kept : Array[@ast.Node] = []
      let mut k = 0
      while k < n {
        kept.push(if k == i { smaller } else { nodes[k] })
        k = k + 1
      }
      out.push(kept)
    }
    i = i + 1
  }
  out
}

///|
fn shrink_node(n : @ast.Node) -> Array[@ast.Node] {
  let out : Array[@ast.Node] = []
  match n {
    Element(e) => {
      // Promote a child, which is the move that finds "this nesting is the
      // problem" rather than "this element is". The caller checks that the
      // promoted child fits where its grandparent is about to put it.
      for c in e.children {
        out.push(c)
      }
      if e.children.length() > 0 {
        let closing : @ast.Closing = match e.closing {
          Explicit => if e.name.ns == Html { Explicit } else { SelfClosing }
          other => other
        }
        out.push(Element({ ..e, children: [], closing, }))
      }
      if e.attrs.length() > 0 {
        out.push(Element({ ..e, attrs: [], }))
      }
      let inner = child_ns(e)
      for kids in shrink_nodes(e.children, e.name.name, inner) {
        if kids.length() > 0 {
          out.push(Element({ ..e, children: kids, }))
        }
      }
    }
    Text(t) =>
      // Only when it is genuinely longer. `"<"` and `"x"` are the same size,
      // and a move that does not shrink is a move `minimize` could cycle on.
      if t.text.length() > 1 {
        out.push(Text({ ..t, text: "x", }))
      }
    _ => ()
  }
  out
}

///|
fn child_ns(e : @ast.Element) -> @ast.Namespace {
  match e.name.ns {
    Html => Html
    other =>
      if @names.is_integration_point(e.name.name.to_lower()) {
        Html
      } else {
        other
      }
  }
}

///|
/// How many nodes a document holds, for the test that says shrinking makes
/// progress.
pub fn size_of(doc : @ast.Document) -> Int {
  let mut total = 0
  for c in doc.children {
    total = total + node_size(c)
  }
  total
}

///|
fn node_size(n : @ast.Node) -> Int {
  match n {
    Element(e) => {
      let mut total = 1 + e.attrs.length()
      for c in e.children {
        total = total + node_size(c)
      }
      total
    }
    // Text counts its length, because one of the shrinker's moves is to
    // simplify a string. Without that the move would leave the size unchanged
    // and `minimize` could cycle.
    Text(t) => 1 + t.text.length()
    _ => 1
  }
}
