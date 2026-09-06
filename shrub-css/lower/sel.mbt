///|
/// Selectors.
///
/// Two passes. The first splits on relation keywords, which is the only
/// structure a selector has; the second reads each run between them as one
/// compound. Juxtaposition inside a run is a compound and never a descendant --
/// shrubbery's tree does not record whitespace, so a space cannot mean
/// anything, and a relation has to be written.

///|
/// A rule's head as a selector list.
///
/// A `[a, b]` bracket at the head is the list. `is(a, b)` is NOT: `:is()` gives
/// every arm the specificity of its most specific member, so spelling a list
/// that way would silently change what the stylesheet matches. The bracket is
/// the list; `is()` stays the pseudo-class it already was.
fn Lowerer::selector_list(
  self : Lowerer,
  head : ArrayView[@sast.Node],
  at : @basic.Span,
) -> Array[@ast.Selector] raise @err.ShrubCssError {
  match head {
    [{ it: Brackets(gs), .. }] => {
      let out : Array[@ast.Selector] = []
      for g in gs {
        let items = match g.it {
          Group(xs) => xs[:]
          _ => one(g)
        }
        out.push(self.selector(items, g.span))
      }
      if out.length() == 0 {
        out.push(Bogus(self.bogus_at(BadSelector, at)))
      }
      out
    }
    _ => [self.selector(head, at)]
  }
}

///|
/// One selector.
fn Lowerer::selector(
  self : Lowerer,
  items : ArrayView[@sast.Node],
  at : @basic.Span,
) -> @ast.Selector raise @err.ShrubCssError {
  if items.length() == 0 {
    return Bogus(self.bogus_at(BadSelector, at))
  }
  // Split into runs separated by relation keywords.
  let runs : Array[ArrayView[@sast.Node]] = []
  let combs : Array[@ast.Combinator] = []
  let mut from = 0
  for i, n in items {
    match n.it {
      Kw(k) =>
        match @names.combinator_of(k) {
          Some(c) => {
            runs.push(items[from:i])
            combs.push(to_ast_combinator(c))
            from = i + 1
          }
          // Not a relation. Left for `compound`, which sees the same node
          // and has somewhere to put the `Bogus` -- reporting here too would
          // make one mistake into two complaints.
          None => ()
        }
      _ => ()
    }
  }
  runs.push(items[from:])
  // A leading empty run means the selector began with a relation, which a
  // nested rule may do: `~child first_child()`.
  let leading = runs.length() > 0 && runs[0].length() == 0 && combs.length() > 0
  let start = if leading { 1 } else { 0 }
  if runs[runs.length() - 1].length() == 0 {
    self.error(DanglingCombinator, span_of(items, at))
  }
  let mut acc : @ast.Selector? = None
  let mut ci = if leading { 1 } else { 0 }
  let mut ri = start
  while ri < runs.length() {
    let run = runs[ri]
    if run.length() == 0 {
      ri = ri + 1
      ci = ci + 1
      continue
    }
    let comp = self.compound(run, at)
    acc = match acc {
      None => Some(Simple(comp))
      Some(prev) => {
        let c = if ci - 1 < combs.length() && ci >= 1 {
          combs[ci - 1]
        } else {
          Descendant
        }
        Some(Complex(prev, c, comp))
      }
    }
    ri = ri + 1
    ci = ci + 1
  }
  let sel = match acc {
    Some(s) => s
    None => Bogus(self.bogus_at(BadSelector, at))
  }
  if leading {
    Relative(combs[0], sel)
  } else {
    sel
  }
}

///|
fn to_ast_combinator(c : @names.Combinator) -> @ast.Combinator {
  match c {
    Descendant => Descendant
    Child => Child
    NextSibling => NextSibling
    SubsequentSibling => SubsequentSibling
    Column => Column
  }
}

///|
/// One element's worth: a type selector and its qualifiers.
fn Lowerer::compound(
  self : Lowerer,
  items : ArrayView[@sast.Node],
  at : @basic.Span,
) -> @ast.Compound raise @err.ShrubCssError {
  let quals : Array[@ast.Qualifier] = []
  let mut type_sel : @ast.TypeSelector? = None
  let mut ns : @ast.NsPrefix? = None
  let mut i = 0
  while i < items.length() {
    let rest = items[i:]
    match as_call(rest) {
      Some((name, args, _)) => {
        i = i + 2
        match self.selector_call(name, args, items[i - 2], ns) {
          Type(t) => {
            if type_sel is Some(_) {
              self.error(TypeSelectorNotFirst, items[i - 2].span)
            }
            type_sel = Some(t)
            ns = None
          }
          // A namespace binds to its type selector, and the surface writes it
          // AFTER the name -- `circle ns(svg)` -- so when a type has already
          // been read the prefix is applied to it rather than left pending.
          Ns(p) =>
            match type_sel {
              Some(Named(_, n)) => type_sel = Some(Named(Some(p), n))
              Some(Universal(_)) => type_sel = Some(Universal(Some(p)))
              None => ns = Some(p)
            }
          Qual(q) => quals.push(q)
        }
        continue
      }
      None => ()
    }
    let n = items[i]
    match n.it {
      Id(name) =>
        // A bare identifier is a type selector, and only the first one can be:
        // two touching element names is the mistake a CSS habit produces, so
        // it gets its own diagnostic naming the relation.
        if has_bogus(quals) {
          // The compound is already broken and already reported. A second
          // complaint about the same run is noise.
          quals.push(Bogus(bogus_node(BadSelector, n)))
        } else if type_sel is Some(_) || quals.length() > 0 {
          // Unless the first name was an at-rule's. `@media screen:` parses
          // cleanly -- at-notation swallows the `@` and leaves `media screen`
          // behind -- so this is the only place the mistake can be caught, and
          // "an at-rule is a call" is the useful thing to say, not "these two
          // names touch".
          let kind : @kind.ErrorKind = if at_rule_head(type_sel) {
            SigilSelector("@")
          } else {
            TypeSelectorNotFirst
          }
          self.error(kind, n.span)
          quals.push(Bogus(bogus_node(kind, n)))
        } else {
          type_sel = Some(Named(ns, @names.unkebab(name)))
          ns = None
        }
      // CSS's own sigils, which this syntax does not use. Each gets the
      // sentence naming what to write instead.
      Op(".") => {
        quals.push(Bogus(self.bogus(SigilSelector("."), n)))
        // Swallow the name the sigil was attached to, so `.card` is one
        // complaint rather than a sigil complaint and then a stray-name one.
        match items[i + 1:] {
          [{ it: Id(_), .. }, ..] => i = i + 1
          _ => ()
        }
      }
      Op("&") => quals.push(Bogus(self.bogus(SigilSelector("&"), n)))
      Op("*") => quals.push(Bogus(self.bogus(SigilSelector("*"), n)))
      Op(">") => quals.push(Bogus(self.bogus(OperatorCombinator(">"), n)))
      Op("+") => quals.push(Bogus(self.bogus(OperatorCombinator("+"), n)))
      Op("::") =>
        // `::before` is legal shrubbery and was the second draft's spelling,
        // so it is worth naming precisely rather than as a stray operator.
        quals.push(Bogus(self.bogus(SigilSelector("::"), n)))
      Kw(k) => quals.push(Bogus(self.bogus(StrayKeyword(k), n)))
      Brackets(_) => quals.push(Bogus(self.bogus(SigilSelector("["), n)))
      _ => quals.push(Bogus(self.bogus(BadSelector, n)))
    }
    i = i + 1
  }
  // A namespace with nothing to qualify.
  match ns {
    Some(_) => if type_sel is None { self.error(BadSelector, at) }
    None => ()
  }
  { type_sel, quals, span: cspan(span_of(items, at)), }
}

///|
/// What a call in selector position turned out to be.
priv enum SelCall {
  Type(@ast.TypeSelector)
  Ns(@ast.NsPrefix)
  Qual(@ast.Qualifier)
}

///|
fn Lowerer::selector_call(
  self : Lowerer,
  name : String,
  args : ArrayView[@sast.Node],
  at : @sast.Node,
  ns : @ast.NsPrefix?,
) -> SelCall raise @err.ShrubCssError {
  match name {
    "any" => return Type(Universal(ns))
    "tag" =>
      match name_arg(args) {
        Some(n) => return Type(Named(ns, n))
        None => return Qual(Bogus(self.bogus(BadCallShape("tag"), at)))
      }
    "class" =>
      match name_arg(args) {
        Some(n) => return Qual(Class(n))
        None => return Qual(Bogus(self.bogus(BadCallShape("class"), at)))
      }
    "id" =>
      match name_arg(args) {
        Some(n) => return Qual(Id(n))
        None => return Qual(Bogus(self.bogus(BadCallShape("id"), at)))
      }
    "parent" => if args.length() == 0 { return Qual(Nesting) }
    "ns" =>
      if args.length() == 0 {
        return Ns(None_)
      } else {
        match args {
          [{ it: Group([{ it: Id("any"), .. }, { it: Parens([]), .. }]), .. }] =>
            return Ns(Any)
          _ =>
            match name_arg(args) {
              Some(n) => return Ns(Named(n))
              None => ()
            }
        }
      }
    "has_attr" => return Qual(self.attr_of(args, at))
    "element" => return Qual(self.element_of(args, at))
    _ => ()
  }
  let css_name = @names.unkebab(name)
  if @names.is_selector_pseudo(css_name) {
    let sels : Array[@ast.Selector] = []
    for g in args {
      let items = match g.it {
        Group(xs) => xs[:]
        _ => one(g)
      }
      sels.push(self.selector(items, g.span))
    }
    return Qual(Pseudo(Sub(css_name, sels)))
  }
  if @names.is_nth_pseudo(css_name) {
    return Qual(self.nth_of(css_name, args, at))
  }
  if css_name == "lang" {
    let langs : Array[String] = []
    for g in arg_groups(args) {
      match g {
        [{ it: Id(n), .. }] => langs.push(n)
        [{ it: Lit(Str(s)), .. }] => langs.push(s)
        _ => ()
      }
    }
    return Qual(Pseudo(Lang(langs)))
  }
  if css_name == "dir" {
    match name_arg(args) {
      Some(d) => return Qual(Pseudo(Dir(d)))
      None => ()
    }
  }
  if @names.is_simple_pseudo(css_name) && args.length() == 0 {
    return Qual(Pseudo(Simple(css_name)))
  }
  // Not a name any table knows. Kept as an unknown pseudo-class rather than
  // dropped, with a warning -- CSS grows selectors faster than this table does.
  self.error(UnknownSelectorCall(name), at.span)
  Qual(Pseudo(Unknown(css_name, self.comma_list(args))))
}

///|
/// `has_attr(type = "text")`, and the five other matchers.
fn Lowerer::attr_of(
  self : Lowerer,
  args : ArrayView[@sast.Node],
  at : @sast.Node,
) -> @ast.Qualifier raise @err.ShrubCssError {
  let gs = arg_groups(args)
  if gs.length() != 1 {
    return Bogus(self.bogus(BadCallShape("has_attr"), at))
  }
  let mut items = gs[0]
  // A leading `ns(...)` qualifies the attribute name.
  let mut ns : @ast.NsPrefix? = None
  match as_call(items) {
    Some((n, a, rest)) if n == "ns" =>
      match self.selector_call(n, a, at, None) {
        Ns(p) => {
          ns = Some(p)
          items = rest
        }
        _ => ()
      }
    _ => ()
  }
  // A trailing `~i` or `~s` flag.
  let mut case_ : @ast.AttrCase = Default
  if items.length() > 0 {
    match items[items.length() - 1].it {
      Kw("i") => {
        case_ = Insensitive
        items = items[0:items.length() - 1]
      }
      Kw("s") => {
        case_ = Sensitive
        items = items[0:items.length() - 1]
      }
      _ => ()
    }
  }
  let name = match items {
    [{ it: Id(n), .. }, ..] => @names.unkebab(n)
    [{ it: Lit(Str(s)), .. }, ..] => s
    _ => return Bogus(self.bogus(BadCallShape("has_attr"), at))
  }
  if items.length() == 1 {
    return Attr({ ns, name, matcher: None, case_, })
  }
  let op : @ast.AttrOp? = match items[1].it {
    Op("=") => Some(Exact)
    Op("~=") => Some(Includes)
    Op("|=") => Some(DashMatch)
    Op("^=") => Some(Prefix)
    Op("$=") => Some(Suffix)
    Op("*=") => Some(Substring)
    _ => None
  }
  match op {
    None => Bogus(self.bogus(BadCallShape("has_attr"), at))
    Some(o) =>
      match items[2:] {
        [{ it: Lit(Str(s)), .. }] =>
          Attr({ ns, name, matcher: Some((o, Str(s))), case_, })
        [{ it: Id(n), .. }] =>
          Attr({
            ns,
            name,
            matcher: Some((o, Ident(@names.unkebab(n)))),
            case_,
          })
        _ => Bogus(self.bogus(BadCallShape("has_attr"), at))
      }
  }
}

///|
/// `element(before)`, `element(part(x))`.
fn Lowerer::element_of(
  self : Lowerer,
  args : ArrayView[@sast.Node],
  at : @sast.Node,
) -> @ast.Qualifier raise @err.ShrubCssError {
  match name_arg(args) {
    Some(n) => return Element(Simple(n))
    None => ()
  }
  // A functional pseudo-element: `element(part(shadow_button))`.
  let gs = arg_groups(args)
  if gs.length() == 1 {
    match as_call(gs[0]) {
      Some((fname, fargs, _)) => {
        let css_name = @names.unkebab(fname)
        if @names.is_selector_pseudo(css_name) {
          let sels : Array[@ast.Selector] = []
          for g in fargs {
            let items = match g.it {
              Group(xs) => xs[:]
              _ => one(g)
            }
            sels.push(self.selector(items, g.span))
          }
          return Element(Sub(css_name, sels))
        }
        return Element(Fn(css_name, self.comma_list(fargs)))
      }
      None => ()
    }
  }
  Bogus(self.bogus(BadCallShape("element"), at))
}

///|
/// `nth_child(2 n + 1)`, with an optional `of` clause.
///
/// The formula is spelled with a space because `2n` is a lexical error in
/// shrubbery -- a number may not run into letters. This is the last place that
/// rule still shows, now that dimensions are calls.
fn Lowerer::nth_of(
  self : Lowerer,
  css_name : String,
  args : ArrayView[@sast.Node],
  at : @sast.Node,
) -> @ast.Qualifier raise @err.ShrubCssError {
  let gs = arg_groups(args)
  if gs.length() == 0 {
    return Bogus(self.bogus(BadCallShape(css_name), at))
  }
  let mut formula = gs[0]
  let mut of_ : Array[@ast.Selector]? = None
  // `of` splits the formula from the selector list that follows it.
  for i, n in formula {
    match n.it {
      Id("of") => {
        let sel_items = formula[i + 1:]
        if sel_items.length() > 0 {
          of_ = Some([self.selector(sel_items, n.span)])
        }
        formula = formula[0:i]
        break
      }
      _ => ()
    }
  }
  match parse_anb(formula) {
    Some(anb) => Pseudo(Nth(css_name, anb, of_))
    None => {
      self.error(BadAnB, at.span)
      Pseudo(Unknown(css_name, self.comma_list(args)))
    }
  }
}

///|
/// The `An+B` shapes, over shrubbery nodes.
fn parse_anb(items : ArrayView[@sast.Node]) -> @ast.AnB? {
  let ts : Array[@sast.Shrub] = []
  for n in items {
    ts.push(n.it)
  }
  match ts {
    [Id("odd")] => Some({ a: 2, b: 1, })
    [Id("even")] => Some({ a: 2, b: 0, })
    [Id("n")] => Some({ a: 1, b: 0, })
    [Lit(Int_(b))] => Some({ a: 0, b: int_of(b), })
    [Op("-"), Id("n")] => Some({ a: -1, b: 0, })
    [Lit(Int_(a)), Id("n")] => Some({ a: int_of(a), b: 0, })
    [Id("n"), Op(s), Lit(Int_(b))] => signed(1, s, b)
    [Op("-"), Id("n"), Op(s), Lit(Int_(b))] => signed(-1, s, b)
    [Lit(Int_(a)), Id("n"), Op(s), Lit(Int_(b))] => signed(int_of(a), s, b)
    _ => None
  }
}

///|
fn signed(a : Int, op : String, b : @bigint.BigInt) -> @ast.AnB? {
  match op {
    "+" => Some({ a, b: int_of(b), })
    "-" => Some({ a, b: -int_of(b), })
    _ => None
  }
}

///|
fn int_of(b : @bigint.BigInt) -> Int {
  @string.parse_int(b.to_string()) catch {
    _ => 0
  }
}

///|
/// Whether anything in this compound has already failed.
fn has_bogus(quals : Array[@ast.Qualifier]) -> Bool {
  for q in quals {
    if q is Bogus(_) {
      return true
    }
  }
  false
}

///|
/// Whether a type selector's name is an at-rule's.
fn at_rule_head(t : @ast.TypeSelector?) -> Bool {
  match t {
    Some(Named(_, n)) => @names.is_at_rule(n)
    _ => false
  }
}

///|
/// A `Bogus` at a span, for the case where there is no node to point at.
fn Lowerer::bogus_at(
  self : Lowerer,
  kind : @kind.ErrorKind,
  at : @basic.Span,
) -> @ast.Bogus raise @err.ShrubCssError {
  self.error(kind, at)
  @ast.Bogus::new(
    @csskind.ErrorKind::Unexpected(kind.code()),
    cspan(at),
    text="",
  )
}
