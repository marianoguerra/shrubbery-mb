///|
/// Printer tests.
///
/// These build trees by hand rather than parsing, because the printer is a
/// complete use of this library on its own -- a code generator never calls the
/// parser -- and because the cases worth checking are the ones no parse can
/// produce.

///|
fn el(
  name : String,
  children : Array[@ast.Node],
  attrs? : Array[@ast.Attribute] = [],
  closing? : @ast.Closing = Explicit,
) -> @ast.Node {
  Element({
    name: @ast.TagName::html(name),
    attrs,
    children,
    closing,
    span: @span.nowhere,
    name_span: @span.nowhere,
  })
}

///|
fn txt(s : String) -> @ast.Node {
  Text(@ast.Text::new(s))
}

///|
fn attr(name : String, value : String) -> @ast.Attribute {
  {
    name: @ast.AttrName::plain(name),
    value: Value(value, None),
    span: @span.nowhere,
  }
}

///|
fn doc(children : Array[@ast.Node]) -> @ast.Document {
  { children, span: @span.nowhere, }
}

///|
test "a tree built by hand prints without ever touching the parser" {
  let d = doc([el("ul", [el("li", [txt("one")]), el("li", [txt("two")])])])
  inspect(
    @write.document(d, style=Pretty),
    content=(
      #|<ul>
      #|  <li>one</li>
      #|  <li>two</li>
      #|</ul>
      #|
    ),
  )
}

///|
test "one inline child makes the whole run verbatim" {
  // `<div>` is block, but `<em>` is not, so nothing here may move: adding a
  // newline before `<em>` would add a space to the rendered page.
  let d = doc([el("div", [txt("a"), el("em", [txt("b")]), txt("c")])])
  inspect(
    @write.document(d, style=Pretty),
    content=(
      #|<div>a<em>b</em>c</div>
      #|
    ),
  )
}

///|
test "whitespace-only text between block children is dropped, not kept" {
  let d = doc([el("div", [txt("\n  "), el("p", [txt("x")]), txt("\n")])])
  inspect(
    @write.document(d, style=Pretty),
    content=(
      #|<div>
      #|  <p>x</p>
      #|</div>
      #|
    ),
  )
  inspect(@write.document(d, style=Minified), content="<div><p>x</p></div>")
}

///|
test "Strict moves nothing at all" {
  let d = doc([el("div", [txt("\n  "), el("p", [txt("x")]), txt("\n")])])
  inspect(
    @write.document(d, style=Pretty, whitespace=Strict),
    content=(
      #|<div>
      #|  <p>x</p>
      #|</div>
      #|
    ),
  )
}

///|
test "Ignore lays out inline content Css would leave alone" {
  let d = doc([el("div", [txt("a"), el("em", [txt("b")]), txt("c")])])
  inspect(
    @write.document(d, style=Pretty, whitespace=Ignore),
    content=(
      #|<div>
      #|  a
      #|  <em>b</em>
      #|  c
      #|</div>
      #|
    ),
  )
}

///|
test "a preformatted element is never laid out, under any policy" {
  let d = doc([el("pre", [txt("  a\n  b")])])
  for ws in [@write.Whitespace::Css, Ignore, Strict] {
    inspect(
      @write.document(d, style=Pretty, whitespace=ws),
      content=(
        #|<pre>  a
        #|  b</pre>
        #|
      ),
    )
  }
}

///|
test "attributes keep their order and their emptiness" {
  let d = doc([
    el(
      "input",
      [],
      attrs=[
        attr("type", "checkbox"),
        {
          name: @ast.AttrName::plain("checked"),
          value: Empty,
          span: @span.nowhere,
        },
        attr("value", ""),
      ],
      closing=Void,
    ),
  ])
  inspect(
    @write.document(d, style=Minified),
    content="<input type=checkbox checked value=\"\">",
  )
  inspect(
    @write.document(d, style=Pretty),
    content=(
      #|<input type="checkbox" checked value="">
      #|
    ),
  )
}

///|
test "a value that could end a tag keeps its quotes" {
  inspect(@write.escape_attr("a\"b&c"), content="a&quot;b&amp;c")
  assert_false(@write.may_go_unquoted(""))
  assert_false(@write.may_go_unquoted("a b"))
  assert_false(@write.may_go_unquoted("/x/"))
  assert_false(@write.may_go_unquoted("a=b"))
  assert_true(@write.may_go_unquoted("checkbox"))
}

///|
test "text escaping closes every way out of a text node" {
  inspect(
    @write.escape_text("<script>a & b</script>"),
    content="&lt;script&gt;a &amp; b&lt;/script&gt;",
  )
}

///|
test "an invisible character is named rather than emitted" {
  // U+00A0 has a name; U+200B does not, and goes out numerically.
  inspect(@write.escape_text("a\u{A0}b\u{200B}c"), content="a&nbsp;b&#x200B;c")
}

///|
test "escapable raw text is escaped as text, not as an attribute value" {
  // `<title>` and `<textarea>` hold text with references but no markup, so
  // their content is escaped the way text is -- `<` included. Escaping it as
  // an attribute value instead leaves the `<` live, and a title whose text
  // contains `</title>` then ends its own element. That is the same injection
  // a `<script>` body would be, in the one raw-text context that HAS an escape
  // and can therefore be printed safely.
  let d = doc([el("title", [txt("</title><script>alert(1)</script>")])])
  inspect(
    @write.document(d, style=Minified),
    content="<title>&lt;/title&gt;&lt;script&gt;alert(1)&lt;/script&gt;</title>",
  )
}

///|
test "a raw-text body containing its own end tag is refused" {
  assert_false(@write.raw_text_is_printable("x </SCRIPT> y", "script"))
  assert_true(@write.raw_text_is_printable("x </style> y", "script"))
}

///|
test "an empty document prints as nothing, not as a newline" {
  inspect(@write.document(doc([]), style=Pretty), content="")
}
