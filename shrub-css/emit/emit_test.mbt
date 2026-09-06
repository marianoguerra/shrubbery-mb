///|
/// The loop, closed.
///
/// The claim these tests make is the one the whole project is for: take CSS,
/// parse it, emit it as shrubbery, read that back, and print CSS again -- and
/// get the same CSS. Anything that survives the CSS parser's own round trip
/// must survive the detour through the notation too.
///
/// Comparing the two CSS strings rather than the two trees is deliberate. A
/// tree comparison would pass on a pair of trees that both print wrongly; the
/// string is the thing anyone actually receives.

///|
/// CSS in, CSS out, the short way: parse and print.
fn direct(src : String) -> String {
  let p = @parse.parse(src) catch {
    e => return "css parse raised: " + e.diagnostic().kind.code()
  }
  @write.stylesheet(p.sheet(), style=Minified)
}

///|
/// CSS in, CSS out, the long way: parse, emit as shrubbery, lower, print.
fn detour(src : String) -> String {
  let p = @parse.parse(src) catch {
    e => return "css parse raised: " + e.diagnostic().kind.code()
  }
  let shrub = @emit.stylesheet(p.sheet())
  let l = @lower.lower_source(shrub) catch {
    e => return "lowering raised: " + e.diagnostic().kind.code()
  }
  @write.stylesheet(l.sheet(), style=Minified)
}

///|
/// The shrubbery a piece of CSS becomes.
fn shrub(src : String) -> String {
  let p = @parse.parse(src) catch {
    e => return "css parse raised: " + e.diagnostic().kind.code()
  }
  @emit.stylesheet(p.sheet())
}

///|
/// The property, over one input: the detour changes nothing.
fn closes(src : String) -> Unit raise {
  let a = direct(src)
  let b = detour(src)
  if a != b {
    fail(
      "the loop did not close\n  css:     " +
      src +
      "\n  direct:  " +
      a +
      "\n  detour:  " +
      b +
      "\n  shrub:\n" +
      shrub(src),
    )
  }
}

///|
test "what a rule becomes" {
  inspect(
    shrub(".card { display: grid; gap: 1rem }"),
    content=(
      #|class(card):
      #|  display: grid
      #|  gap: rem(1)
      #|
    ),
  )
}

///|
test "what a selector becomes" {
  fn s(css : String) -> String raise {
    let p = @parse.parse(css + "{a:b}")
    match p.sheet().items[0] {
      Rule(Style(r)) => @emit.selector(r.selectors[0])
      _ => "not a style rule"
    }
  }

  inspect(s("nav a"), content="nav ~in a")
  inspect(s("nav > a"), content="nav ~child a")
  inspect(s("h2 + p"), content="h2 ~next p")
  inspect(s("h2 ~ p"), content="h2 ~sibling p")
  inspect(s("col || td"), content="col ~column td")
  inspect(s("a.b#c"), content="a class(b) id(c)")
  inspect(s("*"), content="any()")
  inspect(s("&:hover"), content="parent() hover()")
  inspect(s("p::before"), content="p element(before)")
  inspect(s("svg|circle"), content="circle ns(svg)")
  inspect(
    s("input[type=\"text\"]:not(:disabled)"),
    content="input has_attr(type = \"text\") not(disabled())",
  )
  inspect(s("li:nth-child(2n + 1)"), content="li nth_child(2 n + 1)")
  inspect(s("li:nth-child(-n+3)"), content="li nth_child(- n + 3)")
}

///|
test "what a value becomes" {
  fn v(css : String) -> String raise {
    let p = @parse.parse("a{p:" + css + "}")
    match p.sheet().items[0] {
      Rule(Style(r)) =>
        match r.body[0] {
          Decl(d) => @emit.value(d.value)
          _ => "not a declaration"
        }
      _ => "not a style rule"
    }
  }

  inspect(v("10px"), content="px(10)")
  inspect(v("1.5rem"), content="rem(1.5)")
  inspect(v("50%"), content="percent(50)")
  inspect(v("#f7f7f7"), content="hex(f7f7f7)")
  // Leading zeros cannot survive as a bare identifier, so the string escape is
  // not optional here -- the emitter must not create what the lowering refuses
  // to guess at.
  inspect(v("#007700"), content="hex(\"007700\")")
  inspect(v("Charter, Georgia, serif"), content="[Charter, Georgia, serif]")
  inspect(v("1 / 2"), content="1 / 2")
  inspect(v("rgb(0 0 0 / 5%)"), content="rgb(0 0 0 / percent(5))")
  inspect(v("var(--brand, red)"), content="var(--brand, red)")
  inspect(v("url(a.png)"), content="url(\"a.png\")")
  inspect(v("system-ui"), content="system_ui")
}

///|
test "the loop closes on everything the CSS tests cover" {
  let cases = [
    ".card{display:grid;gap:1rem}", "nav a{color:red}", "nav > a{color:red}", "h2 + p{a:b}",
    "h2 ~ p{a:b}", "col || td{a:b}", "a.b#c{a:b}", "*{a:b}", "h1, h2, h3{a:b}", "svg|circle{a:b}",
    "a.b{x:y}", "a .b{x:y}", "[hidden]{a:b}", "[type=\"text\"]{a:b}", "[class~=\"btn\"]{a:b}",
    "[lang|=\"en\"]{a:b}", "[href^=\"https\"]{a:b}", "[src$=\".png\"]{a:b}", "[title*=\"x\"]{a:b}",
    "[type=\"a\" i]{a:b}", "a:hover{a:b}", "a:not(.x, .y){a:b}", "a:is(h1, h2){a:b}",
    "li:nth-child(2n+1){a:b}", "li:nth-child(-n+3){a:b}", "li:nth-child(2n of .x){a:b}",
    "p::before{a:b}", "a:lang(en){a:b}", "&:hover{a:b}", "a{p:0.5em}", "a{p:50%}",
    "a{p:#FFF}", "a{p:rgb(0 0 0 / 5%)}", "a{p:Charter,Georgia,serif}", "a{p:1/2}",
    "a{p:calc(100% - 2rem)}", "a{p:var(--brand,red)}", "a{p:url(\"a/b.png\")}", ":root{--brand:red;color:var(--brand)}",
    "a{b:c !important}", "a{color:red;&:hover{color:blue};margin:0}", "@media (width <= 40rem){.c{p:1rem}}",
    "@media screen and (min-width:40rem){a{b:c}}", "@media only print{a{b:c}}", "@media (20rem <= width <= 40rem){a{b:c}}",
    "@supports not (display:grid){a{b:c}}", "@supports (a:b) and (c:d){x{y:z}}",
    "@supports selector(a > b){x{y:z}}", "@keyframes fade{from{o:0}100%{o:1}}", "@font-face{font-family:\"Inter\"}",
    "@charset \"utf-8\";", "@import \"a.css\" layer(base);", "@layer a,b;", "@layer base{a{b:c}}",
    "@namespace svg \"http://www.w3.org/2000/svg\";", "@container card (width > 20rem){a{b:c}}",
    "@page :first{margin:1in}", "@counter-style x{system:cyclic}", "@starting-style{a{b:c}}",
    "@property --x{syntax:\"*\"}", "a{-webkit-box-orient:vertical}", "a{p:3newunit}",
  ]
  for css in cases {
    closes(css)
  }
}

///|
test "the loop closes on a realistic stylesheet" {
  let src =
    #|@charset "utf-8";
    #|@import url("reset.css") layer(base);
    #|:root {
    #|  --brand: oklch(0.62 0.19 258);
    #|  --gap: 1rem;
    #|  color-scheme: light dark;
    #|}
    #|h1, h2, h3 {
    #|  margin-block: 0 0.5em;
    #|  font-family: Charter, Georgia, serif;
    #|}
    #|nav a {
    #|  color: var(--brand);
    #|  &:hover, &:focus-visible { text-decoration: underline }
    #|  &::after { content: " x" }
    #|}
    #|.card {
    #|  display: grid;
    #|  gap: var(--gap);
    #|  padding: 1rem 1.25rem;
    #|  box-shadow: 0 1px 2px rgb(0 0 0 / 5%), 0 8px 24px rgb(0 0 0 / 8%);
    #|  & > :first-child { font-weight: 600 }
    #|}
    #|#sidebar li:nth-child(2n + 1) { background: #f7f7f7 }
    #|input[type="text"]:not(:disabled) { border: 1px solid #ccc }
    #|@media (width <= 40rem) { .card { padding: 0.75rem } }
    #|@supports not (display: grid) { .card { display: flex } }
    #|@keyframes fade-in { from { opacity: 0 } to { opacity: 1 } }
    #|@font-face { font-family: "Inter"; src: url("inter.woff2") format("woff2") }
    #|.spinner { animation: fade-in 200ms ease-out both !important }
  closes(src)
}

///|
/// The two things the detour normalises, and why neither can be helped.
///
/// A CSS number keeps its source spelling in the CSS tree, and survives the CSS
/// parser's own round trip. It does NOT survive the detour through shrubbery,
/// because shrubbery's numeric literal holds a value rather than a spelling:
/// `1.50` arrives as the double 1.5, and `+1` arrives as 1 with the sign
/// already absorbed by the lexer.
///
/// Recovering either would mean reading the shrubbery node's raw metadata,
/// which the lowering deliberately never does -- that purity is what makes it
/// total over hand-built trees. So this is a documented normalisation rather
/// than a bug, and the test exists to say so out loud.
test "a number's spelling survives CSS but not the notation" {
  // The CSS round trip keeps it.
  inspect(direct("a{p:1.50}"), content="a{p:1.50}")
  inspect(direct("a{p:+1}"), content="a{p:+1}")
  // The detour does not.
  inspect(detour("a{p:1.50}"), content="a{p:1.5}")
  inspect(detour("a{p:+1}"), content="a{p:1}")
  // But it is a normalisation, not a loss of meaning: the value is the same,
  // and a second pass changes nothing.
  inspect(detour("a{p:1.5}"), content="a{p:1.5}")
  inspect(detour("a{p:1}"), content="a{p:1}")
}

///|
test "emitting is idempotent after one pass" {
  // `emit ∘ lower` is a normalisation, not an inverse: `1/2` and `1 / 2` are
  // the same value and only one of them comes back. What IS promised is that
  // the second pass changes nothing.
  let cases = [
    "class(card):\n  gap: rem(1)\n", "a:\n  p: 1/2\n", "a:\n  p: +1\n", "[h1, h2]:\n  a: b\n",
    "nav ~in a:\n  color: red\n",
  ]
  for src in cases {
    let once = @emit.stylesheet(@lower.lower_source(src).sheet())
    let twice = @emit.stylesheet(@lower.lower_source(once).sheet())
    assert_eq(once, twice)
  }
}

///|
test "emitted shrubbery always parses" {
  // Whatever the emitter produces has to be readable, including for inputs the
  // CSS parser only half understood.
  let cases = [
    "a{}", "@media{}", "@unknown x{a{b:c}}", "a{p:}", "a{}b{}", "@tailwind base;",
    "a{*zoom:1}", "a{p:[a b]}",
  ]
  for css in cases {
    let p = @parse.parse(css)
    let s = @emit.stylesheet(p.sheet())
    let l = @lower.lower_source(s)
    // It read back as something; the point is that nothing raised and the
    // notation accepted it.
    let _ = @write.stylesheet(l.sheet(), style=Minified)
  }
}
