///|
/// The identifier transform, and the property that makes it safe.

///|
test "the transform inverts, in both directions, where it can" {
  let css_names = [
    "color", "font-size", "-webkit-box-orient", "--brand", "grid-template-areas",
  ]
  for n in css_names {
    match @names.kebab(n) {
      Some(shrub) => assert_eq(@names.unkebab(shrub), n)
      None => fail("no shrubbery spelling for " + n)
    }
  }
  let shrub_names = ["color", "font_size", "_webkit_box_orient", "fade_in"]
  for n in shrub_names {
    assert_eq(@names.kebab(@names.unkebab(n)), Some(n))
  }
}

///|
test "a name with an underscore has no bare spelling, and says so" {
  // `side_bar` would come back as `side-bar`, so the transform refuses rather
  // than guessing. The caller's answer is `ident("side_bar")`.
  assert_eq(@names.kebab("side_bar"), None)
  assert_eq(@names.kebab("btn__primary"), None)
}

///|
test "a name that already has a hyphen is literal" {
  // The only way a `-` reaches an identifier is a `#{...}` escape, which is
  // deliberate, so it passes through.
  assert_eq(@names.unkebab("-webkit-x"), "-webkit-x")
}

///|
test "units round-trip, including the three CSS capitalises" {
  for u in ["px", "rem", "ms", "fr", "dppx", "cqmin"] {
    assert_eq(@names.unit_of(u), Some(u))
    assert_eq(@names.unit_call(u), Some(u))
  }
  assert_eq(@names.unit_of("q"), Some("Q"))
  assert_eq(@names.unit_call("Q"), Some("q"))
  assert_eq(@names.unit_of("khz"), Some("kHz"))
  assert_eq(@names.unit_call("kHz"), Some("khz"))
  // Not a unit: it falls through to being an ordinary function call.
  assert_eq(@names.unit_of("rgb"), None)
  // A unit this table does not know has no short spelling, so the caller uses
  // the `dim(n, "unit")` escape rather than inventing one.
  assert_eq(@names.unit_call("newunit"), None)
}

///|
test "relations round-trip" {
  for k in ["in", "child", "next", "sibling", "column"] {
    match @names.combinator_of(k) {
      Some(c) => assert_eq(@names.combinator_keyword(c), k)
      None => fail("not a relation: " + k)
    }
  }
  assert_eq(@names.combinator_of("nonsense"), None)
}

///|
test "the tables answer for the names the syntax actually uses" {
  assert_true(@names.is_simple_pseudo("hover"))
  assert_true(@names.is_simple_pseudo("first-child"))
  assert_true(@names.is_selector_pseudo("not"))
  assert_true(@names.is_nth_pseudo("nth-child"))
  assert_true(@names.is_pseudo_element("before"))
  assert_true(@names.is_at_rule("media"))
  assert_true(@names.is_at_rule("font-face"))
  // A CSS function is none of those, so it stays an ordinary call.
  assert_true(!@names.is_simple_pseudo("rgb"))
  assert_true(!@names.is_at_rule("rgb"))
}
