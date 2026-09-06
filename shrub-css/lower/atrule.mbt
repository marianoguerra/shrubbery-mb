///|
/// At-rules.
///
/// An at-rule is a call whose name is in the table, in statement position. It
/// is recognised only there and only in that shape, so a type selector that
/// happens to be called `media` is merely unspellable rather than silently
/// reinterpreted -- `tag(media)` is the way out.

///|
fn Lowerer::at_rule(
  self : Lowerer,
  g : @sast.Node,
  name : String,
  args : ArrayView[@sast.Node],
  block : @sast.Node?,
  ctx : Ctx,
) -> @ast.CssRule? raise @err.ShrubCssError {
  let span = cspan(g.span)
  // The inner context of a conditional group is the one it sits in: `media()`
  // at the top of a file holds rules, and nested inside a rule it holds
  // declarations too. Getting this wrong is the easiest mistake in the whole
  // lowering, so it is named once here.
  let inner = match ctx {
    Top => Ctx::Top
    _ => Ctx::Nested
  }
  match (name, block) {
    ("media", Some(b)) =>
      Some(
        Media({
          queries: self.media_list(args),
          body: self.block_items(b, inner),
          span,
        }),
      )
    ("supports", Some(b)) =>
      Some(
        Supports({
          condition: self.condition(args, g.span),
          body: self.block_items(b, inner),
          span,
        }),
      )
    ("container", Some(b)) => {
      let (cname, rest) = split_container(args)
      Some(
        Container({
          name: cname,
          condition: self.condition(rest, g.span),
          body: self.block_items(b, inner),
          span,
        }),
      )
    }
    ("keyframes", Some(b)) => {
      let kname : @ast.KeyframesName = match name_arg(args) {
        Some(n) => Ident(n)
        None => {
          self.error(BadCallShape("keyframes"), g.span)
          Ident("")
        }
      }
      Some(Keyframes({ name: kname, frames: self.frames(b), span, }))
    }
    ("font-face", Some(b)) => Some(FontFace(self.decl_block(b)))
    ("counter-style", Some(b)) =>
      Some(CounterStyle(name_arg(args).unwrap_or(""), self.decl_block(b)))
    ("property", Some(b)) => {
      let pname = match as_dashed(args_items(args)) {
        Some(n) => n
        None => name_arg(args).unwrap_or("")
      }
      Some(Property({ name: pname, decls: self.decl_block(b), span, }))
    }
    ("page", Some(b)) =>
      Some(
        Page({
          selectors: page_selectors(args),
          body: self.block_items(b, DeclOnly),
          span,
        }),
      )
    ("starting-style", Some(b)) =>
      Some(StartingStyle(self.block_items(b, inner), span))
    ("scope", Some(b)) => {
      let (s, e) = self.scope_parts(args, g.span)
      Some(Scope({ start: s, end: e, body: self.block_items(b, inner), span, }))
    }
    ("layer", Some(b)) =>
      Some(
        Layer({
          names: layer_names(args),
          body: Some(self.block_items(b, inner)),
          span,
        }),
      )
    ("layer", None) =>
      Some(Layer({ names: layer_names(args), body: None, span, }))
    ("charset", None) =>
      match literal_string(args) {
        Some(s) => Some(Charset(s, span))
        None => {
          self.error(BadCallShape("charset"), g.span)
          Some(self.bogus_rule(BadCallShape("charset"), g))
        }
      }
    ("namespace", None) => {
      let gs = arg_groups(args)
      match gs.length() {
        1 =>
          match gs[0] {
            [{ it: Lit(Str(u)), .. }] =>
              Some(Namespace({ prefix: None, url: u, span, }))
            _ => Some(self.bogus_rule(BadCallShape("namespace"), g))
          }
        2 =>
          match (gs[0], gs[1]) {
            ([{ it: Id(p), .. }], [{ it: Lit(Str(u)), .. }]) =>
              Some(Namespace({ prefix: Some(p), url: u, span, }))
            _ => Some(self.bogus_rule(BadCallShape("namespace"), g))
          }
        _ => Some(self.bogus_rule(BadCallShape("namespace"), g))
      }
    }
    ("import", None) => self.import_of(args, g, span)
    (_, blk) => {
      // A known at-rule in the wrong shape, or one the table does not know.
      self.error(BadCallShape(name), g.span)
      let body = match blk {
        Some(b) => Some(self.block_items(b, inner))
        None => None
      }
      Some(
        Unknown({ name, prelude: self.comma_list(args), block: body, span, }),
      )
    }
  }
}

///|
/// The items of a single-group argument list, for a call whose argument is not
/// a name but a shape -- `property(--brand)`.
fn args_items(args : ArrayView[@sast.Node]) -> ArrayView[@sast.Node] {
  match args {
    [{ it: Group(xs), .. }] => xs[:]
    _ => args
  }
}

///|
fn Lowerer::import_of(
  self : Lowerer,
  args : ArrayView[@sast.Node],
  g : @sast.Node,
  span : @cspan.Span,
) -> @ast.CssRule? raise @err.ShrubCssError {
  let gs = arg_groups(args)
  if gs.length() == 0 {
    return Some(self.bogus_rule(BadCallShape("import"), g))
  }
  let url = match gs[0] {
    [{ it: Lit(Str(s)), .. }] => s
    _ => return Some(self.bogus_rule(BadCallShape("import"), g))
  }
  let mut layer : @ast.LayerName?? = None
  let mut supports : @ast.Condition? = None
  let media : Array[@sast.Node] = []
  let mut i = 1
  while i < gs.length() {
    let items = gs[i]
    match as_call(items) {
      Some((n, a, _)) if n == "layer" =>
        layer = Some(Some({ parts: layer_parts(a), }))
      Some((n, a, _)) if n == "supports" =>
        supports = Some(self.condition(a, g.span))
      _ =>
        match items {
          [{ it: Id("layer"), .. }] => layer = Some(None)
          _ =>
            // Whatever is left is a media query.
            for n in items {
              media.push(n)
            }
        }
    }
    i = i + 1
  }
  let queries = if media.length() == 0 {
    []
  } else {
    [self.media_query(media[:], g.span)]
  }
  Some(Import({ url, layer, supports, media: queries, span, }))
}

// -------------------------------------------------------- media and conditions

///|
fn Lowerer::media_list(
  self : Lowerer,
  args : ArrayView[@sast.Node],
) -> Array[@ast.MediaQuery] raise @err.ShrubCssError {
  let out : Array[@ast.MediaQuery] = []
  for g in args {
    let items = match g.it {
      Group(xs) => xs[:]
      _ => one(g)
    }
    out.push(self.media_query(items, g.span))
  }
  out
}

///|
/// `screen and (width <= rem(40))`, `only print`, or a bare condition.
fn Lowerer::media_query(
  self : Lowerer,
  items : ArrayView[@sast.Node],
  at : @basic.Span,
) -> @ast.MediaQuery raise @err.ShrubCssError {
  let mut rest = items
  let mut qualifier : @ast.MediaQualifier? = None
  let mut media_type : String? = None
  match rest {
    [{ it: Id("only"), .. }, { it: Id(t), .. }, ..] => {
      qualifier = Some(Only)
      media_type = Some(@names.unkebab(t))
      rest = rest[2:]
    }
    [{ it: Id("not"), .. }, { it: Id(t), .. }, ..] if !is_logical(t) => {
      qualifier = Some(Not)
      media_type = Some(@names.unkebab(t))
      rest = rest[2:]
    }
    [{ it: Id(t), .. }, ..] if !is_logical(t) && !is_feature_head(rest) => {
      media_type = Some(@names.unkebab(t))
      rest = rest[1:]
    }
    _ => ()
  }
  // A leading `and` joins the type to the condition and carries no meaning of
  // its own.
  match rest {
    [{ it: Id("and"), .. }, ..] => rest = rest[1:]
    _ => ()
  }
  let condition = if rest.length() == 0 {
    None
  } else {
    Some(self.condition_items(rest, at))
  }
  { qualifier, media_type, condition, }
}

///|
/// Whether a run begins a feature test rather than a media type.
///
/// `screen` is a type; `width <= rem(40)` is a feature whose first token also
/// happens to be a bare identifier. The difference is what follows it.
fn is_feature_head(items : ArrayView[@sast.Node]) -> Bool {
  if items.length() < 2 {
    return false
  }
  match items[1].it {
    Op(_) => true
    Block(_) => true
    _ => false
  }
}

///|
fn is_logical(w : String) -> Bool {
  w == "and" || w == "or" || w == "not"
}

///|
fn Lowerer::condition(
  self : Lowerer,
  args : ArrayView[@sast.Node],
  at : @basic.Span,
) -> @ast.Condition raise @err.ShrubCssError {
  match args {
    [{ it: Group(xs), .. }] => self.condition_items(xs[:], at)
    _ => self.condition_items(args, at)
  }
}

///|
/// A condition: features and parenthesised groups, joined by `and`/`or`.
fn Lowerer::condition_items(
  self : Lowerer,
  items : ArrayView[@sast.Node],
  at : @basic.Span,
) -> @ast.Condition raise @err.ShrubCssError {
  if items.length() == 0 {
    return Bogus(self.bogus_at(BadSelector, at))
  }
  let ands = split_word(items, "and")
  let ors = split_word(items, "or")
  if ands.length() > 1 && ors.length() > 1 {
    // CSS requires the parentheses too, so this is a diagnostic rather than a
    // precedence decision.
    self.error(Unsupported("`and` and `or` mixed without parentheses"), at)
    return Bogus(self.bogus_at(BadSelector, at))
  }
  if ands.length() > 1 {
    let cs : Array[@ast.Condition] = []
    for part in ands {
      flatten(cs, self.condition_items(part, at), And)
    }
    return Operation(And, cs)
  }
  if ors.length() > 1 {
    let cs : Array[@ast.Condition] = []
    for part in ors {
      flatten(cs, self.condition_items(part, at), Or)
    }
    return Operation(Or, cs)
  }
  match items {
    [{ it: Id("not"), .. }, ..] =>
      return Operation(Not, [self.condition_items(items[1:], at)])
    _ => ()
  }
  // A parenthesised group is a nested condition; anything else is a leaf.
  match items {
    [{ it: Parens(gs), .. }] =>
      match gs {
        [g] => {
          let inner = match g.it {
            Group(xs) => xs[:]
            _ => one(g)
          }
          if has_logical(inner) {
            return self.condition_items(inner, at)
          }
          return self.feature(inner, at)
        }
        _ => ()
      }
    _ => ()
  }
  match as_call(items) {
    Some((n, a, _)) if n == "selector" => {
      let sels : Array[@ast.Selector] = []
      for g in a {
        let sitems = match g.it {
          Group(xs) => xs[:]
          _ => one(g)
        }
        sels.push(self.selector(sitems, g.span))
      }
      return SelectorFn(sels)
    }
    _ => ()
  }
  self.feature(items, at)
}

///|
fn flatten(
  out : Array[@ast.Condition],
  c : @ast.Condition,
  op : @ast.LogicalOp,
) -> Unit {
  match c {
    Operation(o, inner) if o == op =>
      for x in inner {
        out.push(x)
      }
    _ => out.push(c)
  }
}

///|
fn has_logical(items : ArrayView[@sast.Node]) -> Bool {
  for n in items {
    match n.it {
      Id(w) => if is_logical(w) { return true }
      Parens(_) => return true
      _ => ()
    }
  }
  false
}

///|
/// A feature test, in the four shapes CSS gives it.
///
/// `=` is the canonical spelling for the plain form, because the `:` form opens
/// a block and is one step from the semicolon hazard. Both are accepted.
fn Lowerer::feature(
  self : Lowerer,
  items : ArrayView[@sast.Node],
  at : @basic.Span,
) -> @ast.Condition raise @err.ShrubCssError {
  // `(display: grid)` inside `supports`: a declaration, not a feature.
  match items {
    [{ it: Id(p), .. }, { it: Block(gs), .. }] =>
      if gs.length() == 1 {
        let (value, important) = self.value_of(gs[0])
        let name = @names.unkebab(p)
        // A declaration when it names a property, a plain feature otherwise.
        // Both spell the same shrubbery, and both readings are legal CSS in
        // their own at-rule, so the distinction is left to the consumer.
        return Decl({
          property: Ident(name),
          value,
          important,
          span: cspan(at),
        })
      }
    _ => ()
  }
  // `width = rem(40)`, `width <= rem(40)`.
  let ops = range_ops(items)
  if ops.length() == 1 {
    let (i, op) = ops[0]
    let left = items[0:i]
    let right = items[i + 1:]
    match left {
      [{ it: Id(n), .. }] => {
        let (vs, _) = self.values(right)
        return Feature(
          if op is Eq {
            Plain(@names.unkebab(n), vs)
          } else {
            Range(@names.unkebab(n), op, vs)
          },
        )
      }
      _ =>
        match right {
          [{ it: Id(n), .. }] => {
            let (vs, _) = self.values(left)
            return Feature(Range(@names.unkebab(n), flip(op), vs))
          }
          _ => ()
        }
    }
  }
  if ops.length() == 2 {
    let (i1, op1) = ops[0]
    let (i2, op2) = ops[1]
    match items[i1 + 1:i2] {
      [{ it: Id(n), .. }] => {
        let (lo, _) = self.values(items[0:i1])
        let (hi, _) = self.values(items[i2 + 1:])
        return Feature(Interval(lo, op1, @names.unkebab(n), op2, hi))
      }
      _ => ()
    }
  }
  match items {
    [{ it: Id(n), .. }] => Feature(Boolean(@names.unkebab(n)))
    _ => {
      let (vs, _) = self.values(items)
      Unknown(vs)
    }
  }
}

///|
/// The comparison operators at the top of a run, with their positions.
fn range_ops(items : ArrayView[@sast.Node]) -> Array[(Int, @ast.RangeOp)] {
  let out : Array[(Int, @ast.RangeOp)] = []
  for i, n in items {
    match n.it {
      Op("<") => out.push((i, Lt))
      Op("<=") => out.push((i, Le))
      Op(">") => out.push((i, Gt))
      Op(">=") => out.push((i, Ge))
      Op("=") => out.push((i, Eq))
      _ => ()
    }
  }
  out
}

///|
fn flip(op : @ast.RangeOp) -> @ast.RangeOp {
  match op {
    Lt => Gt
    Le => Ge
    Gt => Lt
    Ge => Le
    Eq => Eq
  }
}

///|
fn split_word(
  items : ArrayView[@sast.Node],
  word : String,
) -> Array[ArrayView[@sast.Node]] {
  let out : Array[ArrayView[@sast.Node]] = []
  let mut from = 0
  for i, n in items {
    match n.it {
      Id(w) =>
        if w == word {
          out.push(items[from:i])
          from = i + 1
        }
      _ => ()
    }
  }
  out.push(items[from:])
  out
}

// ---------------------------------------------------------- small preludes

///|
fn split_container(
  args : ArrayView[@sast.Node],
) -> (String?, ArrayView[@sast.Node]) {
  let gs = arg_groups(args)
  if gs.length() >= 2 {
    match gs[0] {
      [{ it: Id(n), .. }] if !is_logical(n) => return (Some(n), args[1:])
      _ => ()
    }
  }
  (None, args)
}

///|
fn Lowerer::frames(
  self : Lowerer,
  block : @sast.Node,
) -> Array[@ast.KeyframeBlock] raise @err.ShrubCssError {
  let out : Array[@ast.KeyframeBlock] = []
  let groups = match block.it {
    Block(gs) => gs
    _ => return out
  }
  for g in groups {
    let items = match g.it {
      Group(xs) => xs[:]
      _ => continue
    }
    let (head, blk, _) = split_block(items)
    match blk {
      None => {
        self.error(ExpectedBlock, g.span)
        continue
      }
      Some(b) => {
        let selectors : Array[@ast.KeyframeSelector] = []
        for sel_items in comma_runs(head) {
          match self.keyframe_selector(sel_items, g.span) {
            Some(s) => selectors.push(s)
            None => ()
          }
        }
        out.push({ selectors, decls: self.decl_block(b), span: cspan(g.span), })
      }
    }
  }
  out
}

///|
fn Lowerer::keyframe_selector(
  self : Lowerer,
  items : ArrayView[@sast.Node],
  at : @basic.Span,
) -> @ast.KeyframeSelector? raise @err.ShrubCssError {
  match items {
    [{ it: Id("from"), .. }] => Some(From)
    [{ it: Id("to"), .. }] => Some(To)
    _ =>
      match as_call(items) {
        Some((n, args, _)) if n == "percent" =>
          match single_number(args) {
            Some(num) => Some(Percentage(num))
            None => {
              self.error(BadCallShape("percent"), at)
              None
            }
          }
        _ => {
          self.error(Unsupported("this keyframe selector"), at)
          None
        }
      }
  }
}

///|
/// A head split on brackets, for the comma-separated case.
fn comma_runs(head : ArrayView[@sast.Node]) -> Array[ArrayView[@sast.Node]] {
  match head {
    [{ it: Brackets(gs), .. }] => {
      let out : Array[ArrayView[@sast.Node]] = []
      for g in gs {
        match g.it {
          Group(xs) => out.push(xs[:])
          _ => out.push(one(g))
        }
      }
      out
    }
    _ => [head]
  }
}

///|
fn layer_names(args : ArrayView[@sast.Node]) -> Array[@ast.LayerName] {
  let out : Array[@ast.LayerName] = []
  for g in args {
    let items = match g.it {
      Group(xs) => xs[:]
      _ => one(g)
    }
    let parts = layer_parts_items(items)
    if parts.length() > 0 {
      out.push({ parts, })
    }
  }
  out
}

///|
fn layer_parts(args : ArrayView[@sast.Node]) -> Array[String] {
  match args {
    [{ it: Group(xs), .. }] => layer_parts_items(xs[:])
    _ => layer_parts_items(args)
  }
}

///|
/// `base.theme` is `Id . Id`, which is a dotted layer name.
fn layer_parts_items(items : ArrayView[@sast.Node]) -> Array[String] {
  let out : Array[String] = []
  for n in items {
    match n.it {
      Id(p) => out.push(@names.unkebab(p))
      _ => ()
    }
  }
  out
}

///|
fn page_selectors(args : ArrayView[@sast.Node]) -> Array[String] {
  let out : Array[String] = []
  for g in args {
    let items = match g.it {
      Group(xs) => xs[:]
      _ => one(g)
    }
    let b = StringBuilder()
    for n in items {
      match n.it {
        Id(name) => b.write_string(@names.unkebab(name))
        Parens(_) => ()
        _ => ()
      }
    }
    let s = b.to_string()
    if s != "" {
      // A page selector's pseudo-page is written as a call, like every other
      // pseudo: `page(first())` is `@page :first`.
      out.push(":" + s)
    }
  }
  out
}

///|
fn Lowerer::scope_parts(
  self : Lowerer,
  args : ArrayView[@sast.Node],
  at : @basic.Span,
) -> (Array[@ast.Selector]?, Array[@ast.Selector]?) raise @err.ShrubCssError {
  let gs = arg_groups(args)
  let mut start : Array[@ast.Selector]? = None
  let mut end : Array[@ast.Selector]? = None
  for items in gs {
    // `~to` splits the two halves.
    let mut split = -1
    for i, n in items {
      match n.it {
        Kw("to") => split = i
        _ => ()
      }
    }
    if split >= 0 {
      if split > 0 {
        start = Some([self.selector(items[0:split], at)])
      }
      if split + 1 < items.length() {
        end = Some([self.selector(items[split + 1:], at)])
      }
    } else if start is None {
      start = Some([self.selector(items, at)])
    } else {
      end = Some([self.selector(items, at)])
    }
  }
  (start, end)
}
