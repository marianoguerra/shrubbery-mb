///|
fn p(src : String) -> String raise {
  @parser.parse(src).root().canonical()
}

///|
test "the worked examples from the specification" {
  inspect(
    p("def pi = 3.14\n"),
    content="(multi (group |def| |pi| (op |=|) #f64:40091eb851eb851f))",
  )
  inspect(
    p("if x == y\n| #'same\n| #'different\n"),
    content=(
      #|(multi (group |if| |x| (op |==|) |y| (alts (block (group (op |#'|) |same|)) (block (group (op |#'|) |different|)))))
    ),
  )
}

///|
test "a block is opened by a colon and closed by dedenting" {
  inspect(
    p("hello:\n  world\n  universe\n"),
    content="(multi (group |hello| (block (group |world|) (group |universe|))))",
  )
  // All four of these are the same document, per the specification.
  let a = p("hello:\n world\n universe\n")
  let b = p("hello:\n       world\n       universe\n")
  let c = p("hello: world\n       universe\n")
  let d = p("hello:    world\n          universe\n")
  assert_eq(a, b)
  assert_eq(a, c)
  assert_eq(a, d)
}

///|
test "alternatives, however they are laid out" {
  let a = p("hello\n| world\n| universe\n")
  let b = p("hello | world\n      | universe\n")
  let c = p("hello |\n        world\n      |\n        universe\n")
  assert_eq(
    a, "(multi (group |hello| (alts (block (group |world|)) (block (group |universe|)))))",
  )
  assert_eq(a, b)
  assert_eq(a, c)
  // An optional `:` before alternatives on a new line is not preserved.
  assert_eq(p("hello:\n| world\n| universe\n"), a)
}

///|
test "guillemets say the same thing without indentation" {
  let indented = p("hello:\n  if x\n  | world\n    planet\n  | universe\n")
  let flat = p("hello: if x | world; planet | universe\n")
  let armoured = p("hello:« if x |« world; planet » |« universe »»\n")
  assert_eq(indented, flat)
  assert_eq(indented, armoured)
}

///|
test "the classic ambiguities are different documents" {
  // `rind` is inside `inside:` in the first and beside it in the second.
  assert_not_eq(
    p("outside:\n  inside: fruit\n  rind\n"),
    p("outside: inside: fruit; rind\n"),
  )
  assert_eq(
    p("outside:\n  inside: fruit\n  rind\n"),
    p("outside: inside:« fruit »; rind\n"),
  )
}

///|
test "separators" {
  inspect(
    p("(1, 2, 3)\n"),
    content="(multi (group (parens (group 1) (group 2) (group 3))))",
  )
  // A `;` separates groups within a block; a `,` closes back to the bracket.
  inspect(
    p("(hello: world; universe)\n"),
    content="(multi (group (parens (group |hello| (block (group |world|) (group |universe|))))))",
  )
  inspect(
    p("(hello: world, universe)\n"),
    content="(multi (group (parens (group |hello| (block (group |world|))) (group |universe|))))",
  )
}

///|
test "brackets, braces and quotes keep their kind" {
  inspect(
    p("[1] {2} '3'\n"),
    content="(multi (group (brackets (group 1)) (braces (group 2)) (quotes (group 3))))",
  )
  // `'«…»'` disambiguates nested quotes and is not preserved: this is the
  // only way to write a quote directly inside a quote.
  inspect(
    p("'«a 'nested' b»'\n"),
    content="(multi (group (quotes (group |a| (quotes (group |nested|)) |b|))))",
  )
}

///|
test "a backslash joins two lines" {
  assert_eq(p("this is \\\nthe first group\n"), p("this is the first group\n"))
  // Blank and comment lines do not count as the next line.
  assert_eq(p("a \\\n/* c */\nb\n"), p("a b\n"))
}

///|
test "group comments remove a group or an alternative" {
  assert_eq(p("#// a\nb\n"), p("b\n"))
  assert_eq(p("a\n#// b\nc\n"), p("a\nc\n"))
  // A `#//` before a `|` must be on that `|`'s line, and may not START the
  // line: were it allowed to, its own column would have to line up with the
  // alternatives and it would mean two different things at once.
  assert_eq(p("x | a #// | b | c\n"), p("x | a | c\n"))
}

///|
test "at-notation becomes an ordinary call" {
  assert_eq(
    p("@typeset{Write \"hello\"}\n"),
    p("typeset([\"Write \\\"hello\\\"\"])\n"),
  )
  assert_eq(
    p("@typeset(~style: bold){Write}\n"),
    p("typeset(~style: bold, [\"Write\"])\n"),
  )
}

///|
test "an s-expression escape is an ordinary term" {
  inspect(
    p("#{treelist-ref}(x)\n"),
    content="(multi (group |treelist-ref| (parens (group |x|))))",
  )
}
