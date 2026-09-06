///|
/// One diagnostic, rendered, so that the span arithmetic is checked by drawing
/// the caret rather than by asserting about numbers.

///|
/// The span of the first group in a parsed shrubbery source.
///
/// Taken from a real parse rather than hand-built: `@basic.Pos` carries five
/// fields in three different units, and a hand-made one would prove only that
/// the test and the renderer agree with each other.
fn first_span(src : String) -> @basic.Span raise {
  @shrub.parse(src).root().children()[0].span
}

///|
fn mono() -> @render.Config {
  { ..@render.default_config, theme: @style.mono_theme, color: Never, }
}

///|
test "codes are namespaced apart from the markup layer's" {
  assert_eq(
    @kind.ErrorKind::AltsUnsupported.code(),
    "shrubhtml::alts_unsupported",
  )
  assert_eq(@kind.ErrorKind::SigilTag("<").code(), "shrubhtml::sigil_tag")
}

///|
test "the hazard diagnostic names the rule that caught someone out" {
  let src = "p(): \"Hello \" strong(): \"world\" \"!\"\n"
  let sources = @report.Sources::new()
  let id = sources.add("t.shrubhtml", src)
  let d = @err.Diagnostic::of_kind(TrailingRunAfterBlock, first_span(src))
  inspect(
    @render.render_string(d.to_report(id), sources, mono()),
    content=(
      #|warning[shrubhtml::trailing_run_after_block]: everything after the `:` on this line went inside the block
      #|  ╭─[ t.shrubhtml:1:1 ]
      #|  │
      #|1 │ p(): "Hello " strong(): "world" "!"
      #|  │ ─────────────────┬─────────────────
      #|  │                  ╰─ this became a child, not a sibling
      #|  │
      #|  ├─ help: a block runs to the end of its line, so an element with children has to come last
      #|  ╰─
      #|
    ),
  )
}

///|
test "an HTML habit is met with its replacement" {
  let src = "<div>\n"
  let sources = @report.Sources::new()
  let id = sources.add("t.shrubhtml", src)
  let d = @err.Diagnostic::new(SigilTag("<"), first_span(src))
  let out = @render.render_string(d.to_report(id), sources, mono())
  assert_true(out.contains("an element is a call: write `div():` for `<div>`"))
}

///|
test "a taken name says how to ask for the element anyway" {
  let src = "text()\n"
  let sources = @report.Sources::new()
  let id = sources.add("t.shrubhtml", src)
  let d = @err.Diagnostic::new(ReservedCall("text"), first_span(src))
  let out = @render.render_string(d.to_report(id), sources, mono())
  assert_true(out.contains("write `element(\"text\")`"))
}
