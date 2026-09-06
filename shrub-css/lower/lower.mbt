///|
/// Shrubbery notation to a CSS syntax tree.
///
/// The surface syntax has one rule -- write the thing's name, not a symbol for
/// it -- and this is where that rule is read back. A call is a thing, a `~name`
/// keyword is a relation, and everything else is what shrubbery already made of
/// it.
///
/// The lowering is a pure function of the shrubbery tree. It reads `Node.span`,
/// for diagnostics, and never `Node.meta`. That matters more than it looks:
/// because nothing depends on how the source was laid out, the lowering is
/// total over hand-built trees as well as parsed ones, which is what lets the
/// round-trip properties generate trees rather than text.
///
/// It never fails in the tolerant mode. Anything unreadable becomes a `Bogus`
/// carrying the reason, so a file with one mistake still lowers to a stylesheet
/// with everything else intact.

///|
/// A lowering: the tree, and everything noticed on the way.
pub struct Lowered {
  sheet : @ast.Stylesheet
  diagnostics : Array[@err.Diagnostic]
}

///|
pub fn Lowered::sheet(self : Lowered) -> @ast.Stylesheet {
  self.sheet
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
priv struct Lowerer {
  diags : Array[@err.Diagnostic]
  strict : Bool
}

///|
/// Where a group sits, which decides what it may be.
///
/// The distinction is load-bearing and is the first level of the rule/
/// declaration cascade: at the top of a file a `Group` with a block is always a
/// rule, because CSS has no declarations outside rules; inside `font_face()` it
/// is always a declaration, because that at-rule has no nested rules. Most of a
/// real file is settled here, before any head-shape guessing happens at all.
priv enum Ctx {
  /// The top of the file.
  Top
  /// The body of a style rule: declarations and nested rules interleave.
  Nested
  /// `font_face()`, `page()`, `property()`, a keyframe: declarations only.
  DeclOnly
}

///|
/// Lower a parsed shrubbery tree.
pub fn lower(
  root : @sast.Node,
  strict? : Bool = false,
) -> Lowered raise @err.ShrubCssError {
  let l = { diags: [], strict, }
  let items : Array[@ast.TopItem] = []
  let groups = match root.it {
    Multi(gs) => gs
    // A bare group, which is what a fragment parses to.
    Group(_) => [root]
    _ => []
  }
  for g in groups {
    match l.statement(g, Top) {
      Some(r) => items.push(Rule(r))
      None => ()
    }
  }
  { sheet: { items, span: cspan(root.span), }, diagnostics: l.diags, }
}

///|
/// Parse shrubbery source and lower it in one step.
///
/// Shrubbery's own diagnostics come first and are converted, so a caller sees
/// one list rather than having to consult two. A source that does not parse
/// lowers to an empty stylesheet: there is no tree to lower, and inventing one
/// would put the bridge's guesses where the notation's answer should be.
pub fn lower_source(
  src : String,
  strict? : Bool = false,
) -> Lowered raise @err.ShrubCssError {
  let parsed = @shrub.parse(src, recover=true) catch {
    e => {
      let d = shrub_diagnostic(e.diagnostic(), src)
      if strict {
        d.raise_()
      }
      return {
        sheet: { items: [], span: @cspan.Span::new(0, src.length()), },
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
  let out = lower(parsed.root(), strict~)
  let all : Array[@err.Diagnostic] = []
  for d in pre {
    all.push(d)
  }
  for d in out.diagnostics {
    all.push(d)
  }
  { sheet: out.sheet, diagnostics: all, }
}

// -------------------------------------------------------------- statements

///|
/// One group, in a context that says what it may be.
fn Lowerer::statement(
  self : Lowerer,
  g : @sast.Node,
  ctx : Ctx,
) -> @ast.CssRule? raise @err.ShrubCssError {
  let items = match g.it {
    Group(xs) => xs
    _ => return Some(self.bogus_rule(BadSelector, g))
  }
  let (head, block, has_alts) = split_block(items[:])
  if has_alts {
    return Some(self.bogus_rule(AltsUnsupported, g))
  }
  if head.length() == 0 {
    return Some(self.bogus_rule(HeadlessBlock, g))
  }
  // An at-rule is recognised only in statement position, only as `name(...)`,
  // and only for a name in the table -- so a type selector called `media` is
  // merely unspellable rather than silently reinterpreted. `tag(media)` is the
  // way out.
  match as_call(head) {
    Some((name, args, rest)) =>
      if rest.length() == 0 && @names.is_at_rule(@names.unkebab(name)) {
        return self.at_rule(g, @names.unkebab(name), args, block, ctx)
      }
    None => ()
  }
  match block {
    None => Some(self.bogus_rule(ExpectedBlock, g))
    Some(b) =>
      if is_declaration(head, b, ctx) {
        // A declaration is not a rule; the caller that wanted one gets nothing
        // and a diagnostic saying why.
        match ctx {
          Top => {
            self.error(DeclarationAtTopLevel, g.span)
            Some(self.bogus_rule(DeclarationAtTopLevel, g))
          }
          _ => None
        }
      } else {
        match ctx {
          DeclOnly => {
            self.error(RuleInDeclarationContext, g.span)
            Some(self.bogus_rule(RuleInDeclarationContext, g))
          }
          _ => {
            let selectors = self.selector_list(head, g.span)
            let body = self.block_items(b, Nested)
            Some(Style({ selectors, body, span: cspan(g.span), }))
          }
        }
      }
  }
}

///|
/// The rule-versus-declaration cascade, level two and three.
///
/// Level one was the context, already applied by the caller. What is left:
///
///   * head shape -- a declaration head is a lone identifier, a `--custom`
///     property, or the `ident("literal")` escape, and nothing else;
///   * block shape -- for a lone identifier only, a value is one group with no
///     block of its own, while a rule body always contains a group that has
///     one.
///
/// The residue is exactly `a: hover`: a lone identifier over a block of one
/// bare word. It is read as a declaration, which is what CSS would say, and
/// `colon_pseudo` fires so the reader is told rather than surprised.
fn is_declaration(
  head : ArrayView[@sast.Node],
  block : @sast.Node,
  ctx : Ctx,
) -> Bool {
  match ctx {
    Top => return false
    DeclOnly => return true
    Nested => ()
  }
  if as_dashed(head) is Some(_) {
    return true
  }
  match as_call(head) {
    Some((name, args, rest)) =>
      if name == "ident" &&
        rest.length() == 0 &&
        literal_string(args) is Some(_) {
        return true
      }
    None => ()
  }
  match head {
    [{ it: Id(_), .. }] => block_is_value(block)
    _ => false
  }
}

///|
/// Whether a block holds one value rather than a rule body.
fn block_is_value(block : @sast.Node) -> Bool {
  match block.it {
    Block(gs) => gs.length() == 1 && !group_has_block(gs[0])
    _ => false
  }
}

///|
fn group_has_block(g : @sast.Node) -> Bool {
  match g.it {
    Group(xs) => {
      for x in xs {
        match x.it {
          Block(_) | Alts(_) => return true
          _ => ()
        }
      }
      false
    }
    _ => false
  }
}

///|
/// The contents of a block, as declarations and nested rules in source order.
fn Lowerer::block_items(
  self : Lowerer,
  block : @sast.Node,
  ctx : Ctx,
) -> Array[@ast.BlockItem] raise @err.ShrubCssError {
  let out : Array[@ast.BlockItem] = []
  let groups = match block.it {
    Block(gs) => gs
    _ => return out
  }
  for g in groups {
    let items = match g.it {
      Group(xs) => xs
      _ => {
        out.push(Bogus(self.bogus(BadSelector, g)))
        continue
      }
    }
    let (head, blk, has_alts) = split_block(items[:])
    if has_alts {
      out.push(Bogus(self.bogus(AltsUnsupported, g)))
      continue
    }
    match blk {
      None => {
        // A bare term: not a declaration, not a rule. When it names a
        // pseudo-class it is the `a: hover` mistake wearing its top-level
        // spelling, so it gets that diagnostic rather than a vaguer one.
        let what = describe_head(head)
        let css_what = @names.unkebab(what)
        let kind : @kind.ErrorKind = if @names.is_simple_pseudo(css_what) ||
          @names.is_pseudo_element(css_what) {
          ColonPseudo("", css_what)
        } else {
          BareTermInBlock(what)
        }
        self.error(kind, g.span)
        out.push(Bogus(bogus_node(kind, g)))
      }
      Some(b) =>
        if is_declaration(head, b, ctx) {
          match self.declaration(g, head, b) {
            Some(d) => out.push(Decl(d))
            None => ()
          }
        } else {
          match self.statement(g, ctx) {
            Some(r) => out.push(Rule(r))
            None => ()
          }
        }
    }
  }
  out
}

///|
/// A declaration block: the same, but a nested rule is an error rather than a
/// possibility.
fn Lowerer::decl_block(
  self : Lowerer,
  block : @sast.Node,
) -> @ast.DeclBlock raise @err.ShrubCssError {
  { decls: self.block_items(block, DeclOnly), span: cspan(block.span), }
}

// ------------------------------------------------------------ declarations

///|
fn Lowerer::declaration(
  self : Lowerer,
  g : @sast.Node,
  head : ArrayView[@sast.Node],
  block : @sast.Node,
) -> @ast.Declaration? raise @err.ShrubCssError {
  let property : @ast.PropertyName = match as_dashed(head) {
    Some(name) => Custom(name)
    None =>
      match as_call(head) {
        Some((name, args, _)) if name == "ident" =>
          match literal_string(args) {
            Some(s) => Ident(s)
            None => Ident("")
          }
        _ =>
          match head {
            [{ it: Id(n), .. }] => {
              // The one place a CSS habit produces a wrong tree rather than an
              // error: `a: hover` is structurally a declaration and reads as
              // one. Saying so is the whole point of the diagnostic.
              self.warn_colon_pseudo(n, block, g)
              Ident(@names.unkebab(n))
            }
            _ => Ident("")
          }
      }
  }
  let groups = match block.it {
    Block(gs) => gs
    _ => []
  }
  if groups.length() > 1 {
    // `;` after a value puts the next declaration INSIDE this one's block.
    self.error(SemicolonDeclarations, groups[1].span)
  }
  if groups.length() == 0 {
    return None
  }
  let (value, important) = self.value_of(groups[0])
  Some({ property, value, important, span: cspan(g.span), })
}

///|
/// `a: hover`, guarded so that `cursor: default` stays quiet.
///
/// The guard is what makes the check usable: `default`, `link`, `first` and
/// `left` are all pseudo-class names AND ordinary CSS values, so firing on the
/// value alone would cry wolf on every third stylesheet. Requiring the property
/// to be one CSS does not have is what narrows it to the real mistake.
fn Lowerer::warn_colon_pseudo(
  self : Lowerer,
  property : String,
  block : @sast.Node,
  g : @sast.Node,
) -> Unit {
  if is_known_property(@names.unkebab(property)) {
    return
  }
  match block.it {
    Block([{ it: Group([{ it: Id(v), .. }]), .. }]) => {
      let css_v = @names.unkebab(v)
      if @names.is_simple_pseudo(css_v) || @names.is_pseudo_element(css_v) {
        self.diags.push(
          @err.Diagnostic::new(ColonPseudo(property, css_v), g.span),
        )
      }
    }
    _ => ()
  }
}

// --------------------------------------------------------------- mechanics

///|
fn Lowerer::error(
  self : Lowerer,
  kind : @kind.ErrorKind,
  span : @basic.Span,
) -> Unit raise @err.ShrubCssError {
  let d = @err.Diagnostic::new(kind, span)
  self.diags.push(d)
  if self.strict {
    d.raise_()
  }
}

///|
/// A `Bogus` node, with its diagnostic recorded.
fn Lowerer::bogus(
  self : Lowerer,
  kind : @kind.ErrorKind,
  n : @sast.Node,
) -> @ast.Bogus raise @err.ShrubCssError {
  self.error(kind, n.span)
  bogus_node(kind, n)
}

///|
/// A `Bogus` node whose diagnostic the caller has already recorded.
fn bogus_node(kind : @kind.ErrorKind, n : @sast.Node) -> @ast.Bogus {
  // The CSS layer's kinds and this one's are different sets, so the reason is
  // carried across as text. What the printer echoes is the shrubbery source,
  // which is the useful half anyway.
  @ast.Bogus::new(
    @csskind.ErrorKind::Unexpected(kind.code()),
    cspan(n.span),
    text=n.to_source(),
  )
}

///|
fn Lowerer::bogus_rule(
  self : Lowerer,
  kind : @kind.ErrorKind,
  n : @sast.Node,
) -> @ast.CssRule raise @err.ShrubCssError {
  Bogus(self.bogus(kind, n))
}

///|
/// A shrubbery span as a CSS one. Both are UTF-16 code unit offsets, so this
/// reads a field rather than converting anything.
fn cspan(s : @basic.Span) -> @cspan.Span {
  @cspan.Span::new(s.start.idx, s.end.idx)
}

///|
/// A shrubbery diagnostic, carried across with CSS-specific help attached.
///
/// A CSS author's first mistakes are all lexical -- `10px`, `#fff`, `@media` --
/// and shrubbery rejects each of them before this layer sees a tree at all. So
/// the enrichment happens here, on the way past: the original kind and span are
/// kept, and what is added is the sentence naming the thing to type instead.
fn shrub_diagnostic(d : @shrub_err.Diagnostic, src : String) -> @err.Diagnostic {
  let text = slice(src, d.span.start.idx, d.span.end.idx)
  @err.Diagnostic::new(lexical_hint(text), d.span)
}

///|
/// What a rejected run of source most likely meant.
fn lexical_hint(text : String) -> @kind.ErrorKind {
  if text.has_prefix("#") {
    SigilSelector("#")
  } else if text.has_prefix("@") {
    SigilSelector("@")
  } else if text == "~" {
    OperatorCombinator("~")
  } else if looks_dimension(text) {
    Unsupported("`" + text + "`: a CSS dimension is a call, like `px(10)`")
  } else {
    Unsupported("`" + text + "`")
  }
}

///|
/// `10px`, `2n` -- a number run into letters, which shrubbery rejects.
fn looks_dimension(text : String) -> Bool {
  if text.length() == 0 {
    return false
  }
  let mut seen_digit = false
  let mut seen_alpha = false
  for c in text {
    if c >= '0' && c <= '9' {
      if seen_alpha {
        return false
      }
      seen_digit = true
    } else if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '%' {
      if !seen_digit {
        return false
      }
      seen_alpha = true
    } else if c != '.' {
      return false
    }
  }
  seen_digit && seen_alpha
}

///|
fn slice(src : String, from : Int, to : Int) -> String {
  let a = if from < 0 { 0 } else { from }
  let b = if to < a { a } else { to }
  src.clamped_view(start=a, end=b).to_owned()
}

///|
/// A short name for what a head looks like, for a diagnostic to quote.
fn describe_head(head : ArrayView[@sast.Node]) -> String {
  match head {
    [{ it: Id(n), .. }, ..] => n
    [{ it: Kw(k), .. }, ..] => "~" + k
    [{ it: Op(o), .. }, ..] => o
    _ => "this"
  }
}

///|
/// Whether CSS has a property by this name.
///
/// Advisory, and short on purpose: it exists only to keep `colon_pseudo` from
/// firing on `cursor: default`, so it needs the properties whose values collide
/// with pseudo-class names, not all of them. Missing a property makes a
/// diagnostic slightly more eager, never wrong.
fn is_known_property(name : String) -> Bool {
  match name {
    "cursor" | "display" | "position" | "float" | "clear" | "color" => true
    "content" | "visibility" | "overflow" | "direction" | "resize" => true
    "all" | "appearance" | "user-select" | "pointer-events" => true
    "text-align" | "vertical-align" | "white-space" | "word-break" => true
    _ => name.has_prefix("--")
  }
}
