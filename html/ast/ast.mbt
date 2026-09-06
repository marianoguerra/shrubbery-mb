///|
/// A markup syntax tree: HTML, SVG and MathML.
///
/// The shape follows biome for tolerance -- every enum a parse can fail inside
/// of has a `Bogus` member, so a parse always yields a tree rather than an
/// error, and the tree always covers the whole file -- and html5ever for
/// vocabulary, in that an element's name is a namespace and a local name rather
/// than a string.
///
/// It is a MARKUP tree, not a document tree, and that is the load-bearing
/// decision in the whole design. This is what was WRITTEN: `<p>a<p>b` is two
/// start tags and no end tags. A conforming WHATWG parse produces something
/// else -- two sibling paragraphs inside an invented `<html><head><body>`, with
/// misnesting repaired and text foster-parented out of tables -- and that tree
/// is not reversible. A formatter built on it would hand back a file that
/// renders the same and reads differently, which is the one thing a formatter
/// may never do.
///
/// It is also SEMANTIC rather than lossless: parse then write gives back markup
/// that means the same thing, not the same bytes. Four things are preserved
/// anyway, because losing them is a semantic loss rather than a formatting one:
///
///   * a character reference's spelling, in `Text::raw` and `AttrValue`, so
///     `&nbsp;` does not become an invisible byte;
///   * attribute order, so reindenting a file does not rewrite every line;
///   * `disabled` against `disabled=""`, which are the same to a browser and
///     different to a reader;
///   * how an element was closed, in `Closing`, which is what distinguishes
///     `<br>` from `<br/>` and a written `</p>` from one the table supplied.
///
/// Nothing here depends on `error-report`: a `Bogus` carries an
/// `@kind.ErrorKind`, which is a plain closed enum, so building a tree and
/// printing it links neither the diagnostic library nor the parser.

///|
/// What could not be parsed, kept so that the tree covers the whole source.
///
/// `text` is the exact source the node replaced. Keeping it is what lets the
/// printer echo an unparsable region verbatim instead of deleting it -- a page
/// with one templating directive the parser has never seen should come back
/// with that directive still in it.
pub(all) struct Bogus {
  kind : @kind.ErrorKind
  span : @span.Span
  text : String
} derive(Eq, Debug)

///|
pub fn Bogus::new(
  kind : @kind.ErrorKind,
  span : @span.Span,
  text? : String = "",
) -> Bogus {
  { kind, span, text, }
}

// ---------------------------------------------------------------- documents

///|
/// A document, or a fragment: the same type.
///
/// One type rather than two, because a fragment is a document whose children
/// happen not to include a doctype, and every operation either would support is
/// the same operation. html5ever needs the distinction because its tree builder
/// runs different insertion modes for the two; a markup parser has no insertion
/// modes to run.
pub(all) struct Document {
  children : Array[Node]
  span : @span.Span
} derive(Eq, Debug)

///|
pub(all) enum Node {
  Element(Element)
  Text(Text)
  /// The content of a `script` or `style`: never escaped, never markup.
  RawText(RawText)
  Comment(Comment)
  Doctype(Doctype)
  /// A `<![CDATA[...]]>`, which is legal in foreign content and a bogus
  /// comment in HTML. Kept as itself so the printer can put back whichever it
  /// was looking at.
  Cdata(String, @span.Span)
  Bogus(Bogus)
} derive(Eq, Debug)

// ---------------------------------------------------------------- elements

///|
pub(all) struct Element {
  name : TagName
  attrs : Array[Attribute]
  children : Array[Node]
  closing : Closing
  span : @span.Span
  /// Where the name sits inside the start tag, for a diagnostic that wants to
  /// point at `div` rather than at `<div class="...">`.
  name_span : @span.Span
} derive(Eq, Debug)

///|
/// How an element ended.
///
/// You cannot print an element back without knowing this, and no other field
/// can be made to say it. It is the same argument `LayerRule::body` makes on
/// the CSS side: the alternatives are different constructs, not one construct
/// with an optional part.
pub(all) enum Closing {
  /// `<div>...</div>`.
  Explicit
  /// `<circle/>`. Load-bearing in foreign content, ignored in HTML, and a
  /// house style there that a formatter has no business changing.
  SelfClosing
  /// `<br>`: the element cannot have an end tag at all.
  Void
  /// `<li>a<li>b`: closed by the table in `names`, not by the source.
  Implied
  /// Ran to the end of the input. A diagnostic, not a failure.
  Unclosed
} derive(Eq, Debug)

///|
/// An element's name: a namespace and a local name.
///
/// The name is NORMALISED -- ASCII-lowercased in HTML, case-adjusted by table
/// in SVG and MathML -- so that `<DIV>` and `<div>` are one node, and
/// `<LINEARGRADIENT>` and `<linearGradient>` are the one that exists. Case is
/// not a semantic difference in either vocabulary, which is why this normalises
/// where `Text::raw` preserves.
pub(all) struct TagName {
  ns : Namespace
  name : String
} derive(Eq, Debug)

///|
pub fn TagName::html(name : String) -> TagName {
  { ns: Html, name, }
}

///|
/// Which vocabulary a name is drawn from.
///
/// Not decoration: it decides four things that are otherwise ambiguous in the
/// same bytes -- whether `/>` closes an element or is ignored, whether an
/// attribute name is lowercased or table-adjusted, whether `<![CDATA[` is CDATA
/// or a bogus comment, and whether `<title>` holds text or elements.
pub(all) enum Namespace {
  Html
  Svg
  MathMl
  /// Reached only through an `xmlns` this library does not interpret. Kept so
  /// that a name can say it is neither of the three rather than pretending.
  Other(String)
} derive(Eq, Debug)

// -------------------------------------------------------------- attributes

///|
pub(all) struct Attribute {
  name : AttrName
  value : AttrValue
  span : @span.Span
} derive(Eq, Debug)

///|
/// `xlink:href` is `prefix = Some("xlink")`. The prefix is kept unresolved:
/// resolving it needs the `xmlns` declarations in scope, which is a document
/// question and not a markup one.
pub(all) struct AttrName {
  prefix : String?
  name : String
} derive(Eq, Debug)

///|
pub fn AttrName::plain(name : String) -> AttrName {
  { prefix: None, name, }
}

///|
/// The written form of an attribute name, prefix and all.
pub fn AttrName::text(self : AttrName) -> String {
  match self.prefix {
    Some(p) => p + ":" + self.name
    None => self.name
  }
}

///|
/// `Empty` is `disabled`; `Value("", ..)` is `disabled=""`.
///
/// The two are identical to a browser and different to a person reading a
/// diff, so the tree keeps the distinction and the printer decides what to do
/// with it. Quoting style is deliberately NOT kept: `Pretty` always
/// double-quotes and `Minified` drops the quotes where that is legal, the same
/// way the CSS printer normalises `'x'` to `"x"`.
pub(all) enum AttrValue {
  Empty
  /// The decoded value, and the source spelling when decoding was not the
  /// identity -- `&amp;` in a query string, say. `None` when it was.
  Value(String, String?)
} derive(Eq, Debug)

///|
/// The decoded text of a value, with `Empty` reading as `""`.
pub fn AttrValue::text(self : AttrValue) -> String {
  match self {
    Empty => ""
    Value(v, _) => v
  }
}

// ------------------------------------------------------------------- leaves

///|
/// A run of character data, decoded.
///
/// `raw` is the source spelling, kept when decoding was not the identity. It
/// exists for the reason `Number::repr` exists in the CSS tree: a formatter
/// asked to reindent a file must not also rewrite every entity in it, and
/// turning `&nbsp;` into an invisible byte is a change a reviewer cannot see
/// and a reader cannot undo.
pub(all) struct Text {
  text : String
  raw : String?
  span : @span.Span
} derive(Eq, Debug)

///|
pub fn Text::new(
  text : String,
  raw? : String? = None,
  span? : @span.Span = @span.nowhere,
) -> Text {
  { text, raw, span, }
}

///|
/// The body of a `script` or a `style`.
///
/// A separate node from `Text` because it is not text: no reference resolves in
/// it, nothing in it is escaped on the way out, and the printer must refuse to
/// emit a body containing the element's own end tag rather than escaping it,
/// because there is no escape.
pub(all) struct RawText {
  text : String
  span : @span.Span
} derive(Eq, Debug)

///|
/// A `<!-- ... -->`. `text` is the body, without the delimiters.
///
/// Comments are first-class nodes rather than trivia attached to a neighbour.
/// Conditional comments, `<!-- /ko -->` and every framework that hides a
/// directive in one depend on it, and the CSS module's decision to drop them
/// through the notation is the one lossy spot this module does not repeat.
pub(all) struct Comment {
  text : String
  span : @span.Span
} derive(Eq, Debug)

///|
/// A `<!DOCTYPE html>`, or a legacy one with its identifiers.
pub(all) struct Doctype {
  name : String
  public_id : String?
  system_id : String?
  span : @span.Span
} derive(Eq, Debug)

// ---------------------------------------------------------------- accessors

///|
/// The span of any node, for a caller assembling a parent's.
pub fn Node::span(self : Node) -> @span.Span {
  match self {
    Element(e) => e.span
    Text(t) => t.span
    RawText(r) => r.span
    Comment(c) => c.span
    Doctype(d) => d.span
    Cdata(_, s) => s
    Bogus(b) => b.span
  }
}

///|
/// The children of a node, empty for everything that cannot have any.
///
/// A total function rather than an option, because every caller that walks a
/// tree wants to recurse without asking first, and "a text node has no
/// children" is not a case worth making them handle.
pub fn Node::children(self : Node) -> Array[Node] {
  match self {
    Element(e) => e.children
    _ => []
  }
}
