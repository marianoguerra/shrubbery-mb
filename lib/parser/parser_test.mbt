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

///|
/// Parse and rebuild.
fn rt(src : String) -> String raise {
  @parser.parse(src).root().to_source()
}

///|
test "the source rebuilds from the tree" {
  // Every byte, including the parts the tree does not otherwise record:
  // whitespace, comments, the `:` that opened a block, the closer of a paren.
  for
    src in [
      "x + y\n", "hello:\n  world\n  universe\n", "f(1, 2)\n", "a\n| b\n| c\n", "'a ('nested') b'\n",
      "x /* between */ y // after\n", "this is \\\nthe first group\n", "#// a\nb\n",
      "hello:« if x |« world; planet » |« universe »»\n", "@typeset{Write @bold{\"hi\"}}\n",
      "@f(a){b}{c}\n", "\n\n  leading and trailing\n\n",
    ] {
    assert_eq(rt(src), src)
  }
}

///|
test "a comment stays with what it was written about" {
  // The trailing comment belongs to the block it is indented with, not to the
  // group that follows it -- which is what `keep_same_indentation_comments`
  // decides and what makes the rebuild put it back in the right place.
  assert_eq(
    rt("begin:\n 1+2\n // sticks\n\nnext\n"),
    "begin:\n 1+2\n // sticks\n\nnext\n",
  )
}

///|
test "de-indented text keeps the text it was written with" {
  // The datum is the line without its shared indentation; the raw is the line
  // as written. Keeping only one would either change what the text says or
  // make the source unreconstructable.
  let src =
    #|@a{
    #|   one
    #|   two
    #|}
    #|
  assert_eq(rt(src), src)
  inspect(
    p(src),
    content="(multi (group |a| (parens (group (brackets (group \"one\") (group \"\\u{a}\") (group \"two\"))))))",
  )
}

///|
/// Recovery mode on a body whose `@` has nothing valid after it.
///
/// Reported from three directions at once, as a native SIGSEGV and as a
/// wasm-gc `RangeError`, with three different accounts of which inputs did it.
/// None of the accounts held, because the trigger was never the character
/// after the `@`: any failure inside a body strands the body's own tokens at
/// group level, where `AtContent` ends a group without consuming it, and
/// `parse_groups` and `parse_one_group` then call each other for ever. Only
/// recovery reached it -- the first mistake is raised otherwise, before the
/// stranded tokens are seen.
///
/// So the cases below are a net rather than a rule. What makes the bug fixed
/// is that `parse_one_group` refuses to ask for "the rest of the sequence"
/// after a group that consumed nothing; this test is what stops that guard
/// being removed by someone who cannot see what it was for.
test "recovery terminates on every reported at-notation crash" {
  let bodies = [
    "@", "@@", "@@@", "@ ", "@\t", "@ x", "@  x", "x@", "x @ y", "@,", "@}", " @@",
    "@}}", "@1x", "a@1b", ".a { --x: @ }", "@)", "@]", "a@}",
  ]
  for body in bodies {
    let src = "view:\n  C:\n    @style{" + body + "}\n"
    // Returning at all is the claim. Every one of these used to take the
    // process with it.
    let parsed = @parser.parse(src, recover=true)
    assert_true(parsed.diagnostics().length() > 0)
  }
  // And the shapes that were always fine still are.
  for body in ["@x", "@1", "@(1)", "a@b", "plain", "@media (a) { b }"] {
    let src = "view:\n  C:\n    @style{" + body + "}\n"
    assert_eq(@parser.parse(src, recover=true).diagnostics().length(), 0)
  }
}

///|
/// A closer straight after an `@` is the LEXER's complaint.
///
/// The reference reads the term after an `@` through its lexer, so `@}` is a
/// read error at the `}` rather than "invalid after `@`" at the `@`. `@@` is
/// the other way round: that token lexes cleanly and is merely in the wrong
/// place. Nothing in the 696-file corpus writes either, which is why this
/// divergence survived the differential suite and needs a test of its own.
test "an unmatched closer after an at-sign is a read error" {
  for src in ["@f{@}", "@f{@)}", "@)", "@]", "(@)", "@f{a@}b}"] {
    let message = try {
      let _ = @parser.parse(src + "\n")
      "accepted"
    } catch {
      ShrubberyError(d) => d.kind.reference_text()
    }
    assert_eq(message, "read error")
  }
  for src in ["@f{a@@b}", "@f{@,}"] {
    let message = try {
      let _ = @parser.parse(src + "\n")
      "accepted"
    } catch {
      ShrubberyError(d) => d.kind.reference_text()
    }
    assert_eq(message, "invalid after `@`")
  }
}

///|
/// Nesting is bounded, so that input nested without end is refused rather than
/// running the stack out.
///
/// The limit is far past anything written by hand and comfortably below where
/// the smallest backend gives up. This test is the second half of that claim,
/// since it runs on wasm, wasm-gc, js and native: a bound that only held on
/// the roomiest stack would not be worth having, and `wasm` -- where nested
/// blocks overflow between 90 and 100 levels -- is the one that sets it.
///
/// It raises even under `recover=true`: recovery means carrying on, and there
/// is nowhere to carry on to when the parser cannot descend.
test "nesting past the limit is refused rather than fatal" {
  let deep = (n : Int) => {
    let b = StringBuilder()
    for _ in 0..<n {
      b.write_string("(")
    }
    b.write_string("x")
    for _ in 0..<n {
      b.write_string(")")
    }
    b.write_string("\n")
    b.to_string()
  }
  // Under the limit, ordinary input.
  let _ = @parser.parse(deep(@parser.default_max_depth - 4))
  for n in [@parser.default_max_depth + 4, 5000] {
    for recover in [false, true] {
      let kind = try {
        let _ = @parser.parse(deep(n), recover~)
        "accepted"
      } catch {
        ShrubberyError(d) => d.kind.code()
      }
      assert_eq(kind, "shrubbery::nesting_too_deep")
    }
  }
  // Blocks nest through a different path and are bounded by the same counter.
  let blocks = StringBuilder()
  for i in 0..<200 {
    for _ in 0..<i {
      blocks.write_string(" ")
    }
    blocks.write_string("a:\n")
  }
  let kind = try {
    let _ = @parser.parse(blocks.to_string(), recover=true)
    "accepted"
  } catch {
    ShrubberyError(d) => d.kind.code()
  }
  assert_eq(kind, "shrubbery::nesting_too_deep")
}
