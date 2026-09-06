///|
/// The tokenizer, against the cases that separate a correct CSS scanner from a
/// plausible one.

///|
/// Token kinds only, joined -- spans are checked separately, because putting
/// them in every case would bury what each case is actually about.
fn kinds(src : String) -> String {
  let out = StringBuilder()
  let mut first = true
  for t in @token.tokenize(src) {
    if t.kind == Eof {
      break
    }
    if !first {
      out.write_string(" ")
    }
    first = false
    out.write_string(t.kind.to_debug())
  }
  out.to_string()
}

///|
test "the shapes a declaration is made of" {
  inspect(
    kinds("color: red;"),
    content="Ident(\"color\") Colon Whitespace Ident(\"red\") Semicolon",
  )
  inspect(
    kinds(".card { gap: 1rem }"),
    content=(
      #|Delim(".") Ident("card") Whitespace LBrace Whitespace Ident("gap") Colon Whitespace Dimension("1", "rem") Whitespace RBrace
    ),
  )
}

///|
test "a number keeps its spelling, and knows whether it was an integer" {
  inspect(
    kinds("1"),
    content=(
      #|Number("1", int)
    ),
  )
  inspect(
    kinds("1.50"),
    content=(
      #|Number("1.50", num)
    ),
  )
  inspect(
    kinds("+1"),
    content=(
      #|Number("+1", int)
    ),
  )
  inspect(
    kinds("-0.5"),
    content=(
      #|Number("-0.5", num)
    ),
  )
  inspect(
    kinds("1e3"),
    content=(
      #|Number("1e3", num)
    ),
  )
  inspect(
    kinds("50%"),
    content=(
      #|Percentage("50")
    ),
  )
  inspect(
    kinds("10px"),
    content=(
      #|Dimension("10", "px")
    ),
  )
  // A `.` with no digit after it is a delimiter, which is what makes `.card`
  // a class selector rather than a malformed number.
  inspect(
    kinds(".5"),
    content=(
      #|Number(".5", num)
    ),
  )
  inspect(
    kinds(".card"),
    content=(
      #|Delim(".") Ident("card")
    ),
  )
}

///|
test "the three-character lookahead that `-` needs" {
  inspect(kinds("-webkit-box"), content="Ident(\"-webkit-box\")")
  inspect(kinds("--brand"), content="Ident(\"--brand\")")
  inspect(
    kinds("-1px"),
    content=(
      #|Dimension("-1", "px")
    ),
  )
  inspect(kinds("-->"), content="Cdc")
  inspect(kinds("<!--"), content="Cdo")
  inspect(
    kinds("- "),
    content=(
      #|Delim("-") Whitespace
    ),
  )
}

///|
test "a hash knows whether it could be an id" {
  inspect(kinds("#sidebar"), content="Hash(\"sidebar\", Id)")
  inspect(kinds("#f7f7f7"), content="Hash(\"f7f7f7\", Id)")
  // Leading digits make it a colour but not a valid id.
  inspect(kinds("#1a2b3c"), content="Hash(\"1a2b3c\", Unrestricted)")
  inspect(
    kinds("# "),
    content=(
      #|Delim("#") Whitespace
    ),
  )
}

///|
test "a function's paren is part of its token" {
  inspect(
    kinds("rgb(0 0 0)"),
    content=(
      #|Function("rgb") Number("0", int) Whitespace Number("0", int) Whitespace Number("0", int) RParen
    ),
  )
  // With a space before the paren it is an ident and a group, which is a
  // different thing and has to tokenize differently.
  inspect(
    kinds("rgb (0)"),
    content=(
      #|Ident("rgb") Whitespace LParen Number("0", int) RParen
    ),
  )
}

///|
test "url is a token only when its body is unquoted" {
  inspect(kinds("url(a/b.png)"), content="Url(\"a/b.png\")")
  inspect(kinds("url( a/b.png )"), content="Url(\"a/b.png\")")
  inspect(
    kinds("url(\"a/b.png\")"),
    content="Function(\"url\") Str(\"a/b.png\") RParen",
  )
  // An unquoted body may not contain a quote, and the remnants are discarded
  // through the closing paren so the parser resumes in a sane place.
  inspect(kinds("url(a\"b) x"), content="BadUrl Whitespace Ident(\"x\")")
}

///|
test "strings, escapes and the newline that ends one badly" {
  inspect(kinds("\"a b\""), content="Str(\"a b\")")
  inspect(kinds("'a b'"), content="Str(\"a b\")")
  inspect(kinds("\"a\\\"b\""), content="Str(\"a\\\"b\")")
  // `\26` is `&`; the space after the digits is part of the escape.
  inspect(kinds("\"\\26 B\""), content="Str(\"&B\")")
  inspect(
    kinds("\"a\nb\""),
    content=(
      #|BadStr Whitespace Ident("b") Str("")
    ),
  )
}

///|
test "an escape inside an identifier" {
  inspect(kinds("\\41 BC"), content="Ident(\"ABC\")")
  inspect(kinds("a\\-b"), content="Ident(\"a-b\")")
}

///|
test "comments are tokens, and an unterminated one runs to the end" {
  inspect(
    kinds("a /* x */ b"),
    content="Ident(\"a\") Whitespace Comment(\" x \") Whitespace Ident(\"b\")",
  )
  inspect(kinds("/* x"), content="Comment(\" x\")")
}

///|
test "spans cover the input exactly, with no gap and no overlap" {
  let src = ".card { gap: 1rem; }"
  let toks = @token.tokenize(src)
  let mut at = 0
  for t in toks {
    assert_eq(t.span.start, at)
    at = t.span.end
  }
  assert_eq(at, src.length())
  // And the last token is the only Eof.
  assert_eq(toks[toks.length() - 1].kind, Eof)
}

///|
test "tokenizing never fails, whatever it is handed" {
  let nasty = [
    "", "}", ")", "@", "\\", "\"", "'", "url(", "/*", "#", "-", "+", ".", "@\\",
    "url(\\", "\"\\", "1e", "1e+", "--", "<!", "a\\\n", "\u{0}",
  ]
  for s in nasty {
    let toks = @token.tokenize(s)
    // Terminates, ends with Eof, and covers the whole input.
    assert_eq(toks[toks.length() - 1].kind, Eof)
    assert_eq(toks[toks.length() - 1].span.end, s.length())
  }
}
