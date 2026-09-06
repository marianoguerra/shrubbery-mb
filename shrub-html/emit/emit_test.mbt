///|
/// The loop, mostly.
///
/// Each of these takes markup, emits notation, and asserts on the notation --
/// and then, where it matters, lowers that notation back and asserts that the
/// markup is unchanged. The second half is the real claim; the first is what
/// makes a failure readable.

///|
fn shrub(src : String) -> String raise {
  @emit.document(@parse.parse(src).document())
}

///|
/// Markup the short way round, and the long way, as one pair.
///
/// The headline property of the whole bridge: markup -> tree -> notation ->
/// tree -> markup must equal markup -> tree -> markup.
fn loops(src : String) -> (String, String) raise {
  let once = @write.document(@parse.parse(src).document(), style=Minified)
  let twice = @write.document(
    @lower.lower_source(shrub(src)).document(),
    style=Minified,
  )
  (once, twice)
}

///|
test "an element, its attributes and its children" {
  inspect(
    shrub("<div class=\"card\" id=\"a\"><p>hi</p></div>"),
    content=(
      #|div(class: "card", id: "a"):
      #|  p():
      #|    "hi"
      #|
    ),
  )
}

///|
test "a void element has no block, and a flag has no value" {
  inspect(
    shrub("<input type=\"checkbox\" checked><br>"),
    content=(
      #|input(type: "checkbox", checked)
      #|br()
      #|
    ),
  )
}

///|
test "hyphens come back as underscores" {
  inspect(
    shrub("<div data-id=\"3\" aria-label=\"Close\"></div>"),
    content=(
      #|div(data_id: "3", aria_label: "Close")
      #|
    ),
  )
}

///|
test "a name with no bare spelling goes through the escape" {
  inspect(
    shrub("<svg><text>x</text><use xlink:href=\"#a\"/></svg>"),
    content=(
      #|svg():
      #|  element("text"):
      #|    "x"
      #|  use(attr("xlink:href", "#a"))
      #|
    ),
  )
}

///|
test "layout whitespace is dropped and data whitespace is kept" {
  // Between block children the newlines are markup layout, and the notation
  // has no layout to put them in.
  inspect(
    shrub("<ul>\n  <li>one</li>\n  <li>two</li>\n</ul>"),
    content=(
      #|ul():
      #|  li():
      #|    "one"
      #|  li():
      #|    "two"
      #|
    ),
  )
  // Inside a paragraph every space is data, and the strings carry it.
  inspect(
    shrub("<p>Read <a href=\"/x\">more</a>.</p>"),
    content=(
      #|p():
      #|  "Read "
      #|  a(href: "/x"):
      #|    "more"
      #|  "."
      #|
    ),
  )
}

///|
test "comments survive, which CSS comments do not" {
  inspect(
    shrub("<!-- build 3 --><p>x</p>"),
    content=(
      #|comment(" build 3 ")
      #|p():
      #|  "x"
      #|
    ),
  )
}

///|
test "a doctype, plain and legacy" {
  inspect(shrub("<!DOCTYPE html>"), content="doctype()\n")
  inspect(
    shrub(
      "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://x/s.dtd\">",
    ),
    content=(
      #|doctype("-//W3C//DTD HTML 4.01//EN", "http://x/s.dtd")
      #|
    ),
  )
}

///|
test "raw text becomes the raw() escape" {
  inspect(
    shrub("<script>var a = 1 < 2</script>"),
    content=(
      #|script():
      #|  raw("var a = 1 < 2")
      #|
    ),
  )
}

///|
test "the loop closes on a page" {
  let src = "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">" +
    "<title>T</title></head><body><main class=\"card\"><h1>Hi</h1>" +
    "<p>Read <a href=\"/x\">more</a>.</p></main></body></html>"
  let (once, twice) = loops(src)
  assert_eq(once, twice)
}

///|
test "the loop closes on foreign content" {
  let src = "<svg viewBox=\"0 0 24 24\"><linearGradient id=\"g\">" +
    "<stop offset=\"0%\" stop-color=\"#2F6B4F\"/></linearGradient>" +
    "<path d=\"M4 4h16v16H4z\"/><foreignObject><br></foreignObject></svg>" +
    "<math><mfrac><mi>a</mi><mn>2</mn></mfrac></math>"
  let (once, twice) = loops(src)
  assert_eq(once, twice)
}

///|
test "the loop closes on comments, CDATA and character references" {
  let src = "<p>a &amp; b<!-- c --></p><svg><![CDATA[x < y]]></svg>"
  let (once, twice) = loops(src)
  // A character reference's spelling is one of the two things the detour
  // loses: the notation's string holds a value, not a spelling.
  assert_eq(once, "<p>a &amp; b<!-- c --></p><svg><![CDATA[x < y]]></svg>")
  assert_eq(twice, "<p>a &amp; b<!-- c --></p><svg><![CDATA[x < y]]></svg>")
}

///|
test "what the detour normalises, and what it does not" {
  // `<br/>` loses its slash: a void element's slash is a house style, and the
  // notation has no way to write one.
  let (once, twice) = loops("<br/>")
  assert_eq(once, "<br>")
  assert_eq(twice, "<br>")
  // An implied end tag becomes explicit, because the notation has no end tags
  // at all: children are a block, and a block always closes.
  let (a, b) = loops("<ul><li>one<li>two</ul>")
  assert_eq(a, "<ul><li>one<li>two</ul>")
  assert_eq(b, "<ul><li>one</li><li>two</li></ul>")
}

///|
test "an emitted run is never inlined, so the hazard is unreachable" {
  // `p(): "Hello " strong(): "world" "!"` is the one construct that parses
  // cleanly and means the wrong thing. Nothing this emitter writes can be it.
  let out = shrub("<p>Hello <strong>world</strong>!</p>")
  inspect(
    out,
    content=(
      #|p():
      #|  "Hello "
      #|  strong():
      #|    "world"
      #|  "!"
      #|
    ),
  )
  assert_eq(@lower.lower_source(out).diagnostics().length(), 0)
}
