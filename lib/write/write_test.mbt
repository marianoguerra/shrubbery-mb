///|
fn w(src : String, style : @write.Style, width? : Int? = None) -> String raise {
  @write.write(@parser.parse(src).root(), style~, width~)
}

///|
/// The reference's own printer test, stated as a property: whatever is written
/// must read back as the same tree.
fn reparses(src : String) -> Unit raise {
  let tree = @parser.parse(src).root().canonical()
  let cases : Array[(String, @write.Style, Int?)] = [
    ("flat", Flat, None),
    ("pretty", Pretty, None),
    ("pretty/0", Pretty, Some(0)),
    ("pretty/40", Pretty, Some(40)),
    ("armoured", Armoured, None),
    ("armoured/0", Armoured, Some(0)),
    ("multiline", PreferMultiline, None),
    ("multiline/0", PreferMultiline, Some(0)),
  ]
  for c in cases {
    let (name, style, width) = c
    let printed = @write.write(@parser.parse(src).root(), style~, width~)
    let again = @parser.parse(printed).root().canonical()
    if again != tree {
      fail(
        "\{name}: printing changed the tree\n  input:   \{src.escape()}\n  printed: \{printed.escape()}\n  before:  \{tree}\n  after:   \{again}",
      )
    }
  }
}

///|
test "printing round-trips in every style" {
  for
    src in [
      "x + y\n", "hello:\n  world\n  universe\n", "f(1, 2, 3)\n", "a\n| b\n| c\n",
      "a:\n  b\n| c\n| d\n", "'a ('nested') b'\n", "[1, 2] {3} 'four'\n", "x: y: z\n",
      "def pi = 3.14\n", "fun fib(n):\n  match n\n  | 0: 0\n  | 1: 1\n  | n: fib(n-1) + fib(n-2)\n",
      "a\nb\nc\n", "empty:«»\n", "@typeset{Write @bold{\"hi\"}}\n", "x(~kw: 1, ~other: 2)\n",
      "#{treelist-ref}(x)\n", "1/2 0x1F #true #void #inf\n",
    ] {
    reparses(src)
  }
}

///|
test "the flat style is line- and column-insensitive" {
  // No line break and no column carries meaning, so the result reads the same
  // wherever it ends up.
  inspect(
    w("hello:\n  world\n  universe\n", Flat),
    content="hello:« world; universe »",
  )
  inspect(w("a\n| b\n| c\n", Flat), content="a |« b » |« c »")
  inspect(w("a\nb\n", Flat), content="a; b")
}

///|
test "the pretty style comes back onto one line when it fits" {
  inspect(
    w("hello:\n  world\n  universe\n", Pretty, width=Some(80)),
    content="hello: world; universe",
  )
  // At width zero nothing fits, so every break is taken.
  inspect(
    w("hello:\n  world\n  universe\n", Pretty, width=Some(0)),
    content=(
      #|hello:
      #|  world
      #|  universe
    ),
  )
}

///|
test "numbers are written the way Racket writes them" {
  // An integral flonum keeps its point; the notation has no other way to say
  // that it is not an exact integer.
  inspect(w("1.0\n", Flat), content="1.0")
  inspect(w("10.0\n", Flat), content="10.0")
  inspect(w("3.14\n", Flat), content="3.14")
  inspect(w("1/2\n", Flat), content="1/2")
  inspect(w("0x1F\n", Flat), content="31")
  inspect(w("#inf #neginf #nan\n", Flat), content="#inf #neginf #nan")
}

///|
test "a name the notation admits but the printer cannot spell is escaped" {
  // The printer's identifier rule is narrower than the notation's: it admits
  // letters, digits and `_`, so an emoji identifier comes back as an escape.
  inspect(w("\u{1F600}\n", Flat), content="#{\u{1F600}}")
}
