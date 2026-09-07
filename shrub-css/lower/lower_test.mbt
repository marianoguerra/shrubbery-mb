///|
/// Shrubbery CSS, lowered and printed as CSS.
///
/// Printing is how the lowering is checked, for the same reason the CSS
/// parser's tests print: comparing against a tree dump would prove only that
/// the lowering agrees with itself, while the CSS on the right is the thing a
/// reader can check against what they know.

///|
/// Lower shrubbery-CSS source and print it as minified CSS.
fn css(src : String) -> String {
  let l = @lower.lower_source(src) catch {
    e => return "raised: " + e.diagnostic().kind.code()
  }
  @write.stylesheet(l.sheet(), style=Minified)
}

///|
/// The diagnostic codes a lowering produced.
fn codes(src : String) -> String {
  let l = @lower.lower_source(src) catch {
    e => return "raised: " + e.diagnostic().kind.code()
  }
  let out = StringBuilder()
  let mut first = true
  for d in l.diagnostics() {
    if !first {
      out.write_string(" ")
    }
    first = false
    out.write_string(d.kind.code())
  }
  out.to_string()
}

///|
test "a rule, and the declaration that needed no translation at all" {
  let src =
    #|class(card):
    #|  display: grid
    #|  gap: rem(1)
  inspect(css(src), content=".card{display:grid;gap:1rem}")
}

///|
test "things are calls" {
  fn sel(s : String) -> String {
    css(s + ":\n  a: b\n")
  }

  inspect(sel("class(card)"), content=".card{a:b}")
  inspect(sel("id(sidebar)"), content="#sidebar{a:b}")
  inspect(sel("any()"), content="*{a:b}")
  inspect(sel("parent()"), content="&{a:b}")
  inspect(sel("nav hover()"), content="nav:hover{a:b}")
  inspect(sel("p element(before)"), content="p::before{a:b}")
  inspect(sel("a not(disabled())"), content="a:not(:disabled){a:b}")
  inspect(sel("a is(h1, h2)"), content="a:is(h1,h2){a:b}")
  inspect(sel("li nth_child(2 n + 1)"), content="li:nth-child(2n+1){a:b}")
  inspect(sel("li nth_child(odd)"), content="li:nth-child(2n+1){a:b}")
  inspect(
    sel("input has_attr(type = \"text\")"),
    content="input[type=\"text\"]{a:b}",
  )
  inspect(sel("circle ns(svg)"), content="svg|circle{a:b}")
  inspect(sel("a lang(en)"), content="a:lang(en){a:b}")
}

///|
test "relations are keywords, and juxtaposition is a compound" {
  fn sel(s : String) -> String {
    css(s + ":\n  a: b\n")
  }

  inspect(sel("nav ~in a"), content="nav a{a:b}")
  inspect(sel("nav ~child a"), content="nav>a{a:b}")
  inspect(sel("h2 ~next p"), content="h2+p{a:b}")
  inspect(sel("h2 ~sibling p"), content="h2~p{a:b}")
  inspect(sel("col ~column td"), content="col||td{a:b}")
  // The distinction the previous draft could not express at all: these differ.
  inspect(sel("a class(b)"), content="a.b{a:b}")
  inspect(sel("a ~in class(b)"), content="a .b{a:b}")
}

///|
test "a selector list is a bracket, and is() stays the pseudo-class" {
  inspect(css("[h1, h2, h3]:\n  a: b\n"), content="h1,h2,h3{a:b}")
  // Not the same thing: `:is()` gives every arm the specificity of its most
  // specific member, which is exactly why a list may not be spelled this way.
  inspect(css("is(h1, h2):\n  a: b\n"), content=":is(h1,h2){a:b}")
}

///|
test "values: units, percentages, hex colours and the slash" {
  fn v(s : String) -> String {
    css("a:\n  p: " + s + "\n")
  }

  inspect(v("px(10)"), content="a{p:10px}")
  inspect(v("rem(1.5)"), content="a{p:1.5rem}")
  inspect(v("ms(200)"), content="a{p:200ms}")
  inspect(v("percent(50)"), content="a{p:50%}")
  inspect(v("hex(f7f7f7)"), content="a{p:#f7f7f7}")
  inspect(v("hex(\"007700\")"), content="a{p:#007700}")
  inspect(v("dim(3, \"newunit\")"), content="a{p:3newunit}")
  // `1/2` is one rational literal to the lexer, and three things to CSS.
  // Unfolding it is what makes both spellings agree.
  inspect(v("1 / 2"), content="a{p:1/2}")
  inspect(v("1/2"), content="a{p:1/2}")
  inspect(v("[Charter, Georgia, serif]"), content="a{p:Charter,Georgia,serif}")
  inspect(v("rgb(0 0 0 / percent(5))"), content="a{p:rgb(0 0 0/5%)}")
  inspect(v("calc(percent(100) - rem(2))"), content="a{p:calc(100% - 2rem)}")
  inspect(v("url(\"a/b.png\")"), content="a{p:url(\"a/b.png\")}")
  inspect(v("red important()"), content="a{p:red!important}")
}

///|
test "hyphens: underscores become them, and the two escapes" {
  inspect(
    css("a:\n  font_family: system_ui\n"),
    content="a{font-family:system-ui}",
  )
  inspect(
    css("a:\n  _webkit_box_orient: vertical\n"),
    content="a{-webkit-box-orient:vertical}",
  )
  // A custom property keeps its dashes, and `var()` is CSS's own call.
  inspect(
    css("root():\n  --brand: red\n  color: var(--brand)\n"),
    content=":root{--brand:red;color:var(--brand)}",
  )
  // A name that genuinely contains `_` has no bare spelling, so it is written
  // as a literal.
  inspect(
    css("class(\"btn__primary\"):\n  a: b\n"),
    content=".btn__primary{a:b}",
  )
  inspect(
    css("a:\n  ident(\"grid_area\"): side_bar\n"),
    content="a{grid_area:side-bar}",
  )
}

///|
test "nesting, in source order" {
  let src =
    #|nav ~in a:
    #|  color: red
    #|  parent() hover():
    #|    color: blue
    #|  margin: 0
  // No `;` after the nested rule: its `}` already ended it, and a declaration
  // may follow a block directly.
  inspect(css(src), content="nav a{color:red;&:hover{color:blue}margin:0}")
}

///|
test "at-rules are calls" {
  inspect(
    css("media(width <= rem(40)):\n  class(c):\n    p: rem(1)\n"),
    content="@media (width<=40rem){.c{p:1rem}}",
  )
  // The block form is the plain feature; `=` is a range test that compares
  // for equality. CSS has both and they are different nodes, so the syntax
  // needs two spellings too.
  inspect(
    css("media(screen and (min_width: rem(40))):\n  a:\n    b: c\n"),
    content="@media screen and (min-width:40rem){a{b:c}}",
  )
  inspect(
    css("media((min_width = rem(40))):\n  a:\n    b: c\n"),
    content="@media (min-width=40rem){a{b:c}}",
  )
  inspect(
    css("supports(not (display: grid)):\n  a:\n    b: c\n"),
    content="@supports not (display:grid){a{b:c}}",
  )
  inspect(
    css(
      "keyframes(fade_in):\n  percent(0):\n    opacity: 0\n  to:\n    opacity: 1\n",
    ),
    content="@keyframes fade-in{0%{opacity:0}to{opacity:1}}",
  )
  inspect(
    css("font_face():\n  font_family: \"Inter\"\n"),
    content="@font-face{font-family:\"Inter\"}",
  )
  inspect(css("charset(\"utf-8\")\n"), content="@charset \"utf-8\";")
  inspect(
    css("import(\"a.css\", layer(base))\n"),
    content="@import \"a.css\" layer(base);",
  )
  inspect(css("layer(base, components)\n"), content="@layer base,components;")
  inspect(
    css("namespace(svg, \"http://www.w3.org/2000/svg\")\n"),
    content="@namespace svg \"http://www.w3.org/2000/svg\";",
  )
  inspect(
    css("container(card, (width > rem(20))):\n  a:\n    b: c\n"),
    content="@container card (width>20rem){a{b:c}}",
  )
}

///|
test "the hazard is named rather than silent" {
  // `a: hover` is structurally a declaration and reads as one; the diagnostic
  // is what turns a silent misparse into a told one.
  inspect(codes("nav:\n  a: hover\n"), content="shrubcss::colon_pseudo")
  // At the top of a file there are no declarations, so the same mistake wears
  // its other spelling -- a bare word in a rule body -- and gets the same help.
  inspect(
    codes("a: hover\n"),
    content=(
      #|shrubcss::colon_pseudo
    ),
  )
  // But a real property whose value happens to be a pseudo-class name stays
  // quiet -- which is the guard that makes the check usable at all.
  inspect(codes("a:\n  cursor: default\n"), content="")
}

///|
test "CSS's own spellings are refused, with the replacement named" {
  inspect(codes(".card:\n  a: b\n"), content="shrubcss::sigil_selector")
  inspect(codes("a ~nonsense b:\n  a: b\n"), content="shrubcss::stray_keyword")
  // Two element names touching: the mistake a CSS habit produces.
  inspect(
    codes("nav a:\n  x: y\n"),
    content="shrubcss::type_selector_not_first",
  )
}

///|
test "a lexical mistake is met with the thing to type instead" {
  // `10px`, `#fff` and `@media` are rejected by the notation itself, before
  // any of this runs, so the help is attached on the way past.
  inspect(codes("a:\n  width: 10px\n"), content="shrubcss::unsupported")
  inspect(codes("a:\n  color: #fff\n"), content="shrubcss::sigil_selector")
  // `@media` is not even an error to the notation: at-notation swallows the
  // `@` and leaves `media screen` behind, so this is the only layer that can
  // notice, and it says "an at-rule is a call".
  inspect(
    codes("@media screen:\n  a:\n    b: c\n"),
    content="shrubcss::sigil_selector",
  )
}

///|
test "lowering terminates on anything, and never raises tolerantly" {
  let nasty = [
    "", "a", "a:", ":", "()", "[]", "a:\n  b\n", "class():\n  a: b\n", "~in:\n  a: b\n",
    "a ~in:\n  b: c\n", "hex():\n  a: b\n", "media():\n  a:\n    b: c\n", "px():\n  a: b\n",
    "a:\n  b: c\n  d: e\n", "unknown_thing(x):\n  a: b\n",
  ]
  for s in nasty {
    let l = @lower.lower_source(s)
    let _ = @write.stylesheet(l.sheet(), style=Minified)
  }
}

///|
test "a declaration at the top of a file is refused, not reinterpreted" {
  // Reading it as a rule prints `color{ red}` -- something that looks like
  // valid CSS, is not, and hides the mistake instead of naming it.
  inspect(codes("color: red\n"), content="shrubcss::declaration_at_top_level")
  inspect(css("color: red\n"), content="color: red")
  inspect(
    codes("font_family: system_ui\n"),
    content="shrubcss::declaration_at_top_level",
  )
  // The `a: hover` mistake keeps its own diagnostic, which is the more useful
  // one: the author meant a selector, not a declaration.
  inspect(codes("a: hover\n"), content="shrubcss::colon_pseudo")
}

///|
test "a top-level-only at-rule inside a rule is refused" {
  // A browser DROPS a nested `@font-face` rather than complaining, so printing
  // it emits CSS that silently does nothing.
  inspect(
    codes("class(a):\n  font_face():\n    font_family: \"X\"\n"),
    content="shrubcss::at_rule_not_nestable",
  )
  // Blockless ones reach the check too, though they arrive as a bare term.
  inspect(
    codes("class(a):\n  charset(\"utf-8\")\n"),
    content="shrubcss::at_rule_not_nestable",
  )
  inspect(
    codes("class(a):\n  import(\"x.css\")\n"),
    content="shrubcss::at_rule_not_nestable",
  )
  // The conditional group rules nest, and are unaffected.
  inspect(
    css("class(a):\n  media(screen):\n    color: red\n"),
    content=".a{@media screen{color:red}}",
  )
  // And a `@font-face` inside an `@media` at the top of a file is still legal:
  // the check is against the ENCLOSING context, which `media()` leaves at the
  // top level.
  inspect(
    css("media(screen):\n  font_face():\n    font_family: \"X\"\n"),
    content="@media screen{@font-face{font-family:\"X\"}}",
  )
  inspect(
    codes("media(screen):\n  font_face():\n    font_family: \"X\"\n"),
    content="",
  )
}

///|
test "a nested rule where only declarations belong is refused" {
  inspect(
    codes("font_face():\n  a:\n    color: red\n"),
    content="shrubcss::rule_in_declaration_context",
  )
  // Keyframes and page bodies are unaffected: neither goes through the
  // declaration-only context.
  inspect(
    css("keyframes(spin):\n  percent(0):\n    opacity: 0\n"),
    content="@keyframes spin{0%{opacity:0}}",
  )
  inspect(css("page():\n  margin: cm(2)\n"), content="@page{margin:2cm}")
}

///|
test "a refusal carries no layout into minified output" {
  // The echo is the shrubbery that was written, printed flat -- not reproduced
  // from the node's raw metadata, which carried its newline and its indent into
  // a stylesheet that is supposed to have neither.
  let out = css(
    "class(a):\n  color: red\n  charset(\"utf-8\")\n  background: blue\n",
  )
  inspect(out.contains("\n"), content="false")
  inspect(out, content=".a{color:red;charset (\"utf-8\");background:blue}")
}

///|
test "a rule body lowers on its own" {
  // A scoped fragment is made of the declarations `lower` refuses at the top of
  // a file, and correctly refuses. This is the same lowering one level in.
  let l = @lower.lower_block_source("color: red\nclass(b):\n  color: blue\n")
  inspect(l.items().length(), content="2")
  inspect(l.diagnostics().length(), content="0")
  inspect(l.has_errors(), content="false")
  let printed = StringBuilder()
  for item in l.items() {
    match item {
      Decl(d) => printed.write_string(@write.declaration(d, style=Minified))
      Rule(r) => printed.write_string(@write.rule(r, style=Minified))
      _ => ()
    }
  }
  inspect(printed.to_string(), content="color:red.b{color:blue}")
  // The refusals a rule body has of its own still apply.
  let bad = @lower.lower_block_source("font_face():\n  font_family: \"X\"\n")
  inspect(
    bad.diagnostics()[0].kind.code(),
    content="shrubcss::at_rule_not_nestable",
  )
}
