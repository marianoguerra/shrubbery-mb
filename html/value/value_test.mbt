///|
/// Lens tests.
///
/// Each of these is a question the tree does not answer by itself, asked of a
/// tree that came from a real parse -- because a lens that only worked on a
/// hand-built tree would be testing the constructor.

///|
test "an attribute, and the difference between absent and empty" {
  let d = @parse.parse("<input name=\"q\" value=\"\" disabled>").document()
  match d.children[0] {
    Element(e) => {
      assert_eq(@value.attr(e, "name"), Some("q"))
      assert_eq(@value.attr(e, "value"), Some(""))
      // A valueless attribute reads as present with an empty value, which is
      // what HTML says it is.
      assert_eq(@value.attr(e, "disabled"), Some(""))
      assert_eq(@value.attr(e, "missing"), None)
      assert_true(@value.as_bool(e, "disabled"))
      assert_false(@value.as_bool(e, "checked"))
    }
    _ => fail("expected an input")
  }
}

///|
test "a prefixed attribute answers to its whole name" {
  let d = @parse.parse("<svg><use xlink:href=\"#a\"/></svg>").document()
  let uses = @value.by_tag(d, "use")
  assert_eq(@value.attr(uses[0], "xlink:href"), Some("#a"))
  assert_eq(@value.attr(uses[0], "href"), None)
}

///|
test "classes split on whitespace, and empty runs are not classes" {
  let d = @parse.parse("<p class=\"  card  is-open \">x</p>").document()
  match d.children[0] {
    Element(e) => {
      let classes = @value.class_list(e)
      assert_eq(classes.length(), 2)
      assert_eq(classes[0], "card")
      assert_eq(classes[1], "is-open")
    }
    _ => fail("expected a p")
  }
}

///|
test "an element with no class has no classes" {
  let d = @parse.parse("<p>x</p>").document()
  match d.children[0] {
    Element(e) => assert_eq(@value.class_list(e).length(), 0)
    _ => fail("expected a p")
  }
}

///|
test "an integer attribute, when it is one" {
  let d = @parse.parse("<td colspan=\"2\" rowspan=\"x\" start=\"-3\">").document()
  let tds = @value.by_tag(d, "td")
  assert_eq(@value.as_int(tds[0], "colspan"), Some(2))
  assert_eq(@value.as_int(tds[0], "rowspan"), None)
  assert_eq(@value.as_int(tds[0], "start"), Some(-3))
}

///|
test "text content reaches through elements and includes raw text" {
  let d = @parse.parse("<div>a<span>b</span><script>c</script></div>").document()
  assert_eq(@value.text_content(d.children[0]), "abc")
}

///|
test "text content does not include comments" {
  let d = @parse.parse("<div>a<!-- b -->c</div>").document()
  assert_eq(@value.text_content(d.children[0]), "ac")
}

///|
test "elements come back in document order" {
  let d = @parse.parse("<div><p><em>x</em></p><span></span></div>").document()
  let names = StringBuilder()
  for e in @value.elements(d.children[0]) {
    names.write_string(e.name.name)
    names.write_char(' ')
  }
  inspect(names.to_string(), content="div p em span ")
}

///|
test "by_id finds the first, which is all a document should have" {
  let d = @parse.parse("<div id=\"a\"><p id=\"b\">x</p></div>").document()
  match @value.by_id(d, "b") {
    Some(e) => assert_eq(e.name.name, "p")
    None => fail("expected to find #b")
  }
  assert_true(@value.by_id(d, "nope") is None)
}

///|
test "display and voidness are namespace-sensitive" {
  let d = @parse.parse("<p></p><svg><title>t</title></svg>").document()
  match d.children[0] {
    Element(p) => {
      assert_eq(@value.display_of(p), Block)
      assert_false(@value.is_void(p))
    }
    _ => fail("expected a p")
  }
  // SVG's `title` is not HTML's, and neither the display table nor the void
  // table applies to it.
  let titles = @value.by_tag(d, "title")
  assert_eq(@value.display_of(titles[0]), Inline)
}
