///|
/// Generators for CSS syntax trees.
///
/// Everything here produces a **normal** tree: no `Bogus`, numbers already in
/// the spelling the printer would choose, conditions flattened, units in their
/// canonical case. That is what lets the round-trip properties be stated as
/// plain equality -- a generator that produced denormal trees would need a
/// normaliser in every test, and the normaliser would then be the thing under
/// test rather than the library.
///
/// Size discipline is what makes it terminate: every recursive generator halves
/// its budget, and at zero the weighted alternatives are leaves only.

///|
/// The identifiers worth generating.
///
/// A fixed nasty list rather than random letters, because the interesting
/// identifiers are the ones that stress the `_` <-> `-` transform and its two
/// escapes -- and a random generator would essentially never produce one.
fn nasty_idents() -> Array[String] {
  [
    "a", "x1", "color", "font-size", "-webkit-box-orient", "-moz-osx-font-smoothing",
    "btn__primary", "side_bar", "grid-template-areas", "Ünïcode", "AB", "z-9",
  ]
}

///|
/// Property names, kept apart from value identifiers only because a property
/// that is a custom property has to be generated as one.
fn gen_property(r : Rng) -> @ast.PropertyName {
  if r.below(6) == 0 {
    Custom("--" + r.pick(["brand", "gap", "brand-fg", "x"]))
  } else {
    Ident(r.pick(nasty_idents()))
  }
}

///|
/// A number already spelled the way the printer would spell it.
///
/// No leading `+` and no trailing zeros: both are legal CSS and neither
/// survives the notation, so generating them would be testing a documented
/// normalisation rather than the library.
fn gen_number(r : Rng) -> @ast.Number {
  let choice = r.below(6)
  if choice == 0 {
    { repr: "0", value: 0.0, is_int: true, }
  } else if choice == 1 {
    { repr: "-1", value: -1.0, is_int: true, }
  } else if choice == 2 {
    { repr: "0.5", value: 0.5, is_int: false, }
  } else if choice == 3 {
    { repr: "1.25", value: 1.25, is_int: false, }
  } else {
    let n = r.below(400)
    { repr: n.to_string(), value: n.to_double(), is_int: true, }
  }
}

///|
/// A unit this library can spell as a short call, so that the value round-trips
/// through the notation rather than through the `dim()` escape.
fn gen_unit(r : Rng) -> String {
  r.pick(["px", "rem", "em", "ms", "s", "deg", "fr", "vh", "cqw", "Q", "kHz"])
}

///|
fn gen_value(r : Rng, size : Int) -> @ast.ComponentValue {
  if size <= 0 {
    return gen_value_leaf(r)
  }
  let half = size / 2
  r.weighted([(10, LeafV), (3, FunctionV), (1, ParenV), (1, BracketV)])
  |> fn(shape) {
    match shape {
      LeafV => gen_value_leaf(r)
      FunctionV =>
        Function(
          r.pick(["rgb", "calc", "var", "translate", "clamp", "min"]),
          gen_value_list(r, half),
        )
      ParenV => Paren(gen_value_list(r, half))
      BracketV => Bracket(gen_value_list(r, half))
    }
  }
}

///|
priv enum ValueShape {
  LeafV
  FunctionV
  ParenV
  BracketV
}

///|
fn gen_value_leaf(r : Rng) -> @ast.ComponentValue {
  let choice = r.below(8)
  if choice == 0 {
    Ident(r.pick(nasty_idents()))
  } else if choice == 1 {
    Ident("--" + r.pick(["brand", "gap"]))
  } else if choice == 2 {
    Str(r.pick(["x", "a b", "with \"quotes\"", ""]))
  } else if choice == 3 {
    Num(gen_number(r))
  } else if choice == 4 {
    Dimension(gen_number(r), gen_unit(r))
  } else if choice == 5 {
    Percentage(gen_number(r))
  } else if choice == 6 {
    // Hex digits that can be written bare: leading zeros cannot survive the
    // notation, which is a documented refusal rather than a bug to find here.
    Hex(r.pick(["fff", "f7f7f7", "abcdef", "FFF"]))
  } else {
    Url(r.pick(["a.png", "https://example.com/b.svg"]))
  }
}

///|
/// A value list: one to four components, with commas between some of them.
fn gen_value_list(r : Rng, size : Int) -> Array[@ast.ComponentValue] {
  let n = 1 + r.below(3)
  let out : Array[@ast.ComponentValue] = []
  for i in 0..<n {
    if i > 0 {
      // A separator goes between values and never at either end, which is
      // where CSS puts one and what the printer's trimming assumes.
      let sep = r.below(4)
      if sep == 0 {
        out.push(Comma)
      } else if sep == 1 {
        out.push(Slash)
      }
    }
    out.push(gen_value(r, size))
  }
  out
}

///|
fn gen_declaration(r : Rng, size : Int) -> @ast.Declaration {
  {
    property: gen_property(r),
    value: gen_value_list(r, size),
    important: r.below(8) == 0,
    span: @span.nowhere,
  }
}

// ------------------------------------------------------------------ selectors

///|
fn gen_compound(r : Rng, size : Int) -> @ast.Compound {
  let quals : Array[@ast.Qualifier] = []
  let type_sel : @ast.TypeSelector? = if r.below(3) == 0 {
    None
  } else if r.below(6) == 0 {
    Some(Universal(None))
  } else {
    Some(Named(None, r.pick(["a", "div", "nav", "li", "input", "span"])))
  }
  let n = r.below(3)
  for _ in 0..<n {
    // A pseudo-element ends a compound: CSS admits nothing after one, so
    // generating a qualifier there would be generating invalid CSS and
    // testing the parser's recovery rather than the property.
    if quals.length() > 0 && quals[quals.length() - 1] is Element(_) {
      break
    }
    quals.push(gen_qualifier(r, size / 2))
  }
  // A compound with neither a type nor a qualifier prints as `*`, which parses
  // back as a universal selector -- a different tree. Generating one would be
  // testing that difference rather than the library.
  if type_sel is None && quals.length() == 0 {
    quals.push(Class("a"))
  }
  { type_sel, quals, span: @span.nowhere, }
}

///|
fn gen_qualifier(r : Rng, size : Int) -> @ast.Qualifier {
  let choice = r.below(8)
  if choice == 0 {
    Class(r.pick(["card", "is-selected", "btn__primary", "a"]))
  } else if choice == 1 {
    Id(r.pick(["sidebar", "main", "a"]))
  } else if choice == 2 {
    Nesting
  } else if choice == 3 {
    Attr({
      ns: None,
      name: r.pick(["type", "href", "data-x"]),
      matcher: if r.bool() {
        Some(
          (
            r.pick([
              @ast.AttrOp::Exact,
              Includes,
              DashMatch,
              Prefix,
              Suffix,
              Substring,
            ]),
            if r.bool() {
              @ast.AttrValue::Str("text")
            } else {
              Ident("text")
            },
          ),
        )
      } else {
        None
      },
      case_: r.pick([@ast.AttrCase::Default, Insensitive, Sensitive]),
    })
  } else if choice == 4 {
    Pseudo(
      Simple(r.pick(["hover", "focus", "first-child", "disabled", "root"])),
    )
  } else if choice == 5 {
    Element(Simple(r.pick(["before", "after", "marker"])))
  } else if choice == 6 && size > 0 {
    Pseudo(
      Sub(r.pick(["is", "not", "where", "has"]), [gen_selector(r, size / 2)]),
    )
  } else {
    Pseudo(
      Nth(
        r.pick(["nth-child", "nth-of-type"]),
        { a: r.below(5) - 2, b: r.below(7) - 3, },
        None,
      ),
    )
  }
}

///|
fn gen_selector(r : Rng, size : Int) -> @ast.Selector {
  if size <= 0 {
    return Simple(gen_compound(r, 0))
  }
  if r.below(3) == 0 {
    Complex(
      gen_selector(r, size / 2),
      r.pick([
        @ast.Combinator::Descendant,
        Child,
        NextSibling,
        SubsequentSibling,
        Column,
      ]),
      gen_compound(r, size / 2),
    )
  } else {
    Simple(gen_compound(r, size))
  }
}

// ---------------------------------------------------------------- conditions

///|
/// A condition, flattened by construction: an `Operation` never has a child
/// with the same operator, so the tree is already in the normal form the
/// lowering produces.
fn gen_condition(
  r : Rng,
  size : Int,
  supports? : Bool = false,
) -> @ast.Condition {
  if size <= 0 {
    return gen_cond_leaf(r, supports)
  }
  let choice = r.below(6)
  if choice == 0 {
    Operation(Not, [gen_condition(r, size / 2)])
  } else if choice == 1 || choice == 2 {
    let op : @ast.LogicalOp = if r.bool() { And } else { Or }
    let n = 2 + r.below(2)
    let cs : Array[@ast.Condition] = []
    for _ in 0..<n {
      // Children are leaves: a nested operation with the same operator would
      // be denormal, and one with the other operator is what parentheses are
      // for -- both are worth a test, neither is worth a silent mismatch here.
      cs.push(gen_cond_leaf(r, supports))
    }
    Operation(op, cs)
  } else {
    gen_cond_leaf(r, supports)
  }
}

///|
/// A condition leaf.
///
/// `@supports` tests whether a DECLARATION is understood; `@media` and
/// `@container` test a feature. They are different grammars sharing one shape,
/// so a generator that mixed them would produce CSS neither one accepts.
fn gen_cond_leaf(r : Rng, supports : Bool) -> @ast.Condition {
  if supports {
    Decl({
      property: gen_property(r),
      value: [gen_value_leaf(r)],
      important: false,
      span: @span.nowhere,
    })
  } else {
    Feature(gen_feature(r))
  }
}

///|
fn gen_feature(r : Rng) -> @ast.Feature {
  let name = r.pick(["width", "height", "hover", "min-width", "orientation"])
  let choice = r.below(4)
  if choice == 0 {
    Boolean(name)
  } else if choice == 1 {
    Plain(name, [Dimension(gen_number(r), gen_unit(r))])
  } else if choice == 2 {
    Range(name, r.pick([@ast.RangeOp::Lt, Le, Gt, Ge, Eq]), [
      Dimension(gen_number(r), gen_unit(r)),
    ])
  } else {
    Interval(
      [Dimension(gen_number(r), gen_unit(r))],
      r.pick([@ast.RangeOp::Lt, Le]),
      name,
      r.pick([@ast.RangeOp::Lt, Le]),
      [Dimension(gen_number(r), gen_unit(r))],
    )
  }
}

// --------------------------------------------------------------------- rules

///|
fn gen_block(r : Rng, size : Int) -> Array[@ast.BlockItem] {
  let n = 1 + r.below(3)
  let out : Array[@ast.BlockItem] = []
  for _ in 0..<n {
    if size > 0 && r.below(5) == 0 {
      // Only the rules CSS allows inside another rule. `@font-face` and
      // `@keyframes` are top-level, and nesting one would generate CSS the
      // parser is right to reject -- testing its recovery, not the property.
      out.push(Rule(gen_nestable(r, size / 2)))
    } else {
      out.push(Decl(gen_declaration(r, size / 2)))
    }
  }
  out
}

///|
fn gen_rule(r : Rng, size : Int) -> @ast.CssRule {
  if size <= 0 {
    return gen_style_rule(r, 0)
  }
  let choice = r.below(10)
  let half = size / 2
  if choice == 0 {
    Media({
      queries: [gen_media_query(r, half)],
      // Rules, not declarations: a declaration directly inside a top-level
      // conditional group is not valid CSS -- it needs a rule around it.
      body: gen_rule_block(r, half),
      span: @span.nowhere,
    })
  } else if choice == 1 {
    Supports({
      condition: gen_condition(r, half, supports=true),
      body: gen_rule_block(r, half),
      span: @span.nowhere,
    })
  } else if choice == 2 {
    Keyframes({
      name: Ident(r.pick(["fade", "fade-in", "x"])),
      frames: [
        {
          selectors: [r.pick([@ast.KeyframeSelector::From, To])],
          decls: {
            decls: [Decl(gen_declaration(r, half))],
            span: @span.nowhere,
          },
          span: @span.nowhere,
        },
      ],
      span: @span.nowhere,
    })
  } else if choice == 3 {
    FontFace({ decls: [Decl(gen_declaration(r, half))], span: @span.nowhere, })
  } else {
    gen_style_rule(r, size)
  }
}

///|
/// A body of rules, for a conditional group at the top level.
fn gen_rule_block(r : Rng, size : Int) -> Array[@ast.BlockItem] {
  let n = 1 + r.below(2)
  let out : Array[@ast.BlockItem] = []
  for _ in 0..<n {
    out.push(Rule(gen_style_rule(r, size / 2)))
  }
  out
}

///|
/// A rule that may appear inside another rule.
fn gen_nestable(r : Rng, size : Int) -> @ast.CssRule {
  if size > 0 && r.below(3) == 0 {
    let half = size / 2
    if r.bool() {
      Media({
        queries: [gen_media_query(r, half)],
        body: gen_block(r, half),
        span: @span.nowhere,
      })
    } else {
      Supports({
        condition: gen_condition(r, half, supports=true),
        body: gen_block(r, half),
        span: @span.nowhere,
      })
    }
  } else {
    gen_style_rule(r, size)
  }
}

///|
/// A media query.
///
/// `only` and `not` are qualifiers ON a media type, so neither may appear
/// without one: `@media not and (hover)` is not a query, it is a parse error
/// waiting to be recovered from.
fn gen_media_query(r : Rng, size : Int) -> @ast.MediaQuery {
  let media_type : String? = if r.bool() {
    Some(r.pick(["screen", "print", "all"]))
  } else {
    None
  }
  let qualifier : @ast.MediaQualifier? = match media_type {
    Some(_) =>
      if r.below(3) == 0 {
        Some(if r.bool() { Only } else { Not })
      } else {
        None
      }
    None => None
  }
  let condition = if media_type is None || r.bool() {
    Some(gen_condition(r, size))
  } else {
    None
  }
  { qualifier, media_type, condition, }
}

///|
fn gen_style_rule(r : Rng, size : Int) -> @ast.CssRule {
  let n = 1 + r.below(2)
  let sels : Array[@ast.Selector] = []
  for _ in 0..<n {
    sels.push(gen_selector(r, size))
  }
  Style({ selectors: sels, body: gen_block(r, size), span: @span.nowhere, })
}

///|
/// A whole stylesheet.
pub fn gen_stylesheet(r : Rng, size : Int) -> @ast.Stylesheet {
  let n = 1 + r.below(3)
  let items : Array[@ast.TopItem] = []
  for _ in 0..<n {
    items.push(Rule(gen_rule(r, size)))
  }
  { items, span: @span.nowhere, }
}

///|
/// How big a tree is, for the shrinker's termination argument.
pub fn size_of(sheet : @ast.Stylesheet) -> Int {
  let mut n = 0
  for item in sheet.items {
    n = n +
      (match item {
        Rule(r) => rule_size(r)
        _ => 1
      })
  }
  n
}

///|
fn rule_size(r : @ast.CssRule) -> Int {
  match r {
    Style(s) => {
      let mut n = 1 + block_size(s.body[:])
      for sel in s.selectors {
        n = n + selector_size(sel)
      }
      n
    }
    Media(m) => 1 + block_size(m.body[:])
    Supports(s) => 1 + block_size(s.body[:])
    Keyframes(k) => 1 + k.frames.length()
    FontFace(b) => 1 + b.decls.length()
    _ => 1
  }
}

///|
/// A selector's depth counts, not just the number of selectors.
///
/// Without this, replacing `a > b` with `a` leaves the measure unchanged, so
/// the candidate is not a shrink and `minimize`'s termination argument fails --
/// which the meta-test catches rather than letting it spin.
fn selector_size(s : @ast.Selector) -> Int {
  match s {
    Simple(c) => 1 + c.quals.length()
    Complex(l, _, right) => selector_size(l) + 1 + right.quals.length()
    Relative(_, inner) => 1 + selector_size(inner)
    Bogus(_) => 1
  }
}

///|
fn block_size(items : ArrayView[@ast.BlockItem]) -> Int {
  let mut n = 0
  for it in items {
    n = n +
      (match it {
        Decl(d) => 1 + d.value.length()
        Rule(r) => rule_size(r)
        _ => 1
      })
  }
  n
}
