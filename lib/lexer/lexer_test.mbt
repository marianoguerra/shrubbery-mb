///|
/// A compact rendering of the token stream, for snapshots.
fn dump(src : String) -> String {
  let buf = StringBuilder()
  for t in @lexer.lex_all(src) {
    if t.kind is EndOfInput {
      continue
    }
    buf.write_string(t.kind.kind_name())
    buf.write_char(' ')
    buf.write_string(t.text.escape())
    match t.kind {
      Literal(d) => {
        buf.write_char(' ')
        buf.write_string(d.canonical())
      }
      _ => ()
    }
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
/// The invariant everything else rests on.
///
/// If the token texts do not concatenate back to the input, raw-text metadata
/// cannot reconstruct the source and round-tripping is impossible — and the
/// failure would show up much later, as a mysterious printing difference.
fn assert_covers(src : String) -> Unit raise {
  let buf = StringBuilder()
  for t in @lexer.lex_all(src) {
    buf.write_string(t.text)
  }
  if buf.to_string() != src {
    fail(
      "token texts do not reconstruct the input: \{buf.to_string().escape()}",
    )
  }
}

///|
test "identifiers, keywords and operators" {
  inspect(
    dump("x + y ~name #%internal"),
    content=(
      #|identifier "x"
      #|whitespace " "
      #|operator "+"
      #|whitespace " "
      #|identifier "y"
      #|whitespace " "
      #|keyword "~name"
      #|whitespace " "
      #|identifier "#%internal"
      #|
    ),
  )
}

///|
test "the continuing state decides whether a sign starts a number" {
  // `1+2` is three tokens; `1 +2` is two terms, because whitespace drops the
  // continuing state. This one bit is the whole rule.
  inspect(
    dump("1+2"),
    content=(
      #|literal "1" 1
      #|operator "+"
      #|literal "2" 2
      #|
    ),
  )
  inspect(
    dump("1 +2"),
    content=(
      #|literal "1" 1
      #|whitespace " "
      #|literal "+2" 2
      #|
    ),
  )
}

///|
test "numbers in every radix, with separators" {
  inspect(
    dump("0x1F 0o17 0b1011 100_000 1_0.5 1e10 .5 -3"),
    content=(
      #|literal "0x1F" 31
      #|whitespace " "
      #|literal "0o17" 15
      #|whitespace " "
      #|literal "0b1011" 11
      #|whitespace " "
      #|literal "100_000" 100000
      #|whitespace " "
      #|literal "1_0.5" #f64:4025000000000000
      #|whitespace " "
      #|literal "1e10" #f64:4202a05f20000000
      #|whitespace " "
      #|literal ".5" #f64:3fe0000000000000
      #|whitespace " "
      #|literal "-3" -3
      #|
    ),
  )
}

///|
test "a trailing dot joins the number only when nothing longer starts there" {
  inspect(
    dump("1."),
    content=(
      #|literal "1." #f64:3ff0000000000000
      #|
    ),
  )
  // `.+` is a multi-character operator, so the dot is not the number's.
  inspect(
    dump("1.+2"),
    content=(
      #|literal "1" 1
      #|operator ".+"
      #|literal "2" 2
      #|
    ),
  )
  inspect(
    dump("1..2"),
    content=(
      #|literal "1" 1
      #|operator ".."
      #|literal "2" 2
      #|
    ),
  )
}

///|
test "fractions are exact" {
  inspect(
    dump("1/2"),
    content=(
      #|literal "1/2" 1/2
      #|
    ),
  )
  // A `.` after the denominator means it was meant as a decimal, so the `/` is
  // division rather than a fraction bar.
  inspect(
    dump("1/2.0"),
    content=(
      #|literal "1" 1
      #|operator "/"
      #|literal "2.0" #f64:4000000000000000
      #|
    ),
  )
  // A zero denominator is not a fraction either.
  inspect(
    dump("1/0"),
    content=(
      #|literal "1" 1
      #|operator "/"
      #|literal "0" 0
      #|
    ),
  )
}

///|
test "operators stop short of comments" {
  inspect(
    dump("1 +/ 2"),
    content=(
      #|literal "1" 1
      #|whitespace " "
      #|operator "+/"
      #|whitespace " "
      #|literal "2" 2
      #|
    ),
  )
  inspect(
    dump("1 +// 2"),
    content=(
      #|literal "1" 1
      #|whitespace " "
      #|operator "+"
      #|comment "// 2"
      #|
    ),
  )
}

///|
test "a multi-character operator may not end in a colon" {
  inspect(
    dump("x+: y"),
    content=(
      #|identifier "x"
      #|operator "+"
      #|block-operator ":"
      #|whitespace " "
      #|identifier "y"
      #|
    ),
  )
  // All-colon operators are the exception.
  inspect(
    dump("x :: y"),
    content=(
      #|identifier "x"
      #|whitespace " "
      #|operator "::"
      #|whitespace " "
      #|identifier "y"
      #|
    ),
  )
}

///|
test "constants and the delimiter rule" {
  inspect(
    dump("#true #false #void #inf #neginf #nan"),
    content=(
      #|literal "#true" #t
      #|whitespace " "
      #|literal "#false" #f
      #|whitespace " "
      #|literal "#void" #<void>
      #|whitespace " "
      #|literal "#inf" #f64:7ff0000000000000
      #|whitespace " "
      #|literal "#neginf" #f64:fff0000000000000
      #|whitespace " "
      #|literal "#nan" #f64:nan
      #|
    ),
  )
  // `1x` and `#truex` are errors, not a value beside an identifier.
  inspect(
    dump("1x"),
    content=(
      #|fail "1x"
      #|
    ),
  )
  inspect(
    dump("#truex"),
    content=(
      #|fail "#truex"
      #|
    ),
  )
}

///|
test "strings decode their escapes and keep their source" {
  inspect(
    dump(
      (
        #|"a\tb\u3BB\x41\101"
      ),
    ),
    content=(
      #|literal "\"a\\tb\\u3BB\\x41\\101\"" "a\u{9}b\u{3bb}AA"
      #|
    ),
  )
  inspect(
    dump("#\"ab\\x01\""),
    content=(
      #|literal "#\"ab\\x01\"" #"\x61\x62\x01"
      #|
    ),
  )
}

///|
test "comments nest and are kept as tokens" {
  inspect(
    dump("a /* b /* c */ d */ e // f"),
    content=(
      #|identifier "a"
      #|whitespace " "
      #|comment "/* b /* c */ d */"
      #|whitespace " "
      #|identifier "e"
      #|whitespace " "
      #|comment "// f"
      #|
    ),
  )
}

///|
test "quotes are rewritten into openers and closers" {
  inspect(
    dump("'a ('nested') b'"),
    content=(
      #|opener "'"
      #|identifier "a"
      #|whitespace " "
      #|opener "("
      #|opener "'"
      #|identifier "nested"
      #|closer "'"
      #|closer ")"
      #|whitespace " "
      #|identifier "b"
      #|closer "'"
      #|
    ),
  )
}

///|
test "every code unit belongs to exactly one token" {
  assert_covers("x + y\n  z: 1\n")
  assert_covers("'a ('b') c'\n")
  assert_covers("/* nested /* comment */ */ x\r\ny\rz")
  assert_covers("\"unterminated\n")
  assert_covers("1x #bogus ~ \u{0}")
  assert_covers("  \t x\ty\n")
}

///|
test "columns count grapheme clusters and respect tabs" {
  let toks = @lexer.lex_all("\tx")
  // The `x` is one tab in, which is not the same column as any number of
  // spaces: nothing else extends that prefix.
  assert_eq(toks[1].column().to_display(), "0+1tab+0")
  let spaces = @lexer.lex_all("  x")
  assert_eq(spaces[1].column().to_display(), "2")
  // A `|` counts half a column further right than it sits.
  let bar = @lexer.lex_all("  |")
  assert_eq(bar[1].column().to_display(), "2.5")
}
