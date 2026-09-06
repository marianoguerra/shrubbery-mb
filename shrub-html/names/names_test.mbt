///|
/// The tables.
///
/// These are the syntax, so they are worth testing directly rather than only
/// through the two directions that read them. The cases are the ones where
/// `kebab` has to answer `None`, because that answer is what makes the literal
/// escape reachable instead of hypothetical.

///|
test "underscores and hyphens trade places" {
  assert_eq(@names.unkebab("data_id"), "data-id")
  assert_eq(@names.kebab("data-id"), Some("data_id"))
  assert_eq(@names.unkebab("div"), "div")
  assert_eq(@names.kebab("div"), Some("div"))
  // A name that already has a `-` came from a `#{...}` escape and was written
  // literally on purpose.
  assert_eq(@names.unkebab("data-id"), "data-id")
}

///|
test "a name with a real underscore has no bare spelling" {
  // `unkebab` would not invert it: `side_bar` would come back as `side-bar`.
  assert_eq(@names.kebab("side_bar"), None)
  assert_eq(@names.element_escape("side_bar"), "element(\"side_bar\")")
}

///|
test "a name that is not an identifier has no bare spelling either" {
  assert_eq(@names.kebab("xlink:href"), None)
  assert_eq(@names.kebab("2col"), None)
  assert_eq(@names.kebab(""), None)
  assert_eq(@names.kebab("a.b"), None)
}

///|
test "and neither does a name this syntax has taken" {
  // SVG really does have a `<text>`, which is why the escape exists.
  assert_eq(@names.kebab("text"), None)
  assert_eq(@names.kebab("comment"), None)
  assert_true(@names.is_reserved_call("element"))
  assert_false(@names.is_reserved_call("div"))
}

///|
test "camelCase passes through, which is what SVG needs" {
  assert_eq(@names.kebab("viewBox"), Some("viewBox"))
  assert_eq(@names.kebab("linearGradient"), Some("linearGradient"))
  assert_eq(@names.unkebab("viewBox"), "viewBox")
}

///|
test "identifiers are recognised conservatively" {
  assert_true(@names.is_identifier("div"))
  assert_true(@names.is_identifier("_x1"))
  assert_false(@names.is_identifier("1x"))
  assert_false(@names.is_identifier("a-b"))
  assert_false(@names.is_identifier(""))
}

///|
test "quoting is shrubbery's, which is JSON's" {
  assert_eq(@names.quote("a"), "\"a\"")
  assert_eq(@names.quote("a\"b"), "\"a\\\"b\"")
  assert_eq(@names.quote("a\\b"), "\"a\\\\b\"")
  assert_eq(@names.quote("a\nb"), "\"a\\nb\"")
  assert_eq(@names.quote("a\u{1}b"), "\"a\\u{1}b\"")
}
