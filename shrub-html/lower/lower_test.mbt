///|
/// The syntax, checked by writing it and looking at the markup.
///
/// Stated as "lower this, print it, and look" rather than as assertions about
/// the tree, because the markup is what a reader can check against the notation
/// at a glance -- and because it is the pair a user of this module actually
/// cares about.

///|
fn html(src : String) -> String raise {
  @write.document(@lower.lower_source(src).document(), style=Minified)
}

///|
fn pretty(src : String) -> String raise {
  @write.document(@lower.lower_source(src).document())
}

///|
test "an element is a call, and its children are its block" {
  inspect(html("div():\n  p(): \"hi\"\n"), content="<div><p>hi</p></div>")
}

///|
test "an element with no block is empty, and a void one is void" {
  inspect(html("div()\n"), content="<div></div>")
  inspect(html("br()\n"), content="<br>")
  inspect(
    html("img(src: \"a.png\", alt: \"\")\n"),
    content="<img src=a.png alt=\"\">",
  )
}

///|
test "attributes are declarations, and a bare name is a flag" {
  inspect(
    html("input(type: \"checkbox\", checked)\n"),
    content="<input type=checkbox checked>",
  )
  // A bare identifier as a value means its own text, so both spellings agree.
  inspect(html("input(type: submit)\n"), content="<input type=submit>")
  inspect(html("td(colspan: 2)\n"), content="<td colspan=2></td>")
}

///|
test "underscores become hyphens" {
  inspect(
    html("div(data_id: \"3\", aria_label: \"Close\")\n"),
    content="<div data-id=3 aria-label=Close></div>",
  )
  inspect(
    html("my_element():\n  \"x\"\n"),
    content="<my-element>x</my-element>",
  )
}

///|
test "a name with no bare spelling is written literally" {
  inspect(
    html("svg():\n  use(attr(\"xlink:href\", \"#a\"))\n"),
    content="<svg><use xlink:href=#a /></svg>",
  )
  inspect(html("element(\"side_bar\")\n"), content="<side_bar></side_bar>")
}

///|
test "text is a string literal, and carries its own whitespace" {
  // The space before the link is inside the string, which is the whole reason
  // the indentation is free.
  inspect(
    html("p():\n  \"Read \"\n  a(href: \"/x\"): \"more\"\n"),
    content="<p>Read <a href=/x>more</a></p>",
  )
  inspect(
    html("p():\n  \"Read\"\n  a(href: \"/x\"): \"more\"\n"),
    content="<p>Read<a href=/x>more</a></p>",
  )
}

///|
test "a group is a run: several children on one line" {
  inspect(html("p(): \"a\" br() \"b\"\n"), content="<p>a<br>b</p>")
}

///|
test "the one construct that parses cleanly and means the wrong thing" {
  let l = @lower.lower_source("p(): \"Hello \" strong(): \"world\" \"!\"\n")
  // The `!` is inside the strong, not beside it.
  inspect(
    @write.document(l.document(), style=Minified),
    content="<p>Hello <strong>world!</strong></p>",
  )
  assert_eq(
    l.diagnostics()[0].kind.code(),
    "shrubhtml::trailing_run_after_block",
  )
  // And the shape that is merely similar stays quiet.
  assert_eq(
    @lower.lower_source("p(): strong(): \"a\"\n").diagnostics().length(),
    0,
  )
  assert_eq(@lower.lower_source("p(): \"a\" \"b\"\n").diagnostics().length(), 0)
}

///|
test "a comment is a node, not a shrubbery comment" {
  inspect(html("comment(\" build 3 \")\n"), content="<!-- build 3 -->")
}

///|
test "a doctype, plain and legacy" {
  inspect(html("doctype()\n"), content="<!DOCTYPE html>")
  inspect(
    html("doctype(\"-//W3C//DTD HTML 4.01//EN\", \"http://x/s.dtd\")\n"),
    content="<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://x/s.dtd\">",
  )
}

///|
test "raw text has a native spelling, and is not escaped" {
  inspect(
    html("script(type: \"module\"):\n  @{\n    if (a < b) { go() }\n  }\n"),
    content="<script type=module>if (a < b) { go() }</script>",
  )
  inspect(
    html("style():\n  @{\n    .a { color: red }\n  }\n"),
    content="<style>.a { color: red }</style>",
  )
}

///|
test "raw() is the escape when at-notation is inconvenient" {
  inspect(
    html("script(): raw(\"var a = 1\")\n"),
    content="<script>var a = 1</script>",
  )
}

///|
test "preformatted text keeps every byte" {
  inspect(
    pretty("pre():\n  @{line one\n    line two}\n"),
    content=(
      #|<pre>line one
      #|line two</pre>
      #|
    ),
  )
}

///|
test "the namespace follows the element" {
  inspect(
    html(
      "svg(viewBox: \"0 0 24 24\"):\n" +
      "  linearGradient(id: \"g\"):\n" +
      "    stop(offset: \"0%\", stop_color: \"#2F6B4F\")\n" +
      "  path(d: \"M4 4h16v16H4z\")\n",
    ),
    content="<svg viewBox=\"0 0 24 24\"><linearGradient id=g><stop offset=0% stop-color=#2F6B4F /></linearGradient><path d=\"M4 4h16v16H4z\"/></svg>",
  )
}

///|
test "an integration point puts HTML back in scope" {
  inspect(
    html("svg():\n  foreignObject():\n    br()\n"),
    content="<svg><foreignObject><br></foreignObject></svg>",
  )
}

///|
test "MathML too" {
  inspect(
    html(
      "math(display: \"block\"):\n  mfrac():\n    mi(): \"a\"\n    mn(): \"2\"\n",
    ),
    content="<math display=block><mfrac><mi>a</mi><mn>2</mn></mfrac></math>",
  )
}

///|
test "a whole page" {
  inspect(
    pretty(
      "doctype()\n" +
      "html(lang: \"en\"):\n" +
      "  head():\n" +
      "    meta(charset: \"utf-8\")\n" +
      "    title(): \"Shrubbery HTML\"\n" +
      "  body():\n" +
      "    main(class: \"card\"):\n" +
      "      h1(): \"Hello\"\n" +
      "      p():\n" +
      "        \"Written in \"\n" +
      "        a(href: \"/spec\"): \"shrubbery\"\n" +
      "        \".\"\n",
    ),
    content=(
      #|<!DOCTYPE html>
      #|<html lang="en">
      #|  <head>
      #|    <meta charset="utf-8">
      #|    <title>Shrubbery HTML</title>
      #|  </head>
      #|  <body>
      #|    <main class="card">
      #|      <h1>Hello</h1>
      #|      <p>Written in <a href="/spec">shrubbery</a>.</p>
      #|    </main>
      #|  </body>
      #|</html>
      #|
    ),
  )
}

///|
test "an HTML habit is met with its replacement" {
  let l = @lower.lower_source("<div>\n")
  assert_eq(l.diagnostics()[0].kind.code(), "shrubhtml::sigil_tag")
}

///|
test "a bare word is not an element" {
  let l = @lower.lower_source("div():\n  p\n")
  assert_eq(l.diagnostics()[0].kind.code(), "shrubhtml::bare_term_in_block")
  // And the source it could not read is still in the tree.
  inspect(@write.document(l.document(), style=Minified), content="<div>p</div>")
}

///|
test "a reserved name says how to ask for the element anyway" {
  let l = @lower.lower_source("svg():\n  text(): \"x\"\n")
  assert_eq(l.diagnostics()[0].kind.code(), "shrubhtml::bad_escape_call")
  inspect(
    html("svg():\n  element(\"text\"):\n    \"x\"\n"),
    content="<svg><text>x</text></svg>",
  )
}

///|
test "children on a void element are refused, not silently kept" {
  let l = @lower.lower_source("br():\n  \"x\"\n")
  assert_eq(l.diagnostics()[0].kind.code(), "shrubhtml::children_on_void")
  inspect(@write.document(l.document(), style=Minified), content="<br>")
}

///|
test "an alternative has nothing to mean" {
  // Written where the notation admits one -- a `|` under a block is a
  // shrubbery indentation error, and never reaches this layer at all.
  let l = @lower.lower_source("div()\n| a()\n| b()\n")
  assert_eq(l.diagnostics()[0].kind.code(), "shrubhtml::alts_unsupported")
}

///|
test "strict mode raises on the first error" {
  let raised = try {
    let _ = @lower.lower_source("div():\n  p\n", strict=true)
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}

///|
test "a source that does not parse lowers to nothing, and says why" {
  // Shrubbery recovers, so there is still a tree; what matters is that the
  // notation's own complaint reaches the caller in one list with this layer's.
  let l = @lower.lower_source("div(:\n")
  assert_true(l.has_errors())
}

///|
test "the raw-text hook is where the CSS module would plug in" {
  // Not `shrubbery-css` -- that would be a dependency every consumer pays for.
  // A caller that already has both supplies the function.
  let l = @lower.lower_source(
    "style():\n  ignored()\n",
    hook=Some((name, groups) => {
      if name == "style" && groups.length() == 1 {
        Some(".a{b:c}")
      } else {
        None
      }
    }),
  )
  inspect(
    @write.document(l.document(), style=Minified),
    content="<style>.a{b:c}</style>",
  )
}
