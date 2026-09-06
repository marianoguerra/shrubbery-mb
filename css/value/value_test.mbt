///|
/// The lenses, and specificity.
///
/// Tested through the parser rather than over hand-built values, because a
/// lens's job is to read what the parser produced -- a hand-built value could
/// agree with the lens and disagree with reality.

///|
/// The first declaration's first value in a one-rule stylesheet.
fn first_value(css : String) -> @ast.ComponentValue raise {
  let p = @parse.parse("a{p:" + css + "}")
  match p.sheet().items[0] {
    Rule(Style(r)) =>
      match r.body[0] {
        Decl(d) => d.value[0]
        _ => Ident("not-a-declaration")
      }
    _ => Ident("not-a-rule")
  }
}

///|
/// The first selector of a one-rule stylesheet.
fn first_selector(css : String) -> @ast.Selector raise {
  let p = @parse.parse(css + "{a:b}")
  match p.sheet().items[0] {
    Rule(Style(r)) => r.selectors[0]
    _ => Bogus(@ast.Bogus::new(BadSelector, @span.nowhere))
  }
}

///|
test "numbers, and what is not one" {
  assert_eq(@value.as_number(first_value("42")), Some(42.0))
  assert_eq(@value.as_integer(first_value("42")), Some(42))
  // A number written with a fractional part is not an integer, even at a whole
  // value: a grammar asking for an integer should not silently take `2.0`.
  assert_eq(@value.as_integer(first_value("2.0")), None)
  // A percentage is not a number: `50%` and `50` mean different things
  // everywhere in CSS.
  assert_eq(@value.as_number(first_value("50%")), None)
  assert_eq(@value.as_percentage(first_value("50%")), Some(50.0))
}

///|
test "dimensions know what they measure" {
  match @value.as_dimension(first_value("10px")) {
    Some(d) => {
      assert_eq(d.value, 10.0)
      assert_eq(d.unit, "px")
      assert_eq(d.kind, Length)
    }
    None => fail("10px is a dimension")
  }
  assert_true(@value.as_length(first_value("1.5rem")) is Some(_))
  assert_true(@value.as_angle(first_value("45deg")) is Some(_))
  assert_true(@value.as_time(first_value("200ms")) is Some(_))
  assert_true(@value.as_resolution(first_value("2dppx")) is Some(_))
  // Asking for the wrong kind is a question with a negative answer, not an
  // error.
  assert_eq(@value.as_length(first_value("45deg")), None)
  assert_eq(@value.as_angle(first_value("10px")), None)
  // A bare zero is a length, because CSS lets one omit its unit.
  assert_true(@value.as_length(first_value("0")) is Some(_))
  assert_eq(@value.as_length(first_value("1")), None)
  // A unit nobody knows is still a dimension -- CSS gains units.
  match @value.as_dimension(first_value("3newunit")) {
    Some(d) => assert_eq(d.kind, Unknown)
    None => fail("an unknown unit is still a dimension")
  }
  // Units are case-insensitive.
  assert_eq(@value.unit_kind("PX"), Length)
  assert_eq(@value.unit_kind("kHz"), Frequency)
}

///|
test "colours, and the ones that only look like colours" {
  assert_eq(@value.as_color(first_value("#f7f7f7")), Some(Hex("f7f7f7")))
  assert_eq(@value.as_color(first_value("red")), Some(Named("red")))
  assert_eq(
    @value.as_color(first_value("currentColor")),
    Some(Named("currentColor")),
  )
  assert_true(@value.as_color(first_value("oklch(0.62 0.19 258)")) is Some(_))
  // `auto` is an identifier and not a colour; `calc()` is a function and not
  // a colour function.
  assert_eq(@value.as_color(first_value("auto")), None)
  assert_eq(@value.as_color(first_value("calc(1px)")), None)
}

///|
test "hex colours resolve to channels, and nothing else does" {
  assert_eq(@value.to_rgba(Hex("fff")), Some((255, 255, 255, 255)))
  assert_eq(@value.to_rgba(Hex("000")), Some((0, 0, 0, 255)))
  assert_eq(@value.to_rgba(Hex("ff8800")), Some((255, 136, 0, 255)))
  assert_eq(@value.to_rgba(Hex("00000080")), Some((0, 0, 0, 128)))
  // Three-digit and six-digit forms agree, which is the point of the `* 17`.
  assert_eq(@value.to_rgba(Hex("f80")), @value.to_rgba(Hex("ff8800")))
  // A name would need the named-colour table's values, and a colour function
  // would need a colour space. Neither belongs behind a function this cheap.
  assert_eq(@value.to_rgba(Named("red")), None)
}

///|
test "functions, var and url" {
  assert_true(@value.as_function(first_value("calc(1px)"), "calc") is Some(_))
  // Function names are case-insensitive.
  assert_true(@value.as_function(first_value("CALC(1px)"), "calc") is Some(_))
  assert_eq(@value.as_function(first_value("calc(1px)"), "rgb"), None)
  match @value.as_var(first_value("var(--brand, red)")) {
    Some((name, fallback)) => {
      assert_eq(name, "--brand")
      assert_eq(fallback.length(), 1)
    }
    None => fail("var(--brand, red) reads as a var")
  }
  match @value.as_var(first_value("var(--brand)")) {
    Some((name, fallback)) => {
      assert_eq(name, "--brand")
      assert_eq(fallback.length(), 0)
    }
    None => fail("var(--brand) reads as a var")
  }
  // Quoted and unquoted urls are the same node, so the lens sees one thing.
  assert_eq(@value.as_url(first_value("url(a.png)")), Some("a.png"))
  assert_eq(@value.as_url(first_value("url(\"a.png\")")), Some("a.png"))
}

///|
test "keywords are read against the caller's list" {
  let allowed = ["auto", "none", "inherit"]
  assert_eq(@value.as_keyword(first_value("auto"), allowed), Some("auto"))
  assert_eq(@value.as_keyword(first_value("AUTO"), allowed), Some("auto"))
  assert_eq(@value.as_keyword(first_value("grid"), allowed), None)
}

///|
test "specificity, including the three places CSS stops being uniform" {
  fn spec(css : String) -> (Int, Int, Int) raise {
    @value.specificity(first_selector(css)).to_triple()
  }

  assert_eq(spec("*"), (0, 0, 0))
  assert_eq(spec("li"), (0, 0, 1))
  assert_eq(spec("ul li"), (0, 0, 2))
  assert_eq(spec(".card"), (0, 1, 0))
  assert_eq(spec("#sidebar"), (1, 0, 0))
  assert_eq(spec("[type=\"text\"]"), (0, 1, 0))
  assert_eq(spec("a:hover"), (0, 1, 1))
  assert_eq(spec("p::before"), (0, 0, 2))
  assert_eq(spec("#a .b c"), (1, 1, 1))
  // `:is()` takes its most specific argument -- which is exactly why a
  // selector list may not be spelled `is(...)` in the shrubbery syntax.
  assert_eq(spec(":is(h1, #id)"), (1, 0, 0))
  assert_eq(spec(":not(.a, #b)"), (1, 0, 0))
  // `:where()` contributes nothing, whatever is inside it.
  assert_eq(spec(":where(#a, #b)"), (0, 0, 0))
  // `:nth-child(An+B of S)` is a class plus its most specific arm.
  assert_eq(spec("li:nth-child(2n)"), (0, 1, 1))
  assert_eq(spec("li:nth-child(2n of #x)"), (1, 1, 1))
}

///|
test "a selector list has no single specificity, so the highest is reported" {
  let p = @parse.parse("h1, #id, .cls { a: b }")
  match p.sheet().items[0] {
    Rule(Style(r)) =>
      assert_eq(@value.max_specificity(r.selectors).to_triple(), (1, 0, 0))
    _ => fail("not a style rule")
  }
}

///|
test "specificity compares the way the cascade does" {
  let id : @value.Specificity = { ids: 1, classes: 0, elements: 0, }
  let many_classes : @value.Specificity = { ids: 0, classes: 9, elements: 9, }
  // One id beats any number of classes: the comparison is lexicographic, not
  // a sum, which is the whole reason it is a triple.
  assert_true(id.beats(many_classes))
  assert_true(!many_classes.beats(id))
  assert_true(!id.beats(id))
}
