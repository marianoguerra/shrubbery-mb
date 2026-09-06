///|
/// The printer, over trees built by hand.
///
/// Built by hand on purpose: at this stage there is no parser, and a printer
/// tested only through a parser can only ever be shown to agree with it. These
/// cases fix what the output IS, so that when the parser arrives the two can
/// disagree loudly rather than drift together.

///|
fn num(repr : String, value : Double) -> @ast.Number {
  { repr, value, is_int: false, }
}

///|
fn int(n : Int) -> @ast.Number {
  @ast.Number::of_int(n)
}

///|
fn decl(
  name : String,
  value : Array[@ast.ComponentValue],
  important? : Bool = false,
) -> @ast.Declaration {
  {
    property: @ast.PropertyName::Ident(name),
    value,
    important,
    span: @span.nowhere,
  }
}

///|
fn tag(name : String) -> @ast.Selector {
  Simple({ type_sel: Some(Named(None, name)), quals: [], span: @span.nowhere, })
}

///|
fn cls(name : String) -> @ast.Selector {
  Simple({ type_sel: None, quals: [Class(name)], span: @span.nowhere, })
}

///|
fn sheet(items : Array[@ast.TopItem]) -> @ast.Stylesheet {
  { items, span: @span.nowhere, }
}

///|
fn style_rule(
  selectors : Array[@ast.Selector],
  body : Array[@ast.BlockItem],
) -> @ast.CssRule {
  Style({ selectors, body, span: @span.nowhere, })
}

///|
test "a rule in all three modes" {
  let r = style_rule([cls("card")], [
    Decl(decl("display", [Ident("grid")])),
    Decl(decl("gap", [Dimension(int(1), "rem")])),
  ])
  let s = sheet([Rule(r)])
  inspect(
    @write.stylesheet(s, style=Pretty),
    content=(
      #|.card {
      #|  display: grid;
      #|  gap: 1rem;
      #|}
      #|
    ),
  )
  inspect(
    @write.stylesheet(s, style=Compact),
    content=".card { display: grid; gap: 1rem; }\n",
  )
  inspect(
    @write.stylesheet(s, style=Minified),
    content=".card{display:grid;gap:1rem}",
  )
}

///|
test "nesting indents, and a nested rule takes no semicolon" {
  let inner = style_rule(
    [
      Simple({
        type_sel: None,
        quals: [Nesting, Pseudo(Simple("hover"))],
        span: @span.nowhere,
      }),
    ],
    [Decl(decl("color", [Ident("red")]))],
  )
  let outer = style_rule([tag("nav")], [
    Decl(decl("color", [Ident("blue")])),
    Rule(inner),
  ])
  inspect(
    @write.stylesheet(sheet([Rule(outer)]), style=Pretty),
    content=(
      #|nav {
      #|  color: blue;
      #|  &:hover {
      #|    color: red;
      #|  }
      #|}
      #|
    ),
  )
  inspect(
    @write.stylesheet(sheet([Rule(outer)]), style=Minified),
    content="nav{color:blue;&:hover{color:red}}",
  )
}

///|
test "combinators, and the descendant space survives minification" {
  let s : @ast.Selector = Complex(
    Complex(tag("nav"), Descendant, {
      type_sel: Some(Named(None, "ul")),
      quals: [],
      span: @span.nowhere,
    }),
    Child,
    { type_sel: Some(Named(None, "li")), quals: [], span: @span.nowhere, },
  )
  inspect(@write.selector(s), content="nav ul > li")
  inspect(@write.selector(s, style=Minified), content="nav ul>li")
}

///|
test "value spacing: commas bind left, slashes sit between" {
  inspect(
    @write.value([
      Ident("Charter"),
      Comma,
      Ident("Georgia"),
      Comma,
      Ident("serif"),
    ]),
    content="Charter, Georgia, serif",
  )
  inspect(
    @write.value([Ident("Charter"), Comma, Ident("Georgia")], style=Minified),
    content="Charter,Georgia",
  )
  inspect(@write.value([Num(int(1)), Slash, Num(int(2))]), content="1 / 2")
  inspect(
    @write.value([Num(int(1)), Slash, Num(int(2))], style=Minified),
    content="1/2",
  )
  inspect(
    @write.value([
      Function("rgb", [
        Num(int(0)),
        Num(int(0)),
        Num(int(0)),
        Slash,
        Percentage(int(5)),
      ]),
    ]),
    content="rgb(0 0 0 / 5%)",
  )
}

///|
test "a number keeps the spelling it arrived with" {
  inspect(@write.value([Num(num("1.50", 1.5))]), content="1.50")
  inspect(@write.value([Num(num("+1", 1.0))]), content="+1")
  inspect(@write.value([Dimension(num("0.5", 0.5), "em")]), content="0.5em")
}

///|
test "important, attributes and pseudo-elements" {
  inspect(
    @write.declaration(decl("color", [Ident("red")], important=true)),
    content="color: red !important",
  )
  inspect(
    @write.declaration(
      decl("color", [Ident("red")], important=true),
      style=Minified,
    ),
    content="color:red!important",
  )
  let s : @ast.Selector = Simple({
    type_sel: Some(Named(None, "input")),
    quals: [
      Attr({
        ns: None,
        name: "type",
        matcher: Some((Exact, Str("text"))),
        case_: Default,
      }),
      Pseudo(
        Sub("not", [
          Simple({
            type_sel: None,
            quals: [Pseudo(Simple("disabled"))],
            span: @span.nowhere,
          }),
        ]),
      ),
      Element(Simple("before")),
    ],
    span: @span.nowhere,
  })
  inspect(
    @write.selector(s),
    content="input[type=\"text\"]:not(:disabled)::before",
  )
}

///|
test "An+B is printed in its shortest equivalent form" {
  fn nth(a : Int, b : Int) -> String {
    @write.selector(
      Simple({
        type_sel: None,
        quals: [Pseudo(Nth("nth-child", { a, b, }, None))],
        span: @span.nowhere,
      }),
    )
  }

  inspect(nth(2, 1), content=":nth-child(2n+1)")
  inspect(nth(0, 3), content=":nth-child(3)")
  inspect(nth(1, 0), content=":nth-child(n)")
  inspect(nth(-1, 3), content=":nth-child(-n+3)")
  inspect(nth(2, -1), content=":nth-child(2n-1)")
}

///|
test "at-rules" {
  let media : @ast.CssRule = Media({
    queries: [
      {
        qualifier: None,
        media_type: None,
        condition: Some(
          Feature(Range("width", Le, [Dimension(int(40), "rem")])),
        ),
      },
    ],
    body: [
      Rule(
        style_rule([cls("card")], [
          Decl(decl("padding", [Dimension(num("0.75", 0.75), "rem")])),
        ]),
      ),
    ],
    span: @span.nowhere,
  })
  inspect(
    @write.rule(media),
    content=(
      #|@media (width <= 40rem) {
      #|  .card {
      #|    padding: 0.75rem;
      #|  }
      #|}
    ),
  )
  inspect(
    @write.rule(media, style=Minified),
    content="@media (width<=40rem){.card{padding:0.75rem}}",
  )
  let kf : @ast.CssRule = Keyframes({
    name: Ident("fade-in"),
    frames: [
      {
        selectors: [Percentage(int(0))],
        decls: {
          decls: [Decl(decl("opacity", [Num(int(0))]))],
          span: @span.nowhere,
        },
        span: @span.nowhere,
      },
      {
        selectors: [Percentage(int(100))],
        decls: {
          decls: [Decl(decl("opacity", [Num(int(1))]))],
          span: @span.nowhere,
        },
        span: @span.nowhere,
      },
    ],
    span: @span.nowhere,
  })
  inspect(
    @write.rule(kf),
    content=(
      #|@keyframes fade-in {
      #|  0% {
      #|    opacity: 0;
      #|  }
      #|  100% {
      #|    opacity: 1;
      #|  }
      #|}
    ),
  )
}

///|
test "an import says which of its three layer states it is in" {
  fn imp(layer : @ast.LayerName??) -> String {
    @write.rule(
      Import({
        url: "reset.css",
        layer,
        supports: None,
        media: [],
        span: @span.nowhere,
      }),
    )
  }

  inspect(imp(None), content="@import \"reset.css\";")
  inspect(imp(Some(None)), content="@import \"reset.css\" layer;")
  inspect(
    imp(Some(Some({ parts: ["base", "theme"], }))),
    content="@import \"reset.css\" layer(base.theme);",
  )
}

///|
test "a condition parenthesises a nested operation and nothing else" {
  let c : @ast.Condition = Operation(Or, [
    Operation(And, [Feature(Boolean("hover")), Feature(Boolean("pointer"))]),
    Feature(Boolean("grid")),
  ])
  inspect(
    @write.rule(Supports({ condition: c, body: [], span: @span.nowhere, })),
    content="@supports ((hover) and (pointer)) or (grid) {}",
  )
}

///|
test "an unparsable region is echoed, not deleted" {
  let b : @ast.Bogus = @ast.Bogus::new(
    BadDeclaration,
    @span.nowhere,
    text="*zoom: 1",
  )
  let r = style_rule([cls("clearfix")], [
    Bogus(b),
    Decl(decl("display", [Ident("block")])),
  ])
  inspect(
    @write.rule(r),
    content=(
      #|.clearfix {
      #|  *zoom: 1
      #|  display: block;
      #|}
    ),
  )
}
