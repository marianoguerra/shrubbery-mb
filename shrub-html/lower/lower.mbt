///|
/// Shrubbery notation to a markup tree.
///
/// The surface syntax has three laws and this is where they are read back:
///
///   1. An element is a call; its children are its block.
///   2. Its attributes are its arguments; an attribute is a declaration.
///   3. Text is a string literal. Whitespace only ever exists inside one.
///
/// The third is the one that earns the design. Shrubbery's tree does not record
/// whitespace, so in this notation a space cannot mean anything unless it is
/// inside a string -- which means the indentation is free, and the whole of
/// HTML's whitespace-sensitivity problem does not arise. `"Read "` carries its
/// own trailing space; reindent the source however you like and the rendered
/// page is unchanged.
///
/// The lowering is a pure function of the shrubbery tree. It reads `Node.span`,
/// for diagnostics, and never `Node.meta`. That matters more than it looks:
/// because nothing depends on how the source was laid out, the lowering is
/// total over hand-built trees as well as parsed ones, which is what lets the
/// round-trip properties generate trees rather than text.
///
/// It never fails in the tolerant mode. Anything unreadable becomes a `Bogus`
/// carrying the reason, so a file with one mistake still lowers to a document
/// with everything else intact.

///|
/// A lowering: the tree, and everything noticed on the way.
pub struct Lowered {
  document : @ast.Document
  diagnostics : Array[@err.Diagnostic]
}

///|
pub fn Lowered::document(self : Lowered) -> @ast.Document {
  self.document
}

///|
pub fn Lowered::diagnostics(self : Lowered) -> Array[@err.Diagnostic] {
  self.diagnostics
}

///|
pub fn Lowered::has_errors(self : Lowered) -> Bool {
  for d in self.diagnostics {
    if d.is_error() {
      return true
    }
  }
  false
}

///|
/// What to do with the block of a raw-text element.
///
/// The obvious next thought after `style(): @{ ... }` is to let that body hold
/// shrubbery CSS -- and acting on it would make `marianoguerra/shrubbery-css` a
/// dependency of this module, which every consumer would then fetch whether
/// they wanted CSS or not. So the hook is a parameter instead: a caller that
/// already depends on both, such as the command-line tool, supplies one and
/// gets the composition; everyone else pays nothing.
///
/// The function is handed the element's name and the groups in its block, and
/// returns the raw text to put inside it, or `None` to fall back to the
/// ordinary reading.
pub type RawTextHook = (String, Array[@sast.Node]) -> String?

///|
priv struct Lowerer {
  diags : Array[@err.Diagnostic]
  strict : Bool
  hook : RawTextHook?
}

///|
/// Lower a parsed shrubbery tree.
pub fn lower(
  root : @sast.Node,
  strict? : Bool = false,
  hook? : RawTextHook? = None,
) -> Lowered raise @err.ShrubHtmlError {
  let l = { diags: [], strict, hook, }
  let groups = match root.it {
    Multi(gs) => gs
    // A bare group, which is what a fragment parses to.
    Group(_) => [root]
    _ => []
  }
  let children : Array[@ast.Node] = []
  for g in groups {
    for n in l.group(g, Html) {
      children.push(n)
    }
  }
  { document: { children, span: hspan(root.span), }, diagnostics: l.diags, }
}

///|
/// Parse shrubbery source and lower it in one step.
///
/// Shrubbery's own diagnostics come first and are converted, so a caller sees
/// one list rather than having to consult two. A source that does not parse
/// lowers to an empty document: there is no tree to lower, and inventing one
/// would put the bridge's guesses where the notation's answer should be.
pub fn lower_source(
  src : String,
  strict? : Bool = false,
  hook? : RawTextHook? = None,
) -> Lowered raise @err.ShrubHtmlError {
  let parsed = @shrub.parse(src, recover=true) catch {
    e => {
      let d = shrub_diagnostic(e.diagnostic(), src)
      if strict {
        d.raise_()
      }
      return {
        document: { children: [], span: @hspan.Span::new(0, src.length()), },
        diagnostics: [d],
      }
    }
  }
  let pre : Array[@err.Diagnostic] = []
  for d in parsed.diagnostics() {
    pre.push(shrub_diagnostic(d, src))
  }
  if strict && pre.length() > 0 {
    pre[0].raise_()
  }
  let out = lower(parsed.root(), strict~, hook~)
  let all : Array[@err.Diagnostic] = []
  for d in pre {
    all.push(d)
  }
  for d in out.diagnostics {
    all.push(d)
  }
  { document: out.document, diagnostics: all, }
}

// --------------------------------------------------------------- reporting

///|
fn Lowerer::report(
  self : Lowerer,
  kind : @kind.ErrorKind,
  n : @sast.Node,
) -> Unit raise @err.ShrubHtmlError {
  let d = @err.Diagnostic::of_kind(kind, n.span)
  if self.strict && d.is_error() {
    d.raise_()
  }
  self.diags.push(d)
}

///|
/// A node that could not be read, kept with the source it covered.
///
/// The markup layer's kinds and this one's are different sets, so the reason is
/// carried across as text. What the printer echoes is the shrubbery source,
/// which is the useful half anyway -- and echoing it is what keeps the tree
/// covering the whole file.
fn Lowerer::bogus(
  self : Lowerer,
  kind : @kind.ErrorKind,
  n : @sast.Node,
) -> @ast.Node raise @err.ShrubHtmlError {
  self.report(kind, n)
  Bogus(
    @ast.Bogus::new(
      @hkind.ErrorKind::Unexpected(kind.code()),
      hspan(n.span),
      text=n.to_source(),
    ),
  )
}

// ------------------------------------------------------------------ groups

///|
/// One group, as a run of children.
///
/// A group is a RUN, not a single node: `"a" br() "b"` is three children on one
/// line. The trailing block, if there is one, belongs to the LAST element in
/// the run -- which is what makes an element with children have to come last,
/// and what `TrailingRunAfterBlock` warns about when it does not.
fn Lowerer::group(
  self : Lowerer,
  g : @sast.Node,
  ns : @ast.Namespace,
) -> Array[@ast.Node] raise @err.ShrubHtmlError {
  let items = match g.it {
    Group(xs) => xs
    // A block's groups are groups; anything else here is a lone term, which
    // the run reader handles on its own.
    _ => [g]
  }
  let (head, block, has_alts) = split_block(items[:])
  if has_alts {
    return [self.bogus(AltsUnsupported, g)]
  }
  self.run(head, block, ns, g)
}

///|
/// A run of items, with an optional block for the last of them.
fn Lowerer::run(
  self : Lowerer,
  items : ArrayView[@sast.Node],
  block : @sast.Node?,
  ns : @ast.Namespace,
  whole : @sast.Node,
) -> Array[@ast.Node] raise @err.ShrubHtmlError {
  let out : Array[@ast.Node] = []
  let mut i = 0
  while i < items.length() {
    let rest = items[i:]
    match as_call(rest) {
      Some((name, args, after)) => {
        // The block belongs to the LAST call in the run, because shrubbery
        // puts a block at the end of its group and nowhere else. That is the
        // whole of the rule that an element with children has to come last.
        let mine = if after.length() == 0 { block } else { None }
        match mine {
          Some(b) =>
            if i > 0 &&
              rest[0].span.start.line == b.span.start.line &&
              block_run_length(b) >= 2 {
              // The trap. `p(): "Hello " strong(): "world" "!"` parses cleanly
              // and puts the `"!"` INSIDE the `strong`, because a block runs to
              // the end of its line. Nothing in the tree distinguishes that from
              // someone meaning it, so this is a warning rather than an error --
              // and it is reported at all only because the shape is so specific:
              // a same-line block, holding one group, holding a run of more than
              // one child, on a call that already had a sibling before it.
              self.report(TrailingRunAfterBlock, whole)
            }
          None => ()
        }
        out.push(self.call(name, args, mine, ns, rest[0], whole))
        i = i + 2
        continue
      }
      None => ()
    }
    let n = items[i]
    match n.it {
      Lit(Str(s)) =>
        out.push(Text({ text: s, raw: None, span: hspan(n.span), }))
      Lit(Int_(v)) =>
        out.push(Text({ text: v.to_string(), raw: None, span: hspan(n.span), }))
      Lit(Flo(v)) =>
        out.push(Text({ text: v.to_string(), raw: None, span: hspan(n.span), }))
      Id(name) => out.push(self.bogus(BareTermInBlock(name), n))
      Op(o) => out.push(self.bogus(SigilTag(o), n))
      Braces(_) => out.push(self.bogus(BracesUnsupported, n))
      Quotes(_) => out.push(self.bogus(BracesUnsupported, n))
      Block(_) => out.push(self.bogus(BlockOnNonElement, n))
      Kw(k) => out.push(self.bogus(Unsupported("`~" + k + "`"), n))
      _ => out.push(self.bogus(Unsupported("this"), n))
    }
    i = i + 1
  }
  // A block with nothing before it has nothing to be the children of.
  if out.length() == 0 && block is Some(b) {
    out.push(self.bogus(BlockOnNonElement, b))
  }
  out
}

// ------------------------------------------------------------------- calls

///|
/// A `name(...)` call, with the block that follows it if it has one.
fn Lowerer::call(
  self : Lowerer,
  raw_name : String,
  args : ArrayView[@sast.Node],
  block : @sast.Node?,
  ns : @ast.Namespace,
  at : @sast.Node,
  whole : @sast.Node,
) -> @ast.Node raise @err.ShrubHtmlError {
  match raw_name {
    "text" =>
      match literal_string(args) {
        Some(s) => return Text({ text: s, raw: None, span: hspan(at.span), })
        None => return self.bogus(BadEscapeCall("text"), at)
      }
    "raw" =>
      match literal_string(args) {
        Some(s) => return RawText({ text: s, span: hspan(at.span), })
        None => return self.bogus(BadEscapeCall("raw"), at)
      }
    "cdata" =>
      match literal_string(args) {
        Some(s) => return Cdata(s, hspan(at.span))
        None => return self.bogus(BadEscapeCall("cdata"), at)
      }
    "comment" =>
      match literal_string(args) {
        Some(s) => return Comment({ text: s, span: hspan(at.span), })
        None => return self.bogus(BadEscapeCall("comment"), at)
      }
    "doctype" => return self.doctype(args, at)
    "element" =>
      match literal_string(args) {
        Some(s) => return self.element(s, [], block, ns, at, whole)
        None => return self.bogus(BadEscapeCall("element"), at)
      }
    "attr" | "frag" | "bogus" => return self.bogus(ReservedCall(raw_name), at)
    _ => ()
  }
  self.element(@names.unkebab(raw_name), args, block, ns, at, whole)
}

///|
/// `doctype()`, and the legacy form with its identifiers.
fn Lowerer::doctype(
  self : Lowerer,
  args : ArrayView[@sast.Node],
  at : @sast.Node,
) -> @ast.Node raise @err.ShrubHtmlError {
  if args.length() == 0 {
    return Doctype({
      name: "html",
      public_id: None,
      system_id: None,
      span: hspan(at.span),
    })
  }
  match literal_string(args) {
    Some(name) =>
      Doctype({ name, public_id: None, system_id: None, span: hspan(at.span), })
    None =>
      match literal_pair(args) {
        Some((public_id, system_id)) =>
          Doctype({
            name: "html",
            public_id: Some(public_id),
            system_id: Some(system_id),
            span: hspan(at.span),
          })
        None => self.bogus(BadEscapeCall("doctype"), at)
      }
  }
}

///|
/// An element, its attributes, and its children.
fn Lowerer::element(
  self : Lowerer,
  name : String,
  args : ArrayView[@sast.Node],
  block : @sast.Node?,
  parent_ns : @ast.Namespace,
  at : @sast.Node,
  whole : @sast.Node,
) -> @ast.Node raise @err.ShrubHtmlError {
  ignore(whole)
  let ns = namespace_of(name, parent_ns)
  let tag : @ast.TagName = { ns, name: spelled(name, ns), }
  let attrs = self.attributes(args, ns)
  let span = hspan(at.span)
  let is_void = ns == Html && @hnames.is_void(tag.name)
  match block {
    None => {
      let closing : @ast.Closing = if is_void {
        Void
      } else if ns == Html {
        Explicit
      } else {
        // In foreign content an element with no children closes itself, which
        // is what `<circle/>` means and what makes it round-trip.
        SelfClosing
      }
      Element({
        name: tag,
        attrs,
        children: [],
        closing,
        span,
        name_span: span,
      })
    }
    Some(b) => {
      if is_void {
        self.report(ChildrenOnVoid(tag.name), b)
        return Element({
          name: tag,
          attrs,
          children: [],
          closing: Void,
          span,
          name_span: span,
        })
      }
      let children = self.children(tag, b, child_namespace(tag))
      Element({
        name: tag,
        attrs,
        children,
        closing: Explicit,
        span,
        name_span: span,
      })
    }
  }
}

///|
/// The contents of an element's block.
///
/// Raw text is decided here, by the element's name, exactly as the markup
/// tokenizer decides it: inside a `script` or a `style` the body is text and
/// not markup, so an `@{...}` becomes one `RawText` node rather than a run of
/// children.
fn Lowerer::children(
  self : Lowerer,
  tag : @ast.TagName,
  block : @sast.Node,
  ns : @ast.Namespace,
) -> Array[@ast.Node] raise @err.ShrubHtmlError {
  let groups = block_groups(block)
  let raw = tag.ns == Html && @hnames.is_raw_text(tag.name)
  if raw {
    match self.hook {
      Some(f) =>
        match f(tag.name, groups) {
          Some(text) => return [RawText({ text, span: hspan(block.span), })]
          None => ()
        }
      None => ()
    }
  }
  let out : Array[@ast.Node] = []
  for g in groups {
    // `@{...}` is one text block, whatever else the group holds.
    match at_text_of(g) {
      Some(text) => {
        if raw {
          out.push(RawText({ text, span: hspan(g.span), }))
        } else {
          out.push(Text({ text, raw: None, span: hspan(g.span), }))
        }
        continue
      }
      None => ()
    }
    for n in self.group(g, ns) {
      if raw {
        // Everything inside a raw-text element is text, so a nested call is
        // not an element -- it is a name someone wrote inside a script.
        match n {
          Text(t) => out.push(RawText({ text: t.text, span: t.span, }))
          other => out.push(other)
        }
      } else {
        out.push(n)
      }
    }
  }
  out
}

///|
/// How many children the single group in a block would produce.
///
/// A shrubbery-level count rather than a lowered one, because the answer is
/// needed before the block is lowered: a call is two nodes and everything else
/// is one. Zero for a block that is not exactly one group, which is the shape
/// this question is about.
fn block_run_length(b : @sast.Node) -> Int {
  let gs = block_groups(b)
  if gs.length() != 1 {
    return 0
  }
  let items = match gs[0].it {
    Group(xs) => xs
    _ => return 0
  }
  let (head, _, _) = split_block(items[:])
  let mut count = 0
  let mut i = 0
  while i < head.length() {
    if as_call(head[i:]) is Some(_) {
      i = i + 2
    } else {
      i = i + 1
    }
    count = count + 1
  }
  count
}

///|
/// A group that is nothing but an `@{...}` body.
fn at_text_of(g : @sast.Node) -> String? {
  let items = match g.it {
    Group(xs) => xs
    _ => return None
  }
  if items.length() != 1 {
    return None
  }
  as_at_text(items[0])
}

// -------------------------------------------------------------- attributes

///|
/// A call's arguments, as attributes.
///
/// An attribute is a declaration -- `class: "card"` -- which is the same
/// shrubbery shape a CSS declaration already uses, and a bare name is a
/// valueless attribute, which is the same thing HTML writes.
fn Lowerer::attributes(
  self : Lowerer,
  args : ArrayView[@sast.Node],
  ns : @ast.Namespace,
) -> Array[@ast.Attribute] raise @err.ShrubHtmlError {
  let out : Array[@ast.Attribute] = []
  for arg in args {
    let items = match arg.it {
      Group(xs) => xs
      _ => {
        self.report(AttrNotDeclaration, arg)
        continue
      }
    }
    let (head, block, _) = split_block(items[:])
    // `attr("xlink:href", "#a")`, the escape for a name with no bare spelling.
    match as_call(head) {
      Some(("attr", inner, after)) =>
        if after.length() == 0 && block is None {
          match literal_pair(inner) {
            Some((name, value)) => {
              out.push({
                name: split_prefix(name),
                value: Value(value, None),
                span: hspan(arg.span),
              })
              continue
            }
            None =>
              match literal_string(inner) {
                Some(name) => {
                  out.push({
                    name: split_prefix(name),
                    value: Empty,
                    span: hspan(arg.span),
                  })
                  continue
                }
                None => {
                  self.report(BadEscapeCall("attr"), arg)
                  continue
                }
              }
          }
        }
      _ => ()
    }
    if head.length() != 1 {
      self.report(AttrNotDeclaration, arg)
      continue
    }
    let name = match head[0].it {
      Id(n) => spelled_attr(@names.unkebab(n), ns)
      _ => {
        self.report(AttrNotDeclaration, arg)
        continue
      }
    }
    match block {
      None =>
        out.push({
          name: split_prefix(name),
          value: Empty,
          span: hspan(arg.span),
        })
      Some(b) =>
        match self.attr_value(b) {
          Some(v) =>
            out.push({
              name: split_prefix(name),
              value: Value(v, None),
              span: hspan(arg.span),
            })
          None => {
            self.report(BadAttrValue, b)
            out.push({
              name: split_prefix(name),
              value: Value("", None),
              span: hspan(arg.span),
            })
          }
        }
    }
  }
  out
}

///|
/// The text of an attribute's value.
///
/// A string literal is itself; a number is its digits; a bare name is its own
/// text, so that `type: submit` and `type: "submit"` agree. Anything else is a
/// diagnostic rather than a guess: an attribute value is a string in the source
/// and there is nothing for a compound expression to mean.
fn Lowerer::attr_value(self : Lowerer, block : @sast.Node) -> String? {
  ignore(self)
  let groups = block_groups(block)
  if groups.length() != 1 {
    return None
  }
  let items = match groups[0].it {
    Group(xs) => xs
    _ => return None
  }
  if items.length() != 1 {
    return None
  }
  match items[0].it {
    Lit(Str(s)) => Some(s)
    Lit(Int_(v)) => Some(v.to_string())
    Lit(Flo(v)) => Some(v.to_string())
    Id(n) => Some(@names.unkebab(n))
    _ => None
  }
}

// -------------------------------------------------------------- namespaces

///|
/// Which vocabulary an element's name is drawn from.
///
/// The namespace follows the element, exactly as it does in HTML: `svg()` and
/// `math()` enter one, and an HTML integration point leaves it. So the notation
/// needs no keyword for it at all -- writing the element is writing the
/// namespace.
fn namespace_of(name : String, parent : @ast.Namespace) -> @ast.Namespace {
  match parent {
    Html =>
      if name == "svg" {
        Svg
      } else if name == "math" {
        MathMl
      } else {
        Html
      }
    // Inside foreign content every name is foreign, INCLUDING an integration
    // point: `foreignObject` is an SVG element. What is HTML again is its
    // CHILDREN, which is a question `child_namespace` answers.
    other => other
  }
}

///|
/// The namespace an element's children belong to.
///
/// The one place the integration points matter, and getting it wrong is silent:
/// a `<br>` inside a `<foreignObject>` would stop being void and start closing
/// itself, and nothing but the printed output would say so.
fn child_namespace(tag : @ast.TagName) -> @ast.Namespace {
  match tag.ns {
    Html => Html
    other =>
      if @hnames.is_integration_point(tag.name.to_lower()) {
        Html
      } else {
        other
      }
  }
}

///|
/// A name as its vocabulary spells it.
fn spelled(name : String, ns : @ast.Namespace) -> String {
  match ns {
    Svg =>
      match @hnames.svg_tag(name.to_lower()) {
        Some(cased) => cased
        None => name
      }
    _ => name
  }
}

///|
/// An attribute name as its vocabulary spells it.
fn spelled_attr(name : String, ns : @ast.Namespace) -> String {
  match ns {
    Html => name
    _ =>
      match @hnames.foreign_attr(name.to_lower()) {
        Some(cased) => cased
        None => name
      }
  }
}

///|
/// `xlink:href` as a prefix and a name.
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

// ------------------------------------------------------------------ spans

///|
fn hspan(s : @basic.Span) -> @hspan.Span {
  @hspan.Span::new(s.start.idx, s.end.idx)
}

///|
/// A shrubbery diagnostic, carried across with markup-specific help attached.
///
/// An HTML author's first mistake is to write HTML, and shrubbery rejects `<`
/// before this layer sees a tree at all. So the enrichment happens here, on the
/// way past: the original span is kept, and what is added is the sentence
/// naming the thing to type instead.
fn shrub_diagnostic(d : @shrub_err.Diagnostic, src : String) -> @err.Diagnostic {
  let text = slice(src, d.span.start.idx, d.span.end.idx)
  @err.Diagnostic::new(lexical_hint(text), d.span)
}

///|
fn lexical_hint(text : String) -> @kind.ErrorKind {
  if text.has_prefix("</") {
    SigilTag("</")
  } else if text.has_prefix("<") {
    SigilTag("<")
  } else if text.has_prefix("&") {
    SigilTag("&")
  } else {
    Unsupported("`" + text + "`")
  }
}

///|
fn slice(src : String, from : Int, to : Int) -> String {
  let a = if from < 0 { 0 } else { from }
  let b = if to < a { a } else { to }
  src.clamped_view(start=a, end=b).to_owned()
}
