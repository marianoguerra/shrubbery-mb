///|
/// Markup text to a tree.
///
/// A stack machine over the token stream, and short, because the hard part of
/// HTML parsing is the part this deliberately does not do. There are no
/// insertion modes here, no adoption agency, no foster parenting, and no
/// invented `html`/`head`/`body`: what comes out is what was written.
///
/// What it does take from tree construction is the part the specification
/// states as tables rather than as algorithms -- implied end tags, void
/// elements, raw text, and the namespace of a name -- and all four of those
/// live in `html/names` as data. The line is drawn there on purpose. Every step
/// past it buys a few more files that nest the way a browser would nest them,
/// and costs the property that makes this library worth having: that the tree
/// can be printed back.
///
/// Tolerant by construction. There is no path here that returns without a
/// document: an end tag with nothing to close is dropped with a warning, an
/// element that runs to the end of the input is closed with one, and anything
/// the tokenizer could not read arrives as a `Bogus` token and leaves as a
/// `Bogus` node carrying its source. `strict=true` raises the first error
/// instead, for the caller whose input is their own.

///|
/// How deep the element stack may go.
///
/// A bound rather than a stack overflow. Ten thousand `<div>`s is not a
/// document, it is a fuzzer's output or an attack, and a library that
/// segfaulted on one would be unusable in exactly the place a tolerant parser
/// is wanted. Past the bound a start tag becomes a `Bogus` node holding its own
/// source, so nothing is lost and nothing recurses.
const MAX_DEPTH : Int = 400

///|
/// A document, and everything noticed while reading it.
pub struct Parsed {
  document : @ast.Document
  diagnostics : Array[@error.Diagnostic]
}

///|
pub fn Parsed::document(self : Parsed) -> @ast.Document {
  self.document
}

///|
pub fn Parsed::diagnostics(self : Parsed) -> Array[@error.Diagnostic] {
  self.diagnostics
}

///|
pub fn Parsed::has_errors(self : Parsed) -> Bool {
  for d in self.diagnostics {
    if d.is_error() {
      return true
    }
  }
  false
}

///|
/// An element that has been opened and not yet closed.
priv struct Frame {
  name : @ast.TagName
  attrs : Array[@ast.Attribute]
  children : Array[@ast.Node]
  start : Int
  name_span : @span.Span
}

///|
priv struct Parser {
  toks : Array[@token.Token]
  mut pos : Int
  stack : Array[Frame]
  roots : Array[@ast.Node]
  diagnostics : Array[@error.Diagnostic]
  strict : Bool
}

///|
/// Parse markup text.
///
/// Tolerant: malformed input produces diagnostics and a tree that still covers
/// the whole file, so this returns a document for any input at all. Pass
/// `strict=true` to have the first error raised instead.
pub fn parse(
  src : String,
  strict? : Bool = false,
) -> Parsed raise @error.HtmlError {
  let scanned = @token.tokenize(src)
  let p = {
    toks: scanned.tokens,
    pos: 0,
    stack: [],
    roots: [],
    diagnostics: [],
    strict,
  }
  for problem in scanned.problems {
    let (kind, span) = problem
    p.report(kind, span)
  }
  p.run()
  let span = @span.Span::new(0, src.length())
  { document: { children: p.roots, span, }, diagnostics: p.diagnostics, }
}

///|
/// Parse markup text, raising on the first error.
pub fn parse_strict(src : String) -> @ast.Document raise @error.HtmlError {
  parse(src, strict=true).document
}

// ---------------------------------------------------------------- reporting

///|
fn Parser::report(
  self : Parser,
  kind : @kind.ErrorKind,
  span : @span.Span,
) -> Unit raise @error.HtmlError {
  let d = @error.Diagnostic::of_kind(kind, span)
  if self.strict && d.is_error() {
    d.raise_()
  }
  self.diagnostics.push(d)
}

// ------------------------------------------------------------------- stack

///|
/// Where a new child goes: into the innermost open element, or into the
/// document.
fn Parser::sink(self : Parser) -> Array[@ast.Node] {
  let n = self.stack.length()
  if n == 0 {
    self.roots
  } else {
    self.stack[n - 1].children
  }
}

///|
/// The namespace a child of the innermost open element belongs to.
///
/// Foreign content is entered by `<svg>` and `<math>` and left at an HTML
/// integration point -- `foreignObject`, `desc`, SVG `title`, and the MathML
/// text containers. The rule is small enough to state in one function, which is
/// the only reason a markup parser can afford to know about namespaces at all;
/// getting it wrong means `<circle/>` stops closing itself and `viewBox` comes
/// back lowercased, and both are silent.
fn Parser::child_namespace(self : Parser) -> @ast.Namespace {
  let n = self.stack.length()
  if n == 0 {
    return Html
  }
  let parent = self.stack[n - 1]
  match parent.name.ns {
    Html => Html
    other =>
      if @names.is_integration_point(parent.name.name.to_lower()) {
        Html
      } else {
        other
      }
  }
}

///|
/// The normalised name of an element about to be opened.
fn Parser::tag_name(self : Parser, lowered : String) -> @ast.TagName {
  let inherited = self.child_namespace()
  let ns : @ast.Namespace = match inherited {
    Html =>
      if lowered == "svg" {
        Svg
      } else if lowered == "math" {
        MathMl
      } else {
        Html
      }
    other => other
  }
  let name = match ns {
    Svg =>
      match @names.svg_tag(lowered) {
        Some(cased) => cased
        None => lowered
      }
    _ => lowered
  }
  { ns, name, }
}

///|
/// Close the innermost open element and hand it to its parent.
fn Parser::pop(self : Parser, closing : @ast.Closing, end : Int) -> Unit {
  let n = self.stack.length()
  if n == 0 {
    return
  }
  let f = self.stack[n - 1]
  let _ = self.stack.pop()
  let e : @ast.Element = {
    name: f.name,
    attrs: f.attrs,
    children: f.children,
    closing,
    span: @span.Span::new(f.start, end),
    name_span: f.name_span,
  }
  self.sink().push(Element(e))
}

///|
/// The index of the innermost open element with this name, if any.
///
/// The comparison is against the LOWERCASED stored name, because an end tag
/// arrives lowercased and `foreignObject` is stored the way SVG spells it.
/// Comparing the two directly is a bug that shows only inside foreign content,
/// which is exactly where nobody looks.
fn Parser::find_open(self : Parser, lowered : String) -> Int? {
  let mut i = self.stack.length() - 1
  while i >= 0 {
    if self.stack[i].name.name.to_lower() == lowered {
      return Some(i)
    }
    i = i - 1
  }
  None
}

// -------------------------------------------------------------------- run

///|
fn Parser::run(self : Parser) -> Unit raise @error.HtmlError {
  let mut seen_content = false
  while self.pos < self.toks.length() {
    let t = self.toks[self.pos]
    self.pos = self.pos + 1
    match t.kind {
      Eof => break
      StartTag(name, attrs, self_closing) => {
        self.start_tag(name, attrs, self_closing, t.span)
        seen_content = true
      }
      EndTag(name) => {
        self.end_tag(name, t.span)
        seen_content = true
      }
      Text(text, raw) =>
        // A run of nothing at all: `</>` leaves one behind, and keeping it
        // would put an empty text node in the middle of a document.
        if text.length() > 0 {
          self.sink().push(Text({ text, raw, span: t.span, }))
          if !is_blank(text) {
            seen_content = true
          }
        }
      RawText(text) => self.sink().push(RawText({ text, span: t.span, }))
      Comment(text) => self.sink().push(Comment({ text, span: t.span, }))
      Cdata(text) => {
        if self.child_namespace() == Html {
          self.report(CdataInHtmlContent, t.span)
        }
        self.sink().push(Cdata(text, t.span))
        seen_content = true
      }
      Doctype(name, public_id, system_id, _) => {
        if seen_content {
          self.report(DoctypeNotFirst, t.span)
        }
        self.sink().push(Doctype({ name, public_id, system_id, span: t.span, }))
        seen_content = true
      }
      Bogus(kind, text) => {
        self.report(kind, t.span)
        self.sink().push(Bogus(@ast.Bogus::new(kind, t.span, text~)))
        seen_content = true
      }
    }
  }
  // Whatever is still open ran to the end of the input.
  while self.stack.length() > 0 {
    let f = self.stack[self.stack.length() - 1]
    self.report(UnclosedElement(f.name.name), f.name_span)
    self.pop(Unclosed, self.document_end())
  }
}

///|
fn Parser::document_end(self : Parser) -> Int {
  let n = self.toks.length()
  if n == 0 {
    0
  } else {
    self.toks[n - 1].span.end
  }
}

///|
fn is_blank(s : String) -> Bool {
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.unsafe_get(i).to_int().unsafe_to_char()
    if c != ' ' && c != '\t' && c != '\n' && c != '\r' && c != '\u{0C}' {
      return false
    }
    i = i + 1
  }
  true
}

// -------------------------------------------------------------------- tags

///|
fn Parser::start_tag(
  self : Parser,
  lowered : String,
  raw_attrs : Array[@token.RawAttr],
  self_closing : Bool,
  span : @span.Span,
) -> Unit raise @error.HtmlError {
  // An open element the table says this one closes. The loop rather than a
  // single check is what makes `<table><tr><td>a<tr>` put the second row
  // beside the first rather than inside the cell.
  while self.stack.length() > 0 {
    let top = self.stack[self.stack.length() - 1]
    if top.name.ns == Html && @names.implies_close(top.name.name, lowered) {
      self.pop(Implied, span.start)
    } else {
      break
    }
  }
  let name = self.tag_name(lowered)
  let attrs = self.attributes(raw_attrs, name.ns)
  let name_span = @span.Span::new(
    span.start + 1,
    span.start + 1 + lowered.length(),
  )
  let foreign = name.ns != Html
  if !foreign && @names.is_void(name.name) {
    let closing : @ast.Closing = if self_closing { SelfClosing } else { Void }
    self
    .sink()
    .push(Element({ name, attrs, children: [], closing, span, name_span, }))
    return
  }
  if foreign && self_closing {
    self
    .sink()
    .push(
      Element({
        name,
        attrs,
        children: [],
        closing: SelfClosing,
        span,
        name_span,
      }),
    )
    return
  }
  if !foreign && self_closing {
    // `<div/>` is a start tag: the `/` does nothing at all in HTML. Saying so
    // is worth a warning, because whoever wrote it believed otherwise.
    self.report(NonVoidSelfClosing(name.name), span)
  }
  if self.stack.length() >= MAX_DEPTH {
    self.report(
      Unexpected("markup nested less than " + MAX_DEPTH.to_string() + " deep"),
      span,
    )
    self
    .sink()
    .push(
      Bogus(@ast.Bogus::new(Unexpected("shallower nesting"), span, text="")),
    )
    return
  }
  self.stack.push({ name, attrs, children: [], start: span.start, name_span, })
}

///|
fn Parser::end_tag(
  self : Parser,
  lowered : String,
  span : @span.Span,
) -> Unit raise @error.HtmlError {
  if @names.is_void(lowered) && self.child_namespace() == Html {
    self.report(EndTagForVoid(lowered), span)
    return
  }
  match self.find_open(lowered) {
    None => {
      self.report(StrayEndTag(lowered), span)
      return
    }
    Some(target) => {
      // Everything above the match is closed on the way down: implicitly if
      // the table allows it, and with a diagnostic if it does not.
      while self.stack.length() - 1 > target {
        let top = self.stack[self.stack.length() - 1]
        if @names.auto_closes(top.name.name) {
          self.pop(Implied, span.start)
        } else {
          self.report(MismatchedEndTag(lowered, top.name.name), span)
          self.pop(Unclosed, span.start)
        }
      }
      self.pop(Explicit, span.end)
    }
  }
}

///|
/// The attributes of one tag, with names put back the way the vocabulary
/// spells them.
///
/// The tokenizer lowercases every name, which is right for HTML and wrong for
/// SVG. Restoring `viewBox` needs the namespace, which needs the element stack,
/// which is why it happens here and not there.
fn Parser::attributes(
  self : Parser,
  raw : Array[@token.RawAttr],
  ns : @ast.Namespace,
) -> Array[@ast.Attribute] {
  ignore(self)
  let out : Array[@ast.Attribute] = []
  for a in raw {
    let spelled = match ns {
      Html => a.name
      _ =>
        match @names.foreign_attr(a.name) {
          Some(cased) => cased
          None => a.name
        }
    }
    let value : @ast.AttrValue = match a.value {
      None => Empty
      Some(v) => Value(v, a.raw)
    }
    out.push({ name: split_prefix(spelled), value, span: a.span, })
  }
  out
}

///|
/// `xlink:href` as a prefix and a name.
///
/// The prefix is kept unresolved: resolving it needs the `xmlns` declarations
/// in scope, which is a document question and not a markup one. Splitting it at
/// all is what lets `AttrName::text` put it back exactly, colon included.
fn split_prefix(name : String) -> @ast.AttrName {
  let n = name.length()
  let mut i = 0
  while i < n {
    if name.unsafe_get(i).to_int() == 58 {
      if i > 0 && i + 1 < n {
        return {
          prefix: Some(name.clamped_view(start=0, end=i).to_owned()),
          name: name.clamped_view(start=i + 1, end=n).to_owned(),
        }
      }
      break
    }
    i = i + 1
  }
  { prefix: None, name, }
}
