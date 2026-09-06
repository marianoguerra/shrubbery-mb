///|
/// The parser, exercised through the printer.
///
/// Round-tripping is the honest test for a semantic tree: comparing against a
/// dump of the AST would only prove the parser agrees with itself, while
/// `parse` then `write` states what the pair actually promises -- that the CSS
/// comes back meaning the same thing.
///
/// Where the output differs from the input, that difference IS the claim:
/// `1.50` survives, `'x'` becomes `"x"`, `:before` becomes `::before`.

///|
/// Parse and print, tolerantly.
fn rt(src : String, style? : @write.Style = Pretty) -> String {
  let p = @parse.parse(src) catch {
    e => return "raised: " + e.diagnostic().kind.code()
  }
  @write.stylesheet(p.sheet(), style~)
}

///|
/// The diagnostics a parse produced, as codes.
fn codes(src : String) -> String {
  let p = @parse.parse(src) catch {
    e => return "raised: " + e.diagnostic().kind.code()
  }
  let out = StringBuilder()
  let mut first = true
  for d in p.diagnostics() {
    if !first {
      out.write_string(" ")
    }
    first = false
    out.write_string(d.kind.code())
  }
  out.to_string()
}

///|
/// The code a strict parse raised, or `None` if it accepted the input.
fn strict_code(src : String) -> String? {
  let _ = @parse.parse(src, strict=true) catch {
    e => return Some(e.diagnostic().kind.code())
  }
  None
}

///|
test "a stylesheet survives the round trip" {
  inspect(
    rt(".card{display:grid;gap:1rem}"),
    content=(
      #|.card {
      #|  display: grid;
      #|  gap: 1rem;
      #|}
      #|
    ),
  )
  inspect(
    rt(".card { display : grid ; }", style=Minified),
    content=".card{display:grid}",
  )
}

///|
test "selectors: every combinator and qualifier" {
  fn sel(s : String) -> String {
    rt(s + " { a: b }", style=Minified)
  }

  inspect(sel("nav a"), content="nav a{a:b}")
  inspect(sel("nav > a"), content="nav>a{a:b}")
  inspect(sel("h2 + p"), content="h2+p{a:b}")
  inspect(sel("h2 ~ p"), content="h2~p{a:b}")
  inspect(sel("col || td"), content="col||td{a:b}")
  inspect(sel("a.b#c"), content="a.b#c{a:b}")
  inspect(sel("*"), content="*{a:b}")
  inspect(sel("&:hover"), content="&:hover{a:b}")
  inspect(sel("h1, h2 , h3"), content="h1,h2,h3{a:b}")
  inspect(sel("svg|circle"), content="svg|circle{a:b}")
  inspect(sel("*|a"), content="*|a{a:b}")
  inspect(sel("|a"), content="|a{a:b}")
}

///|
test "the difference between a compound and a descendant is kept" {
  inspect(rt("a.b { x: y }", style=Minified), content="a.b{x:y}")
  inspect(rt("a .b { x: y }", style=Minified), content="a .b{x:y}")
}

///|
test "attribute selectors, all six matchers and both flags" {
  fn sel(s : String) -> String {
    rt(s + "{a:b}", style=Minified)
  }

  inspect(sel("[hidden]"), content="[hidden]{a:b}")
  inspect(sel("[type=\"text\"]"), content="[type=\"text\"]{a:b}")
  inspect(sel("[type=text]"), content="[type=text]{a:b}")
  inspect(sel("[class~=\"btn\"]"), content="[class~=\"btn\"]{a:b}")
  inspect(sel("[lang|=\"en\"]"), content="[lang|=\"en\"]{a:b}")
  inspect(sel("[href^=\"https\"]"), content="[href^=\"https\"]{a:b}")
  inspect(sel("[src$=\".png\"]"), content="[src$=\".png\"]{a:b}")
  inspect(sel("[title*=\"x\"]"), content="[title*=\"x\"]{a:b}")
  inspect(sel("[type=\"a\" i]"), content="[type=\"a\" i]{a:b}")
  inspect(sel("[type=\"a\" s]"), content="[type=\"a\" s]{a:b}")
}

///|
test "pseudo-classes by argument shape, and the legacy single colon" {
  fn sel(s : String) -> String {
    rt(s + "{a:b}", style=Minified)
  }

  inspect(sel("a:hover"), content="a:hover{a:b}")
  inspect(sel("a:not(.x, .y)"), content="a:not(.x,.y){a:b}")
  inspect(sel("a:is(h1, h2)"), content="a:is(h1,h2){a:b}")
  inspect(sel("li:nth-child(2n+1)"), content="li:nth-child(2n+1){a:b}")
  inspect(sel("li:nth-child(2n - 1)"), content="li:nth-child(2n-1){a:b}")
  // `odd` and `even` are spellings of a formula, and the tree stores the
  // formula. They come back numeric, the same way `:before` comes back `::`.
  inspect(sel("li:nth-child(odd)"), content="li:nth-child(2n+1){a:b}")
  inspect(sel("li:nth-child(even)"), content="li:nth-child(2n){a:b}")
  inspect(sel("li:nth-child(-n+3)"), content="li:nth-child(-n+3){a:b}")
  inspect(sel("li:nth-child(2n of .x)"), content="li:nth-child(2n of .x){a:b}")
  inspect(sel("p::before"), content="p::before{a:b}")
  // `:before` is the old spelling of a pseudo-element, and comes back as the
  // current one. That is a normalisation, and a deliberate one.
  inspect(sel("p:before"), content="p::before{a:b}")
  inspect(sel("a:lang(en)"), content="a:lang(en){a:b}")
}

///|
test "values keep the shape they arrived in" {
  fn v(s : String) -> String {
    rt("a{p:" + s + "}", style=Minified)
  }

  inspect(v("1.50"), content="a{p:1.50}")
  inspect(v("+1"), content="a{p:+1}")
  inspect(v("1e3"), content="a{p:1e3}")
  inspect(v("0.5em"), content="a{p:0.5em}")
  inspect(v("50%"), content="a{p:50%}")
  inspect(v("#FFF"), content="a{p:#FFF}")
  inspect(v("rgb(0 0 0 / 5%)"), content="a{p:rgb(0 0 0/5%)}")
  inspect(v("Charter, Georgia, serif"), content="a{p:Charter,Georgia,serif}")
  inspect(v("1 / 2"), content="a{p:1/2}")
  inspect(v("calc(100% - 2rem)"), content="a{p:calc(100% - 2rem)}")
  inspect(v("var(--brand, red)"), content="a{p:var(--brand,red)}")
  // A quoted url and an unquoted one are the same node.
  inspect(v("url(a/b.png)"), content="a{p:url(\"a/b.png\")}")
  inspect(v("url(\"a/b.png\")"), content="a{p:url(\"a/b.png\")}")
  // A single-quoted string comes back double-quoted.
  inspect(v("'x'"), content="a{p:\"x\"}")
}

///|
test "custom properties keep their leading dashes" {
  inspect(
    rt(":root { --brand: red; color: var(--brand) }", style=Minified),
    content=":root{--brand:red;color:var(--brand)}",
  )
}

///|
test "important is a flag, not a value" {
  inspect(rt("a{b:c !important}", style=Minified), content="a{b:c!important}")
  inspect(rt("a{b:c!IMPORTANT}", style=Minified), content="a{b:c!important}")
}

///|
test "nesting: a rule inside a rule, in source order" {
  inspect(
    rt("a { color: red; &:hover { color: blue } margin: 0 }"),
    content=(
      #|a {
      #|  color: red;
      #|  &:hover {
      #|    color: blue;
      #|  }
      #|  margin: 0;
      #|}
      #|
    ),
  )
}

///|
test "at-rules with typed preludes" {
  inspect(
    rt("@media (width <= 40rem) { .c { p: 1rem } }", style=Minified),
    content="@media (width<=40rem){.c{p:1rem}}",
  )
  inspect(
    rt("@media screen and (min-width: 40rem) { a{b:c} }", style=Minified),
    content="@media screen and (min-width:40rem){a{b:c}}",
  )
  inspect(
    rt("@media only print { a{b:c} }", style=Minified),
    content="@media only print{a{b:c}}",
  )
  inspect(
    rt("@media (20rem <= width <= 40rem) { a{b:c} }", style=Minified),
    content="@media (20rem<=width<=40rem){a{b:c}}",
  )
  inspect(
    rt("@supports not (display: grid) { a{b:c} }", style=Minified),
    content="@supports not (display:grid){a{b:c}}",
  )
  inspect(
    rt("@supports (a:b) and (c:d) { x{y:z} }", style=Minified),
    content="@supports (a:b) and (c:d){x{y:z}}",
  )
  inspect(
    rt("@supports selector(a > b) { x{y:z} }", style=Minified),
    content="@supports selector(a>b){x{y:z}}",
  )
  inspect(
    rt("@keyframes fade { from { o: 0 } 100% { o: 1 } }", style=Minified),
    content="@keyframes fade{from{o:0}100%{o:1}}",
  )
  inspect(
    rt("@font-face { font-family: \"Inter\" }", style=Minified),
    content="@font-face{font-family:\"Inter\"}",
  )
  inspect(
    rt("@charset \"utf-8\";", style=Minified),
    content="@charset \"utf-8\";",
  )
  inspect(
    rt("@import url(\"a.css\") layer(base) screen;", style=Minified),
    content="@import \"a.css\" layer(base) screen;",
  )
  inspect(rt("@layer a, b;", style=Minified), content="@layer a,b;")
  inspect(
    rt("@layer base { a{b:c} }", style=Minified),
    content="@layer base{a{b:c}}",
  )
  inspect(
    rt("@namespace svg \"http://www.w3.org/2000/svg\";", style=Minified),
    content="@namespace svg \"http://www.w3.org/2000/svg\";",
  )
  inspect(
    rt("@container card (width > 20rem) { a{b:c} }", style=Minified),
    content="@container card (width>20rem){a{b:c}}",
  )
  inspect(
    rt("@page :first { margin: 1in }", style=Minified),
    content="@page :first{margin:1in}",
  )
}

///|
test "an unknown at-rule is kept whole, with a warning" {
  inspect(
    rt("@tailwind base;\na{b:c}", style=Minified),
    content="@tailwind base;a{b:c}",
  )
  inspect(codes("@tailwind base;"), content="css::unknown_at_rule")
  inspect(
    rt("@unknown x { a{b:c} }", style=Minified),
    content="@unknown x{a{b:c}}",
  )
}

///|
test "recovery: a bad declaration is skipped, the rest survives" {
  inspect(
    rt("a { color red; margin: 0 }", style=Minified),
    content="a{margin:0}",
  )
  inspect(codes("a { color red; margin: 0 }"), content="css::expected_colon")
  inspect(rt("a { b: c } } d { e: f }", style=Minified), content="a{b:c}d{e:f}")
  inspect(codes("a { b: c } } d { e: f }"), content="css::unexpected_closer")
}

///|
test "strict mode raises where tolerant mode records" {
  let src = "a { color red }"
  inspect(codes(src), content="css::expected_colon")
  match strict_code(src) {
    Some(c) => assert_eq(c, "css::expected_colon")
    None => fail("strict mode accepted a bad declaration")
  }
}

///|
test "comments are kept between rules" {
  inspect(
    rt("/* first */\na { b: c }"),
    content=(
      #|/* first */
      #|a {
      #|  b: c;
      #|}
      #|
    ),
  )
}

///|
test "parsing terminates on anything, and never raises tolerantly" {
  let nasty = [
    "", "}", "{", "a{", "a{b", "a{b:", "@", "@media", "@media{", "a{}", "/*", "\"",
    "url(", ":::", "a::::b{c:d}", "[[[", ")))", "a{b:c;;;}", "@supports (){}", "@media (){}",
    ";;;", "&&&", "a{--x:}", "()",
  ]
  for s in nasty {
    let p = @parse.parse(s)
    // It produced a sheet, and printing it does not crash either.
    let _ = @write.stylesheet(p.sheet(), style=Minified)
  }
}

///|
/// A stylesheet with the shape real ones have: a reset, tokens, nesting, media
/// queries, keyframes, vendor prefixes and a hack.
///
/// The claim is not that the output equals the input -- it is a semantic tree,
/// so it will not. The claim is that a file like this parses **strictly**, with
/// no diagnostic at all, and that printing it and parsing it again is a fixed
/// point. That second half is the property the whole design rests on.
test "a realistic stylesheet parses strictly and is a printing fixed point" {
  let src =
    #|@charset "utf-8";
    #|@import url("reset.css") layer(base);
    #|
    #|:root {
    #|  --brand: oklch(0.62 0.19 258);
    #|  --gap: 1rem;
    #|  color-scheme: light dark;
    #|}
    #|
    #|h1, h2, h3 {
    #|  margin-block: 0 0.5em;
    #|  font-family: Charter, Georgia, serif;
    #|}
    #|
    #|nav a {
    #|  color: var(--brand);
    #|  &:hover, &:focus-visible { text-decoration: underline }
    #|  &::after { content: " \2197" }
    #|}
    #|
    #|.card {
    #|  display: grid;
    #|  gap: var(--gap);
    #|  padding: 1rem 1.25rem;
    #|  box-shadow: 0 1px 2px rgb(0 0 0 / 5%), 0 8px 24px rgb(0 0 0 / 8%);
    #|  & > :first-child { font-weight: 600 }
    #|}
    #|
    #|#sidebar li:nth-child(2n + 1) { background: #f7f7f7 }
    #|input[type="text"]:not(:disabled) { border: 1px solid #ccc }
    #|
    #|@media (width <= 40rem) {
    #|  .card { padding: 0.75rem }
    #|}
    #|
    #|@supports not (display: grid) {
    #|  .card { display: flex }
    #|}
    #|
    #|@keyframes fade-in {
    #|  from { opacity: 0 }
    #|  to { opacity: 1 }
    #|}
    #|
    #|@font-face {
    #|  font-family: "Inter";
    #|  src: url("inter.woff2") format("woff2");
    #|}
    #|
    #|.spinner {
    #|  -webkit-animation: fade-in 200ms ease-out both;
    #|  animation: fade-in 200ms ease-out both !important;
    #|}
  // No diagnostics at all: strict mode accepts it.
  inspect(codes(src), content="")
  match strict_code(src) {
    Some(c) => fail("strict mode rejected a valid stylesheet: " + c)
    None => ()
  }
  // Printing and reparsing reaches a fixed point after one pass, in every mode.
  for style in [@write.Style::Pretty, Compact, Minified] {
    let once = rt(src, style~)
    let twice = rt(once, style~)
    assert_eq(once, twice)
  }
}
