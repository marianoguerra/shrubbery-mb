///|
/// Parser tests.
///
/// Most of these are stated as "parse this, print it, and look" rather than as
/// assertions about the tree, because the tree has spans in it and the printed
/// form is the only thing a reader can check against the input at a glance. The
/// exceptions are the cases where what is being claimed is a field --
/// `Closing`, a namespace -- which printing does not show.

///|
fn print(src : String, style~ : @write.Style) -> String raise {
  @write.document(@parse.parse(src).document(), style~)
}

///|
test "a document, printed three ways" {
  let src = "<div class=\"card\"><p>hi</p></div>"
  inspect(
    print(src, style=Pretty),
    content=(
      #|<div class="card">
      #|  <p>hi</p>
      #|</div>
      #|
    ),
  )
  inspect(
    print(src, style=Compact),
    content=(
      #|<div class="card">
      #|<p>hi</p>
      #|</div>
      #|
    ),
  )
  inspect(print(src, style=Minified), content="<div class=card><p>hi</p></div>")
}

///|
test "inline content is never reflowed" {
  // The whole point of the `Css` policy: the space before `<em>` is data, and
  // no amount of indenting may move it.
  let src = "<p>Read <em>this</em> now</p>"
  inspect(
    print(src, style=Pretty),
    content=(
      #|<p>Read <em>this</em> now</p>
      #|
    ),
  )
  inspect(print(src, style=Minified), content="<p>Read <em>this</em> now</p>")
}

///|
test "an implied end tag stays implied, and stops the parent laying out" {
  let d = @parse.parse("<ul><li>one<li>two</ul>").document()
  // Not indented, and that is the point: an element with no end tag leaks, so
  // a newline written after it would become part of its text and the file
  // would grow every time it was formatted.
  inspect(
    @write.document(d, style=Pretty),
    content=(
      #|<ul><li>one<li>two</ul>
      #|
    ),
  )
  match d.children[0] {
    Element(ul) =>
      match ul.children[0] {
        Element(li) => assert_eq(li.closing, Implied)
        _ => fail("expected an li")
      }
    _ => fail("expected a ul")
  }
}

///|
test "a paragraph is closed by the block that follows it" {
  inspect(
    print("<p>one<div>two</div>", style=Minified),
    content="<p>one<div>two</div>",
  )
  let d = @parse.parse("<p>one<div>two</div>").document()
  assert_eq(d.children.length(), 2)
}

///|
test "a table row does not end up inside the previous cell" {
  inspect(
    print("<table><tr><td>a<tr><td>b</table>", style=Pretty),
    content=(
      #|<table><tr><td>a<tr><td>b</table>
      #|
    ),
  )
  // Two rows, not a row inside a cell -- which is what the table in `names`
  // buys, and what the flat printing above does not show.
  let d = @parse.parse("<table><tr><td>a<tr><td>b</table>").document()
  match d.children[0] {
    Element(t) => assert_eq(t.children.length(), 2)
    _ => fail("expected a table")
  }
}

///|
test "a void element is void, and remembers how it was written" {
  let d = @parse.parse("<br><br/>").document()
  match d.children[0] {
    Element(e) => assert_eq(e.closing, Void)
    _ => fail("expected a br")
  }
  match d.children[1] {
    Element(e) => assert_eq(e.closing, SelfClosing)
    _ => fail("expected a br")
  }
  inspect(@write.document(d, style=Minified), content="<br><br>")
  inspect(
    @write.document(d, style=Pretty),
    content=(
      #|<br><br/>
      #|
    ),
  )
}

///|
test "a stray end tag is dropped, and said so" {
  let p = @parse.parse("<div>a</span></div>")
  inspect(@write.document(p.document(), style=Minified), content="<div>a</div>")
  assert_eq(p.diagnostics()[0].kind.code(), "html::stray_end_tag")
}

///|
test "an unclosed element is closed, and said so" {
  let p = @parse.parse("<div><span>a")
  inspect(@write.document(p.document(), style=Minified), content="<div><span>a")
  assert_eq(p.diagnostics()[0].kind.code(), "html::unclosed_element")
}

///|
test "the slash in a non-void HTML tag does nothing, and is told so" {
  let p = @parse.parse("<div/>text</div>")
  inspect(
    @write.document(p.document(), style=Minified),
    content="<div>text</div>",
  )
  assert_eq(p.diagnostics()[0].kind.code(), "html::non_void_self_closing")
}

///|
test "the same slash in foreign content closes the element" {
  let d = @parse.parse("<svg><circle r=\"1\"/><rect/></svg>").document()
  inspect(
    @write.document(d, style=Minified),
    content="<svg><circle r=1 /><rect/></svg>",
  )
}

///|
test "SVG keeps the case its vocabulary spells names with" {
  inspect(
    print(
      "<svg viewbox=\"0 0 1 1\"><lineargradient/><foreignobject><p>x</p></foreignobject></svg>",
      style=Minified,
    ),
    content="<svg viewBox=\"0 0 1 1\"><linearGradient/><foreignObject><p>x</p></foreignObject></svg>",
  )
}

///|
test "an integration point puts HTML back in scope" {
  let d = @parse.parse("<svg><foreignObject><br></foreignObject></svg>").document()
  match d.children[0] {
    Element(svg) => {
      assert_eq(svg.name.ns, Svg)
      match svg.children[0] {
        Element(fo) =>
          match fo.children[0] {
            // `br` is void only in HTML; that it is void here is the whole
            // claim.
            Element(br) => {
              assert_eq(br.name.ns, Html)
              assert_eq(br.closing, Void)
            }
            _ => fail("expected a br")
          }
        _ => fail("expected a foreignObject")
      }
    }
    _ => fail("expected an svg")
  }
}

///|
test "MathML is a namespace too" {
  let d = @parse.parse("<math><mfrac><mi>a</mi><mn>2</mn></mfrac></math>").document()
  match d.children[0] {
    Element(m) => assert_eq(m.name.ns, MathMl)
    _ => fail("expected a math")
  }
  inspect(
    @write.document(d, style=Minified),
    content="<math><mfrac><mi>a</mi><mn>2</mn></mfrac></math>",
  )
}

///|
test "a script body is text, and keeps every byte of it" {
  inspect(
    print("<script>if (a < b) { f(\"</p>\") }</script>", style=Minified),
    content="<script>if (a < b) { f(\"</p>\") }</script>",
  )
}

///|
test "a character reference keeps its spelling through a round trip" {
  inspect(
    print("<p>a &amp; b &nbsp; c</p>", style=Minified),
    content="<p>a &amp; b &nbsp; c</p>",
  )
}

///|
test "and an invisible character acquires one" {
  // The text node holds U+00A0 with no source spelling, because it was written
  // as itself. Printing names it, so the file says what it means.
  let d : @ast.Document = {
    children: [Text(@ast.Text::new("a\u{A0}b"))],
    span: @span.nowhere,
  }
  inspect(@write.document(d, style=Minified), content="a&nbsp;b")
}

///|
test "a doctype, and one in the wrong place" {
  inspect(
    print("<!DOCTYPE html><p>x", style=Minified),
    content="<!DOCTYPE html><p>x",
  )
  let p = @parse.parse("<p>x</p><!DOCTYPE html>")
  assert_eq(p.diagnostics()[0].kind.code(), "html::doctype_not_first")
}

///|
test "CDATA is kept where it is legal and flagged where it is not" {
  inspect(
    print("<svg><![CDATA[x < y]]></svg>", style=Minified),
    content="<svg><![CDATA[x < y]]></svg>",
  )
  let p = @parse.parse("<div><![CDATA[x]]></div>")
  assert_eq(p.diagnostics()[0].kind.code(), "html::cdata_in_html_content")
}

///|
test "text is escaped on the way out, and cannot escape its node" {
  let d : @ast.Document = {
    children: [
      Element({
        name: @ast.TagName::html("p"),
        attrs: [
          {
            name: @ast.AttrName::plain("title"),
            value: Value("\"><img onerror=x>", None),
            span: @span.nowhere,
          },
        ],
        children: [Text(@ast.Text::new("</p><script>alert(1)</script>"))],
        closing: Explicit,
        span: @span.nowhere,
        name_span: @span.nowhere,
      }),
    ],
    span: @span.nowhere,
  }
  let printed = @write.document(d, style=Minified)
  inspect(
    printed,
    content="<p title=\"&quot;><img onerror=x>\">&lt;/p&gt;&lt;script&gt;alert(1)&lt;/script&gt;</p>",
  )
  // The claim is not about the bytes, it is that reparsing gives the same
  // strings back.
  let back = @parse.parse(printed).document()
  match back.children[0] {
    Element(e) => {
      assert_eq(e.attrs[0].value.text(), "\"><img onerror=x>")
      match e.children[0] {
        Text(t) => assert_eq(t.text, "</p><script>alert(1)</script>")
        _ => fail("expected text")
      }
    }
    _ => fail("expected a p")
  }
}

///|
test "a script body that contains its own end tag cannot be printed" {
  let d : @ast.Document = {
    children: [
      Element({
        name: @ast.TagName::html("script"),
        attrs: [],
        children: [
          RawText({ text: "var s = \"</script>\"", span: @span.nowhere, }),
        ],
        closing: Explicit,
        span: @span.nowhere,
        name_span: @span.nowhere,
      }),
    ],
    span: @span.nowhere,
  }
  let (_, problems) = @write.document_checked(d, style=Minified)
  assert_eq(problems[0].0.code(), "html::unprintable_raw_text")
}

///|
test "strict mode raises on the first error" {
  let raised = try {
    let _ = @parse.parse("<div><span>a", strict=true)
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}

///|
test "nothing at all is still a document" {
  inspect(print("", style=Pretty), content="")
  inspect(print("", style=Minified), content="")
}
